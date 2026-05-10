import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_build_config.dart';
import '../constants/app_constants.dart';

/// 앱 설정 영구 저장소 (SharedPreferences 기반)
///
/// 사용 전 반드시 `AppSettings.init()` 호출 (main.dart에서 처리)
class AppSettings {
  static AppSettings? _instance;

  static AppSettings get instance {
    assert(_instance != null, 'AppSettings.init() 을 먼저 호출하세요');
    return _instance!;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _instance = AppSettings._(prefs);
    await _instance!._sanitizeForCurrentBuild();
  }

  final SharedPreferences _prefs;
  AppSettings._(this._prefs);

  Future<void> _sanitizeForCurrentBuild() async {
    final savedLlm = _prefs.getString('selectedLlmModel');
    if (savedLlm != null && !isLlmModelAvailable(savedLlm)) {
      await _prefs.setString('selectedLlmModel', defaultLlmModelId);
    }
    if (!AppBuildConfig.enableCalendarIntegration &&
        (_prefs.getBool('autoAddToCalendar') ?? false)) {
      await _prefs.setBool('autoAddToCalendar', false);
    }

    // ── 요약 템플릿 마이그레이션 ─────────────────────────────────
    // 1) 삭제된 프리셋(retrospective, interview)을 저장한 사용자는 일반으로 복귀.
    final savedTemplate = _prefs.getString('summaryTemplateId');
    if (savedTemplate == 'retrospective' || savedTemplate == 'interview') {
      await _prefs.setString('summaryTemplateId', 'general');
    }
    // 2) 단일 'custom' → 'custom1' 로 자동 변경.
    if (savedTemplate == 'custom') {
      await _prefs.setString('summaryTemplateId', 'custom1');
    }
    // 3) 단일 'customSummaryInstruction' 값을 'customSummaryInstruction1' 로 복사.
    final legacy = _prefs.getString('customSummaryInstruction');
    final slot1 = _prefs.getString('customSummaryInstruction1');
    if (legacy != null &&
        legacy.isNotEmpty &&
        (slot1 == null || slot1.isEmpty)) {
      await _prefs.setString('customSummaryInstruction1', legacy);
    }

    // ── 초기 기본값 일괄 적용 (build19~) ─────────────────────────
    // 사용자가 한 번도 직접 선택한 적 없는 키만 새 기본값으로 채운다.
    // 이미 직접 선택한 값은 보존. 마커가 있으면 다시 적용하지 않는다.
    const defaultsMarker = '_settingsDefaultsApplied_v1';
    if (!(_prefs.getBool(defaultsMarker) ?? false)) {
      // 음성 인식 방식: 빠름 (ultraFast)
      if (_prefs.getString('sttProcessingMode') == null) {
        await _prefs.setString('sttProcessingMode', sttModeUltraFast);
        await _prefs.setBool('sttAccurateMode', false);
      }
      // 기본 회의 유형: 주제별 요약 (topic_report)
      if (_prefs.getString('summaryTemplateId') == null) {
        await _prefs.setString('summaryTemplateId', 'topic_report');
      }
      await _prefs.setBool(defaultsMarker, true);
    }
  }

  // ── STT 언어 ──────────────────────────────────────────────────────
  /// Whisper 음성 인식 언어 코드.
  /// `auto`는 Whisper의 언어 자동 감지를 사용한다.
  static const List<String> supportedSttLanguages = [
    'auto',
    'ko',
    'en',
    'ja',
    'zh',
  ];

  static String sttLanguageLabel(String code) => switch (code) {
    'auto' => '자동 감지',
    'ko' => '한국어',
    'en' => 'English',
    'ja' => '日本語',
    'zh' => '中文',
    _ => '한국어',
  };

  static String sttLanguageDescription(String code) => switch (code) {
    'auto' => '한국어+영어처럼 언어가 섞인 회의에 권장합니다.',
    'ko' => '한국어 중심 회의에 권장합니다.',
    'en' => '영어 중심 회의에 권장합니다.',
    'ja' => '일본어 중심 회의에 권장합니다.',
    'zh' => '중국어 중심 회의에 권장합니다.',
    _ => '한국어 중심 회의에 권장합니다.',
  };

  String get sttLanguage {
    final saved = _prefs.getString('sttLanguage') ?? 'ko';
    return supportedSttLanguages.contains(saved) ? saved : 'ko';
  }

