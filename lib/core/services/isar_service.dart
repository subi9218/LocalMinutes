import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';
import '../../domain/entities/glossary_entry.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/meeting_group.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/entities/summary.dart';
import '../../domain/entities/summary_version.dart';

class IsarService {
  static const _userDataFolderName = 'Local Minutes Data';
  static const _schemas = [
    MeetingSchema,
    MeetingGroupSchema,
    TranscriptSchema,
    SummarySchema,
    SummaryVersionSchema,
    GlossaryEntrySchema,
  ];

  static final instance = IsarService._();
  IsarService._();

  Isar? _isar;
  String? _directoryPath;

  bool get isOpen => _isar?.isOpen ?? false;

  Isar get db {
    if (_isar == null || !_isar!.isOpen) {
      throw StateError('IsarService not initialized. Call init() first.');
    }
    return _isar!;
  }

  /// 사용자가 선택한 저장 폴더에 Isar DB를 엽니다.
  ///
  /// [AppSettings.recordingsSavePath]가 비어 있으면 init을 건너뜁니다.
  /// (Apple App Sandbox 가이드라인: 사용자 데이터는 컨테이너가 아닌
  /// 사용자가 접근 가능한 폴더에 저장.)
  ///
  /// 이전 버전이 컨테이너 Application Support에 데이터를 저장했다면,
  /// 사용자 폴더로 이전한 뒤 컨테이너 잔재를 삭제합니다.
  Future<void> init() async {
    if (_isar != null && _isar!.isOpen) return;
    final selectedPath = AppSettings.instance.recordingsSavePath.trim();
    if (selectedPath.isEmpty) {
      // 저장 폴더 미선택 — 컨테이너에 폴백하지 않음.
      return;
    }
    final dirPath = '$selectedPath/$_userDataFolderName';
    await Directory(dirPath).create(recursive: true);

    // 레거시 컨테이너 데이터 이전 (구버전에서 컨테이너에 저장됐던 경우)
    await _migrateLegacyContainerDataIfNeeded(dirPath);

    _isar = await Isar.open(_schemas, directory: dirPath);
    _directoryPath = dirPath;
  }

