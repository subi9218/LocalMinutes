import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/chunked_summarizer.dart';
import '../../core/services/crash_log_service.dart';
import '../../core/services/isar_service.dart';
import '../../core/services/summary_templates.dart';
import '../../core/utils/transcript_text_cleaner.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/entities/summary.dart';
import 'diarization_service.dart';
import 'stt_service.dart';
import '../repositories/meeting_repository_impl.dart';
import '../repositories/transcript_repository_impl.dart';
import '../repositories/summary_repository_impl.dart';

enum PipelineStage {
  idle,
  loadingStt,
  transcribing,
  unloadingStt,
  diarizing,
  loadingLlm,
  summarizing,
  savingResult,
  done,
  error,
}

class PipelineResult {
  final int meetingId;
  final int segmentCount;
  final Summary summary;

  const PipelineResult({
    required this.meetingId,
    required this.segmentCount,
    required this.summary,
  });
}

typedef PipelineEvent = ({
  PipelineStage stage,
  PipelineResult? result,
  String? error,
});

class PipelineService {
  static final instance = PipelineService._();
  PipelineService._();

  static const _stageLabels = {
    PipelineStage.idle: '대기 중',
    PipelineStage.loadingStt: 'Whisper 모델 로드 중... (~2 GB)',
    PipelineStage.transcribing: '한국어 STT 전사 중...',
    PipelineStage.unloadingStt: 'STT 모델 해제 중...',
    PipelineStage.diarizing: '발화자 라벨 생성 중... 긴 녹음은 몇 분 걸릴 수 있습니다.',
    PipelineStage.loadingLlm: '요약 모델 로드 중... (~6–8 GB)',
    PipelineStage.summarizing: '회의 요약 생성 중...',
    PipelineStage.savingResult: 'Isar DB 저장 중...',
    PipelineStage.done: '완료',
    PipelineStage.error: '오류 발생',
  };

  static String labelOf(PipelineStage stage) => _stageLabels[stage] ?? '';

