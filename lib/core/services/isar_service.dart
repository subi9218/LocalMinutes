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
  Future<bool> relocateToUserSelectedDirectory() async {
    final selectedPath = AppSettings.instance.recordingsSavePath.trim();
    if (selectedPath.isEmpty) return false;
    final targetPath = '$selectedPath/$_userDataFolderName';

    if (_directoryPath == targetPath && _isar != null && _isar!.isOpen) {
      return false;
    }

    final current = _isar;
    final currentPath = _directoryPath;

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
      await current.close();
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

    await Directory(targetPath).create(recursive: true);
    final next = await Isar.open(_schemas, directory: targetPath);
    _isar = next;
    _directoryPath = targetPath;

    final hasData =
        meetings.isNotEmpty ||
        groups.isNotEmpty ||
        transcripts.isNotEmpty ||
        summaries.isNotEmpty ||
        summaryVersions.isNotEmpty ||
        glossaryEntries.isNotEmpty;
    if (hasData) {
      await next.writeTxn(() async {
        await next.meetingGroups.putAll(groups);
        await next.meetings.putAll(meetings);
        await next.transcripts.putAll(transcripts);
        await next.summarys.putAll(summaries);
        await next.summaryVersions.putAll(summaryVersions);
        await next.glossaryEntrys.putAll(glossaryEntries);
      });
    }

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
