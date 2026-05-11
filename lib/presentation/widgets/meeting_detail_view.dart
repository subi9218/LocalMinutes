import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/crash_log_service.dart';
import '../../core/services/export_service.dart';
import '../../core/services/isar_service.dart';
import '../../core/services/chunked_summarizer.dart';
import '../../core/services/meeting_quality.dart';
import '../../core/services/speaker_stats.dart';
import '../../core/services/summary_templates.dart';
import '../../core/services/tag_extractor.dart';
import '../../core/services/user_error_message.dart';
import '../../core/utils/auto_bullet.dart';
import '../../core/utils/transcript_text_cleaner.dart';
import '../../core/utils/summary_parser.dart';
import '../../core/utils/transcript_corrector.dart';
import '../../data/datasources/diarization_service.dart';
import '../../data/datasources/llm_service.dart';
import '../../data/datasources/stt_service.dart';
import '../../data/repositories/glossary_repository_impl.dart';
import '../../domain/entities/glossary_entry.dart';
import '../../data/repositories/meeting_repository_impl.dart';
import '../../data/repositories/summary_repository_impl.dart';
import '../../data/repositories/summary_version_repository_impl.dart';
import '../../data/repositories/transcript_repository_impl.dart';
import '../../domain/entities/summary_version.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/meeting_group.dart';
import '../../domain/entities/meeting_processing_report.dart';
import '../../domain/entities/summary.dart';
import '../../domain/entities/transcript.dart';
import '../providers/meeting_providers.dart';

class MeetingDetailView extends ConsumerStatefulWidget {
  final int meetingId;
  const MeetingDetailView({super.key, required this.meetingId});

  @override
  ConsumerState<MeetingDetailView> createState() => _MeetingDetailViewState();
}

class _MeetingDetailViewState extends ConsumerState<MeetingDetailView> {
  bool _isSummarizing = false;
  bool _cancelSummaryRequested = false;
  String _summarizingStatus = '';
  double _summarizingProgress = 0.0; // 0.0~1.0
  DateTime? _summaryStartTime;
  bool _isExtractingTerms = false;
  bool _isRerunningStt = false;
  bool _cancelRerunSttRequested = false;
  String _rerunSttStatus = '';
  double _rerunSttProgress = 0.0; // 0.0 ~ 1.0 (processedMs / totalMs)
  int _rerunSttProcessedMs = 0;
  int _rerunSttTotalMs = 0;
  DateTime? _rerunSttStartTime;
  Timer? _rerunTicker; // 경과시간 1초마다 재빌드

  /// 전사 패널 오디오 플레이어 seek 핸들러.
  /// 자식 _TranscriptWithAudio가 init 시 등록, dispose 시 null 처리.
  /// 근거 다이얼로그에서 타임스탬프 클릭 시 호출됨.
  /// 반환: null=오디오 재생 성공, 외에는 실패 사유 문자열.
  Future<String?> Function(double sec)? _seekTranscriptAudio;
  double _summaryPaneRatio = 0.55;

  String _durationKrFromMs(int ms) {
    if (ms <= 0) return '-';
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes분 $seconds초';
  }

  @override
  void dispose() {
    _rerunTicker?.cancel();
    super.dispose();
  }

  void _requestCancelSummary() {
    if (!_isSummarizing || _cancelSummaryRequested) return;
    setState(() {
      _cancelSummaryRequested = true;
      _summarizingStatus = '요약 중지 요청 중...';
    });
    LlmService.instance.requestCancelActiveGeneration();
  }

  void _requestCancelRerunStt() {
    if (!_isRerunningStt || _cancelRerunSttRequested) return;
    setState(() {
      _cancelRerunSttRequested = true;
      _rerunSttStatus = '음성 인식 중지 요청 중... 현재 청크를 마무리하고 멈춥니다.';
    });
  }

  String? _nativeTaskBlockReason(String actionLabel) {
    final active = OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (active == null) return null;
    return '현재 $active 작업 중입니다. 완료 후 $actionLabel을(를) 다시 시도해주세요.';
  }

