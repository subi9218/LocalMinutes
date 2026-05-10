import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meeting_assistant2/core/services/app_settings.dart';
import 'package:meeting_assistant2/core/services/diagnostic_export_service.dart';
import 'package:meeting_assistant2/core/services/isar_service.dart';
import 'package:meeting_assistant2/data/repositories/meeting_repository_impl.dart';
import 'package:meeting_assistant2/data/repositories/summary_repository_impl.dart';
import 'package:meeting_assistant2/data/repositories/transcript_repository_impl.dart';
import 'package:meeting_assistant2/domain/entities/meeting.dart';
import 'package:meeting_assistant2/domain/entities/summary.dart';
import 'package:meeting_assistant2/domain/entities/transcript.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnostic export creates privacy-safe zip', () async {
    final tempRoot = await Directory.systemTemp.createTemp('diag_export_test_');
    final appSupport = Directory('${tempRoot.path}/app_support');
    final recordings = Directory('${tempRoot.path}/recordings');
    await appSupport.create(recursive: true);
    await recordings.create(recursive: true);

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getApplicationSupportDirectory':
              return appSupport.path;
            case 'getTemporaryDirectory':
              return tempRoot.path;
            default:
              return tempRoot.path;
          }
        });

    PackageInfo.setMockInitialValues(
      appName: '적자생존',
      packageName: 'com.subi9218.localminutes',
      version: '2.1.1',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'recordingsSavePath': recordings.path,
      'selectedLlmModel': 'gemma4_e2b',
      'summaryTemplateId': 'general',
    });

    final rootIsarDylib = File('${Directory.current.path}/libisar.dylib');
    final cacheIsarDylib = File(
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
      'isar_flutter_libs-3.1.0+1/macos/libisar.dylib',
    );
    if (!await rootIsarDylib.exists() && await cacheIsarDylib.exists()) {
      await cacheIsarDylib.copy(rootIsarDylib.path);
    }

    await AppSettings.init();
    await IsarService.instance.init();

    const secretTitle = 'SECRET_DIAGNOSTIC_TITLE';
    const secretTranscript = 'SECRET_DIAGNOSTIC_TRANSCRIPT';
    const secretSummary = 'SECRET_DIAGNOSTIC_SUMMARY';

    final meetingRepo = MeetingRepositoryImpl(IsarService.instance.db);
    final transcriptRepo = TranscriptRepositoryImpl(IsarService.instance.db);
    final summaryRepo = SummaryRepositoryImpl(IsarService.instance.db);
    final now = DateTime(2026, 5, 1, 10, 30);
    final meeting = Meeting()
      ..title = secretTitle
      ..createdAt = now
      ..endedAt = now.add(const Duration(minutes: 3))
      ..status = MeetingStatus.done
      ..audioFilePath = '${recordings.path}/secret.wav'
      ..transcriptPreview = secretTranscript
      ..notes = 'SECRET_DIAGNOSTIC_NOTES'
      ..processingReportJson = jsonEncode({
        'sttElapsedMs': 1000,
        'summaryElapsedMs': 2000,
      });
    final meetingId = await meetingRepo.saveMeeting(meeting);

    await transcriptRepo.saveSegment(
      Transcript()
        ..meetingId = meetingId
        ..segmentIndex = 0
        ..text = secretTranscript
        ..startTimeSeconds = 0
        ..endTimeSeconds = 10
        ..createdAt = now,
    );
    await summaryRepo.saveSummary(
      Summary()
        ..meetingId = meetingId
        ..meetingTitle = secretSummary
        ..meetingDate = now
        ..participants = const ['A']
        ..keyDiscussions = const [secretSummary]
        ..decisions = const []
        ..actionItemsJson = '[]'
        ..openQuestions = const []
        ..createdAt = now,
    );

    final out = File('${tempRoot.path}/diagnostics.zip');
    await DiagnosticExportService.exportToPath(out.path);

    expect(await out.exists(), isTrue);
    final archive = ZipDecoder().decodeBytes(await out.readAsBytes());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, contains('README.txt'));
    expect(names, contains('diagnostics.json'));
    expect(names, contains('logs/crash.log'));

    String fileText(String name) {
      final file = archive.files.firstWhere((f) => f.name == name);
      return utf8.decode(file.content as List<int>);
    }

    final diagnosticsText = fileText('diagnostics.json');
    final diagnostics = jsonDecode(diagnosticsText) as Map<String, dynamic>;
    expect(diagnostics['privacy']['containsOriginalAudio'], isFalse);
    expect(diagnostics['privacy']['containsFullTranscript'], isFalse);
    expect(diagnostics['privacy']['containsSummaryBody'], isFalse);
    expect(diagnostics['privacy']['containsMeetingTitles'], isFalse);

    final allZipText = archive.files
        .where((f) => f.isFile)
        .map((f) => utf8.decode(f.content as List<int>, allowMalformed: true))
        .join('\n');
    expect(allZipText, isNot(contains(secretTitle)));
    expect(allZipText, isNot(contains(secretTranscript)));
    expect(allZipText, isNot(contains(secretSummary)));

    await IsarService.instance.db.close(deleteFromDisk: true);
    if (await rootIsarDylib.exists()) await rootIsarDylib.delete();
    await tempRoot.delete(recursive: true);
  });
}
