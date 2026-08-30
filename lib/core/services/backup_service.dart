import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/meeting_repository_impl.dart';
import '../l10n/app_tr.dart';
import 'app_settings.dart';
import 'crash_log_service.dart';
import 'isar_service.dart';

/// 복원 롤백까지 실패해 수동 복구가 필요한 상태.
/// UI는 이 타입을 감지해 "재시작 + before-restore 폴더 복구" 안내를 띄운다.
class BackupRollbackException implements Exception {
  final String message;
  final Object cause;
  const BackupRollbackException(this.message, this.cause);
  @override
  String toString() => message;
}

/// 전체 백업(.zip) 내보내기 / 가져오기.
///
/// zip 구조:
///   manifest.json          형식 버전·오디오 매핑(원본 경로→zip 이름·크기)·설정
///   db/default.isar        Isar 스냅샷 (Isar.copyToFile — 트랜잭션 안전)
///   audio/[zip 이름]        회의 오디오 (오디오 포함 선택 시)
///   imported/[zip 이름]     '파일 불러오기' 오디오 (앱 지원 폴더 소재)
///
/// 안전 설계:
/// - 내보내기는 임시 파일에 zip을 만든 뒤 성공 시에만 최종 경로로 옮긴다
///   (실패해도 기존 백업 파일을 덮어쓰거나 지우지 않음).
/// - 복원은 기존 라이브러리를 'Local Minutes Data.before-restore-(시각)'로
///   보존하고, 진행 마커(.lm-restore-in-progress)를 남겨 도중 강제종료 시
///   다음 실행에서 IsarService.init()이 자동 원복한다.
/// - 덮어써야 하는 동명 오디오는 safety 폴더로 옮겨 보존하고 롤백 시 되돌린다.
class BackupService {
  BackupService._();

  static const formatVersion = 2;

  /// 백업/복원 진행 중 여부 — 녹음·전사 시작 게이트가 이를 확인해
  /// 백업 도중 DB가 변경되거나(내보내기) 닫히는(복원) 충돌을 막는다.
  static bool get isBusy => _busy;
  static bool _busy = false;

  /// 복원 진행 마커 파일명 (저장 폴더 루트). 내용: {dataDir, safetyDir}.
  static const restoreMarkerName = '.lm-restore-in-progress';

  // ── 내보내기 ─────────────────────────────────────────────────────

  /// 내보내기 전 미리보기(회의 수·오디오 개수·예상 용량 MB).
  static Future<({int meetings, int audioFiles, double audioMb})>
      estimate() async {
    final db = IsarService.instance.db;
    final meetings = await MeetingRepositoryImpl(db).getAllMeetings();
    int audioFiles = 0;
    double audioMb = 0;
    final seen = <String>{};
    for (final m in meetings) {
      final p = m.audioFilePath;
      if (p == null || p.isEmpty || seen.contains(p)) continue;
      seen.add(p);
      final f = File(p);
      if (await f.exists()) {
        audioFiles++;
        audioMb += await f.length() / (1024 * 1024);
      }
    }
    try {
      final appSupport = await getApplicationSupportDirectory();
      final importedDir = Directory('${appSupport.path}/imported');
      if (await importedDir.exists()) {
        await for (final e in importedDir.list()) {
          if (e is File && !seen.contains(e.path)) {
            audioFiles++;
            audioMb += await e.length() / (1024 * 1024);
          }
        }
      }
    } catch (_) {}
    return (meetings: meetings.length, audioFiles: audioFiles, audioMb: audioMb);
  }