  Future<void> setSttLanguage(String v) => _prefs.setString(
    'sttLanguage',
    supportedSttLanguages.contains(v) ? v : 'ko',
  );

  // ── 자동 삭제 ─────────────────────────────────────────────────────
  /// 오래된 녹음 자동 삭제 기준 일수 (0 = 비활성화)
  int get autoDeleteDays => _prefs.getInt('autoDeleteDays') ?? 0;
  Future<void> setAutoDeleteDays(int v) => _prefs.setInt('autoDeleteDays', v);

  // ── 녹음 파일 저장 위치 ────────────────────────────────────────────
  /// 녹음 WAV 저장 경로. 첫 실행 시 사용자가 반드시 선택한다.
  String get recordingsSavePath => _prefs.getString('recordingsSavePath') ?? '';
  Future<void> setRecordingsSavePath(String v) =>
      _prefs.setString('recordingsSavePath', v);

  // ── 테마 모드 ─────────────────────────────────────────────────────
  /// 'system' | 'light' | 'dark'
  String get themeMode => _prefs.getString('themeMode') ?? 'system';
  Future<void> setThemeMode(String v) => _prefs.setString('themeMode', v);

  // ── 요약 템플릿 ───────────────────────────────────────────────────
  /// 프리셋 id (general / topic_report / lecture) 또는 커스텀 슬롯('custom1' / 'custom2').
  /// 과거 standup/planning/retrospective/interview/custom 등은 `_sanitizeForCurrentBuild`
  /// 와 `SummaryTemplates.byId` fallback 으로 안전하게 처리됨.
  /// 신규 사용자 기본값: 'topic_report' (build19~).
  String get summaryTemplateId =>
      _prefs.getString('summaryTemplateId') ?? 'topic_report';
  Future<void> setSummaryTemplateId(String v) =>
      _prefs.setString('summaryTemplateId', v);

  /// 커스텀 슬롯 1 instruction. (templateId == 'custom1' 일 때 사용)
  /// 기존 단일 'customSummaryInstruction' 키는 init 단계에서 이리로 마이그레이션됨.
  String get customSummaryInstruction1 =>
      _prefs.getString('customSummaryInstruction1') ?? '';
  Future<void> setCustomSummaryInstruction1(String v) =>
      _prefs.setString('customSummaryInstruction1', v);

  /// 커스텀 슬롯 2 instruction. (templateId == 'custom2' 일 때 사용)
  String get customSummaryInstruction2 =>
      _prefs.getString('customSummaryInstruction2') ?? '';
  Future<void> setCustomSummaryInstruction2(String v) =>
      _prefs.setString('customSummaryInstruction2', v);

  // ── STT 모델 모드 (v1.9.9) ────────────────────────────────────────
  static const String sttModeUltraFast = 'ultraFast';
  static const String sttModeBalanced = 'balanced';
  static const String sttModeAccurate = 'accurate';
  static const List<String> supportedSttProcessingModes = [
    sttModeUltraFast,
    sttModeBalanced,
    sttModeAccurate,
  ];

  static String sttProcessingModeLabel(String mode) => switch (mode) {
    sttModeUltraFast => '빠름',
    sttModeBalanced => '표준',
    sttModeAccurate => '정밀',
    _ => '표준',
  };

  static String sttProcessingModeDescription(String mode) => switch (mode) {
    sttModeUltraFast => '대기 시간을 조금 더 줄이는 방식입니다. 고유명사와 겹치는 발화 정확도는 낮아질 수 있습니다.',
    sttModeBalanced => '일반 회의 기본값입니다. 속도와 전사 품질을 함께 고려합니다.',
    sttModeAccurate => '정밀 모델과 보수적인 디코딩을 사용합니다. 중요 회의에 적합하지만 오래 걸립니다.',
    _ => '일반 회의 기본값입니다. 속도와 전사 품질을 함께 고려합니다.',
  };

  /// 음성 인식 처리 프로필.
  /// 기존 `sttAccurateMode` 저장값만 있는 사용자는 true=정밀로 승계.
  /// 신규 사용자 기본값: 'ultraFast' (빠름) — build19~.
  String get sttProcessingMode {
    final saved = _prefs.getString('sttProcessingMode');
    if (supportedSttProcessingModes.contains(saved)) return saved!;
    final legacyAccurate = _prefs.getBool('sttAccurateMode') ?? false;
    return legacyAccurate ? sttModeAccurate : sttModeUltraFast;
  }