  void _showNativeTaskBlocked(String actionLabel) {
    final reason = _nativeTaskBlockReason(actionLabel);
    if (reason == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(reason), backgroundColor: Colors.orange.shade700),
    );
  }

  Widget _withDisabledReason(String? reason, Widget child) {
    if (reason == null) return child;
    return MacosTooltip(message: reason, child: child);
  }

  Duration _meetingAudioDuration(Meeting meeting) {
    if (meeting.durationSeconds > 0) {
      return Duration(seconds: meeting.durationSeconds);
    }
    return Duration.zero;
  }

  Duration _boundedEstimate(
    Duration audio,
    double ratio, {
    required int minSeconds,
    required int maxSeconds,
  }) {
    if (audio <= Duration.zero) return Duration.zero;
    final seconds = (audio.inMilliseconds / 1000 * ratio).round();
    return Duration(seconds: seconds.clamp(minSeconds, maxSeconds).toInt());
  }

  double? _previousSttEstimateRatio(
    MeetingProcessingReport report,
    String modelFile,
    Duration audioDuration,
  ) {
    if (audioDuration <= Duration.zero ||
        report.sttRtf <= 0 ||
        report.sttAudioMs <= 0 ||
        report.sttModel != modelFile) {
      return null;
    }

    final audioMs = audioDuration.inMilliseconds;
    final audioDiffRatio = (report.sttAudioMs - audioMs).abs() / audioMs;
    if (audioDiffRatio > 0.15) return null;

    return (report.sttRtf * 1.12).clamp(0.06, 1.2).toDouble();
  }

  String _durationKr(Duration duration) {
    if (duration <= Duration.zero) return '-';
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes분 $seconds초';
  }

  /// Meeting.bookmarksJson을 Bookmark 리스트로 파싱
  static List<Bookmark> _parseMeetingBookmarks(Meeting? meeting) {
    if (meeting == null) return const [];
    final raw = meeting.bookmarksJson;
    if (raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 사이드바 검색 스니펫 텍스트로 시작하는 첫 전사 세그먼트로 점프.
  /// 검색 결과의 snippet은 "...앞뒤 컨텍스트 + 매치된 단어..." 형태로
  /// 정확히 같은 substring을 갖는 세그먼트를 찾기 어려우므로,
  /// 토큰 일치 점수로 가장 잘 매칭되는 세그먼트를 선택한다.
  Future<void> _jumpToSnippet(String snippet) async {
    final transcriptsAsync = ref.read(
      meetingTranscriptProvider(widget.meetingId),
    );
    final segments = transcriptsAsync.asData?.value;
    if (segments == null || segments.isEmpty) return;

    // 스니펫에서 핵심 토큰만 추출 (3자 이상)
    final tokens = snippet
        .toLowerCase()
        .replaceAll(RegExp(r'[…"\[\](){},.!?·:;]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3)
        .toList();
    if (tokens.isEmpty) return;

    int bestIdx = -1;
    int bestScore = 0;
    for (int i = 0; i < segments.length; i++) {
      final lower = segments[i].text.toLowerCase();
      int score = 0;
      for (final t in tokens) {
        if (lower.contains(t)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }
    if (bestIdx < 0 || bestScore == 0) return;

    final startSec = segments[bestIdx].startTimeSeconds;
    final messenger = ScaffoldMessenger.of(context);
    final err = await _seekTranscriptAudio?.call(startSec);
    if (!mounted) return;
    final ok = err == null;
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: ok ? 2 : 4),
        content: Text(
          ok
              ? '검색 결과 — ${_secStr(startSec)} 시점 재생'
              : '검색 결과 — ${_secStr(startSec)} 시점 전사로 이동 · $err',
        ),
        backgroundColor: ok ? Colors.indigo.shade600 : Colors.blueGrey.shade600,
      ),
    );
  }

  /// evidenceJson에서 [key]의 `List<String>`를 안전하게 추출
  List<String> _evidenceList(Summary s, String key) {
    try {
      final m = jsonDecode(s.evidenceJson) as Map<String, dynamic>;
      final l = m[key];
      if (l is List) return l.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  /// 지정 인덱스의 evidence (없으면 빈 문자열)
  String _evidenceAt(Summary s, String key, int idx) {
    if (idx < 0) return '';
    final l = _evidenceList(s, key);
    if (idx >= l.length) return '';
    return l[idx];
  }

  /// 항목별 근거 클릭 처리.
  /// LLM이 명시한 [evidenceTs]가 있으면 해당 시간으로 직접 점프.
  /// 없으면 v1 키워드/유사도 후보 다이얼로그(_showEvidenceForText) 표시.
  Future<void> _handleEvidenceTap({
    required String title,
    required String query,
    required List<Transcript> transcripts,
    required String evidenceTs,
  }) async {
    if (evidenceTs.trim().isEmpty) {
      _showEvidenceForText(
        title: title,
        query: query,
        transcripts: transcripts,
      );
      return;
    }
    final sec = SummaryEvidence.parseStartSec(evidenceTs);
    if (sec == null) {
      _showEvidenceForText(
        title: title,
        query: query,
        transcripts: transcripts,
      );
      return;
    }
    // LLM 시간 명시 → 즉시 점프
    final messenger = ScaffoldMessenger.of(context);
    final audioErr = await _seekTranscriptAudio?.call(sec);
    if (!mounted) return;
    final ok = audioErr == null;
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: ok ? 2 : 4),
        content: Text(
          ok
              ? '$evidenceTs 시점 — 전사로 이동 + 오디오 재생'
              : '$evidenceTs 시점 전사로 이동 · $audioErr',
        ),
        backgroundColor: ok ? Colors.indigo.shade600 : Colors.blueGrey.shade600,
      ),
    );
  }

  void _showEvidenceForText({
    required String title,
    required String query,
    required List<Transcript> transcripts,
  }) {
    final candidates = _findEvidenceCandidates(query, transcripts);
    final needsCheck = candidates.isEmpty || candidates.first.score < 0.24;

    showMacosAlertDialog<void>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const Icon(Icons.manage_search_outlined, size: 48),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(title)),
            if (needsCheck) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  '확인 필요',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ],
        ),
        message: SizedBox(
          width: 620,
          height: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  query,
                  style: const TextStyle(fontSize: 13, height: 1.45),
                ),
              ),
              const SizedBox(height: 12),
              if (candidates.isEmpty)
                Text(
                  '전사본에서 직접 연결할 만한 구간을 찾지 못했습니다.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const Divider(height: 14),
                    itemBuilder: (ctx, i) {
                      final c = candidates[i];
                      final speaker = c.transcript.speakerLabel == null
                          ? ''
                          : ' · 화자 ${c.transcript.speakerLabel}';
                      final canJump = _seekTranscriptAudio != null;
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: !canJump
                            ? null
                            : () async {
                                final navigator = Navigator.of(ctx);
                                final messenger = ScaffoldMessenger.of(context);
                                final startSec = c.transcript.startTimeSeconds;
                                final audioErr = await _seekTranscriptAudio
                                    ?.call(startSec);
                                if (!mounted) return;
                                final okJump = audioErr == null;
                                navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    duration: Duration(seconds: okJump ? 2 : 4),
                                    content: Text(
                                      okJump
                                          ? '${_secStr(startSec)} 시점 — 전사로 이동 + 오디오 재생'
                                          : '${_secStr(startSec)} 시점 전사로 이동 · $audioErr',
                                    ),
                                    backgroundColor: okJump
                                        ? Colors.indigo.shade600
                                        : Colors.blueGrey.shade600,
                                  ),
                                );
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.play_circle_outline,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_secStr(c.transcript.startTimeSeconds)} → ${_secStr(c.transcript.endTimeSeconds)}$speaker',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  if (canJump) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '클릭하여 이동',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  Text(
                                    '유사도 ${(c.score * 100).clamp(0, 99).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c.transcript.text,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('닫기'),
        ),
      ),
    );
  }

  List<_EvidenceCandidate> _findEvidenceCandidates(
    String query,
    List<Transcript> transcripts,
  ) {
    if (query.trim().isEmpty || transcripts.isEmpty) return const [];

    final queryTokens = _keywords(query);
    final queryNorm = _normEvidence(query);
    final candidates = <_EvidenceCandidate>[];

    for (final t in transcripts) {
      final text = t.text.trim();
      if (text.isEmpty) continue;

      final textTokens = _keywords(text);
      var tokenHits = 0;
      for (final token in queryTokens) {
        if (textTokens.contains(token) || text.contains(token)) {
          tokenHits++;
        }
      }
      final tokenScore = queryTokens.isEmpty
          ? 0.0
          : tokenHits / queryTokens.length;
      final phraseScore = _charBigramSimilarity(queryNorm, _normEvidence(text));
      final score = (tokenScore * 0.7) + (phraseScore * 0.3);
      if (score >= 0.12 || tokenHits >= 2) {
        candidates.add(_EvidenceCandidate(transcript: t, score: score));
      }
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.transcript.startTimeSeconds.compareTo(
        b.transcript.startTimeSeconds,
      );
    });
    return candidates.take(5).toList();
  }

  Set<String> _keywords(String input) {
    const stopwords = {
      '그리고',
      '그래서',
      '그런데',
      '그러면',
      '이렇게',
      '저희가',
      '것으로',
      '있는',
      '없는',
      '합니다',
      '했습니다',
      '하기로',
      '대한',
      '관련',
      '미언급',
    };
    return RegExp(r'[A-Za-z0-9가-힣]+')
        .allMatches(input)
        .map((m) => m.group(0)!.toLowerCase())
        .where((token) => token.length >= 2 && !stopwords.contains(token))
        .toSet();
  }

  String _normEvidence(String input) => input
      .replaceAll(RegExp(r'[\s.,!?…·"“”‘’()\[\]{}:;~\-_/]+'), '')
      .toLowerCase();

  double _charBigramSimilarity(String a, String b) {
    if (a.length < 2 || b.length < 2) return 0;
    final aSet = <String>{};
    final bSet = <String>{};
    for (var i = 0; i < a.length - 1; i++) {
      aSet.add(a.substring(i, i + 2));
    }
    for (var i = 0; i < b.length - 1; i++) {
      bSet.add(b.substring(i, i + 2));
    }
    var hit = 0;
    for (final gram in aSet) {
      if (bSet.contains(gram)) hit++;
    }
    final union = {...aSet, ...bSet}.length;
    return union == 0 ? 0 : hit / union;
  }

  // ── 템플릿 선택 다이얼로그 ────────────────────────────────────
  Future<_TemplatePickResult> _pickTemplateDialog(String? currentId) async {
    // null = 전역 설정 따라감, customId = 설정의 커스텀 프롬프트
    String? selected = currentId;
    SummaryStyleMode style = SummaryStyleMode.standard;
    final result = await showDialog<_TemplatePickResult>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            Widget tile(String? id, String label, String desc) {
              return RadioListTile<String?>(
                value: id,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: Text(label, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  desc,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              );
            }

            final scheme = Theme.of(ctx).colorScheme;
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 40,
                vertical: 32,
              ),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 780,
                  maxHeight: 620,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 34),
                            SizedBox(width: 12),
                            Text(
                              '회의 유형 / 재생성 스타일',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Flexible(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          0,
                                          10,
                                          4,
                                        ),
                                        child: Text(
                                          '회의 유형',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      RadioGroup<String?>(
                                        groupValue: selected,
                                        onChanged: (v) =>
                                            setStateDialog(() => selected = v),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            tile(
                                              null,
                                              '설정값 사용',
                                              '설정 화면에서 지정한 회의 유형을 그대로 적용',
                                            ),
                                            const Divider(height: 8),
                                            for (final t
                                                in SummaryTemplates.presets)
                                              tile(t.id, t.name, t.description),
                                            tile(
                                              SummaryTemplates.customId1,
                                              '커스텀1',
                                              '설정에 저장된 사용자 지침 슬롯 1 사용',
                                            ),
                                            tile(
                                              SummaryTemplates.customId2,
                                              '커스텀2',
                                              '설정에 저장된 사용자 지침 슬롯 2 사용',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 22),
                              Container(width: 1, color: scheme.outlineVariant),
                              const SizedBox(width: 22),
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '재생성 스타일',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        MacosTooltip(
                                          message:
                                              '같은 전사본을 다른 톤/길이로 다시 분석합니다.\n'
                                              '회의 유형 위에 누적 적용됩니다.',
                                          child: Icon(
                                            Icons.info_outline,
                                            size: 14,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final m in SummaryStyleMode.values)
                                          ChoiceChip(
                                            label: Text(
                                              m.displayName,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                            selected: style == m,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onSelected: (_) =>
                                                setStateDialog(() => style = m),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest
                                            .withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        style.description,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Spacer(),
                            SizedBox(
                              width: 150,
                              child: PushButton(
                                controlSize: ControlSize.large,
                                secondary: true,
                                onPressed: () => Navigator.of(
                                  ctx,
                                ).pop(const _TemplatePickResult.cancelled()),
                                child: const Text('취소'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 170,
                              child: PushButton(
                                controlSize: ControlSize.large,
                                onPressed: () => Navigator.of(ctx).pop(
                                  _TemplatePickResult(
                                    selected,
                                    styleMode: style,
                                  ),
                                ),
                                child: const Text('요약 실행'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    return result ?? const _TemplatePickResult.cancelled();
  }

  // ── LLM 선택 다이얼로그 ───────────────────────────────────────
  /// 현재 설치된 LLM 목록에서 사용자가 선택. 설치된 게 1개뿐이면 바로 그 id 반환.
  /// null 반환 시 사용자가 취소.
  Future<String?> _pickLlmDialog() async {
    final appSupport = await getApplicationSupportDirectory();
    final modelsDir = '${appSupport.path}/models';
    final installed = <String>[];
    for (final id in AppSettings.availableLlmModelIds) {
      final path = '$modelsDir/${AppSettings.llmModelFileFor(id)}';
      if (await File(path).exists()) installed.add(id);
    }

    if (installed.isEmpty) return null;
    if (installed.length == 1) return installed.first;

    String selected = AppSettings.instance.selectedLlmModel;
    if (!installed.contains(selected)) selected = installed.first;

    String labelOf(String id) {
      switch (id) {
        case 'qwen25_7b':
          return 'Qwen 2.5 7B';
        default:
          return 'Gemma 4 E2B';
      }
    }

    String tipOf(String id) {
      switch (id) {
        case 'qwen25_7b':
          return 'Qwen 2.5 7B Instruct Q4_K_M (~4.7GB)\n한국어·구조화 출력 강함';
        default:
          return 'Gemma 4 E2B Q8_0 (~3GB)\n빠름, 기본 품질';
      }
    }

    if (!mounted) return null;
    return showMacosAlertDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return MacosAlertDialog(
            appIcon: const Icon(Icons.auto_awesome, size: 48),
            title: const Text('요약 모델 선택'),
            message: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '마우스를 올리면 모델 설명이 보입니다.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: installed.map((id) {
                      return MacosTooltip(
                        message: tipOf(id),
                        child: ChoiceChip(
                          label: Text(
                            labelOf(id),
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: selected == id,
                          onSelected: (_) => setD(() => selected = id),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: const Text('요약 실행'),
            ),
            secondaryButton: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('취소'),
            ),
          );
        },
      ),
    );
  }

  // ── 재요약 실행 ────────────────────────────────────────────────
  Future<void> _runResummarize(
    List<Transcript> transcripts,
    Summary? currentSummary, {
    String notes = '',
    Meeting? meeting,
  }) async {
    if (transcripts.isEmpty || _isSummarizing) return;
    if (_nativeTaskBlockReason('요약') != null) {
      _showNativeTaskBlocked('요약');
      return;
    }

    // 템플릿 선택 다이얼로그 — 현재 meeting.summaryTemplateId를 기본값으로
    final picked = await _pickTemplateDialog(meeting?.summaryTemplateId);
    if (picked.cancelled) return;

    // LLM 선택 다이얼로그
    final llmId = await _pickLlmDialog();
    if (llmId == null) return;
    // 선택값을 전역 기본값으로도 저장 (다음번 편의)
    await AppSettings.instance.setSelectedLlmModel(llmId);

    // 선택 결과를 meeting에 반영(변경 시에만)
    if (meeting != null && picked.templateId != meeting.summaryTemplateId) {
      meeting.summaryTemplateId = picked.templateId;
      await MeetingRepositoryImpl(
        IsarService.instance.db,
      ).updateMeeting(meeting);
    }
    setState(() {
      _isSummarizing = true;
      _cancelSummaryRequested = false;
      _summarizingStatus = '요약 모델 준비 중...';
      _summarizingProgress = 0.0;
      _summaryStartTime = DateTime.now();
    });

    try {
      final appSupport = await getApplicationSupportDirectory();
      final llmPath =
          '${appSupport.path}/models/${AppSettings.llmModelFileFor(llmId)}';

      // nCtx 8192 — 긴 회의의 "프롬프트 KV 캐시 구성 실패" 방지 (4096 초과 대응).
      await OnDeviceModelManager.instance.loadLlm(
        llmPath,
        nCtx: 8192,
        nBatch: 512,
      );
      if (_cancelSummaryRequested) throw const SummaryCancelledException();

      if (mounted) setState(() => _summarizingStatus = '회의 내용 재분석 중...');

      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final hasDiar = transcripts.any((t) => t.speakerLabel != null);
      final transcriptTextRaw = transcripts
          .map((t) {
            final label = hasDiar && t.speakerLabel != null
                ? '화자 ${t.speakerLabel}: '
                : '';
            return '[${_secStr(t.startTimeSeconds)}→${_secStr(t.endTimeSeconds)}] $label${t.text}';
          })
          .join('\n');
      final transcriptText = TranscriptTextCleaner.cleanForSummary(
        transcriptTextRaw,
      );
      debugPrint('=== RESUMMARIZE NOTES (${notes.length} chars): $notes ===');

      // 단어집: 전사본에 등장하는 용어만 필터링
      final glossaryRepo = GlossaryRepositoryImpl(IsarService.instance.db);
      final relevantEntries = await glossaryRepo.getRelevantEntries(
        transcriptText,
      );
      final glossarySection = GlossaryRepositoryImpl.toPromptSection(
        relevantEntries,
      );

      final summarySw = Stopwatch()..start();
      final rawOutput = await ChunkedSummarizer.summarize(
        transcript: transcriptText,
        dateStr: dateStr,
        notes: notes,
        participants: currentSummary?.participants ?? const [],
        glossary: glossarySection,
        instruction: SummaryTemplates.resolveInstruction(
          overrideId: picked.templateId,
          styleMode: picked.styleMode,
        ),
        agenda: meeting?.agenda ?? '',
        bookmarks: _parseMeetingBookmarks(meeting),
        maxTokens: 2500,
        speedMode: AppSettings.instance.summarySpeedMode,
        isCancelled: () => _cancelSummaryRequested,
        onProgress: (phase, progress) {
          if (mounted && !_cancelSummaryRequested) {
            setState(() {
              _summarizingStatus = phase;
              _summarizingProgress = progress;
            });
          }
        },
      );
      summarySw.stop();

      if (_cancelSummaryRequested) {
        await OnDeviceModelManager.instance.unloadLlm().catchError((_) {});
        throw const SummaryCancelledException();
      }

      final db = IsarService.instance.db;
      final summaryRepo = SummaryRepositoryImpl(db);
      final versionRepo = SummaryVersionRepositoryImpl(db);

      // 기존 요약 → 이력으로 이동
      if (currentSummary != null) {
        if (mounted) setState(() => _summarizingStatus = '이력 저장 중...');
        final nextVer = await versionRepo.nextVersion(widget.meetingId);
        final sv = SummaryVersion()
          ..meetingId = widget.meetingId
          ..version = nextVer
          ..meetingTitle = currentSummary.meetingTitle
          ..participants = currentSummary.participants
          ..keyDiscussions = currentSummary.keyDiscussions
          ..decisions = currentSummary.decisions
          ..actionItemsJson = currentSummary.actionItemsJson
          ..openQuestions = currentSummary.openQuestions
          ..createdAt = currentSummary.createdAt;
        await versionRepo.saveVersion(sv);
      }

      // 새 요약 저장 (기존 id 재사용 → unique index 충돌 방지)
      debugPrint(
        '=== GEMMA RAW OUTPUT (detail, ${rawOutput.length} chars) ===',
      );
      debugPrint(
        rawOutput.length > 2000
            ? '${rawOutput.substring(0, 2000)}...[truncated]'
            : rawOutput,
      );
      debugPrint('=== END GEMMA OUTPUT ===');

      final newSummary = SummaryParser.parse(
        rawOutput,
        widget.meetingId,
        now,
        forcedParticipants: currentSummary?.participants ?? const [],
      );
      if (currentSummary != null) {
        newSummary.id = currentSummary.id; // 기존 레코드 덮어쓰기(upsert)
      }
      await summaryRepo.saveSummary(newSummary);
      if (meeting != null) {
        final report =
            MeetingProcessingReport.fromJsonString(
              meeting.processingReportJson,
            ).copyWith(
              llmModel: llmId,
              summaryElapsedMs: summarySw.elapsedMilliseconds,
            );
        meeting.processingReportJson = report.toJsonString();
        await MeetingRepositoryImpl(db).updateMeeting(meeting);
      }

      // ── 태그 자동 추출 (빠른 요약에서는 추가 LLM 호출 생략) ─────
      if (AppSettings.instance.summarySpeedMode !=
          AppSettings.summaryModeFast) {
        try {
          if (mounted) setState(() => _summarizingStatus = '태그 자동 추출 중...');
          final tags = await TagExtractor.extractFromSummary(
            newSummary,
            notes: notes,
            agenda: meeting?.agenda ?? '',
          );
          if (tags.isNotEmpty && meeting != null) {
            meeting.tags = TagExtractor.mergeTags(meeting.tags, tags);
            await MeetingRepositoryImpl(db).updateMeeting(meeting);
          }
        } catch (e) {
          debugPrint('[TagExtractor] auto-extract failed: $e');
        }
      }

      await OnDeviceModelManager.instance.unloadLlm();

      if (mounted) {
        ref.invalidate(meetingSummaryProvider(widget.meetingId));
        ref.invalidate(summaryVersionsProvider(widget.meetingId));
        ref.invalidate(meetingsProvider);
        final totalElapsed = _summaryStartTime == null
            ? Duration.zero
            : DateTime.now().difference(_summaryStartTime!);
        final totalStr =
            '${totalElapsed.inMinutes}분 ${(totalElapsed.inSeconds % 60).toString().padLeft(2, '0')}초';
        setState(() {
          _isSummarizing = false;
          _cancelSummaryRequested = false;
          _summarizingStatus = '';
        });
        final styleSuffix = picked.styleMode == SummaryStyleMode.standard
            ? ''
            : ' (${picked.styleMode.displayName})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재요약 완료$styleSuffix · 총 소요 $totalStr'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e, st) {
      await OnDeviceModelManager.instance.unloadLlm().catchError((_) {});
      CrashLogService.instance.recordCaught(e, st, context: 'resummarize');
      if (mounted) {
        final totalElapsed = _summaryStartTime == null
            ? Duration.zero
            : DateTime.now().difference(_summaryStartTime!);
        final totalStr =
            '${totalElapsed.inMinutes}분 ${(totalElapsed.inSeconds % 60).toString().padLeft(2, '0')}초';
        setState(() {
          _isSummarizing = false;
          _cancelSummaryRequested = false;
          _summarizingStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is SummaryCancelledException
                  ? '재요약 중지됨 · 총 소요 $totalStr'
                  : '재요약 오류 · 총 소요 $totalStr\n'
                        '${friendlyErrorText(e, fallbackTitle: '요약을 다시 만들지 못했습니다', fallbackMessage: 'AI 요약 생성 중 문제가 발생했습니다.', nextStep: '잠시 후 다시 시도하거나 더 빠른 요약 모델을 선택해주세요.')}',
            ),
            backgroundColor: e is SummaryCancelledException
                ? Colors.orange.shade700
                : Colors.red.shade700,
          ),
        );
      }
    }
  }

  // ── 음성 인식 다시 돌리기 ───────────────────────────────────────
  Future<void> _rerunStt(Meeting meeting) async {
    if (_isRerunningStt || _isSummarizing) return;
    if (_nativeTaskBlockReason('음성 인식') != null) {
      _showNativeTaskBlocked('음성 인식');
      return;
    }
    final audioPath = meeting.audioFilePath;
    if (audioPath == null) return;
    if (!await File(audioPath).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오디오 파일을 찾을 수 없습니다: $audioPath'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }

    // 두 모델의 설치 여부 확인 — 미설치 모델은 선택지에서 비활성화
    final appSupport = await getApplicationSupportDirectory();
    final modelsDir = '${appSupport.path}/models';
    final fastInstalled = await File(
      '$modelsDir/${AppConstants.sttModelFileFast}',
    ).exists();
    final accurateInstalled = await File(
      '$modelsDir/${AppConstants.sttModelFileAccurate}',
    ).exists();
    if (!fastInstalled && !accurateInstalled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('설치된 음성 인식 모델이 없습니다. 설정 → 모델 관리에서 다운로드하세요.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }

    // 기본 선택: 현재 설정 모드 (설치된 경우), 아니면 설치된 쪽
    var sttMode = AppSettings.instance.sttProcessingMode;
    if (sttMode == AppSettings.sttModeAccurate && !accurateInstalled) {
      sttMode = fastInstalled
          ? AppSettings.sttModeBalanced
          : AppSettings.sttModeAccurate;
    }
    if (sttMode != AppSettings.sttModeAccurate && !fastInstalled) {
      sttMode = AppSettings.sttModeAccurate;
    }
    var sttLanguage = AppSettings.instance.sttLanguage;

    final diarizationModelsReady = await DiarizationService.instance
        .modelsReady();
    var useDiarization =
        AppSettings.instance.diarizationEnabled && diarizationModelsReady;
    final audioDuration = _meetingAudioDuration(meeting);
    final previousReport = MeetingProcessingReport.fromJsonString(
      meeting.processingReportJson,
    );
    bool isAccurateMode(String mode) => mode == AppSettings.sttModeAccurate;
    String modelFileForMode(String mode) => isAccurateMode(mode)
        ? AppConstants.sttModelFileAccurate
        : AppConstants.sttModelFileFast;
    int decodeCodeForMode(String mode) => switch (mode) {
      AppSettings.sttModeUltraFast => 0,
      AppSettings.sttModeAccurate => 2,
      _ => 1,
    };

    double? previousEstimateRatioFor(String mode) {
      if (previousReport.sttProcessingMode.isNotEmpty &&
          previousReport.sttProcessingMode != mode) {
        return null;
      }
      if (previousReport.sttProcessingMode.isEmpty &&
          mode != AppSettings.sttModeAccurate) {
        return null;
      }
      return _previousSttEstimateRatio(
        previousReport,
        modelFileForMode(mode),
        audioDuration,
      );
    }

    Duration sttEstimateFor(String mode) {
      final previousRatio = previousEstimateRatioFor(mode);
      final fallbackRatio = switch (mode) {
        AppSettings.sttModeUltraFast => 0.16,
        AppSettings.sttModeAccurate => 0.36,
        _ => 0.16,
      };
      final ratio = previousRatio ?? fallbackRatio;
      return _boundedEstimate(
        audioDuration,
        ratio,
        minSeconds: isAccurateMode(mode) ? 30 : 15,
        maxSeconds: isAccurateMode(mode) ? 60 * 45 : 60 * 30,
      );
    }

    Duration currentSttEstimate() => sttEstimateFor(sttMode);
    final diarizationEstimate = _boundedEstimate(
      audioDuration,
      0.34,
      minSeconds: 30,
      maxSeconds: 60 * 40,
    );

    Duration totalEstimate() =>
        currentSttEstimate() +
        (useDiarization ? diarizationEstimate : Duration.zero);

    if (!mounted) return;
    final options = await showMacosAlertDialog<_RerunSttOptions>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => MacosAlertDialog(
          appIcon: const Icon(Icons.timer_outlined, size: 48),
          title: const Text('음성 인식 다시 돌리기'),
          message: SizedBox(
            width: 680,
            height: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '기존 전사본을 삭제하고 오디오 파일에서 다시 받아쓰기를 실행합니다. 기존 요약은 유지되며, 필요하면 다시 요약할 수 있습니다.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  _EstimateRow(
                    label: '오디오 길이',
                    value: audioDuration > Duration.zero
                        ? _durationKr(audioDuration)
                        : '확인 불가',
                  ),
                  _EstimateRow(
                    label:
                        '${AppSettings.sttProcessingModeLabel(sttMode)} 음성 인식',
                    value: audioDuration > Duration.zero
                        ? '약 ${_durationKr(currentSttEstimate())}'
                        : '실행 후 표시',
                  ),
                  if (previousEstimateRatioFor(sttMode) != null)
                    Text(
                      '이 회의의 이전 음성 인식 시간을 반영했습니다.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  if (useDiarization)
                    _EstimateRow(
                      label: '발화자 라벨',
                      value: audioDuration > Duration.zero
                          ? '약 ${_durationKr(diarizationEstimate)}'
                          : '실행 후 표시',
                    ),
                  const Divider(height: 22),
                  _EstimateRow(
                    label: '총 예상',
                    value: audioDuration > Duration.zero
                        ? '약 ${_durationKr(totalEstimate())}'
                        : '실행 후 진행률 표시',
                    emphasis: true,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '음성 인식 방식',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: AppSettings.sttModeUltraFast,
                        icon: MacosTooltip(
                          message:
                              'Whisper large-v3-turbo Q8 (~900MB)\n'
                              '대기 시간을 조금 더 줄이는 방식입니다.\n'
                              '파일: ${AppConstants.sttModelFileFast}',
                          child: const Icon(Icons.flash_on, size: 14),
                        ),
                        label: MacosTooltip(
                          message:
                              'Whisper large-v3-turbo Q8 (~900MB)\n'
                              '대기 시간을 조금 더 줄이는 방식입니다.\n'
                              '파일: ${AppConstants.sttModelFileFast}',
                          child: Text(
                            fastInstalled ? '빠름' : '빠름 (미설치)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        enabled: fastInstalled,
                      ),
                      ButtonSegment(
                        value: AppSettings.sttModeBalanced,
                        icon: MacosTooltip(
                          message:
                              'Whisper large-v3-turbo Q8 (~900MB)\n'
                              '속도와 전사 품질을 함께 고려합니다.\n'
                              '파일: ${AppConstants.sttModelFileFast}',
                          child: const Icon(Icons.speed, size: 14),
                        ),
                        label: MacosTooltip(
                          message:
                              'Whisper large-v3-turbo Q8 (~900MB)\n'
                              '속도와 전사 품질을 함께 고려합니다.\n'
                              '파일: ${AppConstants.sttModelFileFast}',
                          child: Text(
                            fastInstalled ? '표준' : '표준 (미설치)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        enabled: fastInstalled,
                      ),
                      ButtonSegment(
                        value: AppSettings.sttModeAccurate,
                        icon: MacosTooltip(
                          message:
                              'Whisper large-v3 Q5_0 (~1.1GB)\n'
                              '품질 우선, 표준보다 오래 걸립니다.\n'
                              '파일: ${AppConstants.sttModelFileAccurate}',
                          child: const Icon(Icons.verified, size: 14),
                        ),
                        label: MacosTooltip(
                          message:
                              'Whisper large-v3 Q5_0 (~1.1GB)\n'
                              '품질 우선, 표준보다 오래 걸립니다.\n'
                              '파일: ${AppConstants.sttModelFileAccurate}',
                          child: Text(
                            accurateInstalled ? '정밀' : '정밀 (미설치)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        enabled: accurateInstalled,
                      ),
                    ],
                    selected: {sttMode},
                    onSelectionChanged: (sel) =>
                        setDialog(() => sttMode = sel.first),
                    style: ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppSettings.sttProcessingModeDescription(sttMode),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: sttLanguage,
                    decoration: const InputDecoration(
                      labelText: '음성 인식 언어',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final code in AppSettings.supportedSttLanguages)
                        DropdownMenuItem(
                          value: code,
                          child: Text(AppSettings.sttLanguageLabel(code)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialog(() => sttLanguage = v);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppSettings.sttLanguageDescription(sttLanguage),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: useDiarization,
                    title: const Text('발화자 라벨 사용'),
                    subtitle: Text(
                      diarizationModelsReady
                          ? '끄면 더 빠르게 끝나지만, A/B/C 발화 흐름 정보는 제거됩니다.'
                          : '발화자 라벨 모델이 설치되어 있지 않습니다.',
                    ),
                    onChanged: diarizationModelsReady
                        ? (v) => setDialog(() => useDiarization = v)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.pop(
              ctx,
              _RerunSttOptions(
                sttMode: sttMode,
                useDiarization: useDiarization,
                sttLanguage: sttLanguage,
              ),
            ),
            child: const Text('실행'),
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
        ),
      ),
    );
    if (options == null) return;
    sttMode = options.sttMode;
    useDiarization = options.useDiarization;
    await AppSettings.instance.setSttProcessingMode(sttMode);
    await AppSettings.instance.setDiarizationEnabled(useDiarization);
    await AppSettings.instance.setSttLanguage(options.sttLanguage);

    final selectedModelFile = modelFileForMode(sttMode);

    setState(() {
      _isRerunningStt = true;
      _cancelRerunSttRequested = false;
      _rerunSttStatus = 'Whisper 모델 로드 중...';
      _rerunSttProgress = 0.0;
      _rerunSttProcessedMs = 0;
      _rerunSttTotalMs = 0;
      _rerunSttStartTime = DateTime.now();
    });
    _rerunTicker?.cancel();
    _rerunTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRerunningStt) setState(() {});
    });

    try {
      // LLM이 로드되어 있을 수 있으므로 해제 (단일 모델 강제)
      await OnDeviceModelManager.instance.unloadLlm().catchError((_) {});

      final sttPath = '$modelsDir/$selectedModelFile';
      await OnDeviceModelManager.instance.loadStt(sttPath);
      if (_cancelRerunSttRequested) throw const SttCancelledException();

      if (mounted) {
        setState(
          () => _rerunSttStatus =
              '${AppSettings.sttLanguageLabel(options.sttLanguage)} 음성 인식 중...',
        );
      }
      final sttSw = Stopwatch()..start();
      final segments = await SttService.instance.transcribeFile(
        audioPath,
        decodeMode: decodeCodeForMode(sttMode),
        isCancelled: () => _cancelRerunSttRequested,
        onProgress: (processedMs, totalMs) {
          if (!mounted || totalMs <= 0 || _cancelRerunSttRequested) return;
          setState(() {
            _rerunSttProcessedMs = processedMs;
            _rerunSttTotalMs = totalMs;
            _rerunSttProgress = (processedMs / totalMs).clamp(0.0, 1.0);
          });
        },
      );
      sttSw.stop();
      if (_cancelRerunSttRequested) throw const SttCancelledException();

      // ── 발화자 라벨 (옵션) ───────────────────────────────────
      List<String?> speakerLabels = List<String?>.filled(segments.length, null);
      var diarizationStatus = useDiarization ? 'skipped' : 'disabled';
      var diarizationElapsedMs = 0;
      if (useDiarization && await DiarizationService.instance.modelsReady()) {
        try {
          final diarSw = Stopwatch()..start();
          await OnDeviceModelManager.instance.unloadStt().catchError((_) {});
          if (_cancelRerunSttRequested) throw const SttCancelledException();
          if (mounted) {
            setState(() {
              _rerunSttStatus = '발화자 라벨 생성 중... 긴 녹음은 몇 분 걸릴 수 있습니다.';
              _rerunSttProgress = 0.0;
              _rerunSttProcessedMs = 0;
              _rerunSttTotalMs = 0;
            });
          }
          final diar = await DiarizationService.instance.diarizeWav(
            audioPath,
            numSpeakersHint: AppSettings.instance.numSpeakersHint,
            onProgress: (percent) {
              if (!mounted || _cancelRerunSttRequested) return;
              final clamped = percent.clamp(0, 100).toDouble();
              final completed = clamped >= 99.5;
              setState(() {
                _rerunSttProgress = completed ? 1.0 : 0.0;
                _rerunSttStatus = completed
                    ? '발화자 라벨 분석 완료. 전사본을 저장하고 있습니다.'
                    : '발화자 라벨 생성 중... 오디오를 분석하고 있습니다.';
              });
            },
          );
          diarSw.stop();
          diarizationElapsedMs = diarSw.elapsedMilliseconds;
          diarizationStatus = 'success';
          if (_cancelRerunSttRequested) throw const SttCancelledException();
          speakerLabels = DiarizationService.assignLabels(
            sttStartMs: segments.map((s) => s.startMs).toList(),
            sttEndMs: segments.map((s) => s.endMs).toList(),
            diar: diar,
          );
        } catch (e) {
          if (e is SttCancelledException) rethrow;
          diarizationStatus = 'failed';
          CrashLogService.instance.recordCaught(
            e,
            StackTrace.current,
            context: 'rerunSttDiarization',
          );
          if (mounted) {
            setState(() {
              _rerunSttStatus = '발화자 구분에 실패했습니다. 라벨 없이 전사본을 저장합니다.';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyDiarizationFailureMessage(
                    nextStep: '전사본은 발화자 라벨 없이 저장합니다.',
                  ),
                ),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }

      if (mounted) setState(() => _rerunSttStatus = '기존 전사본 삭제 중...');
      final db = IsarService.instance.db;
      final transcriptRepo = TranscriptRepositoryImpl(db);
      await transcriptRepo.deleteByMeetingId(widget.meetingId);

      if (mounted) setState(() => _rerunSttStatus = '새 전사본 저장 중...');
      final now = DateTime.now();
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        final transcript = Transcript()
          ..meetingId = widget.meetingId
          ..segmentIndex = i
          ..text = seg.text
          ..startTimeSeconds = seg.startMs / 1000.0
          ..endTimeSeconds = seg.endMs / 1000.0
          ..speakerLabel = speakerLabels[i]
          ..createdAt = now;
        await transcriptRepo.saveSegment(transcript);
      }

      // Meeting 미리보기 갱신
      final fullText = segments.map((s) => s.text).join(' ');
      meeting.transcriptPreview = fullText.length > 200
          ? fullText.substring(0, 200)
          : fullText;
      final audioMs = meeting.durationSeconds > 0
          ? meeting.durationSeconds * 1000
          : _rerunSttTotalMs;
      final report =
          MeetingProcessingReport.fromJsonString(
            meeting.processingReportJson,
          ).copyWith(
            sttModel: selectedModelFile,
            sttLanguage: options.sttLanguage,
            sttElapsedMs: sttSw.elapsedMilliseconds,
            sttAudioMs: audioMs,
            sttRtf: audioMs <= 0 ? 0 : sttSw.elapsedMilliseconds / audioMs,
            sttProcessingMode: sttMode,
            diarizationEnabled: useDiarization,
            diarizationStatus: diarizationStatus,
            diarizationElapsedMs: diarizationElapsedMs,
          );
      meeting.processingReportJson = report.toJsonString();
      await MeetingRepositoryImpl(db).updateMeeting(meeting);

      await OnDeviceModelManager.instance.unloadStt();

      if (mounted) {
        ref.invalidate(meetingTranscriptProvider(widget.meetingId));
        ref.invalidate(meetingsProvider);
        _rerunTicker?.cancel();
        _rerunTicker = null;
        setState(() {
          _isRerunningStt = false;
          _cancelRerunSttRequested = false;
          _rerunSttStatus = '';
        });
        final totalElapsed = _rerunSttStartTime == null
            ? Duration.zero
            : DateTime.now().difference(_rerunSttStartTime!);
        final totalStr =
            '${totalElapsed.inMinutes}분 ${(totalElapsed.inSeconds % 60).toString().padLeft(2, '0')}초';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '음성 인식 완료 — ${segments.length}개 세그먼트 · 총 소요 $totalStr',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e, st) {
      await OnDeviceModelManager.instance.unloadStt().catchError((_) {});
      CrashLogService.instance.recordCaught(e, st, context: 'rerunStt');
      if (mounted) {
        final totalElapsed = _rerunSttStartTime == null
            ? Duration.zero
            : DateTime.now().difference(_rerunSttStartTime!);
        final totalStr =
            '${totalElapsed.inMinutes}분 ${(totalElapsed.inSeconds % 60).toString().padLeft(2, '0')}초';
        _rerunTicker?.cancel();
        _rerunTicker = null;
        setState(() {
          _isRerunningStt = false;
          _cancelRerunSttRequested = false;
          _rerunSttStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is SttCancelledException
                  ? '음성 인식 중지됨 · 총 소요 $totalStr'
                  : '음성 인식 오류 · 총 소요 $totalStr\n'
                        '${friendlyErrorText(e, fallbackTitle: '음성 인식을 완료하지 못했습니다', fallbackMessage: '녹음 파일을 텍스트로 변환하는 중 문제가 발생했습니다.', nextStep: '오디오 파일과 AI 모델 설치 상태를 확인한 뒤 다시 시도해주세요.')}',
            ),
            backgroundColor: e is SttCancelledException
                ? Colors.orange.shade700
                : Colors.red.shade700,
          ),
        );
      }
    }
  }

  // ── 용어 자동 추출 ─────────────────────────────────────────────
  Future<void> _extractTerms(List<Transcript> transcripts) async {
    if (transcripts.isEmpty || _isExtractingTerms || _isSummarizing) return;
    setState(() => _isExtractingTerms = true);

    try {
      final appSupport = await getApplicationSupportDirectory();
      final llmPath =
          '${appSupport.path}/models/${AppSettings.instance.currentLlmModelFile}';
      await OnDeviceModelManager.instance.loadLlm(
        llmPath,
        nCtx: 2048,
        nBatch: 512,
      );

      final transcriptText = transcripts
          .map((t) => t.text)
          .join(' ')
          .substring(
            0,
            transcripts.map((t) => t.text).join(' ').length.clamp(0, 3000),
          );

      final prompt =
          '다음 회의 전사본에서 일반적이지 않은 전문 용어, 약어, 고유명사를 추출하세요.\n'
          '일반 단어(예: 회의, 일정, 오늘)는 제외하세요.\n'
          'JSON 배열만 출력하세요. 다른 텍스트는 절대 쓰지 마세요.\n'
          '형식: [{"term":"용어","description":"추정 의미 (모르면 빈 문자열)"}]\n\n'
          '전사본:\n$transcriptText\n\nJSON:';

      final buf = StringBuffer();
      await for (final tok in LlmService.instance.generate(
        userMessage: prompt,
        maxTokens: 512,
        temperature: 0.25,
        topP: 0.85,
      )) {
        buf.write(tok);
      }
      await OnDeviceModelManager.instance.unloadLlm();

      // 결과 파싱
      final raw = buf.toString();
      List<Map<String, String>> extracted = [];
      try {
        String? jsonStr;
        final cb = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(raw);
        if (cb != null) jsonStr = cb.group(1)?.trim();
        if (jsonStr == null) {
          final s = raw.indexOf('[');
          final e = raw.lastIndexOf(']');
          if (s != -1 && e > s) jsonStr = raw.substring(s, e + 1);
        }
        if (jsonStr != null) {
          final list = jsonDecode(jsonStr) as List;
          extracted = list
              .map(
                (item) => {
                  'term': (item['term'] ?? '').toString(),
                  'description': (item['description'] ?? '').toString(),
                },
              )
              .where((m) => m['term']!.isNotEmpty)
              .toList();
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() => _isExtractingTerms = false);

      if (extracted.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('추출된 전문 용어가 없습니다.')));
        return;
      }

      // 결과 다이얼로그
      await showMacosSheet(
        context: context,
        builder: (ctx) => _TermExtractDialog(
          extracted: extracted,
          onSave: (selected) async {
            final repo = GlossaryRepositoryImpl(IsarService.instance.db);
            for (final item in selected) {
              final entry = GlossaryEntry()
                ..term = item['term']!
                ..description = item['description']!;
              await repo.saveEntry(entry);
            }
          },
        ),
      );
    } catch (e, st) {
      await OnDeviceModelManager.instance.unloadLlm().catchError((_) {});
      CrashLogService.instance.recordCaught(e, st, context: 'extractTerms');
      if (mounted) {
        setState(() => _isExtractingTerms = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorText(
                e,
                fallbackTitle: '용어를 추출하지 못했습니다',
                fallbackMessage: '전사본에서 용어를 찾는 중 문제가 발생했습니다.',
                nextStep: '회의록 내용은 그대로 유지됩니다. 잠시 후 다시 시도해주세요.',
              ),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  static String _secStr(double sec) {
    final s = sec.toInt();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  // ── 이력 보기 다이얼로그 ───────────────────────────────────────
  void _showHistory(BuildContext context) {
    showMacosSheet(
      context: context,
      builder: (ctx) => _SummaryHistoryDialog(meetingId: widget.meetingId),
    );
  }

  // ── 요약 수동 편집 ────────────────────────────────────────────
  Future<void> _showEditSummary(Summary current) async {
    final result = await showMacosSheet<_EditedSummary>(
      context: context,
      builder: (_) => _SummaryEditDialog(current: current),
    );
    if (result == null) return;

    final db = IsarService.instance.db;
    final summaryRepo = SummaryRepositoryImpl(db);
    final versionRepo = SummaryVersionRepositoryImpl(db);

    // 현재 요약을 이력으로 저장
    final nextVer = await versionRepo.nextVersion(widget.meetingId);
    final sv = SummaryVersion()
      ..meetingId = widget.meetingId
      ..version = nextVer
      ..meetingTitle = current.meetingTitle
      ..participants = current.participants
      ..keyDiscussions = current.keyDiscussions
      ..decisions = current.decisions
      ..actionItemsJson = current.actionItemsJson
      ..openQuestions = current.openQuestions
      ..createdAt = current.createdAt;
    await versionRepo.saveVersion(sv);

    // 현재 요약 업데이트
    current
      ..meetingTitle = result.meetingTitle
      ..participants = result.participants
      ..keyDiscussions = result.keyDiscussions
      ..decisions = result.decisions
      ..openQuestions = result.openQuestions
      ..createdAt = DateTime.now();
    await summaryRepo.saveSummary(current);

    if (mounted) {
      ref.invalidate(meetingSummaryProvider(widget.meetingId));
      ref.invalidate(summaryVersionsProvider(widget.meetingId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('요약을 수정했습니다. 이전 버전은 이력에 저장되었습니다.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(meetingSummaryProvider(widget.meetingId));
    final transcriptAsync = ref.watch(
      meetingTranscriptProvider(widget.meetingId),
    );
    final meetingsAsync = ref.watch(meetingsProvider);
    final groupsAsync = ref.watch(groupsProvider);

    // ── 사이드바에서 전사 점프 요청 listen ──────────────────────
    ref.listen<TranscriptJumpRequest?>(transcriptJumpRequestProvider, (
      prev,
      next,
    ) {
      if (next == null || next.meetingId != widget.meetingId) return;
      if (prev?.seq == next.seq) return;
      // 비동기로 처리 — transcripts가 로드된 후 점프
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _jumpToSnippet(next.snippet);
        // 점프 완료 후 요청 클리어 (다른 회의 재선택 시 중복 트리거 방지)
        if (mounted) {
          ref.read(transcriptJumpRequestProvider.notifier).state = null;
        }
      });
    });

    // 회의 메타데이터 (목록에서 찾기)
    final meeting = meetingsAsync.asData?.value.firstWhere(
      (m) => m.id == widget.meetingId,
      orElse: () => Meeting()..title = '',
    );

    // ⌘⇧S → 재요약 실행 (전사본 + meeting이 있을 때만)
    ref.listen<int>(shortcutRunSummarySignalProvider, (prev, next) {
      final transcripts = ref
          .read(meetingTranscriptProvider(widget.meetingId))
          .asData
          ?.value;
      final summary = ref
          .read(meetingSummaryProvider(widget.meetingId))
          .asData
          ?.value;
      if (_isSummarizing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('이미 요약을 생성하고 있습니다.'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
        return;
      }
      if (transcripts != null && transcripts.isNotEmpty) {
        _runResummarize(
          transcripts,
          summary,
          notes: meeting?.notes ?? '',
          meeting: meeting,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('요약할 전사 내용이 없습니다. 먼저 음성 인식을 실행해주세요.'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
    });

    // 내보내기용 데이터 (로딩 완료 시에만 사용 가능)
    final summary = summaryAsync.asData?.value;
    final transcripts = transcriptAsync.asData?.value;
    final isDataReady =
        meeting != null && meeting.title.isNotEmpty && transcriptAsync.hasValue;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 (제목 + 날짜 + 그룹 + 내보내기 버튼) ─────────────
          _buildHeader(
            context,
            ref,
            meeting,
            groups: groupsAsync.asData?.value ?? [],
            summary: summary,
            transcripts: transcripts ?? [],
            isDataReady: isDataReady,
          ),
          const SizedBox(height: 20),

          // ── 요약 + 전사본 (스크롤) ─────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const dividerWidth = 16.0;
                const minSummaryWidth = 360.0;
                const minTranscriptWidth = 340.0;
                final available = constraints.maxWidth - dividerWidth;

                if (available <= minSummaryWidth + minTranscriptWidth) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildSummaryPane(
                          summaryAsync,
                          transcripts,
                          meeting,
                        ),
                      ),
                      const SizedBox(width: dividerWidth),
                      Expanded(
                        child: _buildTranscriptPane(transcriptAsync, meeting),
                      ),
                    ],
                  );
                }

                final minRatio = minSummaryWidth / available;
                final maxRatio = 1 - (minTranscriptWidth / available);
                final ratio = _summaryPaneRatio.clamp(minRatio, maxRatio);
                final summaryWidth = available * ratio;
                final transcriptWidth = available - summaryWidth;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: summaryWidth,
                      child: _buildSummaryPane(
                        summaryAsync,
                        transcripts,
                        meeting,
                      ),
                    ),
                    _DetailPaneResizeHandle(
                      width: dividerWidth,
                      onDrag: (delta) {
                        setState(() {
                          _summaryPaneRatio =
                              ((_summaryPaneRatio * available) + delta) /
                              available;
                          _summaryPaneRatio = _summaryPaneRatio.clamp(
                            minRatio,
                            maxRatio,
                          );
                        });
                      },
                    ),
                    SizedBox(
                      width: transcriptWidth,
                      child: _buildTranscriptPane(transcriptAsync, meeting),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPane(
    AsyncValue<Summary?> summaryAsync,
    List<Transcript>? transcripts,
    Meeting? meeting,
  ) {
    return _isSummarizing
        ? _buildSummarizingIndicator()
        : summaryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('요약 로드 오류: $e')),
            data: (s) => s == null
                ? _buildNoSummary(transcripts ?? [], null, meeting: meeting)
                : _buildSummarySection(context, s, transcripts ?? [], meeting),
          );
  }

  Widget _buildTranscriptPane(
    AsyncValue<List<Transcript>> transcriptAsync,
    Meeting? meeting,
  ) {
    return transcriptAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('녹취록 로드 오류: $e')),
      data: (segments) => _isRerunningStt
          ? _buildRerunSttIndicator()
          : _TranscriptWithAudio(
              key: ValueKey('transcript_${widget.meetingId}'),
              segments: segments,
              audioFilePath: meeting?.audioFilePath,
              meeting: meeting,
              bookmarks: _parseMeetingBookmarks(meeting),
              onRerunStt: meeting?.audioFilePath != null
                  ? () => _rerunStt(meeting!)
                  : null,
              isRerunning: _isRerunningStt,
              onTranscriptChanged: () {
                ref.invalidate(meetingTranscriptProvider(widget.meetingId));
                ref.invalidate(meetingsProvider);
              },
              onSeekRegister: (fn) => _seekTranscriptAudio = fn,
            ),
    );
  }

  // ── 음성 인식 재실행 진행 인디케이터 ─────────────────────────────
  Widget _buildRerunSttIndicator() {
    String fmtMs(int ms) {
      final s = ms ~/ 1000;
      return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    }

    final elapsed = _rerunSttStartTime == null
        ? Duration.zero
        : DateTime.now().difference(_rerunSttStartTime!);
    final elapsedStr =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final pctStr = (_rerunSttProgress * 100).toStringAsFixed(1);
    final isDiarizing = _rerunSttStatus.contains('발화자 라벨');

    // 남은 시간 추정: (1 - progress) / progress * elapsed — 첫 5% 이후에만 표시
    String etaStr = '';
    if (!isDiarizing && _rerunSttProgress > 0.05 && elapsed.inSeconds > 3) {
      final remainSec =
          ((1 - _rerunSttProgress) / _rerunSttProgress * elapsed.inSeconds)
              .round();
      etaStr =
          '  ·  남은 ~${(remainSec ~/ 60)}:${(remainSec % 60).toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _rerunSttStatus,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade300),
                  maxLines: isDiarizing ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: _cancelRerunSttRequested
                    ? null
                    : _requestCancelRerunStt,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.stop_circle_outlined,
                        size: 14,
                        color: Colors.red.shade300,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _cancelRerunSttRequested ? '중지 중' : '중지',
                        style: TextStyle(color: Colors.red.shade300),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (isDiarizing) ...[
            const SizedBox(height: 6),
            Text(
              '말한 사람별 구간을 찾고 있습니다. 이 단계는 진행률이 자주 갱신되지 않을 수 있습니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
          const SizedBox(height: 8),
          const _NativeTaskNotice(),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: isDiarizing && _rerunSttProgress < 1.0
                  ? null
                  : (_rerunSttProgress > 0 ? _rerunSttProgress : null),
              minHeight: 4,
              backgroundColor: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          if (_rerunSttTotalMs > 0 && !isDiarizing)
            Text(
              '${fmtMs(_rerunSttProcessedMs)} / ${fmtMs(_rerunSttTotalMs)}  '
              '·  $pctStr%  ·  경과 $elapsedStr$etaStr',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else
            Text(
              '오디오 분석 중... · 경과 $elapsedStr',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
        ],
      ),
    );
  }

  // ── 재요약 진행 인디케이터 ─────────────────────────────────────
  // 구성:
  //   상단: 원형 인디케이터 + 상태 텍스트 + 경과시간
  //   중단: 선형 진행바 (0~100%)
  //   하단: 요약 모델이 실시간으로 생성 중인 텍스트 (스크롤, 타자기 효과)
  Widget _buildSummarizingIndicator() {
    final elapsed = _summaryStartTime == null
        ? Duration.zero
        : DateTime.now().difference(_summaryStartTime!);
    final elapsedStr =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final pctStr = (_summarizingProgress * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _summarizingStatus.isEmpty
                      ? '요약 준비 중...'
                      : _summarizingStatus,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade300),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: _cancelSummaryRequested
                    ? null
                    : _requestCancelSummary,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.stop_circle_outlined,
                        size: 14,
                        color: Colors.red.shade300,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _cancelSummaryRequested ? '중지 중' : '중지',
                        style: TextStyle(color: Colors.red.shade300),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pctStr%  ·  경과 $elapsedStr',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _NativeTaskNotice(),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _summarizingProgress > 0 ? _summarizingProgress : null,
              minHeight: 4,
              backgroundColor: Colors.grey.shade800,
            ),
          ),
          // 요약 중 실시간 프리뷰는 노출하지 않음 (원문 토큰 유출 방지 + UX 단순화)
        ],
      ),
    );
  }

  // ── 헤더 ────────────────────────────────────────────────────────
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    Meeting? meeting, {
    required List<MeetingGroup> groups,
    required Summary? summary,
    required List<Transcript> transcripts,
    required bool isDataReady,
  }) {
    if (meeting == null || meeting.title.isEmpty) {
      return const SizedBox.shrink();
    }

    final created = meeting.createdAt;
    final dateStr =
        '${created.year}-'
        '${created.month.toString().padLeft(2, '0')}-'
        '${created.day.toString().padLeft(2, '0')} '
        '${created.hour.toString().padLeft(2, '0')}:'
        '${created.minute.toString().padLeft(2, '0')}';
    final durStr = meeting.durationSeconds > 0
        ? '  ·  ${meeting.durationSeconds ~/ 60}분 ${meeting.durationSeconds % 60}초'
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 제목 + 날짜 + 그룹 선택
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      meeting.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 제목 수정 버튼
                  MacosTooltip(
                    message: '제목 수정',
                    child: MacosIconButton(
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                      backgroundColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      boxConstraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                        maxWidth: 22,
                        maxHeight: 22,
                      ),
                      onPressed: () =>
                          _showTitleEditDialog(context, ref, meeting),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '$dateStr$durStr',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 12),
                  // 그룹 선택 드롭다운
                  _GroupSelector(
                    meeting: meeting,
                    groups: groups,
                    onChanged: (groupId) async {
                      meeting.groupId = groupId;
                      await MeetingRepositoryImpl(
                        IsarService.instance.db,
                      ).updateMeeting(meeting);
                      ref.invalidate(meetingsProvider);
                    },
                  ),
                ],
              ),

              // ── 태그 ────────────────────────────────────────────
              const SizedBox(height: 6),
              _MeetingTagsRow(meeting: meeting),

              // ── 녹음 파일명 (클릭 → Finder에서 선택) ───────────
              if (meeting.audioFilePath != null) ...[
                const SizedBox(height: 3),
                _AudioFileReveal(path: meeting.audioFilePath!),
              ],
            ],
          ),
        ),
        // 내보내기 버튼
        _ExportMenu(
          meeting: meeting,
          summary: summary,
          transcripts: transcripts,
          enabled: isDataReady,
        ),
      ],
    );
  }

  // ── 제목 수정 다이얼로그 ────────────────────────────────────────
  void _showTitleEditDialog(
    BuildContext context,
    WidgetRef ref,
    Meeting meeting,
  ) {
    // 날짜 고정 접두사와 추가 제목 분리
    // 저장된 제목이 "26년 04월 18일 14:23 xxx" 형태일 수 있으므로
    // 전체 제목을 그대로 편집 가능하게 처리
    final ctrl = TextEditingController(text: meeting.title);
    showMacosAlertDialog(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const Icon(Icons.edit_outlined, size: 48),
        title: const Text('제목 수정'),
        message: SizedBox(
          width: 400,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '회의 제목',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveTitleEdit(ctx, ref, meeting, ctrl.text),
          ),
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => _saveTitleEdit(ctx, ref, meeting, ctrl.text),
          child: const Text('저장'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
      ),
    );
  }

  Future<void> _saveTitleEdit(
    BuildContext ctx,
    WidgetRef ref,
    Meeting meeting,
    String newTitle,
  ) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    meeting.title = trimmed;
    await MeetingRepositoryImpl(IsarService.instance.db).updateMeeting(meeting);
    ref.invalidate(meetingsProvider);
    if (ctx.mounted) Navigator.pop(ctx);
  }

  // 저장된 불량 meetingTitle 필터 (Gemma 출력 오류 방어)
  static const _badTitles = {
    '분석 불가',
    '분석불가',
    '분석 불가능',
    '분석불가능',
    'N/A',
    'n/a',
    'NA',
    'na',
    '없음',
    'null',
    'NULL',
    'undefined',
    '',
  };

  /// Meeting.speakerNamesJson을 {라벨: 이름} 맵으로 디코드.
  Map<String, String> _resolveSpeakerNames(Meeting? meeting) {
    if (meeting == null) return const {};
    final raw = meeting.speakerNamesJson;
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return const {};
    }
  }

  // ── 요약 섹션 ───────────────────────────────────────────────────
  Widget _buildSummarySection(
    BuildContext context,
    Summary s,
    List<Transcript> transcripts, [
    Meeting? meeting,
  ]) {
    final displayTitle = _badTitles.contains(s.meetingTitle.trim())
        ? '회의 요약'
        : s.meetingTitle.trim().isEmpty
        ? '회의 요약'
        : s.meetingTitle;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 재요약 / 이력 버튼 행 (좁은 창에서 자동 줄바꿈) ───────
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed:
                    (_isExtractingTerms ||
                        _isSummarizing ||
                        transcripts.isEmpty)
                    ? null
                    : () => _extractTerms(transcripts),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isExtractingTerms
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.book_outlined,
                              size: 14,
                              color: Colors.teal.shade700,
                            ),
                      const SizedBox(width: 4),
                      Text(
                        '용어 추출',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.teal.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: _isSummarizing ? null : () => _showEditSummary(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: Colors.deepPurple.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '편집',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.deepPurple.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PushButton(
                controlSize: ControlSize.small,
                secondary: true,
                onPressed: () => _showHistory(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history,
                        size: 14,
                        color: Colors.indigo.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '이력',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              StreamBuilder<NativeModelTaskSnapshot>(
                stream: OnDeviceModelManager.instance.nativeTaskStream,
                initialData: OnDeviceModelManager.instance.nativeTaskSnapshot,
                builder: (context, snapshot) {
                  final active = snapshot.data?.activeLabel;
                  final reason = active == null
                      ? null
                      : '현재 $active 작업 중입니다. 완료 후 다시 요약해주세요.';
                  final disabled =
                      transcripts.isEmpty ||
                      _isSummarizing ||
                      _isRerunningStt ||
                      reason != null;
                  return _withDisabledReason(
                    reason,
                    PushButton(
                      controlSize: ControlSize.small,
                      color: Colors.indigo.shade600,
                      onPressed: disabled
                          ? null
                          : () => _runResummarize(
                              transcripts,
                              s,
                              notes: meeting?.notes ?? '',
                              meeting: meeting,
                            ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: MacosColors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '다시 요약',
                              style: TextStyle(
                                fontSize: 12,
                                color: MacosColors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (meeting != null) ...[
            _buildProcessingReport(meeting),
            const SizedBox(height: 8),
          ],
          _QualityScoreCard(
            report: MeetingQuality.analyze(
              summary: s,
              transcripts: transcripts,
            ),
          ),
          const SizedBox(height: 8),
          _SpeakerStatsCard(
            report: SpeakerStats.analyze(transcripts),
            speakerNames: _resolveSpeakerNames(meeting),
          ),
          const SizedBox(height: 8),
          _SectionCard(
            title: '회의 요약',
            icon: Icons.auto_awesome,
            child: SelectableText(
              displayTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (s.participants.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: '참석자',
              icon: Icons.people_outline,
              child: SelectableText(
                s.participants.join(', '),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
          // ── 어젠다 (있으면 표시, 클릭으로 편집) ────────────────
          if (meeting != null) ...[
            const SizedBox(height: 8),
            _AgendaCard(
              meeting: meeting,
              onChanged: () {
                ref.invalidate(meetingsProvider);
              },
            ),
          ],
          // ── 북마크 (사용자가 녹음 중 마킹한 핵심 시점) ─────────
          if (meeting != null) ...[
            () {
              final bms = _parseMeetingBookmarks(meeting);
              if (bms.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _BookmarksCard(
                  bookmarks: bms,
                  onJump: (sec) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final err = await _seekTranscriptAudio?.call(
                      sec.toDouble(),
                    );
                    if (!mounted) return;
                    final ok = err == null;
                    messenger.showSnackBar(
                      SnackBar(
                        duration: Duration(seconds: ok ? 2 : 4),
                        content: Text(
                          ok ? '북마크 지점으로 이동 + 오디오 재생' : '북마크 지점 전사로 이동 · $err',
                        ),
                        backgroundColor: ok
                            ? Colors.indigo.shade600
                            : Colors.blueGrey.shade600,
                      ),
                    );
                  },
                ),
              );
            }(),
          ],
          if (s.keyDiscussions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: '주요 논의',
              icon: Icons.chat_bubble_outline,
              child: _EvidenceBulletList(
                items: s.keyDiscussions,
                transcripts: transcripts,
                evidence: _evidenceList(s, 'keyDiscussions'),
                onEvidence: (item) {
                  final idx = s.keyDiscussions.indexOf(item);
                  _handleEvidenceTap(
                    title: '주요 논의 근거',
                    query: item,
                    transcripts: transcripts,
                    evidenceTs: _evidenceAt(s, 'keyDiscussions', idx),
                  );
                },
              ),
            ),
          ],
          if (s.decisions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: '결정 사항',
              icon: Icons.gavel,
              child: _EvidenceBulletList(
                items: s.decisions,
                transcripts: transcripts,
                evidence: _evidenceList(s, 'decisions'),
                onEvidence: (item) {
                  final idx = s.decisions.indexOf(item);
                  _handleEvidenceTap(
                    title: '결정 사항 근거',
                    query: item,
                    transcripts: transcripts,
                    evidenceTs: _evidenceAt(s, 'decisions', idx),
                  );
                },
              ),
            ),
          ],
          ..._buildActionItems(s, transcripts),
          if (s.openQuestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: '미해결 이슈',
              icon: Icons.help_outline,
              child: _EvidenceBulletList(
                items: s.openQuestions,
                transcripts: transcripts,
                evidence: _evidenceList(s, 'openQuestions'),
                onEvidence: (item) {
                  final idx = s.openQuestions.indexOf(item);
                  _handleEvidenceTap(
                    title: '미해결 이슈 근거',
                    query: item,
                    transcripts: transcripts,
                    evidenceTs: _evidenceAt(s, 'openQuestions', idx),
                  );
                },
              ),
            ),
          ],
          // ── 내 메모 ──────────────────────────────────────────
          if (meeting != null && meeting.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: '내 메모',
              icon: Icons.edit_note,
              child: _NotesEditor(
                meeting: meeting,
                onSaved: () => ref.invalidate(meetingsProvider),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildActionItems(Summary s, List<Transcript> transcripts) {
    List<ActionItem> items;
    try {
      items = (jsonDecode(s.actionItemsJson) as List)
          .map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      items = [];
    }
    final doneCount = items.where((a) => a.completed).length;
    final ownerUnconfirmedCount = items
        .where((a) => a.ownerNeedsConfirmation)
        .length;
    final deadlineUnconfirmedCount = items
        .where((a) => a.deadlineNeedsConfirmation)
        .length;
    return [
      const SizedBox(height: 8),
      _SectionCard(
        title: items.isEmpty ? '액션 아이템' : '액션 아이템 ($doneCount/${items.length})',
        icon: Icons.check_box_outlined,
        trailing: MacosTooltip(
          message: '액션 아이템 추가',
          child: MacosIconButton(
            icon: const Icon(Icons.add_circle_outline, size: 18),
            backgroundColor: Colors.transparent,
            padding: EdgeInsets.zero,
            boxConstraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
              maxWidth: 24,
              maxHeight: 24,
            ),
            onPressed: () => _editActionItem(s, items, null),
          ),
        ),
        child: items.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '아직 등록된 항목이 없습니다. + 버튼으로 추가하세요.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ownerUnconfirmedCount > 0 ||
                      deadlineUnconfirmedCount > 0) ...[
                    _ActionItemQualityNotice(
                      ownerUnconfirmedCount: ownerUnconfirmedCount,
                      deadlineUnconfirmedCount: deadlineUnconfirmedCount,
                    ),
                    const SizedBox(height: 6),
                  ],
                  for (int i = 0; i < items.length; i++)
                    _ActionItemRow(
                      item: items[i],
                      evidenceTs: _evidenceAt(s, 'actionItems', i),
                      onToggle: (v) => _toggleActionItem(s, items, i, v),
                      onEdit: () => _editActionItem(s, items, i),
                      onDelete: () => _deleteActionItem(s, items, i),
                      onEvidence: transcripts.isEmpty
                          ? null
                          : () {
                              final item = items[i];
                              final parts = [
                                item.task,
                                if (item.owner.isNotEmpty) item.owner,
                                if (item.deadline.isNotEmpty) item.deadline,
                              ];
                              _handleEvidenceTap(
                                title: '액션 아이템 근거',
                                query: parts.join(' '),
                                transcripts: transcripts,
                                evidenceTs: _evidenceAt(s, 'actionItems', i),
                              );
                            },
                    ),
                ],
              ),
      ),
    ];
  }

  Widget _buildProcessingReport(Meeting meeting) {
    final report = MeetingProcessingReport.fromJsonString(
      meeting.processingReportJson,
    );
    if (!report.hasAnyData) return const SizedBox.shrink();

    // 일반 사용자용: 단계 + 소요 시간만 표시 (모델명/상태 등은 고급 정보로 이동)
    final items = <Widget>[];
    if (report.inputQualityStatus == 'empty' ||
        report.inputQualityStatus == 'low') {
      items.add(
        _ReportMetric(
          icon: report.inputQualityStatus == 'empty'
              ? Icons.hearing_disabled_outlined
              : Icons.warning_amber_rounded,
          label: '녹음 품질',
          value: _inputQualityStatusLabel(report.inputQualityStatus),
          subLabel: report.inputQualityReason,
          accentColor: report.inputQualityStatus == 'empty'
              ? Colors.red.shade700
              : Colors.orange.shade700,
        ),
      );
    }
    if (report.sttElapsedMs > 0 || report.sttModel.isNotEmpty) {
      items.add(
        _ReportMetric(
          icon: Icons.graphic_eq,
          label: '음성 인식',
          value: _durationKrFromMs(report.sttElapsedMs),
          subLabel: '',
        ),
      );
    }
    if (report.diarizationEnabled || report.diarizationStatus.isNotEmpty) {
      items.add(
        _ReportMetric(
          icon: Icons.record_voice_over_outlined,
          label: '발화자 라벨',
          value: report.diarizationStatus == 'success'
              ? _durationKrFromMs(report.diarizationElapsedMs)
              : _diarizationStatusLabel(report.diarizationStatus),
          subLabel: '',
        ),
      );
    }
    if (report.summaryElapsedMs > 0 || report.llmModel.isNotEmpty) {
      items.add(
        _ReportMetric(
          icon: Icons.auto_awesome,
          label: '요약 생성',
          value: _durationKrFromMs(report.summaryElapsedMs),
          subLabel: '',
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: '작업 시간',
      icon: Icons.speed_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: items),
          const SizedBox(height: 4),
          _AdvancedReportInfo(report: report),
        ],
      ),
    );
  }

  String _diarizationStatusLabel(String status) => switch (status) {
    'success' => '성공',
    'failed' => '실패',
    'skipped' => '건너뜀',
    'disabled' => '비활성',
    _ => status.isEmpty ? '-' : status,
  };

  String _inputQualityStatusLabel(String status) => switch (status) {
    'empty' => '마이크 입력 낮음',
    'low' => '전사 부족',
    'ok' => '정상',
    _ => status.isEmpty ? '-' : status,
  };

  Future<void> _toggleActionItem(
    Summary s,
    List<ActionItem> items,
    int index,
    bool value,
  ) async {
    final updated = [...items];
    updated[index] = items[index].copyWith(completed: value);
    await _persistActionItems(s, updated);
  }

  Future<void> _editActionItem(
    Summary s,
    List<ActionItem> items,
    int? index,
  ) async {
    final result = await showMacosAlertDialog<ActionItem>(
      context: context,
      builder: (_) =>
          _ActionItemEditDialog(existing: index == null ? null : items[index]),
    );
    if (result == null) return;
    final updated = [...items];
    if (index == null) {
      updated.add(result);
    } else {
      // 완료 상태는 기존 값 유지
      updated[index] = ActionItem(
        task: result.task,
        owner: result.owner,
        deadline: result.deadline,
        completed: items[index].completed,
        ownerConfirmed: result.ownerConfirmed,
        deadlineConfirmed: result.deadlineConfirmed,
      );
    }
    await _persistActionItems(s, updated);
  }

  Future<void> _deleteActionItem(
    Summary s,
    List<ActionItem> items,
    int index,
  ) async {
    final ok = await showMacosAlertDialog<bool>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const Icon(
          Icons.delete_outline,
          color: Colors.orange,
          size: 48,
        ),
        title: const Text('액션 아이템 삭제'),
        message: Text(
          '"${items[index].task}" 을(를) 삭제할까요?',
          textAlign: TextAlign.center,
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          color: MacosColors.systemRedColor,
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제', style: TextStyle(color: MacosColors.white)),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
      ),
    );
    if (ok != true) return;
    final updated = [...items]..removeAt(index);
    await _persistActionItems(s, updated);
  }

  Future<void> _persistActionItems(Summary s, List<ActionItem> updated) async {
    s.actionItemsJson = jsonEncode(updated.map((a) => a.toJson()).toList());
    await SummaryRepositoryImpl(IsarService.instance.db).saveSummary(s);
    if (mounted) {
      ref.invalidate(meetingSummaryProvider(widget.meetingId));
    }
  }

  Widget _buildNoSummary(
    List<Transcript> transcripts,
    Summary? summary, {
    Meeting? meeting,
  }) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.summarize_outlined, size: 40, color: Colors.grey.shade400),
        const SizedBox(height: 8),
        Text('요약이 없습니다.', style: TextStyle(color: Colors.grey.shade500)),
        if (transcripts.isNotEmpty) ...[
          const SizedBox(height: 16),
          StreamBuilder<NativeModelTaskSnapshot>(
            stream: OnDeviceModelManager.instance.nativeTaskStream,
            initialData: OnDeviceModelManager.instance.nativeTaskSnapshot,
            builder: (context, snapshot) {
              final active = snapshot.data?.activeLabel;
              final reason = active == null
                  ? null
                  : '현재 $active 작업 중입니다. 완료 후 요약을 생성해주세요.';
              final disabled =
                  _isSummarizing || _isRerunningStt || reason != null;
              return _withDisabledReason(
                reason,
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: const Text('요약 생성'),
                  onPressed: disabled
                      ? null
                      : () => _runResummarize(
                          transcripts,
                          null,
                          notes: meeting?.notes ?? '',
                          meeting: meeting,
                        ),
                ),
              );
            },
          ),
        ],
      ],
    ),
  );
}

class _DetailPaneResizeHandle extends StatelessWidget {
  final double width;
  final ValueChanged<double> onDrag;

  const _DetailPaneResizeHandle({required this.width, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: width,
          child: Center(
            child: Container(
              width: 6,
              decoration: BoxDecoration(
                color: divider.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(
                child: Container(
                  width: 2,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade500.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 내보내기 팝업 메뉴 ─────────────────────────────────────────────
class _ExportMenu extends StatefulWidget {
  final Meeting meeting;
  final Summary? summary;
  final List<Transcript> transcripts;
  final bool enabled;

  const _ExportMenu({
    required this.meeting,
    required this.summary,
    required this.transcripts,
    required this.enabled,
  });

  @override
  State<_ExportMenu> createState() => _ExportMenuState();
}

class _ExportMenuState extends State<_ExportMenu> {
  bool _busy = false;

  Future<void> _handle(String action) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      switch (action) {
        case 'txt':
          final path = await ExportService.saveAsTxt(
            widget.meeting,
            widget.summary,
            widget.transcripts,
          );
          if (mounted) {
            if (path != null) {
              _showSnack('텍스트 저장 완료 — 클릭하여 열기', openPath: path);
            } else {
              _showSnack('저장 취소됨');
            }
          }
          break;

        case 'markdown':
          final path = await ExportService.saveAsMarkdown(
            widget.meeting,
            widget.summary,
            widget.transcripts,
          );
          if (mounted) {
            if (path != null) {
              _showSnack('Markdown 저장 완료 — 클릭하여 열기', openPath: path);
            } else {
              _showSnack('저장 취소됨');
            }
          }
          break;

        case 'copy_markdown':
          await ExportService.copyMarkdown(
            widget.meeting,
            widget.summary,
            widget.transcripts,
          );
          if (mounted) _showSnack('Markdown 복사 완료');
          break;

        case 'copy_notion':
          await ExportService.copyNotionMarkdown(
            widget.meeting,
            widget.summary,
          );
          if (mounted) _showSnack('Notion용 요약 복사 완료');
          break;

        case 'copy_report':
          await ExportService.copyBusinessReportMarkdown(
            widget.meeting,
            widget.summary,
          );
          if (mounted) _showSnack('보고서 형식 복사 완료');
          break;

        case 'report_pdf':
          String? path;
          path = await ExportService.saveAsBusinessReportPdf(
            widget.meeting,
            widget.summary,
          );
          if (mounted) {
            if (path != null) {
              _showSnack('보고서 PDF 저장 완료 — 클릭하여 열기', openPath: path);
            } else {
              _showSnack('저장 취소됨');
            }
          }
          break;

        case 'report_docx':
          final path = await ExportService.saveAsBusinessReportDocx(
            widget.meeting,
            widget.summary,
          );
          if (mounted) {
            if (path != null) {
              _showSnack('보고서 Word 문서 저장 완료 — 클릭하여 열기', openPath: path);
            } else {
              _showSnack('저장 취소됨');
            }
          }
          break;

        case 'copy_actions':
          await ExportService.copyActionItems(widget.meeting, widget.summary);
          if (mounted) _showSnack('액션아이템 복사 완료');
          break;

        case 'pdf':
          String? path;
          path = await ExportService.saveAsPdf(
            widget.meeting,
            widget.summary,
            widget.transcripts,
            onFontError: () {
              if (mounted) {
                _showSnack(
                  '한국어 폰트를 찾을 수 없습니다. 텍스트(.txt)로 저장해주세요.',
                  isError: true,
                );
              }
            },
          );
          if (mounted) {
            if (path != null) {
              _showSnack('PDF 저장 완료 — 클릭하여 열기', openPath: path);
            }
          }
          break;

        case 'docx':
          final path = await ExportService.saveAsDocx(
            widget.meeting,
            widget.summary,
            widget.transcripts,
          );
          if (mounted) {
            if (path != null) {
              _showSnack('Word 문서 저장 완료 — 클릭하여 열기', openPath: path);
            } else {
              _showSnack('저장 취소됨');
            }
          }
          break;

        case 'email':
          final ok = await ExportService.openEmail(
            widget.meeting,
            widget.summary,
          );
          if (mounted && !ok) {
            _showSnack('메일 앱을 열 수 없습니다.', isError: true);
          }
          break;

        case 'share':
          await ExportService.shareText(
            widget.meeting,
            widget.summary,
            widget.transcripts,
          );
          break;
      }
    } catch (e) {
      if (mounted) _showSnack('내보내기 오류: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg, {bool isError = false, String? openPath}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: openPath != null
            ? GestureDetector(
                onTap: () {
                  Process.run('open', [openPath]);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                child: Row(
                  children: [
                    Expanded(child: Text(msg)),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.open_in_new,
                      size: 15,
                      color: Colors.white70,
                    ),
                  ],
                ),
              )
            : Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _busy
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : PopupMenuButton<String>(
            enabled: widget.enabled,
            tooltip: '내보내기',
            icon: Icon(
              Icons.ios_share,
              color: widget.enabled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade400,
            ),
            onSelected: _handle,
            itemBuilder: (ctx) => [
              _menuItem('txt', Icons.text_snippet_outlined, '텍스트로 저장 (.txt)'),
              _menuItem(
                'markdown',
                Icons.integration_instructions_outlined,
                'Markdown으로 저장 (.md)',
              ),
              _menuItem(
                'copy_markdown',
                Icons.content_copy_outlined,
                'Markdown 복사',
              ),
              _menuItem(
                'copy_notion',
                Icons.dashboard_customize_outlined,
                'Notion용 요약 복사',
              ),
              _menuItem('copy_report', Icons.assignment_outlined, '보고서 형식 복사'),
              _menuItem(
                'report_pdf',
                Icons.request_page_outlined,
                '보고서 PDF 저장',
              ),
              _menuItem('report_docx', Icons.article_outlined, '보고서 Word 저장'),
              _menuItem('copy_actions', Icons.checklist_outlined, '액션아이템만 복사'),
              _menuItem('pdf', Icons.picture_as_pdf_outlined, 'PDF로 저장 (.pdf)'),
              _menuItem(
                'docx',
                Icons.description_outlined,
                'Word 문서로 저장 (.docx)',
              ),
              const PopupMenuDivider(),
              _menuItem('email', Icons.email_outlined, '이메일로 보내기'),
              _menuItem('share', Icons.share_outlined, '공유하기'),
            ],
          );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

// ── 공통 위젯 ────────────────────────────────────────────────────
/// 북마크 카드 — 녹음 중 사용자가 마킹한 핵심 시점들. 클릭으로 점프.
class _BookmarksCard extends StatelessWidget {
  final List<Bookmark> bookmarks;
  final ValueChanged<int> onJump;

  const _BookmarksCard({required this.bookmarks, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final amber = Colors.amber.shade700;
    return _SectionCard(
      title: '핵심 마킹 (${bookmarks.length})',
      icon: Icons.bookmark_rounded,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final b in bookmarks)
            MacosTooltip(
              message: '${b.timeStr} 시점으로 이동',
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onJump(b.sec),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_rounded, size: 12, color: amber),
                      const SizedBox(width: 5),
                      Text(
                        b.timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: amber,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (b.label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          b.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 회의 어젠다 카드 — 입력된 어젠다 항목을 체크리스트 스타일로 표시.
/// 어젠다가 없으면 "어젠다 추가" 버튼만 보여줌. 클릭 시 편집 다이얼로그.
class _AgendaCard extends StatelessWidget {
  final Meeting meeting;
  final VoidCallback onChanged;

  const _AgendaCard({required this.meeting, required this.onChanged});

  Future<void> _editAgenda(BuildContext context) async {
    final ctrl = TextEditingController(text: meeting.agenda);
    final result = await showMacosSheet<String?>(
      context: context,
      builder: (ctx) => MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '회의 어젠다',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '한 줄에 하나씩 입력하세요. 다시 요약 시 항목별로 정리됩니다.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      maxLines: 8,
                      minLines: 4,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '예:\n- 신규 피처 일정\n- QA 리소스 확보',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (meeting.agenda.isNotEmpty) ...[
                    PushButton(
                      controlSize: ControlSize.large,
                      secondary: true,
                      onPressed: () => Navigator.pop(ctx, ''),
                      child: const Text(
                        '지우기',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    child: const Text('저장'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return;
    meeting.agenda = result;
    await MeetingRepositoryImpl(IsarService.instance.db).updateMeeting(meeting);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final agenda = meeting.agenda.trim();
    final lines = agenda
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'^[\-•*]\s*'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return _SectionCard(
      title: '어젠다',
      icon: Icons.checklist_rtl_outlined,
      trailing: MacosTooltip(
        message: agenda.isEmpty ? '어젠다 추가' : '어젠다 편집',
        child: MacosIconButton(
          icon: Icon(
            agenda.isEmpty ? Icons.add_circle_outline : Icons.edit_outlined,
            size: 16,
          ),
          backgroundColor: Colors.transparent,
          padding: EdgeInsets.zero,
          boxConstraints: const BoxConstraints(
            minWidth: 22,
            minHeight: 22,
            maxWidth: 22,
            maxHeight: 22,
          ),
          onPressed: () => _editAgenda(context),
        ),
      ),
      child: lines.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '어젠다가 없습니다. + 버튼으로 추가하면 다음 요약에 반영됩니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6, right: 8),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            lines[i],
                            style: const TextStyle(fontSize: 13, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
            const Divider(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SpeakerStatsCard extends StatelessWidget {
  final SpeakerStatsReport report;
  final Map<String, String> speakerNames;
  const _SpeakerStatsCard({required this.report, required this.speakerNames});

  static const _palette = <Color>[
    Color(0xFF4F46E5), // indigo
    Color(0xFF0D9488), // teal
    Color(0xFFEA580C), // orange
    Color(0xFFDB2777), // pink
    Color(0xFF7C3AED), // violet
    Color(0xFF65A30D), // lime
    Color(0xFF0891B2), // cyan
    Color(0xFFCA8A04), // amber
  ];

  String _displayLabel(String label) {
    final name = speakerNames[label]?.trim();
    if (name == null || name.isEmpty) return '화자 $label';
    return '$name (화자 $label)';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '$s초';
    return '$m분 $s초';
  }

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) return const SizedBox.shrink();
    if (report.speakerCount == 0) {
      // 라벨이 전혀 없는 경우 — 카드를 띄우지 않음 (소음 방지)
      return const SizedBox.shrink();
    }
    return _SectionCard(
      title: '발언 통계',
      icon: Icons.record_voice_over_outlined,
      trailing: Text(
        '${report.speakerCount}명 식별 · ${_formatDuration(report.labeledDuration)}',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 누적 가로 막대
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (var i = 0; i < report.speakers.length; i++)
                    Expanded(
                      flex: (report.speakers[i].percentage * 1000).round(),
                      child: Container(color: _palette[i % _palette.length]),
                    ),
                  if (report.unlabeledDuration > Duration.zero)
                    Expanded(
                      flex:
                          ((report.unlabeledDuration.inMilliseconds /
                                      report.totalDuration.inMilliseconds) *
                                  1000)
                              .round(),
                      child: Container(color: Colors.grey.shade300),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 화자별 행
          for (var i = 0; i < report.speakers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _palette[i % _palette.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _displayLabel(report.speakers[i].label),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(report.speakers[i].percentage * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 76,
                    child: Text(
                      '${_formatDuration(report.speakers[i].duration)} · ${report.speakers[i].segmentCount}회',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          if (report.unlabeledDuration > Duration.zero) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '미식별 (${report.unlabeledSegmentCount}개 세그먼트)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
                Text(
                  _formatDuration(report.unlabeledDuration),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QualityScoreCard extends StatelessWidget {
  final MeetingQualityReport report;
  const _QualityScoreCard({required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) return const SizedBox.shrink();
    final gradeColor = _gradeColor(report.overallScore);
    return _SectionCard(
      title: '회의 품질',
      icon: Icons.insights_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: gradeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: gradeColor.withValues(alpha: 0.4)),
        ),
        child: Text(
          '${report.overallScore} · ${report.gradeLabel}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: gradeColor,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _QualitySubScore(label: '결정', score: report.decisionsScore),
              _QualitySubScore(label: '액션', score: report.actionsScore),
              _QualitySubScore(label: '발화 균형', score: report.balanceScore),
              _QualitySubScore(label: '근거', score: report.evidenceScore),
            ],
          ),
          if (report.hints.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final h in report.hints)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      h.severity == QualityHintSeverity.warning
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 13,
                      color: h.severity == QualityHintSeverity.warning
                          ? Colors.orange.shade700
                          : Colors.blue.shade600,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        h.message,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  static Color _gradeColor(int score) {
    if (score >= 85) return Colors.green.shade700;
    if (score >= 70) return Colors.indigo.shade600;
    if (score >= 50) return Colors.amber.shade700;
    return Colors.red.shade600;
  }
}

class _QualitySubScore extends StatelessWidget {
  final String label;
  final int score;
  const _QualitySubScore({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    final color = _color(score);
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              const Spacer(),
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 4,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  static Color _color(int score) {
    if (score >= 85) return Colors.green.shade600;
    if (score >= 70) return Colors.indigo.shade500;
    if (score >= 50) return Colors.amber.shade700;
    return Colors.red.shade500;
  }
}

class _ReportMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subLabel;
  final Color? accentColor;

  const _ReportMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.subLabel,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subLabel.isNotEmpty && subLabel != '-') ...[
                  const SizedBox(height: 1),
                  Text(
                    subLabel,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 처리 리포트의 "고급 정보" 접기 — RTF, 모델 파일명, 오디오 길이 등
/// 일반 사용자 화면에는 보이지 않고, 클릭하면 펼쳐짐.
class _AdvancedReportInfo extends StatelessWidget {
  final MeetingProcessingReport report;

  const _AdvancedReportInfo({required this.report});

  String _sttModeLabel(String model) {
    if (model.contains('turbo')) return '빠른 모드';
    if (model.contains('q5') || model.contains('large-v3')) return '정확 모드';
    return model.isEmpty ? '-' : model;
  }

  String _llmDisplayName(String id) => switch (id) {
    'qwen25_7b' => 'Qwen 2.5 7B',
    'gemma4_e2b' => 'Gemma 4 E2B',
    _ => id.isEmpty ? '-' : id,
  };

  String _diarStatusLabel(String status) => switch (status) {
    'success' => '성공',
    'failed' => '실패',
    'skipped' => '건너뜀',
    'disabled' => '비활성',
    _ => status.isEmpty ? '-' : status,
  };

  String _inputQualityLabel(String status) => switch (status) {
    'empty' => '거의 빈 녹음',
    'low' => '요약 품질 낮을 수 있음',
    'ok' => '정상',
    _ => status.isEmpty ? '-' : status,
  };

  String _durationKr(int ms) {
    if (ms <= 0) return '-';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m분 $s초';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    if (report.inputQualityStatus.isNotEmpty) {
      rows.add(
        _AdvancedRow(
          label: '녹음 품질',
          value: _inputQualityLabel(report.inputQualityStatus),
        ),
      );
      if (report.inputQualityReason.isNotEmpty) {
        rows.add(
          _AdvancedRow(label: '품질 사유', value: report.inputQualityReason),
        );
      }
      rows.add(
        _AdvancedRow(
          label: '전사 글자/세그먼트',
          value:
              '${report.inputRecognizedChars}자 / ${report.inputSegmentCount}개',
        ),
      );
      if (report.inputMaxLevel > 0) {
        rows.add(
          _AdvancedRow(
            label: '최대 입력 레벨',
            value: '${(report.inputMaxLevel * 100).toStringAsFixed(0)}%',
          ),
        );
      }
    }

    if (report.sttModel.isNotEmpty || report.sttAudioMs > 0) {
      rows.add(
        _AdvancedRow(label: '음성 인식 모드', value: _sttModeLabel(report.sttModel)),
      );
      if (report.sttProcessingMode.isNotEmpty) {
        rows.add(
          _AdvancedRow(
            label: '음성 인식 처리 방식',
            value: AppSettings.sttProcessingModeLabel(report.sttProcessingMode),
          ),
        );
      }
      if (report.sttLanguage.isNotEmpty) {
        rows.add(
          _AdvancedRow(
            label: '음성 인식 언어',
            value: AppSettings.sttLanguageLabel(report.sttLanguage),
          ),
        );
      }
      if (report.sttModel.isNotEmpty) {
        rows.add(_AdvancedRow(label: '음성 인식 모델 파일', value: report.sttModel));
      }
      if (report.sttAudioMs > 0) {
        rows.add(
          _AdvancedRow(label: '오디오 길이', value: _durationKr(report.sttAudioMs)),
        );
      }
      if (report.sttRtf > 0) {
        rows.add(
          _AdvancedRow(
            label: '처리 속도(RTF)',
            value: '${report.sttRtf.toStringAsFixed(2)}x',
          ),
        );
      }
    }

    if (report.diarizationEnabled || report.diarizationStatus.isNotEmpty) {
      rows.add(
        _AdvancedRow(
          label: '발화자 라벨 상태',
          value: _diarStatusLabel(report.diarizationStatus),
        ),
      );
    }

    if (report.llmModel.isNotEmpty) {
      rows.add(
        _AdvancedRow(label: '요약 모델', value: _llmDisplayName(report.llmModel)),
      );
      rows.add(_AdvancedRow(label: '요약 모델 ID', value: report.llmModel));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Theme(
      // ExpansionTile 기본 divider/padding 영향 최소화
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 4, top: 4, bottom: 6),
        dense: true,
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
        title: Text(
          '고급 정보',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        children: rows,
      ),
    );
  }
}

class _AdvancedRow extends StatelessWidget {
  final String label;
  final String value;
  const _AdvancedRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _RerunSttOptions {
  final String sttMode;
  final bool useDiarization;
  final String sttLanguage;

  const _RerunSttOptions({
    required this.sttMode,
    required this.useDiarization,
    required this.sttLanguage,
  });
}

class _EstimateRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;

  const _EstimateRow({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
              color: emphasis ? color.primary : color.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
              color: emphasis ? color.primary : color.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceCandidate {
  final Transcript transcript;
  final double score;

  const _EvidenceCandidate({required this.transcript, required this.score});
}

class _EvidenceBulletList extends StatelessWidget {
  final List<String> items;
  final List<Transcript> transcripts;
  final ValueChanged<String> onEvidence;

  /// LLM이 명시한 근거 타임스탬프 (인덱스 1:1, 빈 문자열 = 미명시)
  final List<String> evidence;

  const _EvidenceBulletList({
    required this.items,
    required this.transcripts,
    required this.onEvidence,
    this.evidence = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('•', style: TextStyle(fontSize: 13, height: 1.5)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    items[i],
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (transcripts.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _EvidenceButton(
                    timestamp: i < evidence.length ? evidence[i] : '',
                    onPressed: () => onEvidence(items[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _EvidenceButton extends StatelessWidget {
  final String timestamp;
  final VoidCallback onPressed;

  const _EvidenceButton({required this.timestamp, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final ts = timestamp.trim();
    final hasTimestamp = ts.isNotEmpty;
    final color = Theme.of(context).colorScheme;
    final foreground = hasTimestamp ? color.primary : Colors.orange.shade700;
    final borderColor = hasTimestamp
        ? color.primary.withValues(alpha: 0.38)
        : Colors.orange.shade300;
    final background = hasTimestamp
        ? color.primary.withValues(alpha: 0.08)
        : Colors.orange.shade50;

    return MacosTooltip(
      message: hasTimestamp
          ? '$ts 시점으로 이동'
          : 'LLM이 근거 타임스탬프를 명시하지 않았습니다. 키워드 검색으로 후보 구간을 찾아보세요.',
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: foreground,
          backgroundColor: background,
          side: BorderSide(color: borderColor),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        icon: Icon(
          hasTimestamp
              ? Icons.play_circle_outline
              : Icons.warning_amber_rounded,
          size: 13,
        ),
        label: Text(hasTimestamp ? '근거 $ts' : '근거 미명시'),
        onPressed: onPressed,
      ),
    );
  }
}

// ── 그룹 선택 드롭다운 ─────────────────────────────────────────────
class _GroupSelector extends StatelessWidget {
  final Meeting meeting;
  final List<MeetingGroup> groups;
  final void Function(int? groupId) onChanged;

  const _GroupSelector({
    required this.meeting,
    required this.groups,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final currentGroup = groups
        .where((g) => g.id == meeting.groupId)
        .firstOrNull;

    return PopupMenuButton<int?>(
      tooltip: '그룹 변경',
      offset: const Offset(0, 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: currentGroup != null
              ? Colors.amber.shade50
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: currentGroup != null
                ? Colors.amber.shade300
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              currentGroup != null ? Icons.folder : Icons.folder_open,
              size: 13,
              color: currentGroup != null
                  ? Colors.amber.shade700
                  : Colors.grey.shade500,
            ),
            const SizedBox(width: 4),
            Text(
              currentGroup?.name ?? '미분류',
              style: TextStyle(
                fontSize: 12,
                color: currentGroup != null
                    ? Colors.amber.shade800
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: currentGroup != null
                  ? Colors.amber.shade700
                  : Colors.grey.shade500,
            ),
          ],
        ),
      ),
      itemBuilder: (ctx) => [
        // 미분류
        PopupMenuItem<int?>(
          value: -1, // sentinel: 미분류
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Text(
                '미분류',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: meeting.groupId == null
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              if (meeting.groupId == null) ...[
                const Spacer(),
                Icon(Icons.check, size: 14, color: Colors.indigo.shade400),
              ],
            ],
          ),
        ),
        if (groups.isNotEmpty) const PopupMenuDivider(),
        // 각 그룹
        for (final g in groups)
          PopupMenuItem<int?>(
            value: g.id,
            child: Row(
              children: [
                Icon(Icons.folder, size: 16, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Text(
                  g.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: meeting.groupId == g.id
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                if (meeting.groupId == g.id) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 14, color: Colors.indigo.shade400),
                ],
              ],
            ),
          ),
      ],
      onSelected: (value) {
        // -1 = 미분류(null), 그 외는 실제 groupId
        onChanged(value == -1 ? null : value);
      },
    );
  }
}

// ── 태그 행 ─────────────────────────────────────────────────────────
class _MeetingTagsRow extends ConsumerStatefulWidget {
  final Meeting meeting;
  const _MeetingTagsRow({required this.meeting});

  @override
  ConsumerState<_MeetingTagsRow> createState() => _MeetingTagsRowState();
}

class _MeetingTagsRowState extends ConsumerState<_MeetingTagsRow> {
  bool _isSuggestingTags = false;

  Future<void> _save() async {
    await MeetingRepositoryImpl(
      IsarService.instance.db,
    ).updateMeeting(widget.meeting);
    ref.invalidate(meetingsProvider);
  }

  String? _tagSuggestionBlockReason() {
    if (ref.read(isSummarizingProvider)) {
      return '요약 작업이 끝난 뒤 태그 추천을 다시 시도해주세요.';
    }
    final active = OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (active != null) {
      return '현재 $active 작업 중입니다. 완료 후 태그 추천을 다시 시도해주세요.';
    }
    return null;
  }

  void _showTagSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<void> _addTag() async {
    final ctrl = TextEditingController();
    final existing = await _collectAllTags();
    final suggestions = existing
        .where((t) => !widget.meeting.tags.contains(t))
        .toList();

    if (!mounted) return;
    final result = await showMacosAlertDialog<String>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const Icon(Icons.tag, size: 48),
        title: const Text('태그 추가'),
        message: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '태그 이름',
                  hintText: '예: 기획, 1on1, 리뷰',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '기존 태그',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in suggestions.take(20))
                      ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        onPressed: () => Navigator.pop(ctx, s),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('추가'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
      ),
    );

    final tag = result?.trim();
    if (tag == null || tag.isEmpty) return;
    if (widget.meeting.tags.contains(tag)) return;
    setState(() => widget.meeting.tags = [...widget.meeting.tags, tag]);
    await _save();
  }

  Future<void> _suggestTags() async {
    if (_isSuggestingTags) return;
    final blockReason = _tagSuggestionBlockReason();
    if (blockReason != null) {
      _showTagSnack(blockReason, backgroundColor: Colors.orange.shade700);
      return;
    }

    final db = IsarService.instance.db;
    final summary = await SummaryRepositoryImpl(
      db,
    ).getSummaryByMeetingId(widget.meeting.id);
    if (summary == null) {
      _showTagSnack('요약을 먼저 생성하면 태그를 추천할 수 있습니다.');
      return;
    }

    final appSupport = await getApplicationSupportDirectory();
    final llmId = AppSettings.instance.selectedLlmModel;
    final modelFile = AppSettings.llmModelFileFor(llmId);
    final modelPath = '${appSupport.path}/models/$modelFile';
    if (!await File(modelPath).exists()) {
      _showTagSnack('요약 모델을 먼저 준비한 뒤 태그 추천을 사용할 수 있습니다.');
      return;
    }

    if (mounted) setState(() => _isSuggestingTags = true);
    List<String> candidates = const [];
    try {
      await OnDeviceModelManager.instance.loadLlm(
        modelPath,
        nCtx: 4096,
        nBatch: 512,
      );
      final suggested = await TagExtractor.extractFromSummary(
        summary,
        notes: widget.meeting.notes,
        agenda: widget.meeting.agenda,
      );
      final existingKeys = widget.meeting.tags
          .map(TagExtractor.normalizeTagKey)
          .toSet();
      candidates = suggested
          .where(
            (tag) => !existingKeys.contains(TagExtractor.normalizeTagKey(tag)),
          )
          .toList();
    } catch (e, st) {
      debugPrint('[TagExtractor] manual suggestion failed: $e\n$st');
      _showTagSnack('태그 추천에 실패했습니다. 잠시 뒤 다시 시도해주세요.');
      return;
    } finally {
      await OnDeviceModelManager.instance.unloadLlm().catchError((_) {});
      if (mounted) setState(() => _isSuggestingTags = false);
    }

    if (!mounted) return;
    if (candidates.isEmpty) {
      _showTagSnack('새로 추천할 태그가 없습니다.');
      return;
    }

    final selected = await _pickSuggestedTags(candidates);
    if (selected == null || selected.isEmpty) return;

    setState(() {
      widget.meeting.tags = TagExtractor.mergeTags(
        widget.meeting.tags,
        selected,
      );
    });
    await _save();
    _showTagSnack('추천 태그를 추가했습니다.', backgroundColor: Colors.green.shade700);
  }

  Future<List<String>?> _pickSuggestedTags(List<String> candidates) {
    final selected = candidates.toSet();
    return showMacosAlertDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => MacosAlertDialog(
          appIcon: const Icon(Icons.sell_outlined, size: 48),
          title: const Text('추천 태그'),
          message: SizedBox(
            width: 360,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in candidates)
                  FilterChip(
                    label: Text('#$tag'),
                    selected: selected.contains(tag),
                    onSelected: (value) {
                      setDialogState(() {
                        if (value) {
                          selected.add(tag);
                        } else {
                          selected.remove(tag);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(ctx, selected.toList()),
            child: const Text('선택한 태그 추가'),
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
        ),
      ),
    );
  }

  Future<List<String>> _collectAllTags() async {
    final meetings = await MeetingRepositoryImpl(
      IsarService.instance.db,
    ).getAllMeetings();
    final set = <String>{};
    for (final m in meetings) {
      set.addAll(m.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _removeTag(String tag) async {
    setState(
      () => widget.meeting.tags = widget.meeting.tags
          .where((t) => t != tag)
          .toList(),
    );
    await _save();
  }

  /// 태그 칩 클릭 → 사이드바 검색에 자동 입력 (단어 모드)
  void _searchByTag(String tag) {
    ref.read(searchQueryProvider.notifier).state = tag;
    ref.read(isAiSearchModeProvider.notifier).state = false;
    ref.read(aiSearchResultsProvider.notifier).state = null;
    // 검색창에 포커스 (Cmd+F와 동일 효과)
    ref.read(shortcutFocusSearchSignalProvider.notifier).update((s) => s + 1);
    // 토스트로 알려주기 — 사이드바가 좁아져 안 보일 수 있음
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('태그 "$tag"로 검색합니다'),
        backgroundColor: Colors.indigo.shade600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tags = widget.meeting.tags;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.sell_outlined, size: 13, color: Colors.grey.shade500),
        for (final t in tags)
          InputChip(
            label: Text('#$t', style: const TextStyle(fontSize: 11)),
            onPressed: () => _searchByTag(t),
            onDeleted: () => _removeTag(t),
            deleteIconColor: Colors.grey.shade600,
            backgroundColor: Colors.indigo.shade50,
            side: BorderSide(color: Colors.indigo.shade200),
            labelStyle: TextStyle(color: Colors.indigo.shade700),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            tooltip: '#$t 태그로 검색',
          ),
        ActionChip(
          avatar: Icon(Icons.add, size: 13, color: Colors.grey.shade600),
          label: Text(
            tags.isEmpty ? '태그 추가' : '추가',
            style: const TextStyle(fontSize: 11),
          ),
          onPressed: _addTag,
          backgroundColor: Colors.grey.shade50,
          side: BorderSide(color: Colors.grey.shade300),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        ),
        ActionChip(
          avatar: _isSuggestingTags
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.teal.shade700,
                  ),
                )
              : Icon(Icons.auto_awesome, size: 13, color: Colors.teal.shade700),
          label: Text(
            _isSuggestingTags ? '추천 중' : '추천',
            style: const TextStyle(fontSize: 11),
          ),
          onPressed: _isSuggestingTags ? null : _suggestTags,
          backgroundColor: Colors.teal.shade50,
          side: BorderSide(color: Colors.teal.shade200),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          tooltip: '요약 내용으로 태그 추천',
        ),
      ],
    );
  }
}

// ── 전사본 + 오디오 플레이어 ─────────────────────────────────────────

/// 전사본 목록 + 인라인 오디오 플레이어
///
/// [audioFilePath] != null 이면:
///   - 상단에 미니 플레이어 바 (재생/정지, 슬라이더, 시간)
///   - 각 세그먼트 행: 클릭 or ▶ 버튼으로 해당 위치로 seek + 재생
///   - 현재 재생 중인 세그먼트 강조 표시
class _TranscriptWithAudio extends StatefulWidget {
  final List<Transcript> segments;
  final String? audioFilePath;
  final VoidCallback? onRerunStt;
  final bool isRerunning;
  final VoidCallback? onTranscriptChanged;

  /// 화자 라벨 편집(이름 변경/통합)에 사용. null이면 편집 불가.
  final Meeting? meeting;

  /// 사용자가 녹음 중 마킹한 북마크 — 세그먼트 옆 ★ 표시에 사용
  final List<Bookmark> bookmarks;

  /// 부모가 자식의 seek 함수를 등록받기 위한 콜백.
  /// 자식 init 시 (fn) 호출, dispose 시 (null) 호출.
  /// 반환값: null=오디오 재생 성공, 외에는 실패 사유 문자열.
  final ValueChanged<Future<String?> Function(double sec)?>? onSeekRegister;

  const _TranscriptWithAudio({
    super.key,
    required this.segments,
    this.audioFilePath,
    this.onRerunStt,
    this.isRerunning = false,
    this.onTranscriptChanged,
    this.onSeekRegister,
    this.meeting,
    this.bookmarks = const [],
  });

  @override
  State<_TranscriptWithAudio> createState() => _TranscriptWithAudioState();
}

class _TranscriptWithAudioState extends State<_TranscriptWithAudio> {
  AudioPlayer? _player;
  bool _playerReady = false;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;

  // 검색
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // 인라인 편집
  int? _editingIndex;
  final TextEditingController _editingCtrl = TextEditingController();

  // 전사 리스트 스크롤 + 점프 하이라이트
  final ScrollController _listScrollCtrl = ScrollController();
  int? _flashSegmentIdx;
  Timer? _flashTimer;
  // 점프 중 보여줄 상단 배너 텍스트 ("01:32 시점으로 이동")
  String? _navHint;
  Timer? _navHintTimer;

  // 화자 색상
  static const _speakerColors = [
    Color(0xFF3949AB), // indigo 600
    Color(0xFF00897B), // teal 600
    Color(0xFFE64A19), // deepOrange 600
    Color(0xFF8E24AA), // purple 600
  ];

  @override
  void initState() {
    super.initState();
    _initPlayer();
    // 한글 IME 조합 완료 후에만 검색 업데이트
    _searchCtrl.addListener(_onSearchChanged);
    // 텍스트 입력 중에는 J/K/Space 단축키가 한글 모음 입력을 가로채지 않게 한다.
    FocusManager.instance.addListener(_onFocusChanged);
    // 전사 점프 함수는 오디오 유무와 관계없이 즉시 등록
    // (오디오가 없어도 우측 패널 스크롤+하이라이트는 가능해야 함)
    widget.onSeekRegister?.call(jumpToSegmentDetailed);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  /// 외부(근거 다이얼로그 등)에서 호출되는 점프 함수.
  /// 1) 우측 전사 패널을 해당 시간대 세그먼트로 스크롤 + 2.5초 하이라이트
  /// 2) 오디오 플레이어가 준비됐으면 추가로 seek + 자동 재생
  /// 반환: null=오디오까지 성공, 외에는 실패 사유 문자열.
  Future<String?> jumpToSegmentDetailed(double sec) async {
    if (widget.segments.isEmpty) return '전사 세그먼트가 없습니다';

    // 1) 시간이 포함된 세그먼트 찾기 (없으면 가장 가까운 것)
    int targetIdx = -1;
    for (int i = 0; i < widget.segments.length; i++) {
      final s = widget.segments[i];
      if (sec >= s.startTimeSeconds && sec < s.endTimeSeconds) {
        targetIdx = i;
        break;
      }
    }
    if (targetIdx < 0) {
      double bestDiff = double.infinity;
      for (int i = 0; i < widget.segments.length; i++) {
        final diff = (widget.segments[i].startTimeSeconds - sec).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          targetIdx = i;
        }
      }
    }
    if (targetIdx < 0) return '대응되는 전사 세그먼트를 찾지 못했습니다';

    // 검색 필터가 걸려있으면 해제 (점프한 항목이 보이도록)
    if (_searchQuery.isNotEmpty) {
      _searchCtrl.clear();
      setState(() => _searchQuery = '');
    }

    // 2) 하이라이트 (2.5초, 도착 후 추가 시간 유지)
    final targetSeg = widget.segments[targetIdx];
    setState(() {
      _flashSegmentIdx = targetIdx;
      _navHint = '${_secToStr(targetSeg.startTimeSeconds)} 시점으로 이동';
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _flashSegmentIdx = null);
    });
    _navHintTimer?.cancel();
    _navHintTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _navHint = null);
    });

    // 3) 스크롤 — 다음 프레임까지 기다린 후 추정 높이로 점프
    //    천천히 + easeInOutCubic으로 사용자가 이동 흐름을 인지할 수 있도록
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _listScrollCtrl.hasClients) {
      // 세그먼트 항목 평균 높이 ≈ 56px (화자 변경 시 +12px)
      const avgHeight = 60.0;
      final maxOffset = _listScrollCtrl.position.maxScrollExtent;
      final target = (targetIdx * avgHeight - 80).clamp(0.0, maxOffset);
      try {
        await _listScrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      } catch (_) {}
    }

    // 4) 오디오 — 가능하면 시킹 + 재생
    //    플레이어가 아직 준비 안 됐으면 lazy-retry 시도
    if (_player == null) {
      debugPrint('[jumpToSegmentDetailed] player not ready, retrying init...');
      await _initPlayer();
    }
    final p = _player;
    if (p == null || !_playerReady) {
      return _playerInitError ?? '오디오 플레이어가 준비되지 않았습니다';
    }
    debugPrint(
      '[seek BEFORE] state=${p.processingState} playing=${p.playing} '
      'volume=${p.volume} duration=${p.duration} pos=${p.position}',
    );

    // 1) 볼륨이 0이면 복원 (사용자가 일시 음소거했거나 초기 0인 케이스)
    if (p.volume < 0.01) {
      try {
        await p.setVolume(1.0);
      } catch (_) {}
    }

    final ms = (sec * 1000).round();
    final dur = p.duration;
    final clamped = dur == null
        ? Duration(milliseconds: ms)
        : Duration(milliseconds: ms.clamp(0, dur.inMilliseconds));
    try {
      await p.seek(clamped);
      await p.play();
      // 재생 명령 후 짧게 대기하고 실제 재생 여부 검증
      await Future.delayed(const Duration(milliseconds: 150));
      debugPrint(
        '[seek AFTER] state=${p.processingState} playing=${p.playing} '
        'pos=${p.position}',
      );
      if (!p.playing) {
        // 재생 명령은 받았으나 실제 재생 상태로 전이 못 함 — 한 번 더 시도
        try {
          await p.play();
          await Future.delayed(const Duration(milliseconds: 150));
        } catch (_) {}
        if (!p.playing) {
          return '오디오 명령은 들어갔지만 재생되지 않음 (시스템 음량/스피커 확인)';
        }
      }
      return null;
    } catch (e) {
      debugPrint('[jumpToSegmentDetailed] 오디오 시킹 실패: $e');
      return '오디오 시킹 실패: $e';
    }
  }

  void _onSearchChanged() {
    // composing 범위가 남아 있으면 IME 조합 중 → 건너뜀
    final composing = _searchCtrl.value.composing;
    if (composing.start >= 0 && composing.end > composing.start) return;
    final newQuery = _searchCtrl.text.trim();
    if (newQuery != _searchQuery) {
      setState(() => _searchQuery = newQuery);
    }
  }

  bool _isTextEditingFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  void dispose() {
    widget.onSeekRegister?.call(null);
    _flashTimer?.cancel();
    _navHintTimer?.cancel();
    _listScrollCtrl.dispose();
    _posSub?.cancel();
    _playingSub?.cancel();
    _player?.dispose();
    FocusManager.instance.removeListener(_onFocusChanged);
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _editingCtrl.dispose();
    super.dispose();
  }

  void _startEditing(int originalIndex) {
    setState(() {
      _editingIndex = originalIndex;
      _editingCtrl.text = widget.segments[originalIndex].text;
    });
  }

  Future<void> _commitEditing() async {
    if (_editingIndex == null) return;
    final newText = _editingCtrl.text.trim();
    final seg = widget.segments[_editingIndex!];
    setState(() => _editingIndex = null);
    if (newText.isNotEmpty && newText != seg.text) {
      seg.text = newText;
      await TranscriptRepositoryImpl(
        IsarService.instance.db,
      ).updateSegment(seg);
    }
  }

  // ── 전사 보정 액션 ──────────────────────────────────────────────

  /// 단어집에 새 용어 추가 (전사본 변경 없음)
  Future<void> _addToGlossary() async {
    final termCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final aliasCtrl = TextEditingController();
    final saved = await showMacosAlertDialog<bool>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const Icon(Icons.book_outlined, size: 48),
        title: const Text('단어집에 추가'),
        message: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: termCtrl,
                decoration: const InputDecoration(
                  labelText: '용어 (예: 빅쿼리)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: '설명',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: aliasCtrl,
                decoration: const InputDecoration(
                  labelText: '별칭(옵션) — 콤마로 구분 (예: 비커리, 빅커리)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '* 별칭은 다음 녹음/요약에서 자동으로 용어로 교정됩니다.',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () {
            if (termCtrl.text.trim().isEmpty) return;
            Navigator.pop(ctx, true);
          },
          child: const Text('추가'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
      ),
    );
    if (saved != true) return;

    final entry = GlossaryEntry()
      ..term = termCtrl.text.trim()
      ..description = descCtrl.text.trim()
      ..aliases = aliasCtrl.text.trim();
    await GlossaryRepositoryImpl(IsarService.instance.db).saveEntry(entry);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('단어집에 "${entry.term}" 추가됨'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  /// 이 회의의 모든 세그먼트에서 [find]→[replace] 일괄 치환
  Future<void> _replaceAcrossTranscript() async {
    final findCtrl = TextEditingController();
    final replaceCtrl = TextEditingController();
    bool addToGlossary = false;
    final confirmed = await showMacosAlertDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => MacosAlertDialog(
          appIcon: const Icon(Icons.find_replace, size: 48),
          title: const Text('전사본 단어 치환'),
          message: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: findCtrl,
                  decoration: const InputDecoration(
                    labelText: '찾을 단어',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: replaceCtrl,
                  decoration: const InputDecoration(
                    labelText: '바꿀 단어',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: addToGlossary,
                  onChanged: (v) => setS(() => addToGlossary = v ?? false),
                  title: const Text(
                    '단어집에도 별칭으로 추가 (다음 녹음/요약 자동 교정)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () {
              if (findCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('치환'),
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    final find = findCtrl.text;
    final replace = replaceCtrl.text;
    if (find.isEmpty) return;

    final repo = TranscriptRepositoryImpl(IsarService.instance.db);
    int changed = 0;
    for (final seg in widget.segments) {
      if (!seg.text.contains(find)) continue;
      final updated = seg.text.replaceAll(find, replace);
      if (updated == seg.text) continue;
      seg.text = updated;
      await repo.updateSegment(seg);
      changed++;
    }

    if (addToGlossary && find.length >= 2) {
      // replace를 term, find를 alias로 등록
      final glossaryRepo = GlossaryRepositoryImpl(IsarService.instance.db);
      final entry = GlossaryEntry()
        ..term = replace
        ..description = '전사본 치환에서 자동 추가'
        ..aliases = find;
      await glossaryRepo.saveEntry(entry);
    }

    widget.onTranscriptChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? '"$find" 을(를) 찾지 못했습니다.'
                : '$changed개 세그먼트에서 "$find" → "$replace" 치환됨'
                      '${addToGlossary ? ' · 단어집에 추가됨' : ''}',
          ),
          backgroundColor: changed == 0
              ? Colors.orange.shade700
              : Colors.green.shade700,
        ),
      );
    }
  }

  // ── 화자 이름/통합 편집 ────────────────────────────────────────

  /// Meeting.speakerNamesJson을 디코드해 {라벨: 이름} 맵 반환
  Map<String, String> get _speakerNames {
    final m = widget.meeting;
    if (m == null) return const {};
    final raw = m.speakerNamesJson;
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return const {};
    }
  }

  /// 현재 회의에 등장하는 모든 화자 라벨(A,B,C...) 수집
  Set<String> _collectSpeakerLetters() {
    final out = <String>{};
    for (final s in widget.segments) {
      final l = s.speakerLabel;
      if (l != null && l.isNotEmpty) out.add(l);
    }
    return out;
  }

  /// 화자 배지 클릭 시 — 이름 변경 / 다른 화자로 통합 다이얼로그
  Future<void> _editSpeakerName(String letter) async {
    final meeting = widget.meeting;
    if (meeting == null) return;
    final namesMap = Map<String, String>.from(_speakerNames);
    final allLetters = _collectSpeakerLetters().toList()..sort();
    final nameCtrl = TextEditingController(text: namesMap[letter] ?? '');
    String? mergeInto; // null = 합치기 안 함

    final result = await showMacosAlertDialog<_SpeakerEditResult>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) => MacosAlertDialog(
            appIcon: const Icon(Icons.person_outline, size: 48),
            title: Text('화자 $letter 편집'),
            message: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '이름 (회의 내에서만 적용)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '예: 철수, 김부장, PM',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: nameCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              tooltip: '이름 삭제',
                              onPressed: () {
                                setS(() => nameCtrl.clear());
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '다른 화자로 통합 (선택)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '이 화자의 모든 발화를 다른 화자로 합칩니다.\n'
                    '한 사람을 시스템이 두 개 화자로 분리한 경우 사용하세요.',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: mergeInto,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: '합치지 않음',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('합치지 않음', style: TextStyle(fontSize: 13)),
                      ),
                      for (final l in allLetters)
                        if (l != letter)
                          DropdownMenuItem<String?>(
                            value: l,
                            child: Text(
                              namesMap[l]?.isNotEmpty == true
                                  ? '화자 $l (${namesMap[l]})'
                                  : '화자 $l',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                    ],
                    onChanged: (v) => setS(() => mergeInto = v),
                  ),
                ],
              ),
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => Navigator.pop(
                ctx,
                _SpeakerEditResult(
                  name: nameCtrl.text.trim(),
                  mergeInto: mergeInto,
                ),
              ),
              child: const Text('저장'),
            ),
            secondaryButton: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
          ),
        );
      },
    );

    if (result == null) return;

    // 1) 합치기 처리 — 모든 세그먼트의 speakerLabel을 mergeInto로 변경
    int mergedCount = 0;
    if (result.mergeInto != null && result.mergeInto != letter) {
      final repo = TranscriptRepositoryImpl(IsarService.instance.db);
      for (final seg in widget.segments) {
        if (seg.speakerLabel == letter) {
          seg.speakerLabel = result.mergeInto;
          await repo.updateSegment(seg);
          mergedCount++;
        }
      }
      // 통합 후, 원래 letter는 사라지므로 namesMap에서 제거
      namesMap.remove(letter);
    } else {
      // 합치기 없음 — 이름만 갱신
      if (result.name.isEmpty) {
        namesMap.remove(letter);
      } else {
        namesMap[letter] = result.name;
      }
    }

    // 2) Meeting.speakerNamesJson 업데이트
    meeting.speakerNamesJson = namesMap.isEmpty ? '' : jsonEncode(namesMap);
    await MeetingRepositoryImpl(IsarService.instance.db).updateMeeting(meeting);

    widget.onTranscriptChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            mergedCount > 0
                ? '$mergedCount개 발화가 화자 ${result.mergeInto}로 통합되었습니다'
                : (result.name.isEmpty
                      ? '화자 $letter 이름이 초기화되었습니다'
                      : '화자 $letter → "${result.name}" 으로 저장되었습니다'),
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  /// 단어집 alias 기반 일괄 재교정
  Future<void> _applyGlossaryAliases() async {
    final glossaryRepo = GlossaryRepositoryImpl(IsarService.instance.db);
    final entries = await glossaryRepo.getAllEntries();
    final corrector = TranscriptCorrector.fromGlossary(entries);

    final repo = TranscriptRepositoryImpl(IsarService.instance.db);
    int changed = 0;
    for (final seg in widget.segments) {
      final fixed = corrector.correctText(seg.text);
      if (fixed == seg.text) continue;
      seg.text = fixed;
      await repo.updateSegment(seg);
      changed++;
    }

    widget.onTranscriptChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? '단어집 별칭으로 교정할 내용을 찾지 못했습니다.'
                : '$changed개 세그먼트에서 단어집 별칭 기반 교정 적용됨',
          ),
          backgroundColor: changed == 0
              ? Colors.blueGrey.shade600
              : Colors.green.shade700,
        ),
      );
    }
  }

  /// 오디오 초기화 결과 — null=성공, 외에는 사용자에게 보여줄 사유
  String? _playerInitError;

  Future<void> _initPlayer() async {
    if (widget.audioFilePath == null) {
      _playerInitError = '회의 데이터에 오디오 파일 경로가 없습니다 (자동 삭제됨)';
      debugPrint('[_initPlayer] audioFilePath is null');
      return;
    }
    final file = File(widget.audioFilePath!);
    if (!await file.exists()) {
      _playerInitError = '오디오 파일을 찾을 수 없습니다: ${widget.audioFilePath}';
      debugPrint('[_initPlayer] file does not exist: ${widget.audioFilePath}');
      return;
    }

    final player = AudioPlayer();
    try {
      await player.setFilePath(widget.audioFilePath!);
    } catch (e) {
      _playerInitError = '오디오 로드 실패: $e';
      debugPrint('[_initPlayer] setFilePath failed: $e');
      player.dispose();
      return;
    }

    if (!mounted) {
      player.dispose();
      return;
    }

    _player = player;
    _playerInitError = null;
    _posSub = player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _playingSub = player.playingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    setState(() => _playerReady = true);
    debugPrint(
      '[_initPlayer] OK — duration=${player.duration} '
      'path=${widget.audioFilePath}',
    );
  }

  // ── 헬퍼 ──────────────────────────────────────────────────────

  /// 현재 재생 위치에 해당하는 세그먼트 인덱스 반환
  int? _activeSegmentIndex() {
    final posSec = _position.inMilliseconds / 1000.0;
    for (int i = 0; i < widget.segments.length; i++) {
      if (posSec >= widget.segments[i].startTimeSeconds &&
          posSec < widget.segments[i].endTimeSeconds) {
        return i;
      }
    }
    return null;
  }

  static String _secToStr(double sec) {
    final s = sec.toInt();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  static String _durStr(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// gap 기반 화자 추정 (1.0s gap → 화자 전환, 1.5s cooldown)
  static List<int> _inferSpeakerIds(List<Transcript> segs) {
    if (segs.isEmpty) return [];
    // 발화자 라벨 결과(speakerLabel)가 있으면 우선 사용
    final anyLabel = segs.any((s) => s.speakerLabel != null);
    if (anyLabel) {
      int fallback = 0;
      return segs.map((s) {
        final l = s.speakerLabel;
        if (l == null || l.isEmpty) return fallback;
        return l.codeUnitAt(0) - 65; // 'A'→0, 'B'→1, ...
      }).toList();
    }
    // 레거시: 시간 간격 기반 추정
    final ids = List<int>.filled(segs.length, 0);
    int current = 0;
    double lastSwitchEnd = -999;
    for (int i = 1; i < segs.length; i++) {
      final gap = segs[i].startTimeSeconds - segs[i - 1].endTimeSeconds;
      final since = segs[i].startTimeSeconds - lastSwitchEnd;
      if (gap >= 1.0 && since > 1.5) {
        current++;
        lastSwitchEnd = segs[i].startTimeSeconds;
      }
      ids[i] = current;
    }
    return ids;
  }

  /// segments에 실제 발화자 라벨이 포함돼 있는지
  static bool _hasDiarizationLabels(List<Transcript> segs) =>
      segs.any((s) => s.speakerLabel != null);

  // ── 플레이어 바 UI ─────────────────────────────────────────────

  Widget _buildPlayerBar() {
    final dur = _player!.duration ?? Duration.zero;
    final maxMs = dur.inMilliseconds.toDouble();
    final curMs = _position.inMilliseconds
        .clamp(0, maxMs > 0 ? maxMs.toInt() : 0)
        .toDouble();

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        children: [
          // 재생/정지 버튼
          SizedBox(
            width: 32,
            height: 32,
            child: MacosIconButton(
              padding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              boxConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
                maxWidth: 32,
                maxHeight: 32,
              ),
              icon: Icon(
                _isPlaying ? Icons.pause_circle : Icons.play_circle,
                size: 22,
                color: Colors.indigo.shade600,
              ),
              onPressed: () => _isPlaying ? _player!.pause() : _player!.play(),
            ),
          ),
          // 현재 시간
          SizedBox(
            width: 36,
            child: Text(
              _durStr(_position),
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.indigo.shade700,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          // 슬라이더
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                trackHeight: 2,
                activeTrackColor: Colors.indigo.shade400,
                inactiveTrackColor: Colors.indigo.shade100,
                thumbColor: Colors.indigo.shade600,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                min: 0,
                max: maxMs > 0 ? maxMs : 1,
                value: maxMs > 0 ? curMs : 0,
                onChanged: maxMs > 0
                    ? (v) => _player!.seek(Duration(milliseconds: v.toInt()))
                    : null,
              ),
            ),
          ),
          // 전체 시간
          SizedBox(
            width: 36,
            child: Text(
              _durStr(dur),
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 검색어 하이라이트 텍스트 ──────────────────────────────────

  Widget _buildHighlightedText(String text, TextStyle? baseStyle) {
    if (_searchQuery.isEmpty) {
      return SelectableText(text, style: baseStyle);
    }
    final lower = text.toLowerCase();
    final queryLower = _searchQuery.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lower.indexOf(queryLower, start);
      if (idx == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        }
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + _searchQuery.length),
          style: (baseStyle ?? const TextStyle()).copyWith(
            backgroundColor: Colors.yellow.shade300,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      );
      start = idx + _searchQuery.length;
    }
    return SelectableText.rich(TextSpan(children: spans));
  }

  // ── 검색 바 UI ────────────────────────────────────────────────

  Widget _buildSearchBar(int totalCount, int matchCount) {
    final hasQuery = _searchQuery.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: '녹취록 검색…',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                prefixIcon: Icon(
                  Icons.search,
                  size: 15,
                  color: Colors.grey.shade400,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                suffixIcon: hasQuery
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 26,
                  minHeight: 26,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 7,
                  horizontal: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.indigo.shade300,
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              // onChanged 대신 addListener(_onSearchChanged) 사용 (한글 IME 대응)
            ),
          ),
          // 일치 개수 배지
          if (hasQuery) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: matchCount > 0
                    ? Colors.indigo.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: matchCount > 0
                      ? Colors.indigo.shade200
                      : Colors.red.shade200,
                ),
              ),
              child: Text(
                matchCount > 0 ? '$matchCount / $totalCount' : '없음',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: matchCount > 0
                      ? Colors.indigo.shade700
                      : Colors.red.shade600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 세그먼트 목록 UI ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasAudio = _player != null && _playerReady;
    final speakerIds = _inferSpeakerIds(widget.segments);
    final hasDiar = _hasDiarizationLabels(widget.segments);
    final activeIdx = hasAudio ? _activeSegmentIndex() : null;

    // 검색 필터 (원본 인덱스 유지)
    final filteredEntries = _searchQuery.isEmpty
        ? widget.segments.asMap().entries.toList()
        : widget.segments
              .asMap()
              .entries
              .where(
                (e) => e.value.text.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              )
              .toList();
    final textEditingFocused = _isTextEditingFocused();

    return CallbackShortcuts(
      bindings: textEditingFocused
          ? const <ShortcutActivator, VoidCallback>{}
          : {
              // Space → 재생/정지 (오디오 있을 때만)
              const SingleActivator(LogicalKeyboardKey.space): () {
                if (!hasAudio) return;
                final p = _player!;
                if (p.playing) {
                  p.pause();
                } else {
                  p.play();
                }
              },
              // J → 이전 세그먼트로 점프
              const SingleActivator(LogicalKeyboardKey.keyJ): () {
                _seekRelativeSegment(-1);
              },
              // K → 다음 세그먼트로 점프
              const SingleActivator(LogicalKeyboardKey.keyK): () {
                _seekRelativeSegment(1);
              },
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 (좁은 창에서 자동 줄바꿈) ──────────────────────
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              // 좌측 타이틀 그룹
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.transcribe, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '녹취록',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (widget.segments.isNotEmpty)
                    Text(
                      '(${widget.segments.length}개)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
              // 우측 액션 그룹 (오디오 정보 + 음성 인식 다시 + 전사 보정 메뉴)
              if (hasAudio)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.headphones_outlined,
                      size: 13,
                      color: Colors.indigo.shade300,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '오디오 있음',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.indigo.shade300,
                      ),
                    ),
                    if (widget.onRerunStt != null) ...[
                      const SizedBox(width: 8),
                      StreamBuilder<NativeModelTaskSnapshot>(
                        stream: OnDeviceModelManager.instance.nativeTaskStream,
                        initialData:
                            OnDeviceModelManager.instance.nativeTaskSnapshot,
                        builder: (context, snapshot) {
                          final active = snapshot.data?.activeLabel;
                          final reason = active == null
                              ? null
                              : '현재 $active 작업 중입니다. 완료 후 음성 인식을 다시 시도해주세요.';
                          final disabled = widget.isRerunning || reason != null;
                          return MacosTooltip(
                            message: reason ?? '',
                            child: PushButton(
                              controlSize: ControlSize.small,
                              secondary: true,
                              onPressed: disabled ? null : widget.onRerunStt,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    widget.isRerunning
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            Icons.replay,
                                            size: 14,
                                            color: Colors.indigo.shade600,
                                          ),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.isRerunning ? '실행 중…' : '음성 인식 다시',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.indigo.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(width: 4),
                    // 전사 보정 메뉴 — 단어집 추가/전체 치환/alias 재교정
                    PopupMenuButton<String>(
                      tooltip: '전사 보정',
                      icon: Icon(
                        Icons.spellcheck,
                        size: 16,
                        color: Colors.indigo.shade600,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: 'add_term',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.bookmark_add_outlined,
                              size: 18,
                            ),
                            title: Text(
                              '단어집에 추가',
                              style: TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '새 용어/별칭 등록',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'replace',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.find_replace, size: 18),
                            title: Text(
                              '전사본 단어 치환',
                              style: TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '이 회의 전체에 일괄 적용',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'apply_aliases',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.auto_fix_high, size: 18),
                            title: Text(
                              '단어집 별칭 재교정',
                              style: TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '등록된 별칭으로 전사본 후처리',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                      onSelected: (v) async {
                        switch (v) {
                          case 'add_term':
                            await _addToGlossary();
                            break;
                          case 'replace':
                            await _replaceAcrossTranscript();
                            break;
                          case 'apply_aliases':
                            await _applyGlossaryAliases();
                            break;
                        }
                      },
                    ),
                  ],
                ),
            ],
          ),

          // ── 검색 바 ─────────────────────────────────────────────
          _buildSearchBar(widget.segments.length, filteredEntries.length),

          // ── 미니 플레이어 바 ────────────────────────────────────
          if (hasAudio) _buildPlayerBar(),

          const SizedBox(height: 4),

          // ── 세그먼트 목록 ───────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                widget.segments.isEmpty
                    ? Center(
                        child: Text(
                          '녹취된 내용이 없습니다.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : _buildSegmentList(
                        filteredEntries,
                        speakerIds,
                        hasDiar,
                        hasAudio,
                        activeIdx,
                      ),
                // 점프 중 상단 네비 힌트 배너
                if (_navHint != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            key: ValueKey(_navHint),
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade600,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.swipe_down_alt,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _navHint!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 현재 활성 세그먼트 기준 [delta]만큼 이전/이후 세그먼트로 seek.
  /// 활성 세그먼트가 없으면 첫 세그먼트로 점프.
  void _seekRelativeSegment(int delta) {
    if (widget.segments.isEmpty) return;
    final cur = _activeSegmentIndex() ?? 0;
    final target = (cur + delta).clamp(0, widget.segments.length - 1);
    final seg = widget.segments[target];
    final p = _player;
    if (p != null && _playerReady) {
      try {
        p.seek(Duration(milliseconds: (seg.startTimeSeconds * 1000).round()));
        if (!p.playing) p.play();
      } catch (_) {}
    }
    // 점프 하이라이트도 같이
    setState(() => _flashSegmentIdx = target);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _flashSegmentIdx = null);
    });
    // 스크롤
    if (_listScrollCtrl.hasClients) {
      const avgHeight = 60.0;
      final maxOffset = _listScrollCtrl.position.maxScrollExtent;
      final off = (target * avgHeight - 80).clamp(0.0, maxOffset);
      try {
        _listScrollCtrl.animateTo(
          off,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    }
  }

  /// 세그먼트 ListView 빌드 — 외부 점프 + flash + 검색 필터 반영
  Widget _buildSegmentList(
    List<MapEntry<int, Transcript>> filteredEntries,
    List<int> speakerIds,
    bool hasDiar,
    bool hasAudio,
    int? activeIdx,
  ) {
    return filteredEntries.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 32, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text(
                  '"$_searchQuery" 검색 결과 없음',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          )
        : ListView.builder(
            controller: _listScrollCtrl,
            itemCount: filteredEntries.length,
            itemBuilder: (_, listIdx) {
              final originalIdx = filteredEntries[listIdx].key;
              final seg = filteredEntries[listIdx].value;
              final isActive = originalIdx == activeIdx;
              final isFlash = originalIdx == _flashSegmentIdx;
              // 이 세그먼트가 사용자 북마크 시점을 포함하는가
              final hasBookmark = widget.bookmarks.any(
                (b) =>
                    b.sec >= seg.startTimeSeconds.floor() &&
                    b.sec <= seg.endTimeSeconds.ceil(),
              );
              final sid = speakerIds.isNotEmpty ? speakerIds[originalIdx] : 0;
              final color = _speakerColors[sid % _speakerColors.length];
              // 화자 배지: 목록 내 이전 항목과 화자 비교
              final prevSid = listIdx > 0
                  ? speakerIds[filteredEntries[listIdx - 1].key]
                  : -1;
              final speakerChanged = listIdx == 0 || sid != prevSid;

              final baseStyle = TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                color: isActive ? Colors.indigo.shade900 : null,
              );

              final speakerLetter = String.fromCharCode(65 + (sid % 26));
              final customName = hasDiar ? _speakerNames[speakerLetter] : null;
              final defaultLabel = hasDiar
                  ? '화자 $speakerLetter'
                  : '참여자 ${sid + 1}';
              final displayLabel = customName?.isNotEmpty == true
                  ? customName!
                  : defaultLabel;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 화자 배지 (화자 바뀔 때) — 클릭 시 이름 편집/통합
                  if (speakerChanged) ...[
                    if (listIdx > 0) const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: hasDiar && widget.meeting != null
                            ? () => _editSpeakerName(speakerLetter)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: color.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                              if (hasDiar && widget.meeting != null) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.edit_outlined,
                                  size: 10,
                                  color: color.withValues(alpha: 0.7),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 세그먼트 행 (클릭 시 해당 위치 재생)
                  InkWell(
                    onTap: () async {
                      // 오디오가 있으면 시킹 후 재생
                      if (hasAudio) {
                        try {
                          await _player!.seek(
                            Duration(
                              milliseconds: (seg.startTimeSeconds * 1000)
                                  .toInt(),
                            ),
                          );
                          if (!_isPlaying) await _player!.play();
                          return;
                        } catch (e) {
                          debugPrint('[seg tap] 시킹 실패: $e');
                        }
                      }
                      // 오디오 없거나 시킹 실패 — 안내 메시지
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          content: const Text('오디오 파일이 없거나 자동 삭제되어 재생할 수 없습니다'),
                          backgroundColor: Colors.blueGrey.shade600,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: isFlash ? 600 : 150),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        vertical: 3,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isFlash
                            ? Colors.amber.shade200
                            : (isActive ? Colors.indigo.shade50 : null),
                        border: isFlash
                            ? Border.all(color: Colors.amber.shade600, width: 2)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: isFlash
                            ? [
                                BoxShadow(
                                  color: Colors.amber.shade400.withValues(
                                    alpha: 0.55,
                                  ),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ▶ 재생 버튼 (오디오 있을 때만)
                          if (hasAudio)
                            Padding(
                              padding: const EdgeInsets.only(right: 4, top: 1),
                              child: Icon(
                                isActive && _isPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_circle_outline,
                                size: 14,
                                color: isActive
                                    ? Colors.indigo.shade600
                                    : Colors.grey.shade400,
                              ),
                            ),
                          // 타임스탬프 + 북마크 ★ 아이콘
                          SizedBox(
                            width: hasAudio ? 78 : 88,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    '[${_secToStr(seg.startTimeSeconds)}'
                                    '→${_secToStr(seg.endTimeSeconds)}]',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isActive
                                          ? Colors.indigo.shade400
                                          : Colors.grey.shade400,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                if (hasBookmark) ...[
                                  const SizedBox(width: 2),
                                  MacosTooltip(
                                    message: '사용자 북마크 시점',
                                    child: Icon(
                                      Icons.bookmark_rounded,
                                      size: 11,
                                      color: Colors.amber.shade700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // 화자 컬러 바
                          Container(
                            width: 2,
                            height: 16,
                            margin: const EdgeInsets.only(right: 5, top: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(
                                alpha: isActive ? 0.8 : 0.4,
                              ),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                          // 발화 텍스트 (더블클릭 편집 / 검색어 하이라이트)
                          Expanded(
                            child: _editingIndex == originalIdx
                                ? TextField(
                                    controller: _editingCtrl,
                                    autofocus: true,
                                    style: baseStyle,
                                    maxLines: null,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(
                                          color: Colors.indigo.shade300,
                                        ),
                                      ),
                                    ),
                                    onSubmitted: (_) => _commitEditing(),
                                    onTapOutside: (_) => _commitEditing(),
                                  )
                                : GestureDetector(
                                    onDoubleTap: () =>
                                        _startEditing(originalIdx),
                                    child: MacosTooltip(
                                      message: '더블클릭하여 수정',
                                      child: _buildHighlightedText(
                                        seg.text,
                                        baseStyle,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
  }
}

// ── 요약 이력 다이얼로그 ──────────────────────────────────────────────
class _SummaryHistoryDialog extends ConsumerWidget {
  final int meetingId;
  const _SummaryHistoryDialog({required this.meetingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionsAsync = ref.watch(summaryVersionsProvider(meetingId));
    return MacosSheet(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 20,
                    color: MacosTheme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '요약 이력',
                    style: MacosTheme.of(
                      context,
                    ).typography.title2.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  MacosIconButton(
                    icon: const Icon(Icons.close, size: 18),
                    backgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    boxConstraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                      maxWidth: 24,
                      maxHeight: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20),
              // 목록
              Expanded(
                child: versionsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('이력 로드 오류: $e')),
                  data: (versions) => versions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.history_toggle_off,
                                size: 40,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '저장된 이력이 없습니다.\n다시 요약하면 이전 요약이 이력으로 저장됩니다.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: versions.length,
                          separatorBuilder: (_, _) => const Divider(height: 12),
                          itemBuilder: (ctx, i) {
                            final v = versions[i];
                            final created = v.createdAt;
                            final dateStr =
                                '${created.year}-${created.month.toString().padLeft(2, '0')}-'
                                '${created.day.toString().padLeft(2, '0')} '
                                '${created.hour.toString().padLeft(2, '0')}:'
                                '${created.minute.toString().padLeft(2, '0')}';
                            return ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(
                                left: 8,
                                bottom: 8,
                              ),
                              leading: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.indigo.shade200,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'v${v.version}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo.shade700,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                v.meetingTitle.isEmpty
                                    ? '(제목 없음)'
                                    : v.meetingTitle,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              children: [
                                if (v.participants.isNotEmpty)
                                  _HistorySection(
                                    label: '참석자',
                                    items: [v.participants.join(', ')],
                                  ),
                                if (v.keyDiscussions.isNotEmpty)
                                  _HistorySection(
                                    label: '주요 논의',
                                    items: v.keyDiscussions,
                                  ),
                                if (v.decisions.isNotEmpty)
                                  _HistorySection(
                                    label: '결정 사항',
                                    items: v.decisions,
                                  ),
                                if (v.openQuestions.isNotEmpty)
                                  _HistorySection(
                                    label: '미해결 이슈',
                                    items: v.openQuestions,
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final String label;
  final List<String> items;
  const _HistorySection({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          ...items.map(
            (item) => Text(
              '• $item',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 메모 인라인 편집기 ────────────────────────────────────────────────
class _NotesEditor extends StatefulWidget {
  final Meeting meeting;
  final VoidCallback onSaved;
  const _NotesEditor({required this.meeting, required this.onSaved});

  @override
  State<_NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<_NotesEditor> {
  bool _editing = false;
  late TextEditingController _ctrl;
  String _prev = ''; // AutoBullet 직전 텍스트 추적
  double _editorHeight = 160.0; // 드래그로 조정 가능 (60~500)

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.meeting.notes);
    _prev = _ctrl.text;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newNotes = _ctrl.text.trim();
    widget.meeting.notes = newNotes;
    await MeetingRepositoryImpl(
      IsarService.instance.db,
    ).updateMeeting(widget.meeting);
    widget.onSaved();
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 텍스트 필드 + 하단 드래그 핸들을 하나의 박스로
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.amber.shade400),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: _editorHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.tab) {
                          final shift =
                              HardwareKeyboard.instance.isShiftPressed;
                          AutoBullet.handleIndent(_ctrl, decrease: shift);
                          _prev = _ctrl.text;
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(fontSize: 13, height: 1.6),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) {
                          _prev = AutoBullet.handle(_prev, value, _ctrl);
                        },
                      ),
                    ),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        _editorHeight = (_editorHeight + details.delta.dy)
                            .clamp(60.0, 500.0);
                      });
                    },
                    child: MacosTooltip(
                      message: '드래그해서 메모창 크기 조정',
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(5),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.drag_handle,
                            size: 14,
                            color: Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _ctrl.text = widget.meeting.notes;
                  _prev = _ctrl.text;
                  setState(() => _editing = false);
                },
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade600,
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                onPressed: _save,
                child: const Text('저장'),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            widget.meeting.notes,
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        const SizedBox(width: 8),
        MacosTooltip(
          message: '메모 수정',
          child: MacosIconButton(
            icon: Icon(
              Icons.edit_outlined,
              size: 15,
              color: Colors.grey.shade500,
            ),
            backgroundColor: Colors.transparent,
            padding: EdgeInsets.zero,
            boxConstraints: const BoxConstraints(
              minWidth: 22,
              minHeight: 22,
              maxWidth: 22,
              maxHeight: 22,
            ),
            onPressed: () => setState(() => _editing = true),
          ),
        ),
      ],
    );
  }
}

// ── 용어 추출 결과 다이얼로그 ─────────────────────────────────────────
class _TermExtractDialog extends StatefulWidget {
  final List<Map<String, String>> extracted;
  final Future<void> Function(List<Map<String, String>> selected) onSave;

  const _TermExtractDialog({required this.extracted, required this.onSave});

  @override
  State<_TermExtractDialog> createState() => _TermExtractDialogState();
}

class _TermExtractDialogState extends State<_TermExtractDialog> {
  late List<bool> _checked;
  late List<TextEditingController> _termCtrls;
  late List<TextEditingController> _descCtrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checked = List.filled(widget.extracted.length, true);
    _termCtrls = widget.extracted
        .map((e) => TextEditingController(text: e['term']))
        .toList();
    _descCtrls = widget.extracted
        .map((e) => TextEditingController(text: e['description']))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _termCtrls) {
      c.dispose();
    }
    for (final c in _descCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _checked.where((v) => v).length;

    return MacosSheet(
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.book_outlined,
                    color: Colors.teal.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '용어 추출 결과',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        Text(
                          '단어집에 추가할 용어를 선택하고 설명을 수정하세요 (${widget.extracted.length}개 발견)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // 목록
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: widget.extracted.length,
                separatorBuilder: (_, _) => const Divider(height: 8),
                itemBuilder: (_, i) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _checked[i],
                      onChanged: (v) =>
                          setState(() => _checked[i] = v ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8, top: 4),
                        child: TextField(
                          controller: _termCtrls[i],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            labelText: '용어',
                            labelStyle: const TextStyle(fontSize: 11),
                          ),
                          enabled: _checked[i],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextField(
                          controller: _descCtrls[i],
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            labelText: '설명 (직접 수정 가능)',
                            labelStyle: const TextStyle(fontSize: 11),
                          ),
                          enabled: _checked[i],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 하단 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Text(
                    '$selectedCount개 선택됨',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (selectedCount == 0 || _saving)
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            final selected = <Map<String, String>>[];
                            for (int i = 0; i < _checked.length; i++) {
                              if (_checked[i]) {
                                selected.add({
                                  'term': _termCtrls[i].text.trim(),
                                  'description': _descCtrls[i].text.trim(),
                                });
                              }
                            }
                            await widget.onSave(selected);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${selected.length}개 용어를 단어집에 추가했습니다.',
                                  ),
                                  backgroundColor: Colors.teal.shade600,
                                ),
                              );
                            }
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(_saving ? '저장 중...' : '단어집에 추가'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 요약 편집 다이얼로그 ───────────────────────────────────────────────
class _EditedSummary {
  final String meetingTitle;
  final List<String> participants;
  final List<String> keyDiscussions;
  final List<String> decisions;
  final List<String> openQuestions;
  const _EditedSummary({
    required this.meetingTitle,
    required this.participants,
    required this.keyDiscussions,
    required this.decisions,
    required this.openQuestions,
  });
}

class _SummaryEditDialog extends StatefulWidget {
  final Summary current;
  const _SummaryEditDialog({required this.current});

  @override
  State<_SummaryEditDialog> createState() => _SummaryEditDialogState();
}

class _SummaryEditDialogState extends State<_SummaryEditDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _participantsCtrl;
  late TextEditingController _discussionsCtrl;
  late TextEditingController _decisionsCtrl;
  late TextEditingController _openQuestionsCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.current;
    _titleCtrl = TextEditingController(text: s.meetingTitle);
    _participantsCtrl = TextEditingController(text: s.participants.join(', '));
    _discussionsCtrl = TextEditingController(text: s.keyDiscussions.join('\n'));
    _decisionsCtrl = TextEditingController(text: s.decisions.join('\n'));
    _openQuestionsCtrl = TextEditingController(
      text: s.openQuestions.join('\n'),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _participantsCtrl.dispose();
    _discussionsCtrl.dispose();
    _decisionsCtrl.dispose();
    _openQuestionsCtrl.dispose();
    super.dispose();
  }

  List<String> _splitLines(String text) =>
      text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  List<String> _splitCsv(String text) => text
      .split(RegExp(r'[,\n]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return MacosSheet(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '요약 편집',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field(label: '제목', controller: _titleCtrl, maxLines: 1),
                    _field(
                      label: '참석자 (콤마 또는 줄바꿈 구분)',
                      controller: _participantsCtrl,
                      maxLines: 2,
                    ),
                    _field(
                      label: '주요 논의 (한 줄에 하나씩)',
                      controller: _discussionsCtrl,
                      maxLines: 6,
                    ),
                    _field(
                      label: '결정 사항 (한 줄에 하나씩)',
                      controller: _decisionsCtrl,
                      maxLines: 5,
                    ),
                    _field(
                      label: '미해결 이슈 (한 줄에 하나씩)',
                      controller: _openQuestionsCtrl,
                      maxLines: 4,
                    ),
                    Text(
                      '※ 액션 아이템은 본문의 체크박스 UI에서 수정하세요.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('저장 (이전 버전은 이력으로)'),
                    onPressed: () {
                      Navigator.pop(
                        context,
                        _EditedSummary(
                          meetingTitle: _titleCtrl.text.trim(),
                          participants: _splitCsv(_participantsCtrl.text),
                          keyDiscussions: _splitLines(_discussionsCtrl.text),
                          decisions: _splitLines(_decisionsCtrl.text),
                          openQuestions: _splitLines(_openQuestionsCtrl.text),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required int maxLines,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: 1,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          labelStyle: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

class _ActionItemQualityNotice extends StatelessWidget {
  final int ownerUnconfirmedCount;
  final int deadlineUnconfirmedCount;

  const _ActionItemQualityNotice({
    required this.ownerUnconfirmedCount,
    required this.deadlineUnconfirmedCount,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (ownerUnconfirmedCount > 0) '담당자 $ownerUnconfirmedCount개',
      if (deadlineUnconfirmedCount > 0) '기한 $deadlineUnconfirmedCount개',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Colors.amber.shade900,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '확인 필요한 액션 정보: ${parts.join(', ')}',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionUnconfirmedChip extends StatelessWidget {
  final String label;

  const _ActionUnconfirmedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return MacosTooltip(
      message: '전사본에서 명확히 확인되지 않은 정보입니다',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.amber.shade900,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── 액션 아이템 행 (체크박스 + 정보 + 편집/삭제) ─────────────────────
class _ActionItemRow extends StatelessWidget {
  final ActionItem item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onEvidence;

  /// LLM이 명시한 근거 타임스탬프 (빈 문자열 = 미명시)
  final String evidenceTs;
  const _ActionItemRow({
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.onEvidence,
    this.evidenceTs = '',
  });

  @override
  Widget build(BuildContext context) {
    final done = item.completed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 22,
            width: 22,
            child: Checkbox(
              value: done,
              onChanged: (v) => onToggle(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: SelectableText.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: done ? Colors.grey.shade500 : null,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                  children: [
                    TextSpan(text: item.task),
                    if (!item.ownerNeedsConfirmation && item.owner.isNotEmpty)
                      TextSpan(
                        text: '  [${item.owner}]',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.indigo.shade400,
                        ),
                      ),
                    if (!item.deadlineNeedsConfirmation &&
                        item.deadline.isNotEmpty)
                      TextSpan(
                        text: ' [${item.deadline}]',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (item.ownerNeedsConfirmation) ...[
            const SizedBox(width: 6),
            const _ActionUnconfirmedChip(label: '담당자 미확인'),
          ],
          if (item.deadlineNeedsConfirmation) ...[
            const SizedBox(width: 6),
            const _ActionUnconfirmedChip(label: '기한 미확인'),
          ],
          if (onEvidence != null) ...[
            const SizedBox(width: 6),
            _EvidenceButton(timestamp: evidenceTs, onPressed: onEvidence!),
          ],
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              size: 14,
              color: Colors.grey.shade500,
            ),
            tooltip: '수정',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 14,
              color: Colors.red.shade300,
            ),
            tooltip: '삭제',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── 액션 아이템 편집 다이얼로그 ────────────────────────────────────────
class _ActionItemEditDialog extends StatefulWidget {
  final ActionItem? existing;
  const _ActionItemEditDialog({this.existing});

  @override
  State<_ActionItemEditDialog> createState() => _ActionItemEditDialogState();
}

class _ActionItemEditDialogState extends State<_ActionItemEditDialog> {
  late TextEditingController _taskCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _deadlineCtrl;

  @override
  void initState() {
    super.initState();
    _taskCtrl = TextEditingController(text: widget.existing?.task ?? '');
    _ownerCtrl = TextEditingController(text: widget.existing?.owner ?? '');
    _deadlineCtrl = TextEditingController(
      text: widget.existing?.deadline ?? '',
    );
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    _ownerCtrl.dispose();
    _deadlineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return MacosAlertDialog(
      appIcon: Icon(isEdit ? Icons.edit_outlined : Icons.add_task, size: 48),
      title: Text(isEdit ? '액션 아이템 수정' : '액션 아이템 추가'),
      message: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _taskCtrl,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '할 일 *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ownerCtrl,
              decoration: const InputDecoration(
                labelText: '담당자',
                hintText: '예: 홍길동',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _deadlineCtrl,
              decoration: const InputDecoration(
                labelText: '마감',
                hintText: '예: 2026-04-30, 이번 주 금요일',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () {
          final task = _taskCtrl.text.trim();
          if (task.isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('할 일을 입력해주세요.')));
            return;
          }
          Navigator.pop(
            context,
            ActionItem(
              task: task,
              owner: _ownerCtrl.text.trim(),
              deadline: _deadlineCtrl.text.trim(),
              completed: widget.existing?.completed ?? false,
            ),
          );
        },
        child: Text(isEdit ? '저장' : '추가'),
      ),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
    );
  }
}

/// 화자 편집 다이얼로그 결과
class _SpeakerEditResult {
  final String name;
  final String? mergeInto;
  const _SpeakerEditResult({required this.name, required this.mergeInto});
}

/// 재요약 템플릿 피커 결과.
/// [cancelled]가 true면 다이얼로그를 닫았음을 의미.
/// [templateId]: null = 전역 설정 사용, 외에는 preset id 또는 customId.
/// [styleMode]: 같은 회의 유형 위에 누적 적용되는 재생성 스타일.
class _TemplatePickResult {
  final String? templateId;
  final SummaryStyleMode styleMode;
  final bool cancelled;
  const _TemplatePickResult(
    this.templateId, {
    this.styleMode = SummaryStyleMode.standard,
  }) : cancelled = false;
  const _TemplatePickResult.cancelled()
    : templateId = null,
      styleMode = SummaryStyleMode.standard,
      cancelled = true;

  @override
  bool operator ==(Object other) =>
      other is _TemplatePickResult &&
      other.cancelled == cancelled &&
      other.templateId == templateId &&
      other.styleMode == styleMode;

  @override
  int get hashCode => Object.hash(cancelled, templateId, styleMode);
}

/// 현재 실행 중이거나 대기 중인 네이티브 모델 작업 안내.
class _NativeTaskNotice extends StatelessWidget {
  const _NativeTaskNotice();

  @override
  Widget build(BuildContext context) {
    final manager = OnDeviceModelManager.instance;
    return StreamBuilder<NativeModelTaskSnapshot>(
      stream: manager.nativeTaskStream,
      initialData: manager.nativeTaskSnapshot,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || !state.hasWork) return const SizedBox.shrink();
        final active = state.activeLabel;
        final queued = state.queuedLabel;
        final text = [
          if (active != null) '현재 작업: $active',
          if (queued != null)
            state.queuedCount > 1
                ? '대기 중: $queued 외 ${state.queuedCount - 1}개'
                : '다음 작업 대기: $queued',
        ].join(' · ');

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              height: 1.35,
            ),
          ),
        );
      },
    );
  }
}

/// LLM 스트리밍 중 실시간 생성 텍스트 표시. 새 토큰이 올 때마다
/// 하단으로 자동 스크롤해 타자기 효과를 낸다.
class _LivePreviewText extends StatefulWidget {
  final String text;
  const _LivePreviewText({required this.text});

  @override
  State<_LivePreviewText> createState() => _LivePreviewTextState();
}

class _LivePreviewTextState extends State<_LivePreviewText> {
  final _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(covariant _LivePreviewText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollCtrl,
      child: SelectableText(
        widget.text,
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: Colors.grey.shade300,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

/// 녹음 파일명 표시 + 클릭 시 Finder에서 해당 파일을 선택한 채로 연다.
/// macOS 전용: `open -R <path>` → Finder가 파일 상위 폴더를 띄우고 파일을 하이라이트.
class _AudioFileReveal extends StatefulWidget {
  final String path;
  const _AudioFileReveal({required this.path});

  @override
  State<_AudioFileReveal> createState() => _AudioFileRevealState();
}

class _AudioFileRevealState extends State<_AudioFileReveal> {
  bool _hover = false;

  Future<void> _reveal() async {
    final file = File(widget.path);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('파일을 찾을 수 없습니다: ${widget.path}')));
      return;
    }
    try {
      await Process.run('open', ['-R', widget.path]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Finder 열기 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.path.split('/').last;
    final color = _hover ? Colors.blue.shade300 : Colors.grey.shade400;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _reveal,
        child: MacosTooltip(
          message: 'Finder에서 보기\n${widget.path}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audio_file_outlined, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                fileName,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontFamily: 'monospace',
                  decoration: _hover ? TextDecoration.underline : null,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 11, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
