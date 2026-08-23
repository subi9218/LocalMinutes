import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_build_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/l10n/app_tr.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/calendar_service.dart';
import '../../core/services/chunked_summarizer.dart';
import '../../core/services/crash_log_service.dart';
import '../../core/services/menu_bar_service.dart';
import '../../core/services/security_scoped_bookmark_service.dart';
import '../../core/services/summary_templates.dart';
import '../../core/services/tag_extractor.dart';
import '../../core/services/user_error_message.dart';
import '../../core/utils/auto_bullet.dart';
import '../../core/utils/transcript_text_cleaner.dart';
import '../../core/utils/summary_parser.dart';
import '../../core/services/isar_service.dart';
import 'package:record/record.dart'
    show AudioEncoder, AudioRecorder, InputDevice, RecordConfig;
import '../../core/utils/wav_mixer.dart';
import '../../data/datasources/diarization_service.dart';
import '../../data/datasources/llm_service.dart';
import '../../data/datasources/microphone_service.dart';
import '../../data/datasources/stt_service.dart';
import '../../data/datasources/system_audio_service.dart';
import 'package:isar/isar.dart' show Isar;
import '../../data/repositories/glossary_repository_impl.dart';
import '../../data/repositories/meeting_repository_impl.dart';
import '../../data/repositories/transcript_repository_impl.dart';
import '../../data/repositories/summary_repository_impl.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/meeting_processing_report.dart';
import '../../domain/entities/transcript.dart';
import '../../domain/entities/summary.dart';
import '../providers/global_container.dart';
import '../providers/meeting_providers.dart';

enum _RecordingPhase {
  idle,
  checkingModels,
  loadingModel,
  recording,
  paused,
  processing,
  stopped,
  summarizing,
  done,
  error,
}

class _RecordingStartException implements Exception {
  final String title;
  final String message;
  const _RecordingStartException({required this.title, required this.message});

  @override
  String toString() => message;
}

class RecordingView extends ConsumerStatefulWidget {
  const RecordingView({super.key});

  @override
  ConsumerState<RecordingView> createState() => _RecordingViewState();
}

class _RecordingViewState extends ConsumerState<RecordingView> {
  /// 진행 중 녹음 세션의 복구용 meetingId — 위젯이 아니라 세션의 소유물.
  /// (녹음 중 다른 화면을 봤다 돌아오면 State가 새로 생성되는데, 이 값이
  ///  위젯 로컬이면 소실되어 정지 시 중복 회의가 생기고 원본이
  ///  status=recording 고스트로 남는다 → static으로 세션에 귀속)
  ///
  /// 반드시 mic.startTime과 쌍으로 대조한다 — id만 보면 '이전에 끝난 세션'의
  /// id를 다음 세션이 물려받아 완료된 회의를 덮어쓰는 참사가 난다.
  static int? _sessionRecoveryMeetingId;
  static DateTime? _sessionRecoveryStartTime;

  /// 이 State가 세션 메타(제목/메모/안건/북마크)의 소유자인지.
  /// 재마운트된 State는 DB에서 메타를 복원하기 전까지 false — 그동안
  /// 체크포인트는 세그먼트만 갱신하고 메타를 빈 값으로 덮지 않는다.
  bool _sessionMetaOwned = true;

  /// dispose 후에도 체크포인트가 제목/메모를 쓸 수 있도록 한 마지막 스냅샷.
  /// (TextEditingController는 dispose 후 .text 접근이 불가)
  String _titleSnapshot = '';
  String _notesSnapshot = '';

  _RecordingPhase _phase = _RecordingPhase.idle;
  final List<SttSegment> _segments = [];
  String _statusMsg = '';
  // LLM 스트리밍 진행 상태 (토큰 수 기반 프로그레스만 노출, 텍스트 프리뷰는 제거됨)
  double _summaryProgress = 0.0;
  DateTime? _summaryStartTime;
  Timer? _summaryTicker;
  bool _cancelSummaryRequested = false;
  int _lastFinalSttElapsedMs = 0;
  int _lastFinalSttAudioMs = 0;
  String _lastFinalSttModel = '';
  int _lastDiarizationElapsedMs = 0;
  String _lastDiarizationStatus = '';

  /// 요약 실패 복구용: LLM 실패 전에 Meeting+Transcripts는 이미 DB에 저장되므로,
  /// 이 필드가 non-null이면 "회의록으로 이동" / "다시 요약" 버튼을 노출할 수 있다.
  int? _failedSummaryMeetingId;
  // _summaryOutput 제거 (UI에서 미사용 — _buildSummarizingCard로 대체됨)
  Timer? _uiTimer;
  bool _isProcessingWindow = false;
  double _inputLevel = 0.0; // 0~1, 녹음 중 VU 미터

  // 모델 파일 존재 여부
  bool _sttModelExists = false;
  bool _sttFastExists = false;
  bool _sttAccurateExists = false;
  bool _llmModelExists = false;
  String _modelDir = '';
  bool _shouldRunFinalAccuratePass = false;

  // 날짜 접두사 (고정) + 제목 접미사 (사용자 입력)
  late String _datePrefix; // e.g. "26년 04월 18일"
  late TextEditingController _titleSuffixController; // 추가 제목

  String? _audioSavePath; // 녹음 WAV 저장 경로
  // 온라인 회의: 시스템 오디오를 함께 캡처한 경우의 임시 WAV 경로. null이면 미사용.
  String? _systemAudioPath;
  RecordingSource _recordingSource = RecordingSource.mic;
  bool _systemAudioSupported = false; // macOS 14.2+ 시스템 오디오 캡처 지원 여부
  DateTime? _recordingStartedAt; // 실제 녹음 시작 시각
  DateTime? _recordingEndedAt; // 실제 녹음 종료 시각

  /// 크래시 복구용 — 녹음 시작 즉시 DB에 Meeting을 저장한 ID.
  /// 이후 _persistMeetingAndTranscripts에서 새로 만들지 않고 이 id를 갱신한다.
  int? _recoveryMeetingId;
  Timer? _checkpointTimer;

  /// _startRecording 재진입 방지 플래그 (트레이 quick-start 등으로 인한
  /// 준비 다이얼로그 중복 트리거 → 중복 회의 생성 방지).
  bool _startInProgress = false;

  /// 회의 어젠다 (녹음 준비 다이얼로그에서 사용자가 입력)
  String _meetingAgenda = '';

  /// 녹음 중 사용자가 마킹한 핵심 순간 북마크
  final List<Bookmark> _bookmarks = [];

  // 마이크 장치 선택
  List<InputDevice> _inputDevices = [];
  InputDevice? _selectedDevice;
  bool _devicesLoaded = false;

  final ScrollController _transcriptScrollController = ScrollController();

  // 인라인 편집
  int? _editingSegIndex;
  final TextEditingController _editingCtrl = TextEditingController();
  bool _transcriptManuallyEdited = false;
  List<String?> _pendingSpeakerLabels = const [];

  // 메모
  final TextEditingController _notesCtrl = TextEditingController();
  bool _notesExpanded = false;
  double _notesHeight = 120.0; // 드래그로 조절 가능한 높이
  String _notesPrev = ''; // AutoBullet 직전값 추적
  DateTime? _lastAudibleInputAt;
  bool _lowInputBannerDismissed = false;
  bool _emptyRecordingPromptShown = false;
  double _maxInputLevelDuringRecording = 0.0;
  bool _lowQualitySummaryConfirmed = false;

  // 참석자
  final List<String> _participants = [];
  final TextEditingController _participantInputCtrl = TextEditingController();
  int? _meetingSpeakerCount;

  // 이 녹음에 적용할 요약 템플릿 id (null = 전역 설정)
  String? _summaryTemplateId;