  Future<void> setSttProcessingMode(String v) async {
    final next = supportedSttProcessingModes.contains(v) ? v : sttModeBalanced;
    await _prefs.setString('sttProcessingMode', next);
    await _prefs.setBool('sttAccurateMode', next == sttModeAccurate);
  }

  /// 하위 호환용: true=정밀, false=표준/빠름.
  bool get sttAccurateMode => sttProcessingMode == sttModeAccurate;
  Future<void> setSttAccurateMode(bool v) =>
      setSttProcessingMode(v ? sttModeAccurate : sttModeBalanced);

  /// 현재 모드에 해당하는 STT 모델 파일명
  String get currentSttModelFile => sttProcessingMode == sttModeAccurate
      ? AppConstants.sttModelFileAccurate
      : AppConstants.sttModelFileFast;

  /// 현재 모드에 해당하는 STT 다운로드 URL
  String get currentSttDownloadUrl => sttProcessingMode == sttModeAccurate
      ? AppConstants.sttDownloadUrlAccurate
      : AppConstants.sttDownloadUrlFast;

  /// whisper.cpp 래퍼에 넘기는 디코딩 프로필 코드.
  /// 0=greedy, 1=beam2, 2=beam5.
  int get sttDecodeModeCode => switch (sttProcessingMode) {
    sttModeUltraFast => 0,
    sttModeAccurate => 2,
    _ => 1,
  };

  // ── 요약 속도/품질 모드 ─────────────────────────────────────────────
  static const String summaryModeFast = 'fast';
  static const String summaryModeBalanced = 'balanced';
  static const String summaryModeDetailed = 'detailed';
  static const List<String> supportedSummaryModes = [
    summaryModeFast,
    summaryModeBalanced,
    summaryModeDetailed,
  ];

  static String summaryModeLabel(String mode) => switch (mode) {
    summaryModeFast => '빠른',
    summaryModeDetailed => '정밀',
    _ => '균형',
  };

  static String summaryModeDescription(String mode) => switch (mode) {
    summaryModeFast => '짧게 먼저 정리합니다. 긴 회의에서 대기 시간이 가장 짧습니다.',
    summaryModeDetailed => '구간별 내용을 더 많이 보존합니다. 시간이 가장 오래 걸립니다.',
    _ => '속도와 내용 보존을 함께 고려합니다.',
  };

  String get summarySpeedMode {
    final saved = _prefs.getString('summarySpeedMode');
    return supportedSummaryModes.contains(saved) ? saved! : summaryModeFast;
  }

  Future<void> setSummarySpeedMode(String v) => _prefs.setString(
    'summarySpeedMode',
    supportedSummaryModes.contains(v) ? v : summaryModeFast,
  );

  // ── 녹음 품질 (v1.9.9+2) ──────────────────────────────────────────
  /// AGC (Auto Gain Control) 활성화 여부. macOS Voice Processing 기반.
  /// 조용한 화자의 볼륨을 자동 보정하지만 배경 소음도 함께 올릴 수 있음.
  bool get recordAutoGain => _prefs.getBool('recordAutoGain') ?? false;
  Future<void> setRecordAutoGain(bool v) => _prefs.setBool('recordAutoGain', v);

  /// 에코 제거 활성화 여부. 통화 환경에는 유리하나 다중 화자 회의에서는
  /// 반대 방향 화자 소리가 함께 감쇄돼 오히려 품질이 떨어질 수 있음.
  bool get recordEchoCancel => _prefs.getBool('recordEchoCancel') ?? false;
  Future<void> setRecordEchoCancel(bool v) =>
      _prefs.setBool('recordEchoCancel', v);

  /// 녹음 저장 시 피크 정규화(normalize) 여부. 전체 음량을 -1dB 헤드룸까지
  /// 끌어올려 작은 목소리도 Whisper가 잘 잡도록 함.
  bool get recordNormalize => _prefs.getBool('recordNormalize') ?? true;
  Future<void> setRecordNormalize(bool v) =>
      _prefs.setBool('recordNormalize', v);

  // ── LLM 모델 선택 (v1.9.9+3) ──────────────────────────────────────
  static const String defaultLlmModelId = 'gemma4_e2b';