  /// 설정 화면에서 사용자가 저장 폴더를 변경할 때 사용합니다.
  /// 기존에 열려 있던 Isar 데이터를 새 폴더로 이전합니다.
  ///
  /// 안전 보장:
  /// - 새 폴더의 Isar를 **먼저 연 뒤** 성공이 확인되어야 기존 DB를 닫는다.
  ///   (열기 실패 시 기존 DB가 닫힌 채 남아 db 게터가 세션 내내 깨지는 것을 방지 — I3/E1)
  /// - 새 폴더에 **이미 회의 데이터가 있으면** putAll로 덮어쓰지 않고 그 라이브러리를
  ///   그대로 채택한다. 기존(소스) 데이터는 원래 위치에 보존한다(삭제 안 함 — I4).
  /// - 이전 시 녹음 WAV 파일도 새 폴더로 옮기고 audioFilePath를 갱신한다(I2, best-effort).
  ///
  /// 실패하면 예외를 그대로 던지며, 이 경우 기존 DB는 닫히지 않아 계속 사용할 수 있다.
  Future<bool> relocateToUserSelectedDirectory() async {
    final selectedPath = AppSettings.instance.recordingsSavePath.trim();
    if (selectedPath.isEmpty) return false;
    final targetPath = '$selectedPath/$_userDataFolderName';

    if (_directoryPath == targetPath && _isar != null && _isar!.isOpen) {
      return false;
    }

    final current = _isar;
    final currentPath = _directoryPath;

    await Directory(targetPath).create(recursive: true);

    // ── I4: 타깃에 이미 데이터가 있으면 병합하지 않고 그대로 채택 ──────────
    if (await _hasIsarFiles(targetPath)) {
      final next = await Isar.open(_schemas, directory: targetPath);
      // 타깃 열기 성공 후에만 기존 DB를 닫는다.
      if (current != null && current.isOpen && currentPath != targetPath) {
        try {
          await current.close();
        } catch (_) {}
      }
      _isar = next;
      _directoryPath = targetPath;
      // 소스 데이터는 다른 라이브러리이므로 삭제하지 않고 원래 위치에 보존.
      return true;
    }

    // ── 타깃이 비어 있음 → 소스 데이터를 이전 ─────────────────────────────
    // 소스 행을 먼저 읽는다(소스는 아직 열린 상태 유지).
    List<Meeting> meetings = const [];
    List<MeetingGroup> groups = const [];
    List<Transcript> transcripts = const [];
    List<Summary> summaries = const [];
    List<SummaryVersion> summaryVersions = const [];
    List<GlossaryEntry> glossaryEntries = const [];

    if (current != null && current.isOpen) {
      meetings = await current.meetings.where().findAll();
      groups = await current.meetingGroups.where().findAll();
      transcripts = await current.transcripts.where().findAll();
      summaries = await current.summarys.where().findAll();
      summaryVersions = await current.summaryVersions.where().findAll();
      glossaryEntries = await current.glossaryEntrys.where().findAll();
    } else {
      // 아직 열린 Isar가 없을 수 있음 — 컨테이너에 잔재 데이터가 있다면 가져옴.
      final legacyData = await _readLegacyContainerData();
      if (legacyData != null) {
        meetings = legacyData.meetings;
        groups = legacyData.groups;
        transcripts = legacyData.transcripts;
        summaries = legacyData.summaries;
        summaryVersions = legacyData.summaryVersions;
        glossaryEntries = legacyData.glossaryEntries;
      }
    }

    // I3/E1: 타깃을 먼저 연다. 실패하면 예외가 전파되고, 소스는 닫히지 않아
    // 기존 DB(_isar=current)를 계속 쓸 수 있다.
    final next = await Isar.open(_schemas, directory: targetPath);

    // 데이터 복사를 포인터 교체보다 먼저 수행한다 — 복사가 실패(디스크 부족 등)
    // 하면 next를 닫고 예외를 전파해, 세션이 기존 DB를 그대로 유지하게 한다.
    // (예전엔 _isar를 먼저 교체해 복사 실패 시 세션이 '빈 DB'로 남았다)
    final hasData =
        meetings.isNotEmpty ||
        groups.isNotEmpty ||
        transcripts.isNotEmpty ||
        summaries.isNotEmpty ||
        summaryVersions.isNotEmpty ||
        glossaryEntries.isNotEmpty;
    if (hasData) {
      try {
        await next.writeTxn(() async {
          await next.meetingGroups.putAll(groups);
          await next.meetings.putAll(meetings);
          await next.transcripts.putAll(transcripts);
          await next.summarys.putAll(summaries);
          await next.summaryVersions.putAll(summaryVersions);
          await next.glossaryEntrys.putAll(glossaryEntries);
        });
      } catch (_) {
        try {
          await next.close();
        } catch (_) {}
        // 방금 만든 빈 DB 파일을 정리한다 — 남겨두면 다음 시도에서 I4
        // 가드('타깃에 데이터 있음')가 이 빈 DB를 채택해 원본이 버려진다.
        // (putAll 경로는 타깃이 비어 있을 때만 도달하므로 삭제 안전)
        try {
          await _deleteLegacyIsarFiles(targetPath);
        } catch (_) {}
        rethrow;
      }
    }

    // 복사 성공 → 이제 소스를 닫고 포인터를 교체한다.
    if (current != null && current.isOpen) {
      try {
        await current.close();
      } catch (_) {}
    }
    _isar = next;
    _directoryPath = targetPath;

    // I2: 녹음 WAV 파일을 새 폴더로 옮기고 audioFilePath 갱신 (best-effort).
    await _migrateAudioFiles(currentPath, targetPath, next);

    if (currentPath != null && currentPath != targetPath) {
      await _deleteLegacyIsarFiles(currentPath);
    }
    // 항상 컨테이너 잔재도 정리
    final appSupport = await getApplicationSupportDirectory();
    if (appSupport.path != targetPath && appSupport.path != currentPath) {
      await _deleteLegacyIsarFiles(appSupport.path);
    }
    return true;
  }

  /// 폴더 이전 시, 기존 루트에 있던 녹음 WAV 파일을 새 루트로 옮기고
  /// Meeting.audioFilePath를 새 절대경로로 갱신한다.
  ///
  /// 사용자 폴더 → 사용자 폴더 이전만 대상(둘 다 '$_userDataFolderName' 하위).
  /// 이동 실패한 파일은 경로를 그대로 두어 기존 동작과 동일하게 둔다(best-effort).
  Future<void> _migrateAudioFiles(
    String? currentPath,
    String targetPath,
    Isar isar,
  ) async {
    if (currentPath == null) return;
    if (!currentPath.endsWith(_userDataFolderName)) return;
    if (!targetPath.endsWith(_userDataFolderName)) return;
    final oldRoot = Directory(currentPath).parent.path;
    final newRoot = Directory(targetPath).parent.path;
    if (oldRoot == newRoot) return;

    try {
      final all = await isar.meetings.where().findAll();
      final updated = <Meeting>[];
      for (final m in all) {
        final p = m.audioFilePath;
        if (p == null || p.isEmpty) continue;
        if (!p.startsWith('$oldRoot/')) continue;
        final src = File(p);
        if (!await src.exists()) continue;
        final name = p.split('/').last;
        final destPath = '$newRoot/$name';
        try {
          await src.rename(destPath);
        } catch (_) {
          // 다른 볼륨 등 rename 실패 → copy+delete 폴백
          try {
            await src.copy(destPath);
            await src.delete().catchError((_) => src);
          } catch (_) {
            continue; // 이동 실패 → audioFilePath 그대로 둠
          }
        }
        m.audioFilePath = destPath;
        updated.add(m);
      }
      if (updated.isNotEmpty) {
        await isar.writeTxn(() async {
          await isar.meetings.putAll(updated);
        });
      }
    } catch (_) {
      // best-effort: 오디오 이동 실패가 폴더 변경 자체를 막지 않도록 한다.
    }
  }