  /// WAV 파일 전체 파이프라인 실행.
  /// Stream으로 진행 단계를 리포팅하고, 완료 시 PipelineResult를 포함한 이벤트를 전달.
  Stream<PipelineEvent> run({
    required String wavPath,
    required String meetingTitle,
  }) async* {
    final manager = OnDeviceModelManager.instance;
    final db = IsarService.instance.db;
    final meetingRepo = MeetingRepositoryImpl(db);
    final transcriptRepo = TranscriptRepositoryImpl(db);
    final summaryRepo = SummaryRepositoryImpl(db);

    final appSupport = await getApplicationSupportDirectory();
    final sttModelPath =
        '${appSupport.path}/models/${AppSettings.instance.currentSttModelFile}';
    final llmModelPath =
        '${appSupport.path}/models/${AppSettings.instance.currentLlmModelFile}';

    final now = DateTime.now();
    final meeting = Meeting()
      ..title = meetingTitle
      ..createdAt = now
      ..status = MeetingStatus.transcribing;
    final meetingId = await meetingRepo.saveMeeting(meeting);
    meeting.id = meetingId;

    try {
      // ── Step 1: STT 로드 + 전사 ──────────────────────────────
      yield (stage: PipelineStage.loadingStt, result: null, error: null);
      await manager.loadStt(sttModelPath);

      yield (stage: PipelineStage.transcribing, result: null, error: null);
      final segments = await SttService.instance.transcribeFile(wavPath);

      // ── 화자 분리 (옵션) ────────────────────────────────────
      List<String?> speakerLabels = List<String?>.filled(segments.length, null);
      if (AppSettings.instance.diarizationEnabled &&
          await DiarizationService.instance.modelsReady()) {
        try {
          yield (stage: PipelineStage.diarizing, result: null, error: null);
          final diar = await DiarizationService.instance.diarizeWav(
            wavPath,
            numSpeakersHint: AppSettings.instance.numSpeakersHint,
          );
          speakerLabels = DiarizationService.assignLabels(
            sttStartMs: segments.map((s) => s.startMs).toList(),
            sttEndMs: segments.map((s) => s.endMs).toList(),
            diar: diar,
          );
        } catch (e) {
          // 화자 분리 실패는 파이프라인 치명 오류로 취급하지 않음 — 라벨 없이 진행
          CrashLogService.instance.recordCaught(
            e,
            StackTrace.current,
            context: 'pipelineDiarization',
          );
        }
      }

      // Transcript 저장
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        final transcript = Transcript()
          ..meetingId = meetingId
          ..segmentIndex = i
          ..text = seg.text
          ..startTimeSeconds = seg.startMs / 1000.0
          ..endTimeSeconds = seg.endMs / 1000.0
          ..speakerLabel = speakerLabels[i]
          ..createdAt = now;
        await transcriptRepo.saveSegment(transcript);
      }

      // Meeting 미리보기 업데이트
      final fullText = segments.map((s) => s.text).join(' ');
      meeting.transcriptPreview = fullText.length > 200
          ? fullText.substring(0, 200)
          : fullText;
      await meetingRepo.updateMeeting(meeting);

      // ── Step 2: STT 해제 ─────────────────────────────────────
      yield (stage: PipelineStage.unloadingStt, result: null, error: null);
      await manager.unloadStt();

      // ── Step 3: LLM 로드 + 요약 ──────────────────────────────
      yield (stage: PipelineStage.loadingLlm, result: null, error: null);
      // nCtx 8192 — 긴 회의(전사본+템플릿+단어집+메모) 4096 초과 "KV 캐시 구성 실패" 방지.
      // Gemma 3n E2B는 32K까지 지원, KV 캐시 메모리 ~1GB로 증가하나 여유 있음.
      await manager.loadLlm(llmModelPath, nCtx: 8192, nBatch: 512);

      yield (stage: PipelineStage.summarizing, result: null, error: null);
      meeting.status = MeetingStatus.summarizing;
      await meetingRepo.updateMeeting(meeting);

      final hasDiar = speakerLabels.any((l) => l != null);
      final transcriptTextRaw = segments
          .asMap()
          .entries
          .map((e) {
            final i = e.key;
            final s = e.value;
            final label = hasDiar && speakerLabels[i] != null
                ? '화자 ${speakerLabels[i]}: '
                : '';
            return '[${s.timestampStr}] $label${s.text}';
          })
          .join('\n');
      final transcriptText = TranscriptTextCleaner.cleanForSummary(
        transcriptTextRaw,
      );
      final dateStr =
          '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final raw = await ChunkedSummarizer.summarize(
        transcript: transcriptText,
        dateStr: dateStr,
        instruction: SummaryTemplates.resolveInstruction(
          overrideId: meeting.summaryTemplateId,
        ),
        maxTokens: 2500,
        speedMode: AppSettings.instance.summarySpeedMode,
      );

      final summary = _parseJsonOutput(raw, meetingId, now);

      // ── Step 4: DB 저장 + LLM 해제 ───────────────────────────
      yield (stage: PipelineStage.savingResult, result: null, error: null);
      await summaryRepo.saveSummary(summary);

      meeting.status = MeetingStatus.done;
      meeting.endedAt = DateTime.now();
      await meetingRepo.updateMeeting(meeting);

      await manager.unloadLlm();