  /// 전체 백업을 [zipPath]에 생성한다.
  /// 임시 파일에 만든 뒤 성공 시에만 [zipPath]로 옮기므로, 실패해도
  /// 같은 이름의 기존 백업 파일은 훼손되지 않는다.
  static Future<void> exportBackup({
    required String zipPath,
    required bool includeAudio,
    void Function(String phase)? onProgress,
  }) async {
    final db = IsarService.instance.db;
    final tmp = await Directory.systemTemp.createTemp('lm_backup_');
    _busy = true;
    try {
      // 1) DB 스냅샷 (열린 DB에서 안전한 공식 핫백업 API)
      onProgress?.call(tr('회의록 데이터 스냅샷 생성 중...',
          'Creating a snapshot of your meeting data...'));
      final dbSnapshot = '${tmp.path}/default.isar';
      await db.copyToFile(dbSnapshot);

      // 2) 오디오 수집 — zip 이름 → {원본 절대경로, 크기}
      //    (같은 basename 충돌 시 접두를 붙이되, manifest에 원본 경로 매핑을
      //     기록해 복원이 정확한 파일로 되돌릴 수 있게 한다)
      final audioMap = <String, String>{}; // zipName → 원본 경로
      final importedMap = <String, String>{};
      final sizes = <String, int>{}; // 'audio/<name>' 또는 'imported/<name>' → bytes
      if (includeAudio) {
        onProgress?.call(tr('오디오 파일 수집 중...', 'Collecting audio files...'));
        final meetings = await MeetingRepositoryImpl(db).getAllMeetings();
        final appSupport = await getApplicationSupportDirectory();
        final importedRoot = '${appSupport.path}/imported';
        final seenPaths = <String>{};
        for (final m in meetings) {
          final p = m.audioFilePath;
          if (p == null || p.isEmpty || seenPaths.contains(p)) continue;
          final f = File(p);
          if (!await f.exists()) continue;
          seenPaths.add(p);
          final base = p.split('/').last;
          final isImported = p.startsWith(importedRoot);
          final bucket = isImported ? importedMap : audioMap;
          var zipName = base;
          var n = 1;
          while (bucket.containsKey(zipName)) {
            zipName = '${n++}_$base';
          }
          bucket[zipName] = p;
          sizes['${isImported ? 'imported' : 'audio'}/$zipName'] =
              await f.length();
        }
        // 회의와 연결이 끊긴 imported 잔여 파일도 보존
        final importedDir = Directory(importedRoot);
        if (await importedDir.exists()) {
          await for (final e in importedDir.list()) {
            if (e is File && !seenPaths.contains(e.path)) {
              final base = e.path.split('/').last;
              if (!importedMap.containsKey(base)) {
                importedMap[base] = e.path;
                sizes['imported/$base'] = await e.length();
              }
            }
          }
        }
      }

      // 3) manifest — v2: 오디오는 {zipName: 원본경로} 매핑 + 크기 기록
      final manifest = {
        'formatVersion': formatVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'osVersion': Platform.operatingSystemVersion,
        'includeAudio': includeAudio,
        'audio': audioMap,
        'imported': importedMap,
        'sizes': sizes,
        'settings': AppSettings.instance.exportableSettings(),
      };
      final manifestPath = '${tmp.path}/manifest.json';
      await File(manifestPath)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));

      // 4) zip 생성 — 임시 경로에 만들고(write-then-move) 워커 isolate에서 압축
      onProgress?.call(tr('백업 파일 압축 중... (오디오가 많으면 몇 분 걸릴 수 있습니다)',
          'Compressing the backup... (may take a few minutes with many recordings)'));
      final stagedZip = '${tmp.path}/out.zip';
      final audioCopy = Map<String, String>.from(audioMap);
      final importedCopy = Map<String, String>.from(importedMap);
      await Isolate.run(() async {
        final encoder = ZipFileEncoder();
        encoder.create(stagedZip);
        try {
          await encoder.addFile(File(manifestPath), 'manifest.json');
          await encoder.addFile(File(dbSnapshot), 'db/default.isar');
          for (final e in audioCopy.entries) {
            await encoder.addFile(File(e.value), 'audio/${e.key}');
          }
          for (final e in importedCopy.entries) {
            await encoder.addFile(File(e.value), 'imported/${e.key}');
          }
        } finally {
          await encoder.close();
        }
      });

