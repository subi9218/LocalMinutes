import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/meeting_repository_impl.dart';
import '../../data/repositories/summary_repository_impl.dart';
import '../../data/repositories/transcript_repository_impl.dart';
import '../constants/app_build_config.dart';
import '../constants/app_constants.dart';
import 'app_settings.dart';
import 'crash_log_service.dart';
import 'isar_service.dart';

class DiagnosticExportService {
  DiagnosticExportService._();

  static const _json = JsonEncoder.withIndent('  ');

  static Future<String?> exportWithSavePanel() async {
    final stamp = _fileStamp(DateTime.now());
    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'ZIP', extensions: ['zip']),
      ],
      suggestedName: 'jeokjasaengjon_diagnostics_$stamp.zip',
    );
    if (location == null) return null;

    final path = location.path.endsWith('.zip')
        ? location.path
        : '${location.path}.zip';
    await exportToPath(path);
    return path;
  }

  static Future<void> exportToPath(String path) async {
    final archive = Archive();
    final createdAt = DateTime.now();

    archive.addFile(ArchiveFile.string('README.txt', _buildReadme(createdAt)));
    archive.addFile(
      ArchiveFile.string(
        'diagnostics.json',
        _json.convert(await _buildDiagnosticsJson(createdAt)),
      ),
    );

    final crashLog = await CrashLogService.instance.readLog(maxChars: 120000);
    archive.addFile(ArchiveFile.string('logs/crash.log', crashLog));

    final crashPath = await CrashLogService.instance.exportPath();
    final oldCrash = File('$crashPath.old');
    if (await oldCrash.exists()) {
      archive.addFile(
        ArchiveFile.string(
          'logs/crash.log.old',
          await _readTextTail(oldCrash, maxChars: 120000),
        ),
      );
    }

    final zipBytes = ZipEncoder().encode(archive);
    await File(path).writeAsBytes(zipBytes, flush: true);
  }

  static String _buildReadme(DateTime createdAt) {
    return '''
Local Minutes 문제 진단 자료

생성 시각: ${createdAt.toIso8601String()}

포함된 파일:
- diagnostics.json: 앱/기기/설정/모델/최근 회의 처리 상태 요약
- logs/crash.log: 앱이 기록한 충돌·예외 로그
- logs/crash.log.old: 로그 회전 백업이 있을 때만 포함

개인정보 안내:
- 원본 녹음 파일은 포함하지 않습니다.
- 전체 전사 텍스트는 포함하지 않습니다.
- 회의 요약 전문은 포함하지 않습니다.
- 최근 회의 정보는 제목 길이, 상태, 시간, 세그먼트 수, 처리 시간 같은 진단용 메타데이터만 포함합니다.
''';
  }

  static Future<Map<String, dynamic>> _buildDiagnosticsJson(
    DateTime createdAt,
  ) async {
    final appSupport = await getApplicationSupportDirectory();
    final package = await PackageInfo.fromPlatform();
    final settings = AppSettings.instance;
    final storagePath = settings.recordingsSavePath;

    return {
      'schemaVersion': 1,
      'createdAt': createdAt.toIso8601String(),
      'privacy': {
        'containsOriginalAudio': false,
        'containsFullTranscript': false,
        'containsSummaryBody': false,
        'containsMeetingTitles': false,
      },
      'app': {
        'appName': package.appName,
        'packageName': package.packageName,
        'version': package.version,
        'buildNumber': package.buildNumber,
        'appStoreComplianceMode': AppBuildConfig.appStoreComplianceMode,
        'calendarIntegrationEnabled': AppBuildConfig.enableCalendarIntegration,
      },
      'system': {
        'operatingSystem': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'localeName': Platform.localeName,
        'numberOfProcessors': Platform.numberOfProcessors,
      },
      'paths': {
        'applicationSupport': _redactHome(appSupport.path),
        'recordingsSavePathSet': storagePath.isNotEmpty,
        'recordingsSavePath': _redactHome(storagePath),
        'recordingsSavePathExists': storagePath.isNotEmpty
            ? await Directory(storagePath).exists()
            : false,
      },
      'settings': {
        'sttLanguage': settings.sttLanguage,
        'sttAccurateMode': settings.sttAccurateMode,
        'recordAutoGain': settings.recordAutoGain,
        'recordEchoCancel': settings.recordEchoCancel,
        'recordNormalize': settings.recordNormalize,
        'selectedLlmModel': settings.selectedLlmModel,
        'summaryTemplateId': settings.summaryTemplateId,
        'diarizationEnabled': settings.diarizationEnabled,
        'numSpeakersHint': settings.numSpeakersHint,
        'autoDeleteDays': settings.autoDeleteDays,
        'themeMode': settings.themeMode,
      },
      'models': await _modelStatuses(appSupport),
      'storage': {
        'applicationSupportBytes': await _dirSizeBytes(appSupport.path),
        'modelsBytes': await _dirSizeBytes('${appSupport.path}/models'),
        'recordingsFolderBytes': storagePath.isNotEmpty
            ? await _dirSizeBytes(storagePath)
            : 0,
      },
      'recentMeetings': await _recentMeetings(),
      'crashLog': {
        'path': _redactHome(await CrashLogService.instance.exportPath()),
        'sizeBytes': await CrashLogService.instance.sizeBytes(),
      },
    };
  }

  static Future<List<Map<String, dynamic>>> _modelStatuses(
    Directory appSupport,
  ) async {
    final modelsDir = '${appSupport.path}/models';
    final files = <({String label, String filename})>[
      (label: 'fastSpeechRecognition', filename: AppConstants.sttModelFileFast),
      (
        label: 'fastSpeechRecognitionCoreMl',
        filename: AppConstants.sttCoreMlEncoderFileFast,
      ),
      (
        label: 'accurateSpeechRecognition',
        filename: AppConstants.sttModelFileAccurate,
      ),
      (label: 'summaryDefault', filename: AppConstants.llmModelFileGemma4E2B),
      (
        label: 'summaryHighQuality',
        filename: AppConstants.llmModelFileQwen25_7B,
      ),
      (label: 'speakerSegment', filename: AppConstants.diarSegModelFile),
      (label: 'speakerEmbedding', filename: AppConstants.diarEmbModelFile),
    ];

    final result = <Map<String, dynamic>>[];
    for (final item in files) {
      final path = '$modelsDir/${item.filename}';
      final type = FileSystemEntity.typeSync(path);
      final exists = type != FileSystemEntityType.notFound;
      result.add({
        'label': item.label,
        'filename': item.filename,
        'exists': exists,
        'sizeBytes': exists
            ? type == FileSystemEntityType.directory
                  ? await _dirSizeBytes(path)
                  : await File(path).length().catchError((_) => 0)
            : 0,
        'expectedBytes': AppConstants.expectedModelBytes(item.filename),
      });
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>> _recentMeetings() async {
    final meetingRepo = MeetingRepositoryImpl(IsarService.instance.db);
    final summaryRepo = SummaryRepositoryImpl(IsarService.instance.db);
    final transcriptRepo = TranscriptRepositoryImpl(IsarService.instance.db);
    final meetings = (await meetingRepo.getAllMeetings()).take(10).toList();
    final rows = <Map<String, dynamic>>[];

    for (final meeting in meetings) {
      final transcripts = await transcriptRepo.getSegmentsByMeetingId(
        meeting.id,
      );
      final summary = await summaryRepo.getSummaryByMeetingId(meeting.id);
      final audioPath = meeting.audioFilePath;
      final audioExists = audioPath != null && await File(audioPath).exists();
      rows.add({
        'id': meeting.id,
        'createdAt': meeting.createdAt.toIso8601String(),
        'endedAt': meeting.endedAt?.toIso8601String(),
        'status': meeting.status.name,
        'durationSeconds': meeting.durationSeconds,
        'titleLength': meeting.title.length,
        'notesLength': meeting.notes.length,
        'tagsCount': meeting.tags.length,
        'agendaLength': meeting.agenda.length,
        'hasAudioFile': audioPath != null,
        'audioFileExists': audioExists,
        'audioFileBytes': audioExists
            ? await File(audioPath).length().catchError((_) => 0)
            : 0,
        'transcriptSegmentCount': transcripts.length,
        'transcriptTotalChars': transcripts.fold<int>(
          0,
          (sum, segment) => sum + segment.text.length,
        ),
        'hasSummary': summary != null,
        'summaryItemCounts': summary == null
            ? null
            : {
                'participants': summary.participants.length,
                'keyDiscussions': summary.keyDiscussions.length,
                'decisions': summary.decisions.length,
                'openQuestions': summary.openQuestions.length,
                'actionItemsJsonLength': summary.actionItemsJson.length,
              },
        'processingReport': meeting.processingReportJson.trim().isEmpty
            ? null
            : _tryDecodeJson(meeting.processingReportJson),
      });
    }
    return rows;
  }

  static dynamic _tryDecodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return {'parseError': true, 'rawLength': raw.length};
    }
  }

  static Future<int> _dirSizeBytes(String path) async {
    if (path.isEmpty) return 0;
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          total += await entity.length().catchError((_) => 0);
        }
      }
    } catch (_) {}
    return total;
  }

  static Future<String> _readTextTail(
    File file, {
    required int maxChars,
  }) async {
    try {
      final text = await file.readAsString();
      if (text.length <= maxChars) return text;
      return '... [앞부분 ${text.length - maxChars}자 생략]\n'
          '${text.substring(text.length - maxChars)}';
    } catch (e) {
      return '로그 읽기 실패: $e';
    }
  }

  static String _redactHome(String path) {
    if (path.isEmpty) return '';
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return path;
    return path.replaceFirst(home, '~');
  }

  static String _fileStamp(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}${two(date.month)}${two(date.day)}_'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}';
  }
}