  /// App Store mode excludes restricted/non-commercial model choices.
  static List<String> get availableLlmModelIds => [
    'gemma4_e2b',
    'qwen25_7b',
    if (AppBuildConfig.allowRestrictedModels) 'exaone35_7b',
  ];

  static bool isLlmModelAvailable(String id) =>
      availableLlmModelIds.contains(id);

  /// 요약·추론에 사용할 LLM id.
  ///
  /// 앱스토어 모드에서 과거 저장값이 `exaone35_7b`이면 안전한 기본값으로 fallback.
  String get selectedLlmModel {
    final saved = _prefs.getString('selectedLlmModel') ?? defaultLlmModelId;
    return isLlmModelAvailable(saved) ? saved : defaultLlmModelId;
  }

  Future<void> setSelectedLlmModel(String v) => _prefs.setString(
    'selectedLlmModel',
    isLlmModelAvailable(v) ? v : defaultLlmModelId,
  );

  /// 디버그/진단용 원본 저장값. 제품 코드에서는 [selectedLlmModel]을 사용한다.
  String? get rawSelectedLlmModelForDiagnostics =>
      _prefs.getString('selectedLlmModel');

  /// 현재 선택된 LLM의 파일명
  String get currentLlmModelFile => llmModelFileFor(selectedLlmModel);

  /// 현재 선택된 LLM의 다운로드 URL
  String get currentLlmDownloadUrl => llmDownloadUrlFor(selectedLlmModel);

  /// id → 파일명 매핑 (공용 헬퍼)
  static String llmModelFileFor(String id) {
    switch (id) {
      case 'qwen25_7b':
        return AppConstants.llmModelFileQwen25_7B;
      case 'exaone35_7b':
        return AppBuildConfig.allowRestrictedModels
            ? AppConstants.llmModelFileExaone35_7B
            : AppConstants.llmModelFileGemma4E2B;
      case 'gemma4_e2b':
      default:
        return AppConstants.llmModelFileGemma4E2B;
    }
  }

  // ── 마이크 가이드 (v1.9.9+6) ──────────────────────────────────────
  /// 녹음 시작 시 "마이크 위치/거리" 가이드 팝업을 봤는지 여부.
  /// 1회성: 한 번 확인 후 다시 보이지 않는다. 설정에서 리셋 가능.
  bool get micGuideShown => _prefs.getBool('micGuideShown') ?? false;
  Future<void> setMicGuideShown(bool v) => _prefs.setBool('micGuideShown', v);

  /// 녹음 종료 후 macOS Calendar.app에 자동 이벤트 등록 여부 (opt-in).
  /// 첫 활성화 시 macOS가 자동화 권한을 요청한다.
  bool get autoAddToCalendar =>
      AppBuildConfig.enableCalendarIntegration &&
      (_prefs.getBool('autoAddToCalendar') ?? false);
  Future<void> setAutoAddToCalendar(bool v) => _prefs.setBool(
    'autoAddToCalendar',
    AppBuildConfig.enableCalendarIntegration && v,
  );

  // ── 발화자 라벨 (v1.9.9+4) ─────────────────────────────────────────
  /// 발화자 라벨 활성화 여부
  bool get diarizationEnabled => _prefs.getBool('diarizationEnabled') ?? false;
  Future<void> setDiarizationEnabled(bool v) =>
      _prefs.setBool('diarizationEnabled', v);

  /// 화자 수 힌트. 0 = auto (클러스터링 threshold 사용), 2~6 = 명시.
  int get numSpeakersHint => _prefs.getInt('numSpeakersHint') ?? 0;
  Future<void> setNumSpeakersHint(int v) => _prefs.setInt('numSpeakersHint', v);

  /// id → 다운로드 URL 매핑 (공용 헬퍼)
  static String llmDownloadUrlFor(String id) {
    switch (id) {
      case 'qwen25_7b':
        return AppConstants.llmDownloadUrlQwen25_7B;
      case 'exaone35_7b':
        return AppBuildConfig.allowRestrictedModels
            ? AppConstants.llmDownloadUrlExaone35_7B
            : AppConstants.llmDownloadUrlGemma4E2B;
      case 'gemma4_e2b':
      default:
        return AppConstants.llmDownloadUrlGemma4E2B;
    }
  }
}