      // 5) 성공 — 최종 경로로 이동 (볼륨이 다르면 copy+delete 폴백)
      try {
        await File(stagedZip).rename(zipPath);
      } on FileSystemException {
        await File(stagedZip).copy(zipPath);
      }
      CrashLogService.instance.info(
        'backup exported: audio=${audioMap.length} imported=${importedMap.length} → $zipPath',
        context: 'backup',
      );
    } finally {
      _busy = false;
      await tmp.delete(recursive: true).catchError((_) => tmp);
    }
  }

  // ── 가져오기 ─────────────────────────────────────────────────────

  /// 백업 zip을 임시 폴더에 해제하고 검증한다.
  /// 취소 시 [discardStaging], 진행 시 [restoreBackup]에 전달
  /// (restoreBackup은 성공/실패와 무관하게 staging을 정리한다).
  static Future<
      ({
        Directory stagingDir,
        int audioCount,
        String createdAt,
        bool includeAudio,
      })> inspectBackup(String zipPath) async {
    final staging = await Directory.systemTemp.createTemp('lm_restore_');
    try {
      await Isolate.run(() => extractFileToDisk(zipPath, staging.path));
      final manifestFile = File('${staging.path}/manifest.json');
      if (!await manifestFile.exists()) {
        throw FormatException(tr('백업 파일이 아닙니다 (manifest 없음).',
            'Not a Local Minutes backup (missing manifest).'));
      }
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final version = manifest['formatVersion'] as int? ?? 0;
      if (version > formatVersion) {
        throw FormatException(tr(
            '이 백업은 더 새로운 버전의 앱에서 만들어졌습니다. 앱을 업데이트해주세요.',
            'This backup was created by a newer app version. Please update the app.'));
      }
      if (!await File('${staging.path}/db/default.isar').exists()) {
        throw FormatException(tr('백업에 회의록 데이터가 없습니다.',
            'The backup contains no meeting data.'));
      }
      final audio = (manifest['audio'] as Map?)?.length ??
          (manifest['audio'] as List?)?.length ??
          0;
      final imported = (manifest['imported'] as Map?)?.length ??
          (manifest['imported'] as List?)?.length ??
          0;
      return (
        stagingDir: staging,
        audioCount: audio + imported,
        createdAt: manifest['createdAt'] as String? ?? '?',
        includeAudio: manifest['includeAudio'] as bool? ?? false,
      );
    } catch (_) {
      await staging.delete(recursive: true).catchError((_) => staging);
      rethrow;
    }
  }

  static Future<void> discardStaging(Directory staging) async {
    await staging.delete(recursive: true).catchError((_) => staging);
  }

  /// 백업을 복원한다. staging은 성공/실패와 무관하게 이 함수가 정리한다.
  static Future<void> restoreBackup({
    required Directory stagingDir,
    void Function(String phase)? onProgress,
  }) async {
    final savePath = AppSettings.instance.recordingsSavePath.trim();
    if (savePath.isEmpty) {
      throw StateError(
          tr('저장 폴더가 설정되어 있지 않습니다.', 'No save folder is configured.'));
    }
    final dataDir = '$savePath/Local Minutes Data';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safetyDir = '$savePath/Local Minutes Data.before-restore-$ts';
    final marker = File('$savePath/$restoreMarkerName');

    _busy = true;
    // 롤백 대장부: 무엇을 바꿨는지 추적해 실패 시 정확히 되돌린다.
    var renamed = false; // dataDir → safetyDir rename 성공 여부
    var createdNewDataDir = false; // 우리가 새 dataDir을 만들었는지
    final overwrittenAudio = <String, String>{}; // 보존 위치 → 원래 위치

    Future<void> placeAudio(Directory src, String destRoot) async {
      if (!await src.exists()) return;
      final preserveRoot = Directory('$safetyDir/overwritten-audio');
      await for (final e in src.list()) {
        if (e is! File) continue;
        final base = e.path.split('/').last;
        final dest = '$destRoot/$base';
        final existing = File(dest);
        if (await existing.exists()) {
          // 덮어쓰기 전 기존 파일을 safety 폴더로 보존 (롤백 시 원복)
          await preserveRoot.create(recursive: true);
          final preserved = '${preserveRoot.path}/$base';
          await existing.rename(preserved);
          overwrittenAudio[preserved] = dest;
        }
        await e.copy(dest);
      }
    }

    try {
      // 0) 진행 마커 — 도중 강제종료 시 다음 실행에서 init()이 자동 원복
      await marker.writeAsString(
          jsonEncode({'dataDir': dataDir, 'safetyDir': safetyDir}),
          flush: true);

      // 1) 현재 DB 닫기 + 기존 라이브러리 안전망 보존
      onProgress?.call(tr('현재 데이터 보존 중...', 'Preserving current data...'));
      await IsarService.instance.closeForRestore();
      if (await Directory(dataDir).exists()) {
        await Directory(dataDir).rename(safetyDir);
        renamed = true;
      }

      // 2) 백업 DB 배치
      onProgress?.call(tr('회의록 데이터 복원 중...', 'Restoring meeting data...'));
      await Directory(dataDir).create(recursive: true);
      createdNewDataDir = true;
      await File('${stagingDir.path}/db/default.isar')
          .copy('$dataDir/default.isar');

      // 3) 오디오 배치 (기존 동명 파일은 safety 폴더에 보존)
      onProgress?.call(tr('오디오 파일 복원 중...', 'Restoring audio files...'));
      await placeAudio(Directory('${stagingDir.path}/audio'), savePath);
      final appSupport = await getApplicationSupportDirectory();
      final importedRoot = '${appSupport.path}/imported';
      await Directory(importedRoot).create(recursive: true);
      await placeAudio(Directory('${stagingDir.path}/imported'), importedRoot);

      // 4) DB 열기 + 경로 재매핑
      onProgress?.call(tr('데이터 확인 중...', 'Verifying data...'));
      await IsarService.instance.init();
      final manifest = jsonDecode(
              await File('${stagingDir.path}/manifest.json').readAsString())
          as Map<String, dynamic>;
      await _remapAudioPaths(manifest, savePath, importedRoot);

      // 5) 설정 적용
      final settings = manifest['settings'];
      if (settings is Map<String, dynamic>) {
        await AppSettings.instance.applyImportedSettings(settings);
      }

      // 성공 — 마커 제거 (safety 폴더는 사용자 안전망으로 남긴다)
      await marker.delete().catchError((_) => marker);
      CrashLogService.instance.info(
        'backup restored (safety: $safetyDir)',
        context: 'backup',
      );
    } catch (e, st) {
      CrashLogService.instance.recordCaught(e, st, context: 'backupRestore');
      // ── 롤백 — '우리가 만든 것'만 지우고 원본을 되돌린다 ──
      try {
        await IsarService.instance.closeForRestore();
        // dataDir 삭제는 우리가 새로 만든 경우에만! rename이 실패했다면
        // dataDir은 여전히 사용자의 원본이므로 절대 건드리면 안 된다.
        if (createdNewDataDir && await Directory(dataDir).exists()) {
          await Directory(dataDir).delete(recursive: true);
        }
        if (renamed && await Directory(safetyDir).exists()) {
          await Directory(safetyDir).rename(dataDir);
        }
        // 덮어쓰기 보존해둔 오디오 원복
        for (final entry in overwrittenAudio.entries) {
          try {
            await File(entry.value).delete();
          } catch (_) {}
          try {
            await File(entry.key).rename(entry.value);
          } catch (_) {}
        }
        await marker.delete().catchError((_) => marker);
        await IsarService.instance.init();
      } catch (rollbackError, rbSt) {
        CrashLogService.instance
            .recordCaught(rollbackError, rbSt, context: 'backupRollback');
        throw BackupRollbackException(
          tr(
            '복원에 실패했고 자동 되돌리기도 완료하지 못했습니다. 앱을 재시작해주세요. '
                '기존 데이터는 저장 폴더의 "Local Minutes Data.before-restore-…" 폴더에 보존되어 있습니다.',
            'Restore failed and automatic rollback could not complete. Please restart the app. '
                'Your original data is preserved in the "Local Minutes Data.before-restore-…" folder inside your save folder.',
          ),
          e,
        );
      }
      rethrow;
    } finally {
      _busy = false;
      await stagingDir.delete(recursive: true).catchError((_) => stagingDir);
    }
  }

  /// manifest의 원본경로→zip이름 매핑을 우선 사용해 audioFilePath를 재매핑.
  /// 매핑에 없으면(구버전 v1 백업) basename + 크기 검증으로 폴백.
  static Future<void> _remapAudioPaths(
    Map<String, dynamic> manifest,
    String savePath,
    String importedRoot,
  ) async {
    final db = IsarService.instance.db;
    final repo = MeetingRepositoryImpl(db);
    final meetings = await repo.getAllMeetings();
    final includeAudio = manifest['includeAudio'] as bool? ?? false;

    // v2 매핑: 원본경로 → 새 위치
    final pathToNew = <String, String>{};
    final audio = manifest['audio'];
    if (audio is Map) {
      for (final e in audio.entries) {
        pathToNew[e.value as String] = '$savePath/${e.key}';
      }
    }
    final imported = manifest['imported'];
    if (imported is Map) {
      for (final e in imported.entries) {
        pathToNew[e.value as String] = '$importedRoot/${e.key}';
      }
    }
    final sizes = (manifest['sizes'] as Map?)?.cast<String, dynamic>() ?? {};

    for (final m in meetings) {
      final p = m.audioFilePath;
      if (p == null || p.isEmpty) continue;
      if (await File(p).exists()) continue; // 같은 기기 복원 — 그대로 유효

      // 1순위: manifest 매핑 (동명 파일도 정확히 연결)
      final mapped = pathToNew[p];
      if (mapped != null && await File(mapped).exists()) {
        m.audioFilePath = mapped;
        await repo.updateMeeting(m);
        continue;
      }
      // 오디오 미포함 백업이면 잘못된 파일에 붙잡히지 않도록 폴백 생략
      if (!includeAudio) continue;

      // 2순위(v1 폴백): basename 검색 + 크기 일치 검증
      final base = p.split('/').last;
      for (final candidate in ['$savePath/$base', '$importedRoot/$base']) {
        final f = File(candidate);
        if (!await f.exists()) continue;
        final expected = sizes['audio/$base'] ?? sizes['imported/$base'];
        if (expected is int && await f.length() != expected) continue;
        m.audioFilePath = candidate;
        await repo.updateMeeting(m);
        break;
      }
    }
  }

  // ── 미완성 복원 자동 원복 (앱 시작 시) ──────────────────────────────

  /// 저장 폴더에 복원 진행 마커가 남아 있으면(복원 도중 강제종료),
  /// 미완성 dataDir을 버리고 safety 폴더를 원복한다.
  /// IsarService.init() 직전에 호출된다.
  static Future<void> recoverInterruptedRestoreIfNeeded(
      String savePath) async {
    final marker = File('$savePath/$restoreMarkerName');
    if (!await marker.exists()) return;
    try {
      final info =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      final dataDir = info['dataDir'] as String?;
      final safetyDir = info['safetyDir'] as String?;
      if (dataDir == null || safetyDir == null) {
        await marker.delete();
        return;
      }
      final safetyExists = await Directory(safetyDir).exists();
      if (safetyExists) {
        // 미완성 복원본 제거 후 원본 복귀
        if (await Directory(dataDir).exists()) {
          await Directory(dataDir).delete(recursive: true);
        }
        await Directory(safetyDir).rename(dataDir);
        CrashLogService.instance.info(
          'interrupted restore recovered — original library restored',
          context: 'backup',
        );
      }
      await marker.delete();
    } catch (e, st) {
      CrashLogService.instance.recordCaught(e, st, context: 'restoreRecover');
      // 마커를 남겨 다음 실행에서 재시도
    }
  }
}