  /// 최종 회의 제목: datePrefix + suffix (suffix가 있으면 공백 포함)
  String get _fullTitle {
    final suffix = _titleSuffixController.text.trim();
    return suffix.isEmpty ? _datePrefix : '$_datePrefix $suffix';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final yy = now.year.toString().substring(2);
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    _datePrefix = '$yy년 $mm월 $dd일 $hh:$min';
    _titleSuffixController = TextEditingController();
    _setupMicCallbacks();
    _loadInputDevices();
    SystemAudioService.instance.isSupported().then((v) {
      if (mounted) setState(() => _systemAudioSupported = v);
    });

    // ── 이미 녹음/일시정지 중이라면 상태 즉시 복원 ──────────────────
    // (사이드바에서 다른 회의를 봤다가 돌아올 때 위젯이 새로 생성됨)
    final mic = MicrophoneService.instance;
    if (mic.isRecording) {
      ref.read(nativeRecordingActiveProvider.notifier).state = true;
      _phase = _RecordingPhase.recording;
      _segments.addAll(mic.segments);
      _statusMsg = tr('녹음 중 (30초마다 자동으로 텍스트 변환)', 'Recording (auto-transcribes every 30s)');
      _sttModelExists = true;
      _llmModelExists = true;
      // 세션 상태 복원 — 없으면 정상 녹음이 '0초 빈 녹음'으로 판정되어
      // 삭제 유도 다이얼로그가 뜨고(삭제 시 실제 WAV 소실), 정지 시
      // 중복 회의가 생기며 크래시 복구 체크포인트도 멈춘다.
      _restoreSessionState(mic);
      _checkpointTimer?.cancel();
      _checkpointTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted || _phase != _RecordingPhase.recording) return;
        _saveRecoveryCheckpoint();
      });
      // UI 경과 시간 갱신 타이머 재시작
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (mic.isPaused) {
      ref.read(nativeRecordingActiveProvider.notifier).state = true;
      _phase = _RecordingPhase.paused;
      _segments.addAll(mic.segments);
      _statusMsg = tr('일시 정지됨 — "계속하기"로 재개하세요.', 'Paused — press "Resume" to continue.');
      _sttModelExists = true;
      _llmModelExists = true;
      _restoreSessionState(mic);
    } else {
      ref.read(nativeRecordingActiveProvider.notifier).state = false;
      _checkModels();
    }

    // 메뉴바 트레이 "빠른 녹음 시작" 처리 — 콜드 스타트(이 위젯이 새로 마운트된 케이스)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(pendingTrayQuickStartProvider);
      if (pending) {
        final fromTray = ref.read(pendingTrayQuickStartFromTrayProvider);
        ref.read(pendingTrayQuickStartProvider.notifier).state = false;
        ref.read(pendingTrayQuickStartFromTrayProvider.notifier).state = false;
        // 모델 체크 끝나기 전이라도 _startRecording는 내부에서 모델 검사함
        _startRecording(showTrayFailureNotice: fromTray);
      }
      final pendingStop = ref.read(pendingTrayStopProvider);
      if (pendingStop) {
        ref.read(pendingTrayStopProvider.notifier).state = false;
        if (MicrophoneService.instance.isRecording ||
            MicrophoneService.instance.isPaused) {
          _stopRecording();
        }
      }
      _consumePendingTrayBookmarks();
    });
  }

  // ── 모델 파일 존재 여부 확인 ─────────────────────────────────────
  Future<void> _checkModels() async {
    setState(() => _phase = _RecordingPhase.checkingModels);
    try {
      final appSupport = await getApplicationSupportDirectory();
      final dir = '${appSupport.path}/models';
      _modelDir = dir;
      _sttFastExists = await File(
        '$dir/${AppConstants.sttModelFileFast}',
      ).exists();
      _sttAccurateExists = await File(
        '$dir/${AppConstants.sttModelFileAccurate}',
      ).exists();
      _sttModelExists = _sttFastExists || _sttAccurateExists;
      final llmGemma = await File(
        '$dir/${AppConstants.llmModelFileGemma4E2B}',
      ).exists();
      final llmQwen = await File(
        '$dir/${AppConstants.llmModelFileQwen25_7B}',
      ).exists();
      _llmModelExists = llmGemma || llmQwen;
    } catch (_) {}
    if (mounted) setState(() => _phase = _RecordingPhase.idle);
  }

  void _setupMicCallbacks() {
    final mic = MicrophoneService.instance;
    mic.onSegment = (seg) {
      if (!mounted) return;
      setState(() => _segments.add(seg));
      // 새 세그먼트가 그려진 직후 최하단(최신)으로 스크롤
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_transcriptScrollController.hasClients) {
          _transcriptScrollController.animateTo(
            _transcriptScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    };
    mic.onProcessing = (processing) {
      if (mounted) setState(() => _isProcessingWindow = processing);
    };
    mic.onLevel = (lvl) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _inputLevel = lvl;
        if (lvl > _maxInputLevelDuringRecording) {
          _maxInputLevelDuringRecording = lvl;
        }
        if (lvl >= 0.08) {
          _lastAudibleInputAt = now;
          _lowInputBannerDismissed = false;
        }
      });
    };
    mic.onError = (err) {
      if (mounted) {
        setState(() {
          _phase = _RecordingPhase.error;
          _statusMsg = err;
        });
      }
    };
  }

  void _startEditingSeg(int index) {
    setState(() {
      _editingSegIndex = index;
      _editingCtrl.text = _segments[index].text;
    });
  }

  void _commitEditingSeg() {
    if (_editingSegIndex == null) return;
    final newText = _editingCtrl.text.trim();
    if (newText.isNotEmpty) {
      setState(() {
        final index = _editingSegIndex!;
        if (_segments[index].text != newText) {
          _segments[index] = _segments[index].copyWith(text: newText);
          _transcriptManuallyEdited = true;
        }
      });
    }
    setState(() => _editingSegIndex = null);
  }

  String? _selectLiveSttModelFile() {
    final sttMode = AppSettings.instance.sttProcessingMode;
    if (sttMode == AppSettings.sttModeAccurate) {
      // 녹음 중에는 빠른 모델을 초안용으로 우선 사용하고,
      // 요약 직전 정확 모델로 전체 WAV를 다시 전사한다.
      if (_sttFastExists) return AppConstants.sttModelFileFast;
      if (_sttAccurateExists) return AppConstants.sttModelFileAccurate;
    } else {
      if (_sttFastExists) return AppConstants.sttModelFileFast;
      if (_sttAccurateExists) return AppConstants.sttModelFileAccurate;
    }
    return null;
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _summaryTicker?.cancel();
    _checkpointTimer?.cancel();
    _titleSuffixController.dispose();
    _editingCtrl.dispose();
    _transcriptScrollController.dispose();
    MicrophoneService.instance.onSegment = null;
    MicrophoneService.instance.onProcessing = null;
    MicrophoneService.instance.onError = null;
    MicrophoneService.instance.onLevel = null;
    _notesCtrl.dispose();
    _participantInputCtrl.dispose();
    super.dispose();
  }

  /// 재마운트 시 세션 상태 복원. 세션 id는 mic.startTime과 쌍으로 대조해
  /// '이전에 끝난 세션'의 id를 잘못 물려받는 것(완료된 회의 파괴)을 막는다.
  void _restoreSessionState(MicrophoneService mic) {
    _recordingStartedAt = mic.startTime;
    _audioSavePath = mic.savedAudioPath;
    // 시스템 오디오 캡처가 진행 중이면 세션 상태를 서비스에서 되살린다 —
    // 위젯 필드에만 있으면 재마운트 후 pause/정지 선정지/최종 믹스가 전부
    // 건너뛰어져 상대방 음성이 최종 오디오에서 사라진다.
    if (SystemAudioService.instance.isRecording) {
      _systemAudioPath = SystemAudioService.instance.currentOutputPath;
      _recordingSource = _parseRecordingSource(
        AppSettings.instance.recordingSource,
      );
    }
    final sameSession = _sessionRecoveryStartTime != null &&
        _sessionRecoveryStartTime == mic.startTime;
    if (sameSession && _sessionRecoveryMeetingId != null) {
      _recoveryMeetingId = _sessionRecoveryMeetingId;
      // 메타(제목/메모/안건/북마크)는 DB에서 복원될 때까지 체크포인트가
      // 덮어쓰지 않는다 — 복원 전에 덮으면 사용자가 입력한 값이 빈 값이 된다.
      _sessionMetaOwned = false;
      unawaited(_restoreSessionMeta(_sessionRecoveryMeetingId!));
    }
    // sameSession이 아니면 _recoveryMeetingId는 null로 남아
    // 다음 체크포인트가 initial 분기로 '새 회의'를 만든다 (안전).
  }

  /// DB에 저장된 진행 중 회의의 메타를 컨트롤러/필드로 되살린다.
  /// 성공하면 이 State가 메타 소유권을 회복한다.
  Future<void> _restoreSessionMeta(int meetingId) async {
    try {
      final m = await MeetingRepositoryImpl(
        IsarService.instance.db,
      ).getMeetingById(meetingId);
      if (m == null) return; // 사용자가 삭제한 경우 — 소유권 미회복(안 덮음)
      // 제목은 접두어+접미어 재조합 대신 저장된 전체 제목을 그대로 유지한다.
      _datePrefix = m.title;
      _titleSuffixController.clear();
      _notesCtrl.text = m.notes;
      _meetingAgenda = m.agenda;
      _summaryTemplateId = m.summaryTemplateId;
      _bookmarks
        ..clear()
        ..addAll(_parseBookmarksJson(m.bookmarksJson));
      _titleSnapshot = m.title;
      _notesSnapshot = m.notes.trim();
      _sessionMetaOwned = true;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[Restore] session meta restore failed: $e');
    }
  }

  static List<Bookmark> _parseBookmarksJson(String raw) {
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

  /// 북마크 리스트를 JSON 직렬화 (빈 리스트면 빈 문자열 반환)
  String _bookmarksToJson() => _bookmarks.isEmpty
      ? ''
      : jsonEncode(_bookmarks.map((b) => b.toJson()).toList());

  /// 현재 녹음 경과 시간(초)
  int _currentRecordingSec() {
    // 일시 정지 시간을 뺀 실제 녹음 경과 시간 사용 (transcript 타임스탬프와 정렬).
    final elapsedSec = MicrophoneService.instance.elapsed.inSeconds;
    if (elapsedSec > 0) return elapsedSec;
    // elapsed가 아직 시작 전이거나 0이면 기존 계산으로 폴백.
    if (_recordingStartedAt == null) return 0;
    return DateTime.now().difference(_recordingStartedAt!).inSeconds;
  }

  int _recognizedCharCount() =>
      _segments.fold<int>(0, (sum, seg) => sum + seg.text.trim().length);

  Duration _recordingDuration() {
    if (_recordingStartedAt == null) return Duration.zero;
    final end = _recordingEndedAt ?? DateTime.now();
    final duration = end.difference(_recordingStartedAt!);
    return duration.isNegative ? Duration.zero : duration;
  }

  bool get _hasLowInputForAWhile {
    if (_phase != _RecordingPhase.recording || _lowInputBannerDismissed) {
      return false;
    }
    final duration = _recordingDuration();
    if (duration < const Duration(seconds: 20)) return false;

    final mic = MicrophoneService.instance;
    if (mic.totalBytesReceived == 0) return true;

    final lastAudible = _lastAudibleInputAt;
    if (lastAudible == null) return true;
    return DateTime.now().difference(lastAudible) >=
        const Duration(seconds: 18);
  }

  bool _looksLikeEmptyRecording() {
    return _recordingQualityStatus().$1 == 'empty';
  }

  (String, String) _recordingQualityStatus() {
    final duration = _recordingDuration();
    final chars = _recognizedCharCount();
    final bytes = MicrophoneService.instance.totalBytesReceived;
    final segments = _segments.length;

    if (duration < const Duration(seconds: 5)) {
      return ('empty', tr('녹음 시간이 ${duration.inSeconds}초로 너무 짧습니다.', 'The recording is only ${duration.inSeconds}s — too short.'));
    }
    if (bytes == 0) return ('empty', tr('마이크에서 오디오 데이터가 들어오지 않았습니다.', 'No audio data was received from the microphone.'));
    if (segments == 0 && duration >= const Duration(seconds: 12)) {
      // 콜드 모델 로드가 끝나기 전에 정지된 세션: 전사가 없는 건 오디오
      // 문제가 아니라 모델이 준비되기 전이었기 때문. WAV는 정상 저장되므로
      // 삭제를 유도하지 않고 '다시 전사' 안내로 강등한다.
      if (!MicrophoneService.instance.sttReadyThisSession) {
        return (
          'low',
          tr('음성 인식 준비가 끝나기 전에 정지되어 실시간 전사가 없습니다. 저장된 녹음에서 "다시 전사"를 실행하면 전사본을 만들 수 있습니다.',
              'Recording stopped before speech recognition finished preparing, so there is no live transcript. Run "Re-transcribe" on the saved recording to create one.'),
        );
      }
      return ('empty', tr('음성 인식 결과가 생성되지 않았습니다.', 'No speech recognition results were produced.'));
    }
    if (chars < 20 &&
        duration >= const Duration(seconds: 20) &&
        _maxInputLevelDuringRecording < 0.10) {
      return ('empty', tr('인식된 글자 수가 $chars자로 매우 적고, 녹음 중 입력 음량도 낮았습니다.', 'Only $chars characters were recognized, and the input level was low during recording.'));
    }
    if (duration >= const Duration(seconds: 30) && chars < 60) {
      return ('low', tr('녹음 시간에 비해 인식된 발화가 적습니다.', 'Little speech was recognized relative to the recording length.'));
    }
    if (duration >= const Duration(seconds: 30) && segments <= 1) {
      return ('low', tr('전사 세그먼트가 $segments개뿐이라 요약 품질이 낮을 수 있습니다.', 'Only $segments transcript segment(s) — summary quality may be low.'));
    }
    if (duration >= const Duration(seconds: 30) &&
        _maxInputLevelDuringRecording < 0.16) {
      return ('low', tr('녹음 중 입력 음량이 낮아 일부 발화가 누락됐을 수 있습니다.', 'The input level was low during recording, so some speech may be missing.'));
    }
    return ('ok', '');
  }

  bool _looksLikeLowQualityRecording() {
    final status = _recordingQualityStatus().$1;
    return status == 'empty' || status == 'low';
  }

  String _emptyRecordingReason() {
    final quality = _recordingQualityStatus();
    if (quality.$2.isNotEmpty) return quality.$2;
    return tr('녹음 품질을 확인하기 어렵습니다.', 'Unable to assess the recording quality.');
  }

  String _qualityStatusLabel(String status) => switch (status) {
    'empty' => tr('거의 빈 녹음', 'Nearly empty recording'),
    'low' => tr('요약 품질 낮을 수 있음', 'Summary quality may be low'),
    'ok' => tr('정상', 'Good'),
    _ => tr('확인 필요', 'Needs review'),
  };

  Color _qualityStatusColor(String status) => switch (status) {
    'empty' => Colors.red.shade700,
    'low' => Colors.orange.shade700,
    _ => Colors.green.shade700,
  };

  IconData _qualityStatusIcon(String status) => switch (status) {
    'empty' => Icons.hearing_disabled_outlined,
    'low' => Icons.warning_amber_rounded,
    _ => Icons.check_circle_outline,
  };

  Future<_EmptyRecordingAction?> _showLowQualityRecordingDialog({
    required bool allowSummarize,
  }) async {
    final duration = _recordingDuration();
    final chars = _recognizedCharCount();
    final quality = _recordingQualityStatus();
    final status = quality.$1;
    final reason = quality.$2.isEmpty ? _emptyRecordingReason() : quality.$2;
    final color = _qualityStatusColor(status);

    return showMacosSheet<_EmptyRecordingAction>(
      context: context,
      builder: (ctx) => MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(_qualityStatusIcon(status), color: color, size: 48),
              const SizedBox(height: 12),
              Text(
                _qualityStatusLabel(status),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 440,
                child: Text(
                  tr(
                    '$reason\n\n'
                        '녹음 시간: ${duration.inSeconds}초\n'
                        '인식된 글자 수: $chars자\n'
                        '전사 세그먼트: ${_segments.length}개\n'
                        '최대 입력 레벨: ${(_maxInputLevelDuringRecording * 100).toStringAsFixed(0)}%\n\n'
                        '마이크 위치나 입력 장치를 확인한 뒤 다시 녹음하는 것을 권장합니다.',
                    '$reason\n\n'
                        'Duration: ${duration.inSeconds}s\n'
                        'Recognized characters: $chars\n'
                        'Transcript segments: ${_segments.length}\n'
                        'Peak input level: ${(_maxInputLevelDuringRecording * 100).toStringAsFixed(0)}%\n\n'
                        'We recommend checking the microphone position or input device and recording again.',
                  ),
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () =>
                        Navigator.pop(ctx, _EmptyRecordingAction.keep),
                    child: Text(tr('보관만 하기', 'Keep only')),
                  ),
                  const SizedBox(width: 8),
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () =>
                        Navigator.pop(ctx, _EmptyRecordingAction.delete),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tr('삭제', 'Delete'),
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (allowSummarize) ...[
                    const SizedBox(width: 8),
                    PushButton(
                      controlSize: ControlSize.large,
                      color: color,
                      onPressed: () =>
                          Navigator.pop(ctx, _EmptyRecordingAction.summarize),
                      child: Text(
                        tr('그래도 요약하기', 'Summarize anyway'),
                        style: const TextStyle(color: MacosColors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _qualityLogMessage() {
    final quality = _recordingQualityStatus();
    return 'quality=${quality.$1}, reason=${quality.$2}, '
        'durationSec=${_recordingDuration().inSeconds}, '
        'segments=${_segments.length}, chars=${_recognizedCharCount()}, '
        'maxLevel=${_maxInputLevelDuringRecording.toStringAsFixed(3)}, '
        'bytes=${MicrophoneService.instance.totalBytesReceived}';
  }

  void _recordQualityIfNeeded({required String context}) {
    final quality = _recordingQualityStatus();
    if (quality.$1 == 'ok') return;
    CrashLogService.instance.info(_qualityLogMessage(), context: context);
  }

  Future<void> _maybeWarnEmptyRecordingAfterStop() async {
    if (!mounted ||
        _emptyRecordingPromptShown ||
        !_looksLikeLowQualityRecording()) {
      return;
    }
    _emptyRecordingPromptShown = true;
    _recordQualityIfNeeded(context: 'emptyRecordingAfterStop');

    final action = await _showLowQualityRecordingDialog(allowSummarize: false);

    if (action == _EmptyRecordingAction.delete) {
      await _discardEmptyRecordingDraft();
    } else if (mounted) {
      final label = _qualityStatusLabel(_recordingQualityStatus().$1);
      setState(() {
        _statusMsg = tr('$label 상태입니다. 마이크 상태를 확인한 뒤 요약 여부를 선택하세요.', 'Status: $label. Check the microphone, then choose whether to summarize.');
      });
    }
  }

  Future<void> _discardEmptyRecordingDraft() async {
    final audioPath =
        MicrophoneService.instance.savedAudioPath ?? _audioSavePath;
    try {
      final meetingId = _recoveryMeetingId;
      if (meetingId != null) {
        final db = IsarService.instance.db;
        await TranscriptRepositoryImpl(db).deleteByMeetingId(meetingId);
        await SummaryRepositoryImpl(db).deleteSummaryByMeetingId(meetingId);
        await MeetingRepositoryImpl(db).deleteMeeting(meetingId);
      }
      if (audioPath != null && audioPath.isNotEmpty) {
        final file = File(audioPath);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('[EmptyRecording] discard failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('빈 녹음 삭제 실패: $e', 'Failed to delete empty recording: $e')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    ref.invalidate(meetingsProvider);
    setState(() {
      _phase = _RecordingPhase.idle;
      _statusMsg = tr('빈 녹음을 삭제했습니다. 다시 녹음할 수 있습니다.', 'Empty recording deleted. You can record again.');
      _segments.clear();
      _pendingSpeakerLabels = const [];
      _audioSavePath = null;
      _recordingStartedAt = null;
      _recordingEndedAt = null;
      _recoveryMeetingId = null;
      _sessionRecoveryMeetingId = null;
      _sessionRecoveryStartTime = null;
      _inputLevel = 0;
      _lastAudibleInputAt = null;
      _maxInputLevelDuringRecording = 0;
      _emptyRecordingPromptShown = false;
      _lowInputBannerDismissed = false;
    });
  }

  /// 북마크 추가 — 녹음 중일 때만 동작.
  /// 녹음 시작 후 경과 시간을 기준으로 저장.
  void _addBookmark({String label = '', bool showFeedback = true}) {
    if (_phase != _RecordingPhase.recording &&
        _phase != _RecordingPhase.paused) {
      return;
    }
    final sec = _currentRecordingSec();
    setState(() => _bookmarks.add(Bookmark(sec: sec, label: label)));

    // SnackBar 피드백
    if (!showFeedback) return;
    final time = Bookmark(sec: sec).timeStr;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1500),
        content: Row(
          children: [
            const Icon(
              Icons.bookmark_added_rounded,
              color: Colors.amber,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label.isEmpty
                  ? tr('북마크 저장됨 — $time', 'Bookmark saved — $time')
                  : tr('북마크 저장됨 — $time · $label', 'Bookmark saved — $time · $label'),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade700,
      ),
    );
  }

  void _consumePendingTrayBookmarks() {
    final count = ref.read(pendingTrayBookmarkCountProvider);
    if (count <= 0) return;
    ref.read(pendingTrayBookmarkCountProvider.notifier).state = 0;

    if (_phase != _RecordingPhase.recording &&
        _phase != _RecordingPhase.paused) {
      return;
    }

    for (var i = 0; i < count; i++) {
      _addBookmark(showFeedback: false);
    }
    final sec = _currentRecordingSec();
    final time = Bookmark(sec: sec).timeStr;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1600),
        content: Row(
          children: [
            const Icon(
              Icons.bookmark_added_rounded,
              color: Colors.amber,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(count == 1
                ? tr('트레이 북마크 저장됨 — $time', 'Tray bookmark saved — $time')
                : tr('트레이 북마크 $count개 저장됨', '$count tray bookmarks saved')),
          ],
        ),
        backgroundColor: Colors.indigo.shade700,
      ),
    );
  }

  /// 크래시 복구용 체크포인트.
  /// [initial]=true 이면 Meeting을 새로 생성. 이후 호출은 같은 Meeting을 갱신
  /// + 현재 _segments를 transcripts 테이블에 일괄 교체.
  Future<void> _saveRecoveryCheckpoint({bool initial = false}) async {
    // dispose 후에도 저장은 진행한다 — 정지 마무리(최대 30초+) 중 화면을
    // 떠나면 예전엔 여기서 return해 마지막 전사 flush가 무산되고 done 회의의
    // 꼬리 세그먼트가 유실됐다. 컨트롤러는 dispose 후 접근 불가이므로
    // mounted일 때 스냅샷을 갱신하고, 아니면 마지막 스냅샷을 쓴다.
    if (mounted) {
      _titleSnapshot = _fullTitle;
      _notesSnapshot = _notesCtrl.text.trim();
    }
    final title = _titleSnapshot;
    final notes = _notesSnapshot;
    try {
      final db = IsarService.instance.db;
      final meetingRepo = MeetingRepositoryImpl(db);
      final transcriptRepo = TranscriptRepositoryImpl(db);
      final now = DateTime.now();

      Meeting meeting;
      if (initial || _recoveryMeetingId == null) {
        meeting = Meeting()
          ..title = title
          ..createdAt = _recordingStartedAt ?? now
          ..status = MeetingStatus.recording
          ..audioFilePath = _audioSavePath
          ..notes = notes
          ..summaryTemplateId = _summaryTemplateId
          ..agenda = _meetingAgenda
          ..bookmarksJson = _bookmarksToJson();
        _recoveryMeetingId = await meetingRepo.saveMeeting(meeting);
        // 세션 소유 id — 재마운트된 새 State가 이어받을 수 있도록.
        // 반드시 시작 시각과 쌍으로 저장한다 (다음 세션이 오염되지 않게).
        _sessionRecoveryMeetingId = _recoveryMeetingId;
        _sessionRecoveryStartTime = MicrophoneService.instance.startTime;
        _sessionMetaOwned = true; // 초기 생성 State가 메타 소유자
      } else {
        final existing = await meetingRepo.getMeetingById(_recoveryMeetingId!);
        if (existing == null) {
          // 사용자가 사이드바에서 삭제한 경우 — 새로 만들지 않고 그냥 무시
          return;
        }
        // 재마운트 직후(메타 미복원) State는 세그먼트만 flush한다 —
        // 여기서 메타를 덮으면 사용자가 입력한 제목/메모/북마크가
        // 재마운트 State의 빈 값으로 파괴된다.
        if (_sessionMetaOwned) {
          existing
            ..title = title
            ..notes = notes
            ..summaryTemplateId = _summaryTemplateId
            ..agenda = _meetingAgenda
            ..bookmarksJson = _bookmarksToJson();
          await meetingRepo.updateMeeting(existing);
        }
      }

      // 현재 segments 일괄 교체 (segmentIndex로 정렬되므로 단순 replace).
      // dispose 후에는 onSegment 콜백이 끊겨 위젯 _segments가 최종 flush
      // 세그먼트를 못 받으므로 서비스 세그먼트를 진실 소스로 쓴다.
      final segs = mounted ? _segments : MicrophoneService.instance.segments;
      final mid = _recoveryMeetingId!;
      await transcriptRepo.deleteByMeetingId(mid);
      for (int i = 0; i < segs.length; i++) {
        final seg = segs[i];
        final t = Transcript()
          ..meetingId = mid
          ..segmentIndex = i
          ..text = seg.text
          ..startTimeSeconds = seg.startMs / 1000.0
          ..endTimeSeconds = seg.endMs / 1000.0
          ..speakerLabel = null
          ..createdAt = now;
        await transcriptRepo.saveSegment(t);
      }
      // 사이드바 목록 갱신 (녹음 진행 표시) — dispose 후에도 안전하도록
      // ref 대신 전역 컨테이너 사용.
      globalProviderContainer.invalidate(meetingsProvider);
    } catch (e) {
      debugPrint('[Checkpoint] save failed: $e');
    }
  }

  String _formatDurationKr(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return tr('$minutes분 $seconds초', '${minutes}m ${seconds}s');
  }

  String _formatDurationClock(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String? _nativeTaskBlockReason(String actionLabel) {
    final active = OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (active == null) return null;
    return tr('현재 $active 작업 중입니다. 완료 후 $actionLabel을(를) 다시 시도해주세요.', '$active is currently running. Please try $actionLabel again once it finishes.');
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

  void _startSummaryTicker() {
    _summaryTicker?.cancel();
    _summaryTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _phase == _RecordingPhase.summarizing) {
        setState(() {});
      }
    });
  }

  Duration _currentSummaryElapsed() {
    final start = _summaryStartTime;
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  String? _trayBusyLabel() {
    return switch (_phase) {
      _RecordingPhase.checkingModels => tr('모델 확인 중...', 'Checking models...'),
      _RecordingPhase.loadingModel => tr('녹음 준비 중...', 'Preparing recording...'),
      _RecordingPhase.processing => tr('녹음 정리 중...', 'Finalizing recording...'),
      _RecordingPhase.summarizing => tr('요약 중...', 'Summarizing...'),
      _ => null,
    };
  }

  void _requestCancelSummary() {
    if (_phase != _RecordingPhase.summarizing || _cancelSummaryRequested) {
      return;
    }
    setState(() {
      _cancelSummaryRequested = true;
      _statusMsg = tr('요약 중지 중', 'Stopping summary');
    });
    LlmService.instance.requestCancelActiveGeneration();
  }

  // ── 녹음 제어 ─────────────────────────────────────────────────
  Future<void> _startRecording({bool showTrayFailureNotice = false}) async {
    // 재진입 방지: 준비 다이얼로그가 열려 있는 동안 트레이 quick-start 등으로
    // 두 번째 _startRecording이 호출되면 중복 회의가 생성된다.
    if (_startInProgress) return;
    _startInProgress = true;
    try {
    final prep = await _showRecordingPrepDialog();
    if (!mounted) return;
    if (prep == null) return;
    _meetingSpeakerCount = prep.speakerCount;
    _selectedDevice = prep.device;
    _summaryTemplateId = prep.summaryTemplateId;
    _meetingAgenda = prep.agenda;
    _bookmarks.clear();
    _lastAudibleInputAt = null;
    _lowInputBannerDismissed = false;
    _emptyRecordingPromptShown = false;
    _maxInputLevelDuringRecording = 0.0;
    _lowQualitySummaryConfirmed = false;
    await AppSettings.instance.setNumSpeakersHint(prep.speakerCount);
    await AppSettings.instance.setDiarizationEnabled(prep.diarizationEnabled);
    await AppSettings.instance.setSttLanguage(prep.sttLanguage);
    if (prep.markMicGuideShown && !AppSettings.instance.micGuideShown) {
      await AppSettings.instance.setMicGuideShown(true);
    }

    // 모델 파일 존재 확인 → 없으면 크래시 방지
    await _checkModels();
    if (!_sttModelExists) {
      setState(() {
        _phase = _RecordingPhase.error;
        _statusMsg = tr('음성 인식 모델 파일이 없습니다. 아래 안내를 따라 모델을 설치해주세요.', 'The speech recognition model file is missing. Follow the guide below to install it.');
      });
      if (showTrayFailureNotice) {
        await _showTrayRecordingStartFailureDialog(
          title: tr('음성 인식 모델이 필요합니다', 'Speech recognition model required'),
          message: tr('트레이에서 바로 녹음하려면 먼저 음성 인식 모델을 설치해주세요.', 'To record directly from the tray, please install the speech recognition model first.'),
        );
      }
      return;
    }

    // 시스템 오디오 동의는 '모델 로드 중' 진행바를 띄우기 전에 먼저 받는다.
    // (진행바 뒤에서 다이얼로그가 떠 사용자가 "처리 중이라 기다려야 한다"고
    //  오해하는 문제 방지 — 실제 모델 로드는 동의 이후 startRecording에서 시작)
    var resolvedSource = _parseRecordingSource(
      AppSettings.instance.recordingSource,
    );
    if (resolvedSource != RecordingSource.mic) {
      final consent = await _ensureSystemAudioConsent();
      if (!mounted) return;
      if (!consent) resolvedSource = RecordingSource.mic;
    }

    setState(() {
      _phase = _RecordingPhase.loadingModel;
      _statusMsg = tr('음성 인식 모델 준비 중', 'Preparing speech recognition model');
      _segments.clear();
      _transcriptManuallyEdited = false;
      _pendingSpeakerLabels = const [];
      _meetingSpeakerCount = prep.speakerCount;
      _participants.clear();
      _participantInputCtrl.clear();
      // 날짜/시간 갱신 (재녹음 시 새 시각으로)
      final now2 = DateTime.now();
      final yy = now2.year.toString().substring(2);
      final mm = now2.month.toString().padLeft(2, '0');
      final dd = now2.day.toString().padLeft(2, '0');
      final hh = now2.hour.toString().padLeft(2, '0');
      final min = now2.minute.toString().padLeft(2, '0');
      _datePrefix = '$yy년 $mm월 $dd일 $hh:$min';
      _titleSuffixController.text = prep.titleSuffix.trim();
    });
    MicrophoneService.instance.reset();

    try {
      final appSupport = await getApplicationSupportDirectory();
      final liveSttModelFile = _selectLiveSttModelFile();
      if (liveSttModelFile == null) {
        throw Exception(tr('설치된 음성 인식 모델이 없습니다.', 'No speech recognition model is installed.'));
      }
      final sttPath = '${appSupport.path}/models/$liveSttModelFile';
      _shouldRunFinalAccuratePass =
          AppSettings.instance.sttProcessingMode ==
              AppSettings.sttModeAccurate &&
          liveSttModelFile == AppConstants.sttModelFileFast &&
          _sttAccurateExists;
      if (mounted) {
        setState(() {
          // CoreML 가속팩 최초 로드는 macOS의 Neural Engine 컴파일 때문에
          // 몇 분까지 걸릴 수 있어(OS 업데이트·재설치 후 재발) 미리 안내한다.
          _statusMsg = liveSttModelFile == AppConstants.sttModelFileFast
              ? tr('빠른 음성 인식 준비 중 — 최초 실행은 가속 준비로 몇 분 걸릴 수 있어요',
                  'Preparing fast speech recognition — the first run may take a few minutes to warm up')
              : tr('정확 음성 인식 준비 중 — 최초 실행은 준비에 몇 분 걸릴 수 있어요',
                  'Preparing accurate speech recognition — the first run may take a few minutes');
        });
      }

      // 녹음 저장 폴더 + 파일 경로 결정
      final recordingsDirPath = AppSettings.instance.recordingsSavePath;
      if (recordingsDirPath.isEmpty) {
        throw _RecordingStartException(
          title: tr('저장 폴더 선택이 필요합니다', 'Choose a save folder'),
          message: tr('회의 녹음을 시작하려면 먼저 녹음 파일을 저장할 폴더를 선택해주세요.', 'To start recording, please choose a folder to save recording files first.'),
        );
      }
      final restoredAccess =
          await SecurityScopedBookmarkService.restoreRecordingsFolderAccess();
      if (!restoredAccess) {
        throw _RecordingStartException(
          title: tr('저장 폴더 권한이 필요합니다', 'Save folder access required'),
          message: tr(
            'macOS 보안 정책 때문에 저장 폴더 접근 권한을 다시 받아야 합니다.\n'
                '설정에서 녹음 파일 저장 위치를 다시 선택한 뒤 녹음을 시작해주세요.\n\n'
                '현재 폴더: $recordingsDirPath',
            'macOS security requires re-granting access to the save folder.\n'
                'Re-select the recording save location in Settings, then start recording.\n\n'
                'Current folder: $recordingsDirPath',
          ),
        );
      }
      final recordingsDir = Directory(recordingsDirPath);
      try {
        await recordingsDir.create(recursive: true);
      } catch (_) {
        throw _RecordingStartException(
          title: tr('저장 폴더에 접근할 수 없습니다', 'Cannot access the save folder'),
          message: tr(
            '선택한 저장 폴더에 녹음 파일을 만들 수 없습니다.\n'
                '설정에서 다른 저장 폴더를 선택한 뒤 다시 시도해주세요.\n\n'
                '현재 폴더: $recordingsDirPath',
            'Recording files cannot be created in the selected save folder.\n'
                'Choose a different save folder in Settings and try again.\n\n'
                'Current folder: $recordingsDirPath',
          ),
        );
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      _audioSavePath = '${recordingsDir.path}/meeting_$ts.wav';

      // 온라인 회의: 선택한 소스가 시스템 오디오를 포함하면 마이크 시작 전에
      // 시스템 캡처를 켜고, 실시간 중간 전사용 PCM 소스를 마이크 서비스에 연결한다.
      // 실패(미지원/권한 거부)해도 마이크 녹음은 계속한다(graceful).
      _recordingSource = resolvedSource;
      _systemAudioPath = null;
      if (_recordingSource != RecordingSource.mic && _audioSavePath != null) {
        // 시스템 오디오 동의는 모델 로드 전 단계에서 이미 받았다.
        // 여기서는 시스템 오디오 캡처만 시작한다.
        {
          final sysPath = _audioSavePath!.replaceFirst(
            RegExp(r'\.wav$'),
            '_system.wav',
          );
          try {
            final ok = await SystemAudioService.instance.start(sysPath);
            _systemAudioPath = ok ? sysPath : null;
            CrashLogService.instance.info(
              'system audio start ok=$ok path=$sysPath',
              context: 'systemAudio',
            );
            if (!ok && mounted) {
              _showSystemAudioFailSnack(
                tr(
                  '시스템 오디오 캡처를 시작하지 못해 마이크만 녹음합니다.',
                  'Could not start system audio capture; recording mic only.',
                ),
              );
            }
          } catch (e) {
            _systemAudioPath = null;
            CrashLogService.instance.info(
              'system audio start FAILED: $e',
              context: 'systemAudio',
            );
            if (mounted) {
              _showSystemAudioFailSnack(
                tr(
                  '시스템 오디오 권한이 필요합니다. 마이크만 녹음합니다.',
                  'System audio permission is required; recording mic only.',
                ),
              );
            }
          }
        }
      }

      // 실시간 중간 전사 윈도우에 시스템 오디오를 합산할 소스 연결 (없으면 null).
      MicrophoneService.instance.systemPcmSource = _systemAudioPath != null
          ? SystemAudioService.instance.drainPcm
          : null;

      // 새 세션 시작 — 이전 세션의 static 잔재를 반드시 무효화한다.
      // (남아 있으면 초기 체크포인트 전에 재마운트될 경우 이전 회의를
      //  물려받아 그 회의의 전사·제목을 덮어쓴다)
      _sessionRecoveryMeetingId = null;
      _sessionRecoveryStartTime = null;
      _sessionMetaOwned = true;

      // 모델 로드(콜드 캐시 시 몇 분) 중 화면을 떠나도 사이드바의
      // "녹음 진행 중" 배너·가드가 작동하도록 미리 켠다.
      ref.read(nativeRecordingActiveProvider.notifier).state = true;

      await MicrophoneService.instance.startRecording(
        sttPath,
        audioSavePath: _audioSavePath,
        device: _selectedDevice,
      );

      if (!mounted) {
        // 모델 로드 중 사용자가 다른 화면으로 이동해 이 뷰가 dispose됨.
        // 녹음(마이크 스트림)은 서비스에서 계속되고, 사이드바 배너로 복귀하면
        // initState 복원 경로가 상태를 되살린다. dispose된 ref/setState를
        // 건드리면 StateError가 나므로 여기서 조용히 종료한다.
        CrashLogService.instance.info(
          'recording continues headless (view disposed during model load)',
          context: 'recording',
        );
        return;
      }

      // 시작 시각은 마이크 스트림이 실제 열린 시점 기준
      // (모델 로드가 오래 걸려도 오디오는 그 시점부터 쌓였음)
      _recordingStartedAt =
          MicrophoneService.instance.startTime ?? DateTime.now();
      _recordingEndedAt = null;

      // 크래시 복구: 녹음 시작 즉시 Meeting을 DB에 저장 (status=recording)
      // 30초마다 부분 transcripts를 flush하여 앱이 비정상 종료돼도 복구 가능
      await _saveRecoveryCheckpoint(initial: true);
      _checkpointTimer?.cancel();
      _checkpointTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted || _phase != _RecordingPhase.recording) return;
        _saveRecoveryCheckpoint();
      });

      // 1초마다 UI 갱신 (경과 시간)
      _uiTimer?.cancel();
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });

      setState(() {
        _phase = _RecordingPhase.recording;
        _statusMsg = _shouldRunFinalAccuratePass
            ? tr('녹음 중 (빠른 모델로 30초마다 초안 전사 · 요약 전 정확 전사)', 'Recording (draft every 30s with the fast model · accurate transcription before summary)')
            : tr('녹음 중 (30초마다 자동으로 텍스트 변환)', 'Recording (auto-transcribes every 30s)');
      });
    } on MicrophonePermissionDeniedException catch (e) {
      // 로드가 비동기화되며 실패 시점에 뷰가 dispose됐을 수 있음 → mounted 가드
      if (mounted) {
        ref.read(nativeRecordingActiveProvider.notifier).state = false;
        setState(() {
          _phase = _RecordingPhase.error;
          _statusMsg = e.message;
        });
        await _showMicPermissionDialog();
      }
    } on _RecordingStartException catch (e) {
      if (mounted) {
        ref.read(nativeRecordingActiveProvider.notifier).state = false;
        setState(() {
          _phase = _RecordingPhase.error;
          _statusMsg = e.message;
        });
        if (showTrayFailureNotice) {
          await _showTrayRecordingStartFailureDialog(
            title: e.title,
            message: e.message,
          );
        }
      }
    } catch (e, st) {
      CrashLogService.instance.recordCaught(e, st, context: 'startRecording');
      if (mounted) {
        ref.read(nativeRecordingActiveProvider.notifier).state = false;
        final friendly = friendlyErrorMessage(
          e,
          fallbackTitle: tr('녹음을 시작하지 못했습니다', 'Could not start recording'),
          fallbackMessage: tr('잠시 후 다시 시도해주세요.', 'Please try again in a moment.'),
          nextStep: tr('마이크, 저장 폴더, AI 모델 설치 상태를 확인해주세요.', 'Check the microphone, save folder, and AI model installation.'),
        );
        setState(() {
          _phase = _RecordingPhase.error;
          _statusMsg = friendly.fullText;
        });
        if (showTrayFailureNotice) {
          await _showTrayRecordingStartFailureDialog(
            title: friendly.title,
            message: friendly.message,
          );
        }
      }
    }
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> _showTrayRecordingStartFailureDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showMacosAlertDialog<void>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const Icon(
          Icons.error_outline_rounded,
          color: Colors.orange,
          size: 48,
        ),
        title: Text(title),
        message: Text(message, textAlign: TextAlign.center),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(tr('확인', 'OK')),
        ),
      ),
    );
  }

  /// 마이크 권한 거부 → 시스템 설정 안내 다이얼로그 + 직접 이동 버튼
  Future<void> _showMicPermissionDialog() async {
    await showMacosAlertDialog<void>(
      context: context,
      builder: (ctx) => MacosAlertDialog(
        appIcon: const Icon(Icons.mic_off, color: Colors.red, size: 48),
        title: Text(tr('마이크 권한이 필요합니다', 'Microphone access required')),
        message: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  '회의 녹음을 위해 마이크 접근 권한이 필요합니다.\n'
                      '시스템 설정에서 "Local Minutes" 항목을 켜주세요.',
                  'Microphone access is required to record meetings.\n'
                      'Enable "Local Minutes" in System Settings.',
                ),
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tr('경로: 시스템 설정 → 개인정보 보호 및 보안 → 마이크', 'Path: System Settings → Privacy & Security → Microphone'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () async {
            // macOS x-apple.systempreferences URL — 마이크 섹션으로 직접 이동
            try {
              await Process.run('open', [
                'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
              ]);
            } catch (_) {}
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.open_in_new, size: 14, color: MacosColors.white),
                const SizedBox(width: 4),
                Text(tr('시스템 설정 열기', 'Open System Settings'), style: const TextStyle(color: MacosColors.white)),
              ],
            ),
          ),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('나중에', 'Later')),
        ),
      ),
    );
  }

  Future<void> _pauseRecording() async {
    await MicrophoneService.instance.pauseRecording();
    // 시스템 오디오 캡처도 함께 일시정지 — 시스템 트랙만 계속 기록되면
    // 최종 믹스에서 두 트랙의 시간축이 어긋난다. (서비스 상태 기준 —
    // 위젯 필드는 재마운트로 비어 있을 수 있다)
    if (SystemAudioService.instance.isRecording) {
      await SystemAudioService.instance.setPaused(true);
    }
    setState(() {
      _phase = _RecordingPhase.paused;
      _statusMsg = tr('일시 정지됨 — "계속하기"로 재개하세요.', 'Paused — press "Resume" to continue.');
    });
  }

  Future<void> _resumeRecording() async {
    await MicrophoneService.instance.resumeRecording();
    if (SystemAudioService.instance.isRecording) {
      await SystemAudioService.instance.setPaused(false);
    }
    // paused 상태로 재마운트된 State는 체크포인트 타이머가 없다 — 재개 시 보장.
    if (_checkpointTimer == null || !_checkpointTimer!.isActive) {
      _checkpointTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted || _phase != _RecordingPhase.recording) return;
        _saveRecoveryCheckpoint();
      });
    }
    setState(() {
      _phase = _RecordingPhase.recording;
      _statusMsg = tr('녹음 중 (30초마다 자동으로 텍스트 변환)', 'Recording (auto-transcribes every 30s)');
    });
  }

  Future<void> _stopRecording() async {
    _uiTimer?.cancel();
    _checkpointTimer?.cancel();
    setState(() {
      _phase = _RecordingPhase.processing;
      _statusMsg = tr('녹음 정리 중', 'Finalizing recording');
    });
    // 시스템 오디오 캡처를 마이크 정지보다 먼저 멈춘다 — mic 정지는 최종
    // 전사 flush로 최대 30초+ 걸리는데, 그동안 시스템 캡처가 계속 파일에
    // 기록되면 시스템 트랙이 마이크보다 길어져 믹스 싱크가 어긋난다.
    if (SystemAudioService.instance.isRecording) {
      // 주의: stop()이 currentOutputPath를 지우므로 최종 믹스용 경로를
      // 먼저 위젯 필드에 확보해 둔다.
      _systemAudioPath ??= SystemAudioService.instance.currentOutputPath;
      try {
        await SystemAudioService.instance.stop();
      } catch (_) {}
    }
    // stopRecording은 최대 30초까지 걸릴 수 있다. 이 사이에 사용자가 화면을
    // 벗어나면 위젯이 dispose되므로, 영속화(회의 status=done + 마지막
    // 체크포인트)를 ref/setState보다 먼저 수행해 중간 이탈에도 회의가
    // status=recording에 멈추지 않고 올바르게 마무리되도록 한다.
    await MicrophoneService.instance.stopRecording();
    _recordingEndedAt = DateTime.now();

    // 온라인 회의: 시스템 오디오를 함께 캡처했다면 최종 오디오 파일을 믹스/대체한다.
    // (전사·요약이 파일을 읽기 전에 수행 — 마이크 경로에 덮어쓰므로 downstream 변경 불필요)
    await _finalizeSystemAudioIfNeeded();

    // ── 영속화 (UI 갱신보다 먼저, 가드 이전에 반드시 완료) ──
    // 마지막 체크포인트: status=done으로 표기 (요약 전 단계)
    if (_recoveryMeetingId != null) {
      try {
        final meetingRepo = MeetingRepositoryImpl(IsarService.instance.db);
        final m = await meetingRepo.getMeetingById(_recoveryMeetingId!);
        if (m != null) {
          m
            ..status = MeetingStatus.done
            ..endedAt = _recordingEndedAt;
          await meetingRepo.updateMeeting(m);
        }
      } catch (_) {}
    }
    await _saveRecoveryCheckpoint();

    // provider 정리는 dispose 여부와 무관하게 반드시 실행 — 예전엔 정지
    // 마무리 중 화면 이탈 시 nativeRecordingActiveProvider가 true로 고착돼
    // 사이드바 '녹음 진행 중' 배너와 게이트가 영구히 잠겼다.
    globalProviderContainer.read(nativeRecordingActiveProvider.notifier).state =
        false;
    globalProviderContainer.invalidate(meetingsProvider);

    // ── 여기서부터 UI 갱신: 위젯이 dispose됐으면 안전하게 종료 ──
    if (!mounted) return;
    setState(() {
      _inputLevel = 0;
      _phase = _RecordingPhase.stopped;
      _statusMsg = tr('녹음 완료. 요약을 실행하세요.', 'Recording complete. Run the summary.');
    });
    await _maybeWarnEmptyRecordingAfterStop();
  }

  RecordingSource _parseRecordingSource(String s) => switch (s) {
    'system' => RecordingSource.systemAudio,
    'both' => RecordingSource.micAndSystem,
    _ => RecordingSource.mic,
  };

  /// 시스템 오디오 녹음 첫 사용 시 통화/회의 녹음 법적 고지에 동의받는다.
  /// 동의하면 true(이후 표시 안 함), 거부하면 false(마이크만 녹음).
  Future<bool> _ensureSystemAudioConsent() async {
    if (AppSettings.instance.systemAudioConsentShown) return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr('시스템 오디오 녹음 안내', 'System audio recording notice')),
        content: Text(
          tr(
            '온라인 회의 상대방의 목소리(시스템 오디오)를 함께 녹음합니다. '
                '통화·회의 녹음은 지역에 따라 상대방의 동의가 필요할 수 있습니다. '
                '관련 법규를 준수하고 필요한 동의를 받은 뒤 사용하세요.',
            'This also records the other party\'s audio (system output). '
                'Recording calls/meetings may require their consent depending on your region. '
                'Please comply with applicable laws and obtain any required consent.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(tr('마이크만', 'Mic only')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(tr('동의하고 계속', 'Agree & continue')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppSettings.instance.setSystemAudioConsentShown(true);
      return true;
    }
    return false;
  }

  /// 시스템 오디오 시작 실패 안내 + '설정 열기' 액션.
  void _showSystemAudioFailSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: tr('설정 열기', 'Open settings'),
          onPressed: () => SystemAudioService.instance.openPrivacySettings(),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// 시스템 오디오 캡처를 종료하고, 선택 소스에 따라 최종 오디오 파일을 만든다.
  /// - systemAudio: 시스템 WAV를 16kHz 모노로 변환해 마이크 경로에 덮어씀
  /// - micAndSystem: 마이크 + 시스템을 믹스해 마이크 경로에 덮어씀
  /// 시스템 파일이 없거나 믹스 실패 시 마이크 녹음을 그대로 사용한다(graceful).
  Future<void> _finalizeSystemAudioIfNeeded() async {
    // 위젯 필드가 재마운트로 비었더라도 서비스가 세션 경로를 알고 있다.
    final sysPath =
        _systemAudioPath ?? SystemAudioService.instance.currentOutputPath;
    if (sysPath == null) return;
    _systemAudioPath = null;
    // 믹스가 실제로 성공했을 때만 시스템 원본을 지운다 — 예전엔 finally에서
    // 무조건 삭제해, 믹스 실패 시 상대방 음성의 유일한 원본이 영구 소실됐다.
    var mixSucceeded = false;
    try {
      await SystemAudioService.instance.stop();
      final micPath =
          MicrophoneService.instance.savedAudioPath ?? _audioSavePath;
      final sysLen = await File(sysPath).exists()
          ? await File(sysPath).length()
          : -1;
      CrashLogService.instance.info(
        'system audio finalize: source=$_recordingSource sysBytes=$sysLen micPath=$micPath',
        context: 'systemAudio',
      );
      if (micPath == null) return;
      if (sysLen <= 0) {
        mixSucceeded = true; // 빈 파일 → 지워도 잃을 것 없음
        return;
      }

      if (_recordingSource == RecordingSource.systemAudio) {
        mixSucceeded = await WavMixer.mixFiles([sysPath], micPath);
      } else {
        final mixedTmp = '$micPath.mix.wav';
        final ok = await WavMixer.mixFiles([micPath, sysPath], mixedTmp);
        if (ok) {
          await File(mixedTmp).rename(micPath);
          mixSucceeded = true;
        } else {
          await File(mixedTmp).delete().catchError((_) => File(mixedTmp));
        }
      }
      CrashLogService.instance.info(
        'system audio mix done → $micPath (ok=$mixSucceeded)',
        context: 'systemAudio',
      );
    } catch (e, st) {
      CrashLogService.instance.recordCaught(
        e,
        st,
        context: 'systemAudioFinalize',
      );
    } finally {
      if (mixSucceeded) {
        try {
          await File(sysPath).delete();
        } catch (_) {}
      } else {
        // 원본 보존 — 사용자가 수동으로 복구할 수 있도록 로그에 경로를 남긴다.
        CrashLogService.instance.info(
          'system audio kept (mix failed): $sysPath',
          context: 'systemAudio',
        );
      }
    }
  }

  Future<_RecordingPrepResult?> _showRecordingPrepDialog() async {
    var speakerCount =
        _meetingSpeakerCount ?? AppSettings.instance.numSpeakersHint;
    if (speakerCount < 2 || speakerCount > 6) speakerCount = 2;
    var selectedDeviceId = _selectedDevice?.id;
    if (!_inputDevices.any((device) => device.id == selectedDeviceId)) {
      selectedDeviceId = null;
    }
    var templateId = _summaryTemplateId;
    var diarizationEnabled = AppSettings.instance.diarizationEnabled;
    var sttLanguage = AppSettings.instance.sttLanguage;
    var recordingSource = AppSettings.instance.recordingSource; // mic/system/both
    var titleText = _titleSuffixController.text.trim();
    var agendaText = '';
    var titleFieldVersion = 0;
    var agendaFieldVersion = 0;
    Future<void> Function()? stopMicTest;
    final result = await showDialog<_RecordingPrepResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final viewport = MediaQuery.sizeOf(ctx);
            final scheme = Theme.of(ctx).colorScheme;
            final dialogWidth = (viewport.width - 96)
                .clamp(560.0, 680.0)
                .toDouble();
            final dialogMaxHeight = (viewport.height - 96)
                .clamp(600.0, 780.0)
                .toDouble();
            InputDecoration prepDecoration(
              String label, {
              String? hintText,
              String? helperText,
            }) {
              return InputDecoration(
                labelText: label,
                hintText: hintText,
                helperText: helperText,
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.62),
                ),
                helperStyle: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.34,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: scheme.primary),
                ),
                isDense: true,
              );
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 48,
                vertical: 40,
              ),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth,
                  maxHeight: dialogMaxHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 42,
                          color: scheme.onSurface,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          tr('녹음 준비', 'Recording setup'),
                          textAlign: TextAlign.center,
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (AppBuildConfig.enableCalendarIntegration)
                                  _CalendarSuggestionPanel(
                                    onPick: (event) {
                                      setLocalState(() {
                                        if (titleText.trim().isEmpty) {
                                          titleText = event.title;
                                          titleFieldVersion++;
                                        }
                                        if (agendaText.trim().isEmpty) {
                                          final t = event.title;
                                          agendaText = '- $t';
                                          agendaFieldVersion++;
                                        }
                                      });
                                    },
                                  ),
                                TextFormField(
                                  key: ValueKey(
                                    'prep-title-$titleFieldVersion',
                                  ),
                                  initialValue: titleText,
                                  onChanged: (v) => titleText = v,
                                  decoration: prepDecoration(
                                    tr('회의 제목', 'Meeting title'),
                                    hintText: tr('예: 제품 주간 회의', 'e.g. Product weekly'),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        isExpanded: true,
                                        initialValue: speakerCount,
                                        decoration: prepDecoration(tr('말할 사람 수', 'Number of speakers')),
                                        items: [
                                          DropdownMenuItem(
                                            value: 2,
                                            child: Text(tr('2명', '2 people')),
                                          ),
                                          DropdownMenuItem(
                                            value: 3,
                                            child: Text(tr('3명', '3 people')),
                                          ),
                                          DropdownMenuItem(
                                            value: 4,
                                            child: Text(tr('4명', '4 people')),
                                          ),
                                          DropdownMenuItem(
                                            value: 5,
                                            child: Text(tr('5명', '5 people')),
                                          ),
                                          DropdownMenuItem(
                                            value: 6,
                                            child: Text(tr('6명', '6 people')),
                                          ),
                                        ],
                                        onChanged: (v) {
                                          if (v != null) {
                                            setLocalState(
                                              () => speakerCount = v,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: DropdownButtonFormField<String?>(
                                        isExpanded: true,
                                        initialValue: templateId,
                                        decoration: prepDecoration(tr('회의 유형', 'Meeting type')),
                                        items: [
                                          DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text(
                                              tr('설정값 사용', 'Use default setting'),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          for (final t
                                              in SummaryTemplates.presets)
                                            DropdownMenuItem<String?>(
                                              value: t.id,
                                              child: Text(
                                                t.name,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          DropdownMenuItem<String?>(
                                            value: SummaryTemplates.customId1,
                                            child: Text(
                                              tr('커스텀1', 'Custom 1'),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          DropdownMenuItem<String?>(
                                            value: SummaryTemplates.customId2,
                                            child: Text(
                                              tr('커스텀2', 'Custom 2'),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                        onChanged: (v) {
                                          setLocalState(() => templateId = v);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // ── 어젠다 (선택) ──────────────────────────────
                                TextFormField(
                                  key: ValueKey(
                                    'prep-agenda-$agendaFieldVersion',
                                  ),
                                  initialValue: agendaText,
                                  onChanged: (v) => agendaText = v,
                                  maxLines: 4,
                                  minLines: 2,
                                  decoration: prepDecoration(
                                    tr('어젠다 (선택)', 'Agenda (optional)'),
                                    hintText: tr(
                                      '한 줄에 하나씩 입력하면 요약이 어젠다별로 정리됩니다.\n'
                                          '예:\n'
                                          '- 신규 피처 일정\n'
                                          '- 결제 모듈 리뷰',
                                      'Enter one item per line and the summary will be organized by agenda.\n'
                                          'e.g.:\n'
                                          '- New feature schedule\n'
                                          '- Payment module review',
                                    ),
                                    helperText: tr(
                                      '비워두면 일반 요약. 입력하면 항목별 결정·액션이 정리됩니다.',
                                      'Leave empty for a general summary. Fill in to organize decisions and actions per item.',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: sttLanguage,
                                  decoration: prepDecoration(tr('음성 인식 언어', 'Recognition language')),
                                  items: [
                                    for (final code
                                        in AppSettings.supportedSttLanguages)
                                      DropdownMenuItem(
                                        value: code,
                                        child: Text(
                                          AppSettings.sttLanguageLabel(code),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setLocalState(() => sttLanguage = v);
                                    }
                                  },
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  AppSettings.sttLanguageDescription(
                                    sttLanguage,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                                if (_systemAudioSupported) ...[
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: recordingSource,
                                    decoration: prepDecoration(
                                      tr('녹음 소스', 'Recording source'),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'mic',
                                        child: Text(tr('마이크만', 'Mic only')),
                                      ),
                                      DropdownMenuItem(
                                        value: 'both',
                                        child: Text(
                                          tr('마이크 + 시스템', 'Mic + system'),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'system',
                                        child: Text(
                                          tr('시스템 오디오만', 'System audio only'),
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) {
                                        setLocalState(() => recordingSource = v);
                                        unawaited(
                                          AppSettings.instance
                                              .setRecordingSource(v),
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    tr(
                                      '온라인 회의(Zoom 등) 상대 목소리까지 녹음하려면 시스템 오디오를 켜세요.',
                                      'Turn on system audio to also record the other party in online meetings.',
                                    ),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String?>(
                                  initialValue: selectedDeviceId,
                                  decoration: prepDecoration(tr('마이크', 'Microphone')),
                                  items: [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text(tr('시스템 기본 마이크', 'System default microphone')),
                                    ),
                                    for (final device in _inputDevices)
                                      DropdownMenuItem<String?>(
                                        value: device.id,
                                        child: Text(
                                          device.label,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    setLocalState(() => selectedDeviceId = v);
                                  },
                                ),
                                const SizedBox(height: 8),
                                _MicTestPanel(
                                  selectedDeviceId: selectedDeviceId,
                                  devices: _inputDevices,
                                  onStopReady: (stop) => stopMicTest = stop,
                                ),
                                const SizedBox(height: 12),
                                _PrepToggleRow(
                                  title: tr('발화자 라벨 사용', 'Use speaker labels'),
                                  subtitle: tr('발화 흐름을 A/B/C로 구분합니다.', 'Distinguishes the speaking flow as A/B/C.'),
                                  value: diarizationEnabled,
                                  onChanged: (v) {
                                    setLocalState(() => diarizationEnabled = v);
                                  },
                                ),
                                if (!AppSettings.instance.micGuideShown) ...[
                                  const Divider(height: 24),
                                  Text(
                                    tr('녹음 품질 체크', 'Recording quality check'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _PrepGuideRow(
                                    icon: Icons.center_focus_strong_rounded,
                                    text: tr('기기 또는 마이크를 말하는 사람들의 중앙에 두세요.', 'Place the device or microphone in the center of the speakers.'),
                                  ),
                                  _PrepGuideRow(
                                    icon: Icons.volume_down_rounded,
                                    text: tr('에어컨, 선풍기, 키보드 소음은 가능한 한 멀리 두세요.', 'Keep AC, fan, and keyboard noise as far away as possible.'),
                                  ),
                                  _PrepGuideRow(
                                    icon: Icons.record_voice_over_outlined,
                                    text: tr('여러 명이 참석하면 겹쳐 말하는 시간을 줄이면 좋습니다.', 'With several attendees, reducing overlapping speech helps.'),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  tr('7명 이상 회의는 현재 가장 가까운 값인 6명을 선택하세요.', 'For meetings with 7+ people, choose 6 — the closest available value.'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: PushButton(
                                controlSize: ControlSize.large,
                                secondary: true,
                                onPressed: () async {
                                  await stopMicTest?.call();
                                  if (ctx.mounted) Navigator.of(ctx).pop(null);
                                },
                                child: Text(tr('취소', 'Cancel')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PushButton(
                                controlSize: ControlSize.large,
                                onPressed: () async {
                                  await stopMicTest?.call();
                                  if (!ctx.mounted) return;
                                  InputDevice? selectedDevice;
                                  if (selectedDeviceId != null) {
                                    for (final device in _inputDevices) {
                                      if (device.id == selectedDeviceId) {
                                        selectedDevice = device;
                                        break;
                                      }
                                    }
                                  }
                                  Navigator.of(ctx).pop(
                                    _RecordingPrepResult(
                                      titleSuffix: titleText.trim(),
                                      speakerCount: speakerCount,
                                      device: selectedDevice,
                                      summaryTemplateId: templateId,
                                      diarizationEnabled: diarizationEnabled,
                                      sttLanguage: sttLanguage,
                                      markMicGuideShown:
                                          !AppSettings.instance.micGuideShown,
                                      agenda: agendaText.trim(),
                                    ),
                                  );
                                },
                                child: Text(tr('녹음 시작', 'Start recording')),
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
    return result;
  }

  // ── LLM 선택 다이얼로그 ────────────────────────────────────────
  Future<String?> _pickLlmDialog() async {
    final appSupport = await getApplicationSupportDirectory();
    final modelsDir = '${appSupport.path}/models';
    final installed = <String>[];
    for (final id in AppSettings.availableLlmModelIds) {
      if (await File(
        '$modelsDir/${AppSettings.llmModelFileFor(id)}',
      ).exists()) {
        installed.add(id);
      }
    }
    if (installed.isEmpty) return null;
    if (installed.length == 1) return installed.first;

    String selected = AppSettings.instance.selectedLlmModel;
    if (!installed.contains(selected)) selected = installed.first;

    String labelOf(String id) => switch (id) {
      'qwen25_7b' => 'Qwen 2.5 7B',
      _ => 'Gemma 4 E2B',
    };
    String tipOf(String id) => switch (id) {
      'qwen25_7b' => tr('Qwen 2.5 7B Instruct Q4_K_M (~4.7GB)\n한국어·구조화 출력 강함', 'Qwen 2.5 7B Instruct Q4_K_M (~4.7GB)\nStrong Korean & structured output'),
      _ => tr('Gemma 4 E2B Q8_0 (~3GB)\n빠름, 기본 품질', 'Gemma 4 E2B Q8_0 (~3GB)\nFast, baseline quality'),
    };

    if (!mounted) return null;
    return showMacosAlertDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return MacosAlertDialog(
            appIcon: const Icon(Icons.auto_awesome, size: 48),
            title: Text(tr('요약 모델 선택', 'Choose summary model')),
            message: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('마우스를 올리면 모델 설명이 보입니다.', 'Hover to see the model description.'),
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
              child: Text(tr('요약 실행', 'Run summary')),
            ),
            secondaryButton: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(tr('취소', 'Cancel')),
            ),
          );
        },
      ),
    );
  }

  // ── LLM 이름 표시용 헬퍼 ──────────────────────────────────────
  static String _llmDisplayName(String id) => switch (id) {
    'qwen25_7b' => 'Qwen 2.5',
    _ => 'Gemma 4',
  };

  Duration _currentAudioDurationEstimate() {
    if (_recordingStartedAt != null && _recordingEndedAt != null) {
      return _recordingEndedAt!.difference(_recordingStartedAt!);
    }
    if (_segments.isNotEmpty) {
      return Duration(milliseconds: _segments.last.endMs);
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
    final bounded = seconds.clamp(minSeconds, maxSeconds).toInt();
    return Duration(seconds: bounded);
  }

  Future<bool> _confirmSummaryEstimate() async {
    final audio = _currentAudioDurationEstimate();
    var useDiarization = AppSettings.instance.diarizationEnabled;

    final finalSttEstimate = _shouldRunFinalAccuratePass
        ? _boundedEstimate(audio, 0.36, minSeconds: 30, maxSeconds: 60 * 45)
        : Duration.zero;
    final diarizationEstimate = _boundedEstimate(
      audio,
      0.34,
      minSeconds: 30,
      maxSeconds: 60 * 40,
    );
    final summaryRatio = switch (AppSettings.instance.summarySpeedMode) {
      AppSettings.summaryModeDetailed => 0.14,
      AppSettings.summaryModeBalanced => 0.11,
      _ => 0.08,
    };
    final summaryEstimate = _boundedEstimate(
      audio,
      summaryRatio,
      minSeconds: 15,
      maxSeconds: 60 * 18,
    );

    Duration totalFor(bool withDiarization) =>
        finalSttEstimate +
        (withDiarization ? diarizationEstimate : Duration.zero) +
        summaryEstimate;

    final result = await showMacosAlertDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => MacosAlertDialog(
          appIcon: const Icon(Icons.timer_outlined, size: 48),
          title: Text(tr('예상 처리 시간', 'Estimated processing time')),
          message: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('회의 길이 ${_formatDurationKr(audio)} 기준의 대략적인 예상입니다. 기기 성능과 모델에 따라 달라질 수 있습니다.', 'A rough estimate based on a ${_formatDurationKr(audio)} meeting. Actual time varies by device and model.'),
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),
                if (finalSttEstimate > Duration.zero)
                  _EstimateRow(
                    label: tr('정확 음성 인식', 'Accurate recognition'),
                    value: _formatDurationKr(finalSttEstimate),
                  ),
                if (useDiarization)
                  _EstimateRow(
                    label: tr('발화자 라벨', 'Speaker labels'),
                    value: _formatDurationKr(diarizationEstimate),
                  ),
                _EstimateRow(
                  label: tr('요약 생성', 'Summary generation'),
                  value: _formatDurationKr(summaryEstimate),
                ),
                const Divider(height: 22),
                _EstimateRow(
                  label: tr('총 예상', 'Total estimate'),
                  value: tr('약 ${_formatDurationKr(totalFor(useDiarization))}', 'about ${_formatDurationKr(totalFor(useDiarization))}'),
                  emphasis: true,
                ),
                const SizedBox(height: 12),
                _PrepToggleRow(
                  value: useDiarization,
                  title: tr('발화자 라벨 사용', 'Use speaker labels'),
                  subtitle: tr('끄면 더 빠르게 요약하지만, 발화 흐름 정보는 줄어듭니다.', 'Turning this off summarizes faster but reduces speaking-flow detail.'),
                  onChanged: (v) {
                    setLocalState(() => useDiarization = v);
                  },
                ),
              ],
            ),
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () async {
              await AppSettings.instance.setDiarizationEnabled(useDiarization);
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: Text(tr('시작', 'Start')),
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('취소', 'Cancel')),
          ),
        ),
      ),
    );

    return result ?? false;
  }

  // ── LLM 요약 + Isar 저장 ──────────────────────────────────────
  Future<void> _runSummary() async {
    // 재진입 방지 — 요약 준비 다이얼로그가 떠 있는 동안 ⌘⇧S 재입력 등으로
    // 두 번째 _runSummary가 겹치면 다이얼로그 중복·이중 요약이 발생한다.
    if (_summaryFlowActive) return;
    _summaryFlowActive = true;
    try {
      await _runSummaryInner();
    } finally {
      _summaryFlowActive = false;
    }
  }

  bool _summaryFlowActive = false;

  Future<void> _runSummaryInner() async {
    if (_segments.isEmpty) {
      if (_looksLikeEmptyRecording()) {
        _recordQualityIfNeeded(context: 'summaryBlockedEmptyRecording');
        final action = await _showLowQualityRecordingDialog(
          allowSummarize: false,
        );
        if (action == _EmptyRecordingAction.delete) {
          await _discardEmptyRecordingDraft();
        } else if (mounted) {
          setState(() {
            _statusMsg = tr('변환된 내용이 없습니다. 마이크 상태를 확인한 뒤 다시 녹음해 주세요.', 'No transcribed content. Check the microphone and record again.');
          });
        }
      } else {
        setState(() {
          _statusMsg = tr('변환된 내용이 없습니다. 먼저 녹음해 주세요.', 'No transcribed content. Please record first.');
        });
      }
      return;
    }
    if (_phase != _RecordingPhase.summarizing &&
        _nativeTaskBlockReason(tr('요약', 'summary')) != null) {
      _showNativeTaskBlocked(tr('요약', 'summary'));
      return;
    }

    if (!_lowQualitySummaryConfirmed && _looksLikeLowQualityRecording()) {
      _recordQualityIfNeeded(context: 'summaryLowQualityPrompt');
      final action = await _showLowQualityRecordingDialog(allowSummarize: true);
      if (action == _EmptyRecordingAction.delete) {
        await _discardEmptyRecordingDraft();
        return;
      }
      if (action != _EmptyRecordingAction.summarize) {
        if (mounted) {
          setState(() {
            _statusMsg = tr('요약하지 않고 보관했습니다. 필요하면 다시 요약할 수 있습니다.', 'Kept without summarizing. You can summarize later if needed.');
          });
        }
        return;
      }
      _lowQualitySummaryConfirmed = true;
    }

    // LLM 선택 (설치된 모델이 2개 이상이면 다이얼로그)
    final llmId = await _pickLlmDialog();
    if (llmId == null) return;
    await AppSettings.instance.setSelectedLlmModel(llmId);

    final confirmed = await _confirmSummaryEstimate();
    if (!mounted || !confirmed) return;

    setState(() {
      _phase = _RecordingPhase.summarizing;
      _cancelSummaryRequested = false;
      _statusMsg = tr('전사 저장 중', 'Saving transcript');
      _summaryProgress = 0.0;
      _summaryStartTime = DateTime.now();
      _lastFinalSttElapsedMs = 0;
      _lastFinalSttAudioMs = 0;
      _lastFinalSttModel = '';
      _lastDiarizationElapsedMs = 0;
      _lastDiarizationStatus = AppSettings.instance.diarizationEnabled
          ? 'skipped'
          : 'disabled';
    });
    _startSummaryTicker();
    globalProviderContainer.read(isSummarizingProvider.notifier).state = true;

    if (_failedSummaryMeetingId == null) {
      await _refreshFinalTranscriptIfNeeded();
    }
    if (_cancelSummaryRequested) {
      globalProviderContainer.read(isSummarizingProvider.notifier).state = false;
      _summaryTicker?.cancel();
      if (mounted) {
        final totalStr = _formatDurationKr(_currentSummaryElapsed());
        setState(() {
          _phase = _RecordingPhase.stopped;
          _statusMsg = tr('요약 중지됨 · 총 소요 $totalStr', 'Summary stopped · total $totalStr');
          _cancelSummaryRequested = false;
        });
      }
      return;
    }

    // 발화자 라벨(옵션) — 최종 전사본에 A/B/C 라벨을 붙여 발화 흐름 파악을 돕는다.
    // 실패해도 치명 오류로 취급하지 않고 라벨 없이 계속 진행한다.
    await _runDiarizationIfEnabled();
    if (_cancelSummaryRequested) {
      globalProviderContainer.read(isSummarizingProvider.notifier).state = false;
      _summaryTicker?.cancel();
      if (mounted) {
        final totalStr = _formatDurationKr(_currentSummaryElapsed());
        setState(() {
          _phase = _RecordingPhase.stopped;
          _statusMsg = tr('요약 중지됨 · 총 소요 $totalStr', 'Summary stopped · total $totalStr');
          _cancelSummaryRequested = false;
        });
      }
      return;
    }

    // ── 1단계: 전사/회의 레코드를 먼저 저장 (LLM 실패해도 소실 방지) ──
    // 재시도 경로에서는 기존 meetingId를 재사용한다.
    final int meetingId;
    final DateTime recStart;
    final DateTime now = DateTime.now();
    try {
      if (_failedSummaryMeetingId != null) {
        meetingId = _failedSummaryMeetingId!;
        recStart = _recordingStartedAt ?? now;
      } else {
        final persisted = await _persistMeetingAndTranscripts(now);
        meetingId = persisted.meetingId;
        recStart = persisted.recStart;
      }
    } catch (e, st) {
      CrashLogService.instance.recordCaught(
        e,
        st,
        context: 'persistMeetingAndTranscripts',
      );
      globalProviderContainer.read(isSummarizingProvider.notifier).state = false;
      final totalStr = _formatDurationKr(_currentSummaryElapsed());
      _summaryTicker?.cancel();
      final friendly = friendlyErrorText(
        e,
        fallbackTitle: tr('전사 저장에 실패했습니다', 'Failed to save transcript'),
        fallbackMessage: tr('회의 텍스트를 저장하지 못했습니다.', 'Could not save the meeting text.'),
        nextStep: tr('저장 폴더와 디스크 여유 공간을 확인한 뒤 다시 시도해주세요.', 'Check the save folder and free disk space, then try again.'),
      );
      if (mounted) {
        setState(() {
          _phase = _RecordingPhase.error;
          _statusMsg = tr('전사 저장 실패 · 총 소요 $totalStr\n$friendly', 'Transcript save failed · total $totalStr\n$friendly');
        });
      }
      return;
    }

    // ── 2단계: LLM 요약 ─────────────────────────────────────
    try {
      setState(() => _statusMsg = tr('요약 모델 준비 중', 'Preparing summary model'));
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
      if (mounted) setState(() => _statusMsg = tr('회의 요약 생성 중', 'Generating meeting summary'));

      final dateStr =
          '${recStart.year}-'
          '${recStart.month.toString().padLeft(2, '0')}-'
          '${recStart.day.toString().padLeft(2, '0')}';
      final transcriptTextRaw = _segments
          .asMap()
          .entries
          .map((e) {
            final i = e.key;
            final s = e.value;
            final label =
                (i < _pendingSpeakerLabels.length &&
                    _pendingSpeakerLabels[i] != null)
                ? '화자 ${_pendingSpeakerLabels[i]}: '
                : '';
            return '[${s.timestampStr}] $label${s.text}';
          })
          .join('\n');
      final transcriptText = TranscriptTextCleaner.cleanForSummary(
        transcriptTextRaw,
      );
      final notesText = _notesCtrl.text.trim();

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
        notes: notesText,
        participants: List.unmodifiable(_participants),
        glossary: glossarySection,
        instruction: SummaryTemplates.resolveInstruction(
          overrideId: _summaryTemplateId,
        ),
        agenda: _meetingAgenda,
        bookmarks: List.unmodifiable(_bookmarks),
        maxTokens: 2500,
        speedMode: AppSettings.instance.summarySpeedMode,
        isCancelled: () => _cancelSummaryRequested,
        onProgress: (phase, progress) {
          if (mounted && !_cancelSummaryRequested) {
            setState(() {
              _statusMsg = phase;
              _summaryProgress = progress;
            });
          }
        },
      );
      summarySw.stop();

      if (_cancelSummaryRequested) {
        await OnDeviceModelManager.instance.unloadLlm().catchError((_) {});
        throw const SummaryCancelledException();
      }

      debugPrint('=== LLM output received (${rawOutput.length} chars) ===');

      final summary = _parseJsonForMic(
        rawOutput,
        meetingId,
        recStart,
        participants: List.unmodifiable(_participants),
      );
      final summaryRepo = SummaryRepositoryImpl(IsarService.instance.db);
      // 재시도 시 기존 Summary가 있으면 덮어쓰도록 먼저 정리
      await summaryRepo.deleteSummaryByMeetingId(meetingId);
      await summaryRepo.saveSummary(summary);
      await _updateProcessingReport(
        meetingId: meetingId,
        llmId: llmId,
        summaryElapsedMs: summarySw.elapsedMilliseconds,
      );

      // ── 태그 자동 추출 (빠른 요약에서는 추가 LLM 호출 생략) ─────
      if (AppSettings.instance.summarySpeedMode !=
          AppSettings.summaryModeFast) {
        try {
          if (mounted) setState(() => _statusMsg = tr('태그 정리 중', 'Organizing tags'));
          final tags = await TagExtractor.extractFromSummary(
            summary,
            notes: notesText,
            agenda: _meetingAgenda,
          );
          if (tags.isNotEmpty) {
            final mRepo = MeetingRepositoryImpl(IsarService.instance.db);
            final m = await mRepo.getMeetingById(meetingId);
            if (m != null) {
              m.tags = TagExtractor.mergeTags(m.tags, tags);
              await mRepo.updateMeeting(m);
            }
          }
        } catch (e) {
          debugPrint('[TagExtractor] auto-extract failed: $e');
        }
      }

      await OnDeviceModelManager.instance.unloadLlm();

      // 전역 플래그 정리는 화면 이탈(dispose) 여부와 무관하게 반드시 실행 —
      // mounted 가드 안에 두면 요약 중 화면을 떠났을 때 isSummarizing이
      // true로 고착돼 새 녹음·파일 불러오기가 영구히 잠긴다.
      _summaryTicker?.cancel();
      globalProviderContainer.read(isSummarizingProvider.notifier).state =
          false;
      globalProviderContainer.read(nativeRecordingActiveProvider.notifier)
          .state = false;
      globalProviderContainer.invalidate(meetingsProvider);

      if (mounted) {
        final totalStr = _formatDurationKr(_currentSummaryElapsed());
        setState(() {
          _phase = _RecordingPhase.done;
          _statusMsg = tr('저장 완료 · 총 소요 $totalStr · meetingId: $meetingId', 'Saved · total $totalStr · meetingId: $meetingId');
          _failedSummaryMeetingId = null;
          _cancelSummaryRequested = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('요약 완료 · 총 소요 $totalStr', 'Summary complete · total $totalStr')),
            backgroundColor: Colors.green.shade700,
          ),
        );

        // MeetingDetailView로 이동 (화면에 있을 때만 의미 있는 동작)
        ref.read(selectedMeetingIdProvider.notifier).state = meetingId;
        ref.read(isRecordingActiveProvider.notifier).state = false;
      }
    } catch (e, st) {
      await OnDeviceModelManager.instance.unloadLlm().catchError((_) {});
      CrashLogService.instance.recordCaught(e, st, context: 'runSummary');
      globalProviderContainer.read(isSummarizingProvider.notifier).state = false;
      final totalStr = _formatDurationKr(_currentSummaryElapsed());
      _summaryTicker?.cancel();
      final friendly = friendlyErrorText(
        e,
        fallbackTitle: tr('요약을 만들지 못했습니다', 'Could not create summary'),
        fallbackMessage: tr('AI 요약 생성 중 문제가 발생했습니다.', 'A problem occurred while generating the AI summary.'),
        nextStep: tr('전사는 이미 저장되었습니다. 다시 요약하거나 회의록을 열어 내용을 확인할 수 있습니다.', 'The transcript is already saved. You can re-run the summary or open the meeting to review it.'),
      );
      if (mounted) {
        setState(() {
          _phase = e is SummaryCancelledException
              ? _RecordingPhase.stopped
              : _RecordingPhase.error;
          _statusMsg = e is SummaryCancelledException
              ? tr('요약 중지됨 · 총 소요 $totalStr\n전사는 이미 저장되었습니다. 다시 요약할 수 있습니다.', 'Summary stopped · total $totalStr\nThe transcript is already saved. You can summarize again.')
              : tr('요약 오류 · 총 소요 $totalStr\n$friendly', 'Summary error · total $totalStr\n$friendly');
          _failedSummaryMeetingId = meetingId;
          _cancelSummaryRequested = false;
        });
      }
    }
  }

  Future<void> _refreshFinalTranscriptIfNeeded() async {
    if (!_shouldRunFinalAccuratePass) return;
    if (_cancelSummaryRequested) return;
    if (_transcriptManuallyEdited) {
      _shouldRunFinalAccuratePass = false;
      return;
    }

    final audioPath =
        MicrophoneService.instance.savedAudioPath ?? _audioSavePath;
    if (audioPath == null || !await File(audioPath).exists()) {
      _shouldRunFinalAccuratePass = false;
      return;
    }

    final appSupport = await getApplicationSupportDirectory();
    final accuratePath =
        '${appSupport.path}/models/${AppConstants.sttModelFileAccurate}';
    if (!await File(accuratePath).exists()) {
      _shouldRunFinalAccuratePass = false;
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _statusMsg = tr('정확 전사 준비 중', 'Preparing accurate transcription');
          _summaryProgress = 0.0;
        });
      }
      await OnDeviceModelManager.instance.unloadStt().catchError((_) {});
      if (_cancelSummaryRequested) return;
      await OnDeviceModelManager.instance.loadStt(accuratePath);

      final sttSw = Stopwatch()..start();
      final finalSegments = await SttService.instance.transcribeFile(
        audioPath,
        isCancelled: () => _cancelSummaryRequested,
        onProgress: (processedMs, totalMs) {
          if (!mounted || totalMs <= 0 || _cancelSummaryRequested) return;
          final progress = (processedMs / totalMs).clamp(0.0, 1.0);
          setState(() {
            _statusMsg = tr('정확 전사 중 ${(progress * 100).toStringAsFixed(0)}%', 'Accurate transcription ${(progress * 100).toStringAsFixed(0)}%');
            _summaryProgress = progress * 0.25;
          });
        },
      );
      sttSw.stop();
      _lastFinalSttElapsedMs = sttSw.elapsedMilliseconds;
      _lastFinalSttAudioMs =
          _recordingEndedAt != null && _recordingStartedAt != null
          ? _recordingEndedAt!.difference(_recordingStartedAt!).inMilliseconds
          : finalSegments.isEmpty
          ? 0
          : finalSegments.last.endMs;
      _lastFinalSttModel = AppConstants.sttModelFileAccurate;

      await OnDeviceModelManager.instance.unloadStt();
      if (_cancelSummaryRequested) return;

      if (finalSegments.isNotEmpty && mounted) {
        setState(() {
          _segments
            ..clear()
            ..addAll(finalSegments);
          _statusMsg = tr('정확 전사 완료. 전사 저장 중', 'Accurate transcription complete. Saving transcript');
          _summaryProgress = 0.25;
        });
      }
    } catch (e, st) {
      await OnDeviceModelManager.instance.unloadStt().catchError((_) {});
      CrashLogService.instance.recordCaught(
        e,
        st,
        context: 'refreshFinalTranscript',
      );
      final friendly = friendlyErrorMessage(
        e,
        fallbackTitle: tr('정확 전사에 실패했습니다', 'Accurate transcription failed'),
        fallbackMessage: tr('정확도 높은 음성 인식을 완료하지 못했습니다.', 'Could not complete high-accuracy speech recognition.'),
        nextStep: tr('실시간 전사본으로 요약을 계속합니다.', 'Continuing the summary with the live transcript.'),
      );
      if (mounted) {
        setState(() {
          _statusMsg = tr('정확 전사 실패 — 실시간 전사본으로 요약을 계속합니다.', 'Accurate transcription failed — continuing the summary with the live transcript.');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendly.fullText),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      _shouldRunFinalAccuratePass = false;
    }
  }

  Future<void> _runDiarizationIfEnabled() async {
    if (!AppSettings.instance.diarizationEnabled) return;

    final audioPath =
        MicrophoneService.instance.savedAudioPath ?? _audioSavePath;
    if (audioPath == null) return;
    if (!await File(audioPath).exists()) return;

    // diarization 모델이 없으면 조용히 스킵
    if (!await DiarizationService.instance.modelsReady()) return;
    if (_segments.isEmpty) return;

    try {
      final diarSw = Stopwatch()..start();
      if (mounted) {
        setState(() {
          _statusMsg = tr('발화자 라벨 분석 중', 'Analyzing speaker labels');
          _summaryProgress = _summaryProgress < 0.27 ? 0.27 : _summaryProgress;
        });
      }

      final diar = await DiarizationService.instance.diarizeWav(
        audioPath,
        numSpeakersHint:
            _meetingSpeakerCount ?? AppSettings.instance.numSpeakersHint,
        onProgress: (percent) {
          if (!mounted || _cancelSummaryRequested) return;
          final clamped = percent.clamp(0, 100).toDouble();
          final completed = clamped >= 99.5;
          setState(() {
            _statusMsg = completed
                ? tr('발화자 라벨 분석 완료. 요약을 준비하고 있습니다.', 'Speaker label analysis complete. Preparing the summary.')
                : tr('발화자 라벨 분석 중', 'Analyzing speaker labels');
            _summaryProgress = completed
                ? 0.3
                : (_summaryProgress < 0.27 ? 0.27 : _summaryProgress);
          });
        },
      );
      diarSw.stop();
      _lastDiarizationElapsedMs = diarSw.elapsedMilliseconds;
      _lastDiarizationStatus = 'success';
      if (_cancelSummaryRequested) return;

      final labels = DiarizationService.assignLabels(
        sttStartMs: _segments.map((s) => s.startMs).toList(),
        sttEndMs: _segments.map((s) => s.endMs).toList(),
        diar: diar,
      );

      // UI/DB 저장을 위해 보관
      _pendingSpeakerLabels = labels;
    } catch (e) {
      _pendingSpeakerLabels = const [];
      _lastDiarizationStatus = 'failed';
      CrashLogService.instance.recordCaught(
        e,
        StackTrace.current,
        context: 'runDiarizationBeforeSummary',
      );
      if (mounted) {
        setState(() {
          _statusMsg = tr('발화자 구분에 실패했습니다. 라벨 없이 요약을 계속합니다.', 'Speaker separation failed. Continuing the summary without labels.');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyDiarizationFailureMessage(nextStep: tr('회의 요약은 계속 진행합니다.', 'The meeting summary will continue.')),
            ),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  /// Meeting + Transcript 레코드를 DB에 저장 (요약 전 단계).
  /// 요약 단계가 실패해도 전사/녹음이 보존되도록 분리.
  ///
  /// 크래시 복구용으로 _recoveryMeetingId가 이미 있으면 새로 만들지 않고
  /// 그 레코드를 갱신한다 (status=done, endedAt, audioFilePath 등).
  Future<_PersistedMeeting> _persistMeetingAndTranscripts(DateTime now) async {
    final db = IsarService.instance.db;
    final meetingRepo = MeetingRepositoryImpl(db);
    final transcriptRepo = TranscriptRepositoryImpl(db);
    final summaryRepo = SummaryRepositoryImpl(db);

    final fullText = _segments.map((s) => s.text).join(' ');
    final recStart = _recordingStartedAt ?? now;
    final recEnd = _recordingEndedAt ?? now;
    final preview = fullText.length > 200
        ? fullText.substring(0, 200)
        : fullText;
    final quality = _recordingQualityStatus();
    final qualityReport = MeetingProcessingReport.fromJsonString('')
        .copyWith(
          inputQualityStatus: quality.$1,
          inputQualityReason: quality.$2,
          inputRecognizedChars: _recognizedCharCount(),
          inputSegmentCount: _segments.length,
          inputMaxLevel: _maxInputLevelDuringRecording,
        )
        .toJsonString();
    _recordQualityIfNeeded(context: 'persistMeetingInputQuality');

    int meetingId;
    Meeting meeting;

    if (_recoveryMeetingId != null) {
      // 체크포인트로 이미 저장된 레코드 — 갱신
      final existing = await meetingRepo.getMeetingById(_recoveryMeetingId!);
      if (existing != null) {
        existing
          ..title = _fullTitle
          ..endedAt = recEnd
          ..status = MeetingStatus.done
          ..audioFilePath = MicrophoneService.instance.savedAudioPath
          ..notes = _notesCtrl.text.trim()
          ..summaryTemplateId = _summaryTemplateId
          ..agenda = _meetingAgenda
          ..bookmarksJson = _bookmarksToJson()
          ..transcriptPreview = preview
          ..processingReportJson = qualityReport;
        await meetingRepo.updateMeeting(existing);
        meetingId = existing.id;
        meeting = existing;
      } else {
        // 사용자가 사이드바에서 삭제했거나 누락된 경우 — 새로 만듦
        meeting = Meeting()
          ..title = _fullTitle
          ..createdAt = recStart
          ..status = MeetingStatus.done
          ..endedAt = recEnd
          ..audioFilePath = MicrophoneService.instance.savedAudioPath
          ..notes = _notesCtrl.text.trim()
          ..summaryTemplateId = _summaryTemplateId
          ..agenda = _meetingAgenda
          ..bookmarksJson = _bookmarksToJson()
          ..transcriptPreview = preview
          ..processingReportJson = qualityReport;
        meetingId = await meetingRepo.saveMeeting(meeting);
      }
    } else {
      meeting = Meeting()
        ..title = _fullTitle
        ..createdAt = recStart
        ..status = MeetingStatus.done
        ..endedAt = recEnd
        ..audioFilePath = MicrophoneService.instance.savedAudioPath
        ..notes = _notesCtrl.text.trim()
        ..summaryTemplateId = _summaryTemplateId
        ..agenda = _meetingAgenda
        ..bookmarksJson = _bookmarksToJson()
        ..transcriptPreview = preview
        ..processingReportJson = qualityReport;
      meetingId = await meetingRepo.saveMeeting(meeting);
    }

    // autoincrement collision (schema migration 직후 발생 가능) 방어
    final existingSummary = await summaryRepo.getSummaryByMeetingId(meetingId);
    if (existingSummary != null) {
      debugPrint(
        '[Persist] autoincrement collision meetingId=$meetingId, re-saving',
      );
      await meetingRepo.deleteMeeting(meetingId);
      meeting.id = Isar.autoIncrement;
      meetingId = await meetingRepo.saveMeeting(meeting);
    }

    // 기존 transcripts 일괄 삭제 후 재저장 (체크포인트가 남긴 부분 segments 정리)
    await transcriptRepo.deleteByMeetingId(meetingId);
    for (int i = 0; i < _segments.length; i++) {
      final seg = _segments[i];
      final t = Transcript()
        ..meetingId = meetingId
        ..segmentIndex = i
        ..text = seg.text
        ..startTimeSeconds = seg.startMs / 1000.0
        ..endTimeSeconds = seg.endMs / 1000.0
        ..speakerLabel = (i < _pendingSpeakerLabels.length)
            ? _pendingSpeakerLabels[i]
            : null
        ..createdAt = now;
      await transcriptRepo.saveSegment(t);
    }

    // 복구 ID 정리 — 정상 흐름 종료 (세션 static도 함께 무효화:
    // 남겨두면 다음 세션의 재마운트가 이 완료된 회의를 물려받아 파괴한다)
    _recoveryMeetingId = null;
    _sessionRecoveryMeetingId = null;
    _sessionRecoveryStartTime = null;

    // ── macOS Calendar.app에 자동 이벤트 등록 (설정 ON일 때) ───────
    if (AppSettings.instance.autoAddToCalendar) {
      // UI 블록 안 되도록 fire-and-forget. 결과는 SnackBar로 알림.
      unawaited(
        _addCurrentMeetingToCalendar(
          title: _fullTitle,
          start: recStart,
          end: recEnd,
          notes: _notesCtrl.text.trim(),
          agenda: _meetingAgenda,
        ),
      );
    }

    return _PersistedMeeting(meetingId: meetingId, recStart: recStart);
  }

  /// 녹음한 회의를 캘린더에 등록 — 비동기, 실패해도 녹음 흐름엔 영향 없음.
  Future<void> _addCurrentMeetingToCalendar({
    required String title,
    required DateTime start,
    required DateTime end,
    required String notes,
    required String agenda,
  }) async {
    final descLines = <String>[];
    if (agenda.trim().isNotEmpty) descLines.add(tr('어젠다:\n$agenda', 'Agenda:\n$agenda'));
    if (notes.trim().isNotEmpty) descLines.add(tr('메모:\n$notes', 'Notes:\n$notes'));
    descLines.add(tr('— Local Minutes에서 자동 등록', '— Added automatically by Local Minutes'));
    final description = descLines.join('\n\n');

    final err = await CalendarService.instance.addEventToCalendar(
      title: title,
      start: start,
      end: end,
      description: description,
    );
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(tr('macOS 캘린더에 회의가 등록되었습니다', 'The meeting was added to the macOS Calendar')),
          backgroundColor: Colors.indigo.shade600,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(tr('캘린더 등록 실패 · $err', 'Calendar registration failed · $err')),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
  }

  Future<void> _updateProcessingReport({
    required int meetingId,
    required String llmId,
    required int summaryElapsedMs,
  }) async {
    final repo = MeetingRepositoryImpl(IsarService.instance.db);
    final meeting = await repo.getMeetingById(meetingId);
    if (meeting == null) return;

    final audioMs = _lastFinalSttAudioMs > 0
        ? _lastFinalSttAudioMs
        : meeting.durationSeconds * 1000;
    final report =
        MeetingProcessingReport.fromJsonString(
          meeting.processingReportJson,
        ).copyWith(
          sttModel: _lastFinalSttModel,
          sttLanguage: AppSettings.instance.sttLanguage,
          sttElapsedMs: _lastFinalSttElapsedMs,
          sttAudioMs: audioMs,
          sttRtf: audioMs <= 0 ? 0 : _lastFinalSttElapsedMs / audioMs,
          sttProcessingMode: AppSettings.instance.sttProcessingMode,
          diarizationEnabled: AppSettings.instance.diarizationEnabled,
          diarizationStatus: _lastDiarizationStatus,
          diarizationElapsedMs: _lastDiarizationElapsedMs,
          llmModel: llmId,
          summaryElapsedMs: summaryElapsedMs,
        );
    meeting.processingReportJson = report.toJsonString();
    await repo.updateMeeting(meeting);
    ref.invalidate(meetingsProvider);
  }

  /// 요약 실패 후 사용자가 "회의록 열기"를 눌렀을 때 호출.
  /// 저장된 meetingId로 이동하여 detail view에서 재요약/편집 가능.
  void _openFailedMeeting() {
    final id = _failedSummaryMeetingId;
    if (id == null) return;
    ref.invalidate(meetingsProvider);
    ref.read(selectedMeetingIdProvider.notifier).state = id;
    ref.read(isRecordingActiveProvider.notifier).state = false;
    ref.read(nativeRecordingActiveProvider.notifier).state = false;
    setState(() {
      _failedSummaryMeetingId = null;
    });
  }

  // ── 버튼 빌더 ─────────────────────────────────────────────────

  /// 녹음 단계별 제어 버튼 Row
  ///
  /// • idle/error          → [🔴 녹음 시작]
  /// • loadingModel        → [로드 중... (비활성)]
  /// • recording           → [⏸ 일시 정지  mm:ss] [■ 녹음 중지]
  /// • paused              → [▶ 계속하기] [■ 녹음 중지]
  /// • processing          → [처리 중... (비활성)]
  /// • stopped / done      → [녹음 시작] [✨ 요약]
  Widget _buildControlButtons(bool isRecording, bool isPaused, bool isBusy) {
    final scheme = Theme.of(context).colorScheme;

    // ── 녹음 중 ────────────────────────────────────────────────
    if (isRecording) {
      return Row(
        children: [
          // ⏸ 일시 정지
          Expanded(
            child: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: _pauseRecording,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pause, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      tr('일시 정지  ${_elapsedStr()}', 'Pause  ${_elapsedStr()}'),
                      style: TextStyle(color: Colors.orange.shade700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ⭐ 북마크 (현재 시점 마킹) — Cmd+B 단축키와 연동
          MacosTooltip(
            message: tr('핵심 순간 북마크 (⌘B)\n현재 시점을 표시해 요약에서 우선 처리합니다', 'Bookmark key moment (⌘B)\nMarks this point to prioritize it in the summary'),
            child: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => _addBookmark(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bookmark_add_rounded,
                      size: 18,
                      color: Colors.amber.shade800,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr('북마크 ${_bookmarks.isEmpty ? "" : "${_bookmarks.length}"}', 'Bookmark ${_bookmarks.isEmpty ? "" : "${_bookmarks.length}"}'),
                      style: TextStyle(color: Colors.amber.shade800),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ■ 녹음 중지
          Expanded(
            child: PushButton(
              controlSize: ControlSize.large,
              color: MacosColors.systemRedColor,
              onPressed: _stopRecording,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stop, size: 18, color: MacosColors.white),
                    const SizedBox(width: 6),
                    Text(
                      tr('녹음 중지', 'Stop'),
                      style: const TextStyle(color: MacosColors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ── 일시 정지 중 ────────────────────────────────────────────
    if (isPaused) {
      return Row(
        children: [
          // ▶ 계속하기
          Expanded(
            child: PushButton(
              controlSize: ControlSize.large,
              color: MacosColors.systemGreenColor,
              onPressed: _resumeRecording,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 18, color: MacosColors.white),
                    const SizedBox(width: 6),
                    Text(tr('계속하기', 'Resume'), style: const TextStyle(color: MacosColors.white)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ■ 녹음 중지 (정지 상태에서 최종 종료)
          Expanded(
            child: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: _stopRecording,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stop, size: 18, color: Colors.red.shade600),
                    const SizedBox(width: 6),
                    Text(tr('녹음 중지', 'Stop'), style: TextStyle(color: Colors.red.shade600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_phase == _RecordingPhase.checkingModels ||
        _phase == _RecordingPhase.loadingModel ||
        _phase == _RecordingPhase.processing) {
      final label = switch (_phase) {
        _RecordingPhase.checkingModels => tr('모델 확인 중...', 'Checking models...'),
        _RecordingPhase.loadingModel => tr('모델 로드 중', 'Loading model'),
        _RecordingPhase.processing => tr('처리 중', 'Processing'),
        _ => tr('처리 중', 'Processing'),
      };
      return Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MacosColors.white,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MacosColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // ── 완료 후: 녹음 시작 + 요약 ──────────────────────────────
    final showSummaryBtn =
        _phase == _RecordingPhase.stopped || _phase == _RecordingPhase.done;

    final isSummarizing = _phase == _RecordingPhase.summarizing;

    // 녹음 시작 가능한 단계: idle, error, stopped, done (요약 중엔 불가)
    final canStartRecording =
        !isBusy &&
        !isSummarizing &&
        (_phase == _RecordingPhase.idle ||
            _phase == _RecordingPhase.error ||
            _phase == _RecordingPhase.stopped ||
            _phase == _RecordingPhase.done);

    // 세그먼트가 있고 요약 전이면 확인 다이얼로그 표시
    Future<void> onStartPressed() async {
      if (_segments.isNotEmpty && _phase == _RecordingPhase.stopped) {
        final confirmed = await showMacosAlertDialog<bool>(
          context: context,
          builder: (ctx) => MacosAlertDialog(
            appIcon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 48,
            ),
            title: Text(tr('녹음 내용이 삭제됩니다', 'The recording will be deleted')),
            message: Text(
              tr(
                '아직 요약을 실행하지 않았습니다.\n'
                    '새 녹음을 시작하면 현재 녹취 내용이 모두 삭제됩니다.\n\n'
                    '계속하시겠습니까?',
                'You haven\'t run a summary yet.\n'
                    'Starting a new recording will delete all current transcript content.\n\n'
                    'Do you want to continue?',
              ),
              textAlign: TextAlign.center,
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              color: MacosColors.systemRedColor,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                tr('삭제하고 새 녹음', 'Delete & record anew'),
                style: const TextStyle(color: MacosColors.white),
              ),
            ),
            secondaryButton: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('취소', 'Cancel')),
            ),
          ),
        );
        if (confirmed != true) return;
      }
      _startRecording();
    }

    // 요약 실패 복구 row (전사는 이미 저장됨)
    final hasRecoverable =
        _phase == _RecordingPhase.error && _failedSummaryMeetingId != null;

    return StreamBuilder<NativeModelTaskSnapshot>(
      stream: OnDeviceModelManager.instance.nativeTaskStream,
      initialData: OnDeviceModelManager.instance.nativeTaskSnapshot,
      builder: (context, snapshot) {
        final nativeActive = snapshot.data?.activeLabel;
        final recordingBlock = nativeActive == null
            ? null
            : tr('현재 $nativeActive 작업 중입니다. 완료 후 녹음을 시작해주세요.', '$nativeActive is currently running. Please start recording once it finishes.');
        final summaryBlock = nativeActive == null
            ? null
            : tr('현재 $nativeActive 작업 중입니다. 완료 후 요약을 다시 시도해주세요.', '$nativeActive is currently running. Please try the summary again once it finishes.');
        final canStartNow = canStartRecording && recordingBlock == null;
        final canSummaryNow =
            _phase != _RecordingPhase.summarizing &&
            _segments.isNotEmpty &&
            summaryBlock == null;

        return Column(
          children: [
            if (hasRecoverable) ...[
              Row(
                children: [
                  Expanded(
                    child: _withDisabledReason(
                      summaryBlock,
                      PushButton(
                        controlSize: ControlSize.large,
                        color: scheme.primary,
                        onPressed: summaryBlock == null ? _runSummary : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.refresh,
                                size: 18,
                                color: MacosColors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tr('요약 다시 시도', 'Retry summary'),
                                style: const TextStyle(color: MacosColors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PushButton(
                      controlSize: ControlSize.large,
                      secondary: true,
                      onPressed: _openFailedMeeting,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder_open, size: 18),
                            const SizedBox(width: 6),
                            Text(tr('회의록 열기', 'Open meeting')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: _withDisabledReason(
                    canStartRecording ? recordingBlock : null,
                    PushButton(
                      controlSize: ControlSize.large,
                      onPressed: canStartNow ? onStartPressed : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            (isBusy || isSummarizing)
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: MacosColors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.fiber_manual_record,
                                    size: 18,
                                    color: MacosColors.white,
                                  ),
                            const SizedBox(width: 6),
                            Text(
                              isSummarizing
                                  ? tr('요약 중', 'Summarizing')
                                  : _phase == _RecordingPhase.loadingModel
                                  ? tr('모델 로드 중', 'Loading model')
                                  : _phase == _RecordingPhase.processing
                                  ? tr('처리 중', 'Processing')
                                  : (showSummaryBtn ? tr('새 녹음 시작', 'New recording') : tr('녹음 시작', 'Start recording')),
                              style: const TextStyle(color: MacosColors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (showSummaryBtn) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _withDisabledReason(
                      _segments.isEmpty ? null : summaryBlock,
                      PushButton(
                        controlSize: ControlSize.large,
                        color: _segments.isEmpty ? Colors.grey : scheme.primary,
                        onPressed: canSummaryNow ? _runSummary : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _phase == _RecordingPhase.summarizing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: MacosColors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.auto_awesome,
                                      size: 18,
                                      color: MacosColors.white,
                                    ),
                              const SizedBox(width: 6),
                              Text(
                                _phase == _RecordingPhase.summarizing
                                    ? tr('요약 중', 'Summarizing')
                                    : tr('${_llmDisplayName(AppSettings.instance.selectedLlmModel)} 요약', '${_llmDisplayName(AppSettings.instance.selectedLlmModel)} summary'),
                                style: const TextStyle(
                                  color: MacosColors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  // ── 요약 진행 카드 ───────────────────────────────────────────
  String _summaryProcessingTitle() {
    if (_statusMatch(_statusMsg, const ['전사', 'transcri'])) {
      return tr('정확한 전사본을 준비하고 있습니다', 'Preparing an accurate transcript');
    }
    if (_statusMatch(_statusMsg, const ['발화자', 'speaker'])) {
      return tr('발화자를 구분하고 있습니다', 'Identifying speakers');
    }
    if (_statusMatch(_statusMsg, const ['로드', '준비', 'load', 'prepar'])) {
      return tr('요약 모델을 준비하고 있습니다', 'Preparing the summary model');
    }
    return tr('${_llmDisplayName(AppSettings.instance.selectedLlmModel)}가 회의 내용을 분석하고 있습니다', '${_llmDisplayName(AppSettings.instance.selectedLlmModel)} is analyzing the meeting');
  }

  String _summaryProcessingDescription() {
    if (_statusMatch(_statusMsg, const ['발화자', 'speaker'])) {
      return tr('말한 구간을 분석 중입니다.\n긴 녹음은 시간이 더 걸릴 수 있습니다.', 'Analyzing spoken segments.\nLonger recordings may take more time.');
    }
    if (_statusMatch(_statusMsg, const ['전사', 'transcri'])) {
      return tr('전사본을 정리하고 있습니다.\n잠시만 기다려 주세요.', 'Organizing the transcript.\nPlease wait a moment.');
    }
    return tr('요약과 액션아이템을 정리하고 있습니다.\n잠시만 기다려 주세요.', 'Organizing the summary and action items.\nPlease wait a moment.');
  }

  Widget _buildSummarizingCard() {
    final elapsedStr = _formatDurationClock(_currentSummaryElapsed());
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return Card(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: accent.withValues(alpha: 0.74),
                    ),
                  ),
                  Icon(Icons.auto_awesome, size: 26, color: accent),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _summaryProcessingTitle(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _summaryProcessingDescription(),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _SummaryStepIndicator(statusMsg: _statusMsg),
              const SizedBox(height: 8),
              Text(
                _statusMsg.isEmpty ? tr('처리 준비 중', 'Preparing') : _statusMsg,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              const _NativeTaskNotice(),
              const SizedBox(height: 12),
              // 진행바
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _summaryProgress > 0 ? _summaryProgress : null,
                  minHeight: 4,
                  color: accent,
                  backgroundColor: scheme.outlineVariant.withValues(
                    alpha: 0.55,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('${(_summaryProgress * 100).toStringAsFixed(0)}% · 경과 $elapsedStr', '${(_summaryProgress * 100).toStringAsFixed(0)}% · elapsed $elapsedStr'),
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _cancelSummaryRequested
                    ? null
                    : _requestCancelSummary,
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: Text(_cancelSummaryRequested ? tr('중지 중', 'Stopping') : tr('중지', 'Stop')),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.red.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 메모 패널 빌더 ────────────────────────────────────────────
  Widget _buildNotesPanel() {
    final canEdit =
        _phase == _RecordingPhase.recording ||
        _phase == _RecordingPhase.paused ||
        _phase == _RecordingPhase.stopped ||
        _phase == _RecordingPhase.done;
    final isReadOnly = !canEdit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        // ── 헤더 (항상 표시) ───────────────────────────────────
        InkWell(
          onTap: () => setState(() => _notesExpanded = !_notesExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _notesExpanded
                  ? Colors.amber.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _notesExpanded
                    ? Colors.amber.shade300
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 15,
                  color: _notesExpanded
                      ? Colors.amber.shade800
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  tr('메모', 'Notes'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _notesExpanded
                        ? Colors.amber.shade800
                        : Colors.grey.shade700,
                  ),
                ),
                if (_notesCtrl.text.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tr('입력됨', 'Filled'),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  _notesExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
        // ── 내용 + 드래그 핸들 (펼쳐졌을 때) ─────────────────
        if (_notesExpanded) ...[
          const SizedBox(height: 4),
          // 전체를 하나의 테두리 컨테이너로 감싸기
          Container(
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              children: [
                // 텍스트 필드
                SizedBox(
                  height: _notesHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (isReadOnly) return KeyEventResult.ignored;
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.tab) {
                          final shift =
                              HardwareKeyboard.instance.isShiftPressed;
                          AutoBullet.handleIndent(_notesCtrl, decrease: shift);
                          _notesPrev = _notesCtrl.text;
                          setState(() {});
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _notesCtrl,
                        readOnly: isReadOnly,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                        decoration: InputDecoration(
                          hintText: tr(
                            '회의 중 주요 내용을 자유롭게 메모하세요.\n요약 생성 시 함께 반영됩니다.',
                            'Jot down key points during the meeting.\nThey are included when the summary is generated.',
                          ),
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade400,
                            height: 1.5,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) {
                          _notesPrev = AutoBullet.handle(
                            _notesPrev,
                            value,
                            _notesCtrl,
                          );
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                ),
                // ── 드래그 핸들 ───────────────────────────────
                MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        _notesHeight = (_notesHeight + details.delta.dy).clamp(
                          60.0,
                          400.0,
                        );
                      });
                    },
                    child: MacosTooltip(
                      message: tr('드래그해서 메모창 크기 조정', 'Drag to resize the notes panel'),
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade300,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(7),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.drag_handle,
                            size: 16,
                            color: Colors.amber.shade900,
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
      ],
    );
  }

  // ── 참석자 입력 UI (녹음 전 단계에서만 편집 가능) ────────────────
  Widget _buildParticipantsInput() {
    final canEdit =
        _phase == _RecordingPhase.idle ||
        _phase == _RecordingPhase.error ||
        _phase == _RecordingPhase.checkingModels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.people_outline, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              tr('참석자 (선택)', 'Attendees (optional)'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (_participants.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                tr('${_participants.length}명', '${_participants.length} people'),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ..._participants.map(
              (name) => Chip(
                label: Text(name, style: const TextStyle(fontSize: 12)),
                deleteIcon: canEdit ? const Icon(Icons.close, size: 14) : null,
                onDeleted: canEdit
                    ? () => setState(() => _participants.remove(name))
                    : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (canEdit)
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _participantInputCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: tr('이름 입력 후 Enter', 'Type a name, then Enter'),
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  onSubmitted: (val) {
                    final name = val.trim();
                    if (name.isNotEmpty && !_participants.contains(name)) {
                      setState(() => _participants.add(name));
                    }
                    _participantInputCtrl.clear();
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── 요약 템플릿 선택 UI ────────────────────────────────────────
  Widget _buildTemplateSelector() {
    final globalId = AppSettings.instance.summaryTemplateId;
    final effectiveId = _summaryTemplateId ?? globalId;
    final isUsingGlobal = _summaryTemplateId == null;
    final effectiveName = effectiveId == SummaryTemplates.customId1
        ? tr('커스텀1', 'Custom 1')
        : effectiveId == SummaryTemplates.customId2
        ? tr('커스텀2', 'Custom 2')
        : SummaryTemplates.byId(effectiveId).name;

    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          tr('회의 유형', 'Meeting type'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String?>(
            value: _summaryTemplateId,
            isDense: true,
            isExpanded: true,
            underline: const SizedBox(),
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  tr('설정값 사용 (현재: $effectiveName)', 'Use default (current: $effectiveName)'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              for (final t in SummaryTemplates.presets)
                DropdownMenuItem<String?>(
                  value: t.id,
                  child: Text(t.name, style: const TextStyle(fontSize: 12)),
                ),
              DropdownMenuItem<String?>(
                value: SummaryTemplates.customId1,
                child: Text(tr('커스텀1', 'Custom 1'), style: const TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem<String?>(
                value: SummaryTemplates.customId2,
                child: Text(tr('커스텀2', 'Custom 2'), style: const TextStyle(fontSize: 12)),
              ),
            ],
            onChanged: (v) => setState(() => _summaryTemplateId = v),
          ),
        ),
        if (!isUsingGlobal)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tr('오버라이드', 'Override'),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── 마이크 장치 선택 UI ────────────────────────────────────────
  Widget _buildDeviceSelector() {
    return Row(
      children: [
        Icon(Icons.mic, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          tr('마이크', 'Microphone'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDevice?.id,
              isDense: true,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: _inputDevices.map((d) {
                final isBluetooth =
                    d.label.contains('AirPods') ||
                    d.label.contains('Bluetooth') ||
                    d.label.contains('블루투스');
                return DropdownMenuItem<String>(
                  value: d.id,
                  child: Row(
                    children: [
                      Icon(
                        isBluetooth ? Icons.bluetooth_audio : Icons.mic_none,
                        size: 13,
                        color: isBluetooth
                            ? Colors.blue.shade400
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(d.label),
                      if (isBluetooth) ...[
                        const SizedBox(width: 4),
                        Text(
                          tr('(불안정)', '(unstable)'),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              onChanged: (id) {
                final device = _inputDevices
                    .where((d) => d.id == id)
                    .firstOrNull;
                setState(() => _selectedDevice = device);
              },
            ),
          ),
        ),
        MacosTooltip(
          message: tr('목록 새로고침', 'Refresh list'),
          child: MacosIconButton(
            icon: Icon(Icons.refresh, size: 14, color: Colors.grey.shade500),
            backgroundColor: Colors.transparent,
            padding: EdgeInsets.zero,
            boxConstraints: const BoxConstraints(
              minWidth: 22,
              minHeight: 22,
              maxWidth: 22,
              maxHeight: 22,
            ),
            onPressed: () => _loadInputDevices(force: true),
          ),
        ),
      ],
    );
  }

  // ── 마이크 장치 목록 로드 (최초 1회만, 또는 새로고침 버튼 시) ──
  Future<void> _loadInputDevices({bool force = false}) async {
    if (_devicesLoaded && !force) return;
    // 녹음 중에는 별도 AudioRecorder 생성 금지 (충돌 방지)
    if (MicrophoneService.instance.isRecording) return;
    try {
      // 권한 확인 후에만 목록 조회 (권한 없으면 팝업 반복 방지)
      final recorder = AudioRecorder();
      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        recorder.dispose();
        return;
      }
      final devices = await recorder.listInputDevices();
      recorder.dispose();
      if (mounted) {
        setState(() {
          _devicesLoaded = true;
          _inputDevices = devices;
          // 이미 선택된 장치가 있으면 유지, 없으면 내장 마이크 우선 선택
          if (_selectedDevice == null) {
            final builtIn = devices
                .where(
                  (d) =>
                      d.label.contains('내장') ||
                      d.label.contains('Built-in') ||
                      d.label.contains('MacBook') ||
                      d.label.toLowerCase().contains('internal'),
                )
                .firstOrNull;
            _selectedDevice =
                builtIn ?? (devices.isNotEmpty ? devices.first : null);
          }
        });
      }
    } catch (_) {}
  }

  // ── 헬퍼 ──────────────────────────────────────────────────────
  String _elapsedStr() {
    final e = MicrophoneService.instance.elapsed;
    final m = e.inMinutes.toString().padLeft(2, '0');
    final s = (e.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // 공통 파서 위임
  static Summary _parseJsonForMic(
    String raw,
    int meetingId,
    DateTime date, {
    List<String> participants = const [],
  }) => SummaryParser.parse(
    raw,
    meetingId,
    date,
    forcedParticipants: participants,
  );

  // ── 모델 미설치 안내 화면 ──────────────────────────────────────
  Widget _buildModelMissingBanner() {
    final scheme = Theme.of(context).colorScheme;
    final warning = Colors.orange.shade700;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warning.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.download_for_offline_outlined,
                color: warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                tr('AI 모델 설치 필요', 'AI model installation required'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: warning,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('아래 모델 파일을 다운로드하여\n$_modelDir\n폴더에 넣어주세요.', 'Download the model files below and place them in the folder:\n$_modelDir'),
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          // STT 모델
          _ModelFileRow(
            label: tr('① Whisper Large V3 Turbo (음성 인식 · 실시간 초안 · 약 900 MB)', '① Whisper Large V3 Turbo (recognition · live draft · ~900 MB)'),
            filename: AppConstants.sttModelFileFast,
            url: AppConstants.sttDownloadUrlFast,
            exists: _sttFastExists,
          ),
          const SizedBox(height: 6),
          _ModelFileRow(
            label: tr('② Whisper Large V3 Q5_0 (음성 인식 · 최종 정확 전사 · 약 1.1 GB)', '② Whisper Large V3 Q5_0 (recognition · final accurate transcription · ~1.1 GB)'),
            filename: AppConstants.sttModelFileAccurate,
            url: AppConstants.sttDownloadUrlAccurate,
            exists: _sttAccurateExists,
          ),
          const SizedBox(height: 6),
          // LLM 모델 (현재 선택된 것만 안내 — 상세 관리는 설정 화면)
          _ModelFileRow(
            label: tr('③ 요약 모델 — 3종 중 선택 설치', '③ Summary model — install one of three'),
            filename: AppSettings.instance.currentLlmModelFile,
            url: AppSettings.instance.currentLlmDownloadUrl,
            exists: _llmModelExists,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _checkModels,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(tr('다운로드 완료 후 여기를 눌러 확인', 'After downloading, tap here to verify')),
              style: OutlinedButton.styleFrom(
                foregroundColor: warning,
                side: BorderSide(color: warning.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isRecording = _phase == _RecordingPhase.recording;
    final isPaused = _phase == _RecordingPhase.paused;
    final isBusy =
        _phase == _RecordingPhase.loadingModel ||
        _phase == _RecordingPhase.processing ||
        _phase == _RecordingPhase.summarizing ||
        _phase == _RecordingPhase.checkingModels;

    // 모델 미설치 여부
    final modelsReady = _sttModelExists;

    final trayStartState = isBusy
        ? TrayStartState.busy
        : modelsReady
        ? TrayStartState.ready
        : TrayStartState.modelsRequired;
    MenuBarService.instance.setStartState(
      trayStartState,
      busyLabel: _trayBusyLabel(),
    );

    // ── 메뉴바 트레이 신호 listen ──────────────────────────
    ref.listen<int>(trayStartRecordingSignalProvider, (prev, next) {
      // idle 상태에서만 — 이미 녹음/처리 중이면 무시
      if (_phase == _RecordingPhase.idle ||
          _phase == _RecordingPhase.stopped ||
          _phase == _RecordingPhase.done) {
        final fromTray = ref.read(pendingTrayQuickStartFromTrayProvider);
        ref.read(pendingTrayQuickStartProvider.notifier).state = false;
        ref.read(pendingTrayQuickStartFromTrayProvider.notifier).state = false;
        _startRecording(showTrayFailureNotice: fromTray);
      } else {
        // 시작 불가 phase에 온 신호도 pending 플래그는 소거한다 —
        // 남겨두면 다음 위젯 마운트 때 유령 자동 시작이 발생한다.
        ref.read(pendingTrayQuickStartProvider.notifier).state = false;
        ref.read(pendingTrayQuickStartFromTrayProvider.notifier).state = false;
      }
    });
    ref.listen<int>(trayStopRecordingSignalProvider, (prev, next) {
      if (isRecording || isPaused) {
        ref.read(pendingTrayStopProvider.notifier).state = false;
        _stopRecording();
      }
    });
    ref.listen<int>(trayBookmarkSignalProvider, (prev, next) {
      if (isRecording || isPaused) {
        final pendingCount = ref.read(pendingTrayBookmarkCountProvider);
        if (pendingCount > 0) {
          _consumePendingTrayBookmarks();
        } else {
          _addBookmark();
        }
      }
    });
    // ⌘⇧S → 요약 실행 (녹음 종료된 stopped 상태에서만)
    ref.listen<int>(shortcutRunSummarySignalProvider, (prev, next) {
      if (_phase == _RecordingPhase.stopped) {
        _runSummary();
        return;
      }
      if (_phase == _RecordingPhase.recording ||
          _phase == _RecordingPhase.paused) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('녹음을 중지한 뒤 요약을 실행할 수 있습니다.', 'Stop recording before running the summary.')),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      } else if (_phase == _RecordingPhase.summarizing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('이미 요약을 생성하고 있습니다.', 'A summary is already being generated.')),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      } else if (_segments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('요약할 전사 내용이 없습니다. 먼저 녹음해 주세요.', 'No transcript to summarize. Please record first.')),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
    });

    // 녹음 상태 → 메뉴바 트레이 아이콘/메뉴 갱신
    final elapsed = _recordingStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_recordingStartedAt!);
    MenuBarService.instance.setRecordingState(
      isRecording: isRecording || isPaused,
      elapsed: elapsed,
    );

    return CallbackShortcuts(
      bindings: {
        // ⌘B : 녹음 중 핵심 순간 북마크
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () {
          if (isRecording || isPaused) _addBookmark();
        },
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 제목 헤더 ────────────────────────────────────────────
              Text(
                tr('새 녹음', 'New recording'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // ── 회의 제목 입력 (날짜 고정 + 추가 제목) ──────────────
              Row(
                children: [
                  // 날짜 접두사 (수정 불가)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(4),
                      ),
                    ),
                    child: Text(
                      _datePrefix,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  // 추가 제목 입력
                  Expanded(
                    child: TextField(
                      controller: _titleSuffixController,
                      decoration: InputDecoration(
                        hintText: tr('추가 제목 (선택)', 'Title (optional)'),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      enabled: !isRecording && !isBusy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── 참석자 입력 (녹음 전 단계에서만) ────────────────────────
              if (!isRecording && !isPaused && !isBusy) ...[
                _buildParticipantsInput(),
                const SizedBox(height: 8),
                _buildTemplateSelector(),
                const SizedBox(height: 8),
              ],

              // ── 마이크 장치 선택 ──────────────────────────────────────
              if (_inputDevices.isNotEmpty && !isRecording && !isPaused)
                _buildDeviceSelector(),

              const SizedBox(height: 8),

              // ── 모델 미설치 안내 배너 ───────────────────────────────
              if (!modelsReady && _phase != _RecordingPhase.checkingModels)
                _buildModelMissingBanner(),

              // ── 녹음 제어 버튼 ──────────────────────────────────────
              _buildControlButtons(
                isRecording,
                isPaused,
                isBusy || !modelsReady,
              ),
              const SizedBox(height: 6),

              // ── 상태 메시지 + 윈도우 처리 인디케이터 ─────────────────
              Row(
                children: [
                  if (_isProcessingWindow)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _isProcessingWindow ? tr('텍스트로 변환 중...', 'Converting to text...') : _statusMsg,
                      style: TextStyle(
                        fontSize: 11,
                        color: _phase == _RecordingPhase.error
                            ? Colors.red.shade700
                            : _phase == _RecordingPhase.done
                            ? Colors.green.shade700
                            : _phase == _RecordingPhase.paused
                            ? Colors.orange.shade700
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // ── 녹음 중: 음성 펄스 카드 (마이크 글로우 + 음량 히스토리) ─
              if (isRecording && !_isProcessingWindow) ...[
                const SizedBox(height: 6),
                _VoicePulseCard(
                  level: _inputLevel,
                  isReceiving:
                      MicrophoneService.instance.totalBytesReceived > 0,
                ),
              ],
              if (_hasLowInputForAWhile) ...[
                const SizedBox(height: 6),
                _LowInputWarningBanner(
                  noSignal: MicrophoneService.instance.totalBytesReceived == 0,
                  onDismiss: () =>
                      setState(() => _lowInputBannerDismissed = true),
                ),
              ],
              const SizedBox(height: 6),

              // ── 메인 영역: 요약 중이면 진행 카드, 아니면 전사 리스트 ──
              Expanded(
                child: _phase == _RecordingPhase.summarizing
                    ? _buildSummarizingCard()
                    : Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.transcribe, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    tr('실시간 녹취 내용', 'Live transcript'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  if (_segments.isNotEmpty) ...[
                                    const Spacer(),
                                    Text(
                                      tr('${_segments.length}개', '${_segments.length}'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const Divider(height: 12),
                              Expanded(
                                child: _segments.isEmpty
                                    ? Center(
                                        child: Text(
                                          isRecording
                                              ? tr('말씀해 주세요. 곧 텍스트로 변환됩니다.', 'Start speaking — text will appear shortly.')
                                              : tr('녹음을 시작하면 내용이 여기에 표시됩니다', 'Content appears here once you start recording'),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      )
                                    : ListView.separated(
                                        controller: _transcriptScrollController,
                                        itemCount: _segments.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 6),
                                        itemBuilder: (_, i) {
                                          final seg = _segments[i];
                                          final isEditing =
                                              _editingSegIndex == i;
                                          return Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                seg.timestampStr,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade500,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: isEditing
                                                    ? TextField(
                                                        controller:
                                                            _editingCtrl,
                                                        autofocus: true,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          height: 1.5,
                                                        ),
                                                        decoration: InputDecoration(
                                                          isDense: true,
                                                          contentPadding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 4,
                                                              ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          focusedBorder: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                            borderSide:
                                                                BorderSide(
                                                                  color: Colors
                                                                      .indigo
                                                                      .shade300,
                                                                ),
                                                          ),
                                                        ),
                                                        onSubmitted: (_) =>
                                                            _commitEditingSeg(),
                                                        onTapOutside: (_) =>
                                                            _commitEditingSeg(),
                                                      )
                                                    : GestureDetector(
                                                        onDoubleTap: () =>
                                                            _startEditingSeg(i),
                                                        child: MacosTooltip(
                                                          message: tr('더블클릭하여 수정', 'Double-click to edit'),
                                                          child: SelectableText(
                                                            seg.text,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 13,
                                                                  height: 1.5,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              // ── 메모 패널 (요약 중엔 숨김) ──────────────────────────
              if (_phase != _RecordingPhase.summarizing) _buildNotesPanel(),

              // ── 메모리 정보 (요약 중엔 숨김) ────────────────────────
              if (_phase != _RecordingPhase.summarizing)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr(
                      '피크 메모리: 음성 인식 중 ~2 GB → 요약 시작 시 ~7–9 GB\n'
                          'VAD: RMS 에너지 기반 (무음 구간 자동 제외)',
                      'Peak memory: ~2 GB during recognition → ~7–9 GB when summarizing\n'
                          'VAD: RMS-energy based (silence automatically excluded)',
                    ),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ), // Focus
    ); // CallbackShortcuts
  }
}

// ── 요약 진행 단계 표시 위젯 ───────────────────────────────────────────
class _SummaryStepIndicator extends StatelessWidget {
  final String statusMsg;
  const _SummaryStepIndicator({required this.statusMsg});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 각 단계는 한국어/영어 상태 문자열 모두에서 인식되도록 키워드 목록을 갖는다.
    final steps = <(String, List<String>)>[
      (tr('전사 확인', 'Check transcript'), const ['전사', 'transcri']),
      (tr('발화자 라벨', 'Speaker labels'), const ['발화자', 'speaker']),
      (
        tr('요약 생성', 'Generate summary'),
        const ['요약', '로드', '분석', '생성', '준비', 'summ', 'load', 'analyz', 'generat', 'prepar'],
      ),
      (tr('결과 저장', 'Save result'), const ['저장', 'sav']),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: steps.asMap().entries.map((entry) {
        final idx = entry.key;
        final step = entry.value;
        final isActive = _statusMatch(statusMsg, step.$2);

        return Row(
          children: [
            if (idx > 0) ...[
              Container(width: 16, height: 1, color: scheme.outlineVariant),
            ],
            Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    border: Border.all(
                      color: isActive ? scheme.primary : scheme.outlineVariant,
                    ),
                  ),
                  child: Center(
                    child: isActive
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            '${idx + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.$1,
                  style: TextStyle(
                    fontSize: 9,
                    color: isActive
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ],
        );
      }).toList(),
    );
  }
}

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
          if (active != null) tr('현재 작업: $active', 'Current: $active'),
          if (queued != null)
            state.queuedCount > 1
                ? tr('대기 중: $queued 외 ${state.queuedCount - 1}개', 'Queued: $queued and ${state.queuedCount - 1} more')
                : tr('다음 작업 대기: $queued', 'Next up: $queued'),
        ].join(' · ');
        final scheme = Theme.of(context).colorScheme;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
          ),
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: scheme.primary, height: 1.35),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}

// ── 모델 파일 행 (다운로드 링크 + 설치 여부 표시) ─────────────────────
class _ModelFileRow extends StatelessWidget {
  final String label;
  final String filename;
  final String url;
  final bool exists;

  const _ModelFileRow({
    required this.label,
    required this.filename,
    required this.url,
    required this.exists,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          exists ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: exists ? Colors.green.shade600 : Colors.orange.shade400,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: exists
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
              ),
              Text(
                filename,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        if (!exists)
          TextButton.icon(
            onPressed: () async {
              final uri = Uri.parse(url);
              // url_launcher 없이 Process로 브라우저 열기
              await Process.run('open', [uri.toString()]);
            },
            icon: const Icon(Icons.open_in_browser, size: 14),
            label: Text(tr('다운로드', 'Download'), style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              tr('설치됨', 'Installed'),
              style: TextStyle(
                fontSize: 11,
                color: Colors.green.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

/// LLM 스트리밍 라이브 미리보기 (자동 스크롤 타자기).
class _LiveSummaryPreview extends StatefulWidget {
  final String text;
  const _LiveSummaryPreview({required this.text});

  @override
  State<_LiveSummaryPreview> createState() => _LiveSummaryPreviewState();
}

class _LiveSummaryPreviewState extends State<_LiveSummaryPreview> {
  final _ctrl = ScrollController();

  @override
  void didUpdateWidget(covariant _LiveSummaryPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ctrl.hasClients) {
          _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _ctrl,
      child: SelectableText(
        widget.text,
        style: TextStyle(
          fontSize: 11,
          height: 1.45,
          color: Colors.grey.shade800,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

// ── 음성 펄스 카드 ──────────────────────────────────────────────────────────
//
// 일반 사용자가 "내 목소리가 잘 들어가고 있구나"를 한눈에 알 수 있도록
// 설계된 마이크 시각화 위젯.
//
// 구성:
//   • 좌측: 마이크 아이콘 칩 — RMS에 비례한 후광(halo)이 크기·색상·진동으로 변화
//   • 중앙: 큰 상태 라벨 ("잘 들리고 있어요" / "조금 작아요" / "너무 커요" / "신호 없음")
//   • 하단: 최근 8초간 입력 음량 미니 파형 (32개 막대, 오른쪽 = 최신)
//
// 의도:
//   - 숫자(KB, dB, 초)를 직접 보여주지 않음 → "내 목소리가 들어가는지" 직관 우선
//   - 파형 바는 회의 중 "내가 너무 빨리 말했나?" 같은 자기인식에도 도움
class _VoicePulseCard extends StatefulWidget {
  /// 0.0 ~ 1.0
  final double level;

  /// 마이크에서 데이터가 들어오고 있는가
  final bool isReceiving;

  const _VoicePulseCard({required this.level, required this.isReceiving});

  @override
  State<_VoicePulseCard> createState() => _VoicePulseCardState();
}

class _VoicePulseCardState extends State<_VoicePulseCard>
    with SingleTickerProviderStateMixin {
  /// 32개 슬롯 — 약 8초간 음량 히스토리 (240ms 마다 1개)
  static const int _historyCap = 32;
  // growable=true 필수 — removeAt(0) / add() 사용
  final List<double> _history = List.filled(_historyCap, 0.0, growable: true);
  Timer? _sampler;
  late final AnimationController _haloCtrl;

  @override
  void initState() {
    super.initState();
    _haloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    // 240ms 마다 현재 level을 history에 추가
    _sampler = Timer.periodic(const Duration(milliseconds: 240), (_) {
      if (!mounted) return;
      setState(() {
        _history.removeAt(0);
        _history.add(widget.level);
      });
    });
  }

  @override
  void dispose() {
    _sampler?.cancel();
    _haloCtrl.dispose();
    super.dispose();
  }

  ({String label, Color color, IconData icon}) _statusOf(double l) {
    if (!widget.isReceiving) {
      return (
        label: tr('마이크 신호가 없습니다', 'No microphone signal'),
        color: Colors.red.shade600,
        icon: Icons.mic_off_rounded,
      );
    }
    if (l > 0.95) {
      return (
        label: tr('음량이 너무 큽니다', 'Volume is too high'),
        color: Colors.red.shade600,
        icon: Icons.warning_amber_rounded,
      );
    }
    if (l < 0.06) {
      return (
        label: tr('음성을 감지하지 못하고 있어요', 'Not detecting any voice'),
        color: Colors.grey.shade600,
        icon: Icons.hearing_rounded,
      );
    }
    if (l < 0.15) {
      return (
        label: tr('말씀하시면 마이크가 따라갑니다', 'The mic follows when you speak'),
        color: Colors.orange.shade700,
        icon: Icons.mic_rounded,
      );
    }
    return (
      label: tr('잘 들리고 있어요', 'Audio is clear'),
      color: const Color(0xFF007AFF),
      icon: Icons.mic_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusOf(widget.level);
    final scheme = Theme.of(context).colorScheme;
    final cardBg = scheme.surfaceContainerHighest.withValues(alpha: 0.30);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ── 마이크 칩 + 후광 ──
              _MicHalo(
                level: widget.level,
                isReceiving: widget.isReceiving,
                color: status.color,
                animation: _haloCtrl,
              ),
              const SizedBox(width: 14),
              // ── 상태 라벨 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: status.color,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _hint(widget.level, widget.isReceiving),
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── 미니 파형 (최근 8초) ──
          SizedBox(
            height: 22,
            child: _MiniWaveform(
              history: _history,
              barColor: status.color,
              isReceiving: widget.isReceiving,
            ),
          ),
        ],
      ),
    );
  }

  String _hint(double l, bool receiving) {
    if (!receiving) return tr('시스템 설정에서 마이크 권한과 입력 장치를 확인해주세요', 'Check microphone permission and input device in System Settings');
    if (l > 0.95) return tr('마이크와 거리를 두거나 입력 음량을 낮춰주세요', 'Move away from the mic or lower the input volume');
    if (l < 0.06) return tr('마이크에 더 가까이 말하거나 음량을 높여주세요', 'Speak closer to the mic or raise the volume');
    if (l < 0.15) return tr('조금 더 가까이 말하면 인식 정확도가 올라갑니다', 'Speaking a bit closer improves recognition accuracy');
    return tr('회의 중 평소 톤으로 자연스럽게 말씀하세요', 'Speak naturally in your usual tone during the meeting');
  }
}

/// 마이크 칩 + 후광 — RMS에 비례한 halo 크기/투명도, 호흡 같은 ripple 효과
class _MicHalo extends StatelessWidget {
  final double level;
  final bool isReceiving;
  final Color color;
  final Animation<double> animation;

  const _MicHalo({
    required this.level,
    required this.isReceiving,
    required this.color,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, _) {
          // 펄스 진폭은 level 비례. ring 2개가 시간차로 퍼져 나간다.
          final amp = isReceiving ? level.clamp(0.06, 1.0) : 0.0;
          final t1 = animation.value;
          final t2 = (animation.value + 0.5) % 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // 외곽 ring 1
              _ripple(amp, t1),
              // 외곽 ring 2 (시간차)
              _ripple(amp, t2),
              // 중심 마이크 칩
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: color.withValues(alpha: 0.44),
                    width: 1,
                  ),
                  boxShadow: amp > 0.1
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.18 * amp),
                            blurRadius: 10 * amp,
                            spreadRadius: 0.5 * amp,
                          ),
                        ]
                      : null,
                ),
                child: Icon(Icons.mic_rounded, size: 20, color: color),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 동심원 ripple — t는 0..1, 0에서 시작해 1로 퍼지며 페이드아웃
  Widget _ripple(double amp, double t) {
    if (amp <= 0.05) return const SizedBox.shrink();
    final size = 38 + 14 * t * amp.clamp(0.2, 1.0); // 38 ~ 52
    final opacity = (1 - t) * 0.28 * amp;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: opacity)),
      ),
    );
  }
}

/// 8초 음량 히스토리 미니 파형 (32개 막대, 가운데 정렬, 오른쪽=최신)
class _MiniWaveform extends StatelessWidget {
  final List<double> history;
  final Color barColor;
  final bool isReceiving;

  const _MiniWaveform({
    required this.history,
    required this.barColor,
    required this.isReceiving,
  });

  @override
  Widget build(BuildContext context) {
    // 자동 스케일링 — 최근 4초 max로 정규화 (실제 음성은 0.05~0.4 범위가 흔함)
    double localMax = 0.05;
    final tail = history.sublist(history.length ~/ 2);
    for (final v in tail) {
      if (v > localMax) localMax = v;
    }
    final scale = (1.0 / localMax).clamp(1.5, 8.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(history.length, (i) {
        final raw = history[i];
        final norm = (raw * scale).clamp(0.0, 1.0);
        // 최신일수록 진하게 (오른쪽이 최신)
        final freshness = i / (history.length - 1); // 0=오래됨, 1=최신
        final alpha = isReceiving
            ? (0.25 + 0.7 * freshness) * (0.5 + 0.5 * norm)
            : 0.15;
        final h = isReceiving ? (3 + 16 * norm) : 3.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0.6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              height: h,
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// 요약 전 단계에서 저장된 Meeting id + 녹음 시작 시각을 묶어서 반환.
class _PersistedMeeting {
  final int meetingId;
  final DateTime recStart;
  const _PersistedMeeting({required this.meetingId, required this.recStart});
}

/// 녹음 준비 다이얼로그 상단의 캘린더 이벤트 추천 패널.
/// macOS Calendar.app에서 다가오는/현재 진행 중인 이벤트를 가져와
/// "선택" 클릭 시 회의 제목/어젠다 자동 채움.
class _CalendarSuggestionPanel extends StatefulWidget {
  final ValueChanged<CalendarEvent> onPick;

  const _CalendarSuggestionPanel({required this.onPick});

  @override
  State<_CalendarSuggestionPanel> createState() =>
      _CalendarSuggestionPanelState();
}

class _CalendarSuggestionPanelState extends State<_CalendarSuggestionPanel> {
  List<CalendarEvent>? _events;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await CalendarService.instance.getUpcomingEvents();
    if (!mounted) return;
    setState(() {
      _events = list;
      _loading = false;
    });
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _relativeStart(DateTime start) {
    final now = DateTime.now();
    final diff = start.difference(now);
    if (diff.isNegative) {
      final mins = (-diff.inMinutes);
      if (mins == 0) return tr('진행 중', 'In progress');
      return tr('$mins분 전 시작', 'Started $mins min ago');
    }
    if (diff.inMinutes < 60) return tr('${diff.inMinutes}분 후', 'in ${diff.inMinutes} min');
    return tr('${diff.inHours}시간 ${diff.inMinutes % 60}분 후', 'in ${diff.inHours}h ${diff.inMinutes % 60}m');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final list = _events ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_outlined, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                tr('다가오는 캘린더 회의', 'Upcoming calendar meetings'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                tr('· 클릭하면 제목/어젠다 자동 채움', '· Click to auto-fill title/agenda'),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final e in list.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => widget.onPick(e),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_fmtTime(e.start)} ~ ${_fmtTime(e.end)} '
                              '· ${_relativeStart(e.start)} · ${e.calendarName}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: scheme.primary.withValues(alpha: 0.6),
                      ),
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

class _RecordingPrepResult {
  final String titleSuffix;
  final int speakerCount;
  final InputDevice? device;
  final String? summaryTemplateId;
  final bool diarizationEnabled;
  final String sttLanguage;
  final bool markMicGuideShown;
  final String agenda;

  const _RecordingPrepResult({
    required this.titleSuffix,
    required this.speakerCount,
    required this.device,
    required this.summaryTemplateId,
    required this.diarizationEnabled,
    required this.sttLanguage,
    required this.markMicGuideShown,
    required this.agenda,
  });
}

class _MicTestPanel extends StatefulWidget {
  final String? selectedDeviceId;
  final List<InputDevice> devices;
  final ValueChanged<Future<void> Function()> onStopReady;

  const _MicTestPanel({
    required this.selectedDeviceId,
    required this.devices,
    required this.onStopReady,
  });

  @override
  State<_MicTestPanel> createState() => _MicTestPanelState();
}

class _MicTestPanelState extends State<_MicTestPanel> {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  double _level = 0;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.onStopReady(_stop);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restart());
  }

  @override
  void didUpdateWidget(covariant _MicTestPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.onStopReady(_stop);
    if (oldWidget.selectedDeviceId != widget.selectedDeviceId) {
      _restart();
    }
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  InputDevice? get _selectedDevice {
    final id = widget.selectedDeviceId;
    if (id == null) return null;
    for (final device in widget.devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<void> _restart() async {
    await _stop();
    if (!mounted) return;
    setState(() {
      _starting = true;
      _error = null;
      _level = 0;
    });
    try {
      final recorder = AudioRecorder();
      _recorder = recorder;
      if (!await recorder.hasPermission()) {
        throw MicrophonePermissionDeniedException(
          tr('마이크 권한이 꺼져 있습니다. 시스템 설정에서 마이크 권한을 켜주세요.', 'Microphone access is off. Enable it in System Settings.'),
        );
      }
      final stream = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          device: _selectedDevice,
          autoGain: AppSettings.instance.recordAutoGain,
          echoCancel: AppSettings.instance.recordEchoCancel,
        ),
      );
      _sub = stream.listen(
        (chunk) {
          if (!mounted) return;
          setState(() => _level = _computeLevel(chunk));
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() => _error = tr('마이크 테스트 오류: $e', 'Mic test error: $e'));
        },
      );
    } catch (e) {
      await _stop();
      if (!mounted) return;
      setState(
        () => _error = e is MicrophonePermissionDeniedException
            ? e.message
            : tr('마이크 입력을 확인하지 못했습니다. 입력 장치와 권한을 확인해주세요.', 'Could not verify microphone input. Check the input device and permissions.'),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel().catchError((_) {});
    final recorder = _recorder;
    _recorder = null;
    try {
      if (recorder != null && await recorder.isRecording()) {
        await recorder.stop();
      }
    } catch (_) {}
    await recorder?.dispose().catchError((_) {});
  }

  double _computeLevel(Uint8List chunk) {
    if (chunk.length < 2) return 0;
    var sumSquares = 0.0;
    var samples = 0;
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final lo = chunk[i];
      final hi = chunk[i + 1];
      var sample = (hi << 8) | lo;
      if (sample & 0x8000 != 0) sample -= 0x10000;
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
      samples++;
    }
    if (samples == 0) return 0;
    final rms = math.sqrt(sumSquares / samples);
    return (rms * 8).clamp(0.0, 1.0);
  }

  ({String label, String hint, Color color, IconData icon}) _status() {
    if (_error != null) {
      return (
        label: tr('확인 필요', 'Needs review'),
        hint: _error!,
        color: Colors.red.shade700,
        icon: Icons.mic_off_rounded,
      );
    }
    if (_starting) {
      return (
        label: tr('테스트 준비 중', 'Preparing test'),
        hint: tr('선택한 마이크 입력을 확인하고 있습니다.', 'Checking the selected microphone input.'),
        color: Colors.grey.shade600,
        icon: Icons.hourglass_empty_rounded,
      );
    }
    if (_level >= 0.18) {
      return (
        label: tr('입력이 잘 들어오고 있어요', 'Input is coming in clearly'),
        hint: tr('이 상태로 녹음하면 음성 인식 품질이 좋아집니다.', 'Recording in this state gives good recognition quality.'),
        color: Colors.green.shade700,
        icon: Icons.check_circle_outline_rounded,
      );
    }
    if (_level >= 0.06) {
      return (
        label: tr('조금 작게 들립니다', 'Sounds a bit quiet'),
        hint: tr('마이크를 말하는 사람 가까이에 두면 더 좋습니다.', 'Placing the mic closer to the speaker helps.'),
        color: Colors.orange.shade700,
        icon: Icons.warning_amber_rounded,
      );
    }
    return (
      label: tr('너무 조용합니다', 'Too quiet'),
      hint: tr('3초 정도 말해보세요. 계속 낮으면 입력 장치나 권한을 확인해주세요.', 'Try speaking for ~3 seconds. If it stays low, check the input device or permissions.'),
      color: Colors.red.shade700,
      icon: Icons.hearing_disabled_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: status.color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.icon, size: 18, color: status.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: status.color,
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('마이크 테스트 다시 시작', 'Restart mic test'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: _starting ? null : _restart,
                icon: const Icon(Icons.refresh_rounded, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _starting ? null : _level.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.black.withValues(alpha: 0.08),
              color: status.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status.hint,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

enum _EmptyRecordingAction { keep, delete, summarize }

class _LowInputWarningBanner extends StatelessWidget {
  final bool noSignal;
  final VoidCallback onDismiss;

  const _LowInputWarningBanner({
    required this.noSignal,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final title = noSignal ? tr('마이크 신호가 없습니다', 'No microphone signal') : tr('음성이 거의 감지되지 않습니다', 'Almost no voice detected');
    final body = noSignal
        ? tr('입력 장치가 올바른지, 시스템 설정에서 마이크 권한이 켜져 있는지 확인하세요.', 'Check that the input device is correct and microphone access is enabled in System Settings.')
        : tr('마이크를 말하는 사람 가까이에 두거나 입력 음량을 올려주세요.', 'Place the mic closer to the speaker or raise the input volume.');
    final scheme = Theme.of(context).colorScheme;
    final warning = Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warning.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(
            noSignal ? Icons.mic_off_rounded : Icons.hearing_disabled_outlined,
            size: 20,
            color: warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          MacosTooltip(
            message: tr('닫기', 'Close'),
            child: MacosIconButton(
              icon: Icon(Icons.close, size: 16, color: warning),
              backgroundColor: Colors.transparent,
              padding: EdgeInsets.zero,
              boxConstraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
                maxWidth: 24,
                maxHeight: 24,
              ),
              onPressed: onDismiss,
            ),
          ),
        ],
      ),
    );
  }
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

class _PrepGuideRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PrepGuideRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrepToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrepToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 처리 상태 메시지가 주어진 키워드 중 하나라도 포함하는지 (대소문자 무시).
/// 상태 문자열이 한국어/영어 어느 쪽이든 단계 표시가 동작하도록 한다.
bool _statusMatch(String status, List<String> needles) {
  final s = status.toLowerCase();
  for (final n in needles) {
    if (s.contains(n.toLowerCase())) return true;
  }
  return false;
}

/// 녹음 오디오 소스. 온라인 회의(시스템 출력) 캡처 지원용.
enum RecordingSource {
  /// 마이크만 (대면 회의, 기본값)
  mic,

  /// 시스템 오디오만 (상대방 목소리만 듣고 기록)
  systemAudio,

  /// 마이크 + 시스템 오디오 믹스 (온라인 회의 권장)
  micAndSystem,
}