      final result = PipelineResult(
        meetingId: meetingId,
        segmentCount: segments.length,
        summary: summary,
      );
      yield (stage: PipelineStage.done, result: result, error: null);
    } catch (e) {
      // 오류 시 모델 정리 + Meeting 상태 업데이트
      await manager.unloadStt().catchError((_) {});
      await manager.unloadLlm().catchError((_) {});
      meeting.status = MeetingStatus.error;
      await meetingRepo.updateMeeting(meeting).catchError((_) {});
      yield (stage: PipelineStage.error, result: null, error: e.toString());
    }
  }

  /// JSON 파싱 — 여러 전략으로 LLM 출력에서 JSON 추출
  static Summary _parseJsonOutput(
    String raw,
    int meetingId,
    DateTime meetingDate,
  ) {
    Map<String, dynamic>? map;

    // 전략 1: ```json ... ``` 코드 블록
    final codeBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(raw);
    if (codeBlock != null) {
      map = _tryDecode(codeBlock.group(1)?.trim() ?? '');
    }

    // 전략 2: 첫 { ~ 마지막 } 추출
    if (map == null) {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start != -1 && end > start) {
        map = _tryDecode(raw.substring(start, end + 1));
      }
    }

    // 전략 3: 불완전 JSON 복구 (끝이 잘린 경우 배열/객체 닫기)
    if (map == null) {
      final start = raw.indexOf('{');
      if (start != -1) {
        final partial = raw.substring(start);
        map = _tryDecode(_repairJson(partial));
      }
    }

    if (map != null) {
      return _buildSummary(map, meetingId, meetingDate);
    }

    // 전략 4: JSON 파싱 완전 실패 → 자유 텍스트 파싱
    return _parseFreeText(raw, meetingId, meetingDate);
  }

  /// JSON 디코딩 시도 — 실패 시 null 반환
  static Map<String, dynamic>? _tryDecode(String s) {
    if (s.isEmpty) return null;
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {
      // trailing comma 제거 후 재시도
      final fixed = s
          .replaceAll(RegExp(r',\s*}'), '}')
          .replaceAll(RegExp(r',\s*]'), ']');
      try {
        final v = jsonDecode(fixed);
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }
    return null;
  }

  /// 잘린 JSON에 닫힌 괄호 추가해 복구 시도
  static String _repairJson(String s) {
    final openBraces = '{'.allMatches(s).length - '}'.allMatches(s).length;
    final openBrackets = '['.allMatches(s).length - ']'.allMatches(s).length;
    final buf = StringBuffer(s.trimRight());
    // 마지막 문자가 , 이면 제거
    if (buf.toString().endsWith(',')) {
      final str = buf.toString();
      return str.substring(0, str.length - 1) +
          ']' * openBrackets.clamp(0, 10) +
          '}' * openBraces.clamp(0, 10);
    }
    for (int i = 0; i < openBrackets.clamp(0, 10); i++) {
      buf.write(']');
    }
    for (int i = 0; i < openBraces.clamp(0, 10); i++) {
      buf.write('}');
    }
    return buf.toString();
  }

  /// JSON 파싱 성공 시 Summary 생성
  static Summary _buildSummary(
    Map<String, dynamic> map,
    int meetingId,
    DateTime meetingDate,
  ) {
    List<String> asList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String && v.isNotEmpty) return [v];
      return [];
    }

    final rawItems = map['actionItems'];
    String actionItemsJson = '[]';
    if (rawItems is List) {
      try {
        final items = rawItems
            .whereType<Map<String, dynamic>>()
            .map((e) => ActionItem.fromJson(e).toJson())
            .toList();
        actionItemsJson = jsonEncode(items);
      } catch (_) {}
    }

    return Summary()
      ..meetingId = meetingId
      ..meetingTitle = map['meetingTitle'] as String? ?? '회의 요약'
      ..meetingDate = meetingDate
      ..participants = asList(map['participants'])
      ..keyDiscussions = asList(map['keyDiscussions'])
      ..decisions = asList(map['decisions'])
      ..actionItemsJson = actionItemsJson
      ..openQuestions = asList(map['openQuestions'])
      ..createdAt = DateTime.now();
  }

  /// JSON 완전 실패 → 줄 단위 자유 텍스트 파싱 (최후 수단)
  static Summary _parseFreeText(
    String raw,
    int meetingId,
    DateTime meetingDate,
  ) {
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 의미 있는 내용이 있으면 keyDiscussions에 넣기
    final discussions = lines
        .where((l) => !l.startsWith('{') && !l.startsWith('}') && l.length > 5)
        .take(5)
        .toList();

    return Summary()
      ..meetingId = meetingId
      ..meetingTitle = '회의 요약'
      ..meetingDate = meetingDate
      ..participants = []
      ..keyDiscussions = discussions.isNotEmpty
          ? discussions
          : ['요약 생성 중 파싱 오류가 발생했습니다.']
      ..decisions = []
      ..actionItemsJson = '[]'
      ..openQuestions = []
      ..createdAt = DateTime.now();
  }
}