  /// 컨테이너 Application Support 에 남아 있는 레거시 Isar 데이터를
  /// 사용자 폴더로 이전합니다. 이전 후 컨테이너 Isar 파일은 삭제됩니다.
  ///
  /// 타깃 폴더에 이미 Isar 데이터가 있으면 덮어쓰지 않고 컨테이너 잔재만 삭제합니다.
  Future<void> _migrateLegacyContainerDataIfNeeded(String targetPath) async {
    final appSupport = await getApplicationSupportDirectory();
    final legacyPath = appSupport.path;
    if (legacyPath == targetPath) return;

    final legacyDir = Directory(legacyPath);
    if (!await legacyDir.exists()) return;
    if (!await _hasIsarFiles(legacyPath)) return;

    // 타깃이 이미 데이터를 갖고 있으면 마이그레이션하지 않음
    // (컨테이너 잔재만 정리)
    if (await _hasIsarFiles(targetPath)) {
      await _deleteLegacyIsarFiles(legacyPath);
      return;
    }

    Isar? legacy;
    try {
      legacy = await Isar.open(_schemas, directory: legacyPath);
      final meetings = await legacy.meetings.where().findAll();
      final groups = await legacy.meetingGroups.where().findAll();
      final transcripts = await legacy.transcripts.where().findAll();
      final summaries = await legacy.summarys.where().findAll();
      final summaryVersions = await legacy.summaryVersions.where().findAll();
      final glossaryEntries = await legacy.glossaryEntrys.where().findAll();
      await legacy.close();
      legacy = null;

      final hasData =
          meetings.isNotEmpty ||
          groups.isNotEmpty ||
          transcripts.isNotEmpty ||
          summaries.isNotEmpty ||
          summaryVersions.isNotEmpty ||
          glossaryEntries.isNotEmpty;
      if (hasData) {
        final target = await Isar.open(_schemas, directory: targetPath);
        try {
          await target.writeTxn(() async {
            await target.meetingGroups.putAll(groups);
            await target.meetings.putAll(meetings);
            await target.transcripts.putAll(transcripts);
            await target.summarys.putAll(summaries);
            await target.summaryVersions.putAll(summaryVersions);
            await target.glossaryEntrys.putAll(glossaryEntries);
          });
        } finally {
          await target.close();
        }
      }
      await _deleteLegacyIsarFiles(legacyPath);
    } catch (_) {
      // 이전 실패 시 부팅을 막지 않음 — 사용자 폴더는 빈 상태로 시작
    } finally {
      if (legacy != null) {
        try {
          await legacy.close();
        } catch (_) {}
      }
    }
  }

  /// 컨테이너 잔재 데이터만 읽고 닫음 (relocate 경로용).
  Future<_LegacyData?> _readLegacyContainerData() async {
    final appSupport = await getApplicationSupportDirectory();
    final legacyPath = appSupport.path;
    if (!await _hasIsarFiles(legacyPath)) return null;
    try {
      final legacy = await Isar.open(_schemas, directory: legacyPath);
      try {
        return _LegacyData(
          meetings: await legacy.meetings.where().findAll(),
          groups: await legacy.meetingGroups.where().findAll(),
          transcripts: await legacy.transcripts.where().findAll(),
          summaries: await legacy.summarys.where().findAll(),
          summaryVersions: await legacy.summaryVersions.where().findAll(),
          glossaryEntries: await legacy.glossaryEntrys.where().findAll(),
        );
      } finally {
        await legacy.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasIsarFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return false;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (name.endsWith('.isar')) return true;
    }
    return false;
  }

  Future<void> _deleteLegacyIsarFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (name.endsWith('.isar') || name.endsWith('.isar.lock')) {
        await entity.delete().catchError((_) => entity);
      }
    }
  }
}

class _LegacyData {
  final List<Meeting> meetings;
  final List<MeetingGroup> groups;
  final List<Transcript> transcripts;
  final List<Summary> summaries;
  final List<SummaryVersion> summaryVersions;
  final List<GlossaryEntry> glossaryEntries;

  const _LegacyData({
    required this.meetings,
    required this.groups,
    required this.transcripts,
    required this.summaries,
    required this.summaryVersions,
    required this.glossaryEntries,
  });
}
