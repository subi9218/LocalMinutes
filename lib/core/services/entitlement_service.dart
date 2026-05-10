import 'package:shared_preferences/shared_preferences.dart';

/// 사용자 구독 등급. 결제 통합 전에는 모두 [EntitlementTier.pro] 로 hardcoded.
enum EntitlementTier {
  /// 무료 — 출시 후 결제 통합 시 적용. 현재는 사용 안 함.
  free,

  /// 무료 체험 — 14일.
  trialing,

  /// 유료 구독 (월/연).
  pro,
}

/// 게이트 결정 결과. 차단된 경우 [PaywallTrigger] 로 페이월 다이얼로그를 띄울 이유를 포함.
class EntitlementDecision {
  final bool allowed;
  final PaywallTrigger? trigger;

  const EntitlementDecision._({required this.allowed, this.trigger});

  factory EntitlementDecision.allowed() =>
      const EntitlementDecision._(allowed: true);
  factory EntitlementDecision.blocked(PaywallTrigger reason) =>
      EntitlementDecision._(allowed: false, trigger: reason);
}

/// 게이트가 차단됐을 때 페이월 다이얼로그가 받을 트리거 이유.
/// UI 측에서 "왜 막혔는지" 사용자에게 명확히 보여주는 데 사용.
enum PaywallTrigger {
  /// 월 무료 회의 횟수(기본 3회) 초과.
  monthlyMeetingLimit,

  /// 회의당 시간 제한(기본 30분) 초과.
  meetingDurationLimit,

  /// 정확 음성 인식 모델은 Pro 만.
  accurateSttMode,

  /// 내보내기에서 워터마크 제거는 Pro 만.
  exportWithoutWatermark,

  /// 재생성 스타일·임원 보고용 등 고급 요약은 Pro 만.
  advancedSummary,

  /// 단어집 11개 이상 등록은 Pro 만.
  glossarySize,
}

/// 무료/유료 게이트 결정. 결제 인프라(RevenueCat 등) 통합 전에는
/// 인터페이스만 잡고 모든 게이트가 [EntitlementDecision.allowed] 를 반환한다.
///
/// 출시 시:
///   1. [currentTier] 를 SharedPreferences + 결제 SDK 의 영수증에서 결정
///   2. 각 게이트 메서드 안의 hardcoded `true` 를 실제 정책 (월 3회 / 30분 / Pro 잠금 등)으로 교체
///   3. 호출처는 그대로 유지 — 인터페이스가 동일하므로
class EntitlementService {
  EntitlementService._(this._prefs);

  static EntitlementService? _instance;

  static EntitlementService get instance {
    assert(_instance != null, 'EntitlementService.init() 을 main() 에서 먼저 호출하세요');
    return _instance!;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _instance = EntitlementService._(prefs);
  }

  final SharedPreferences _prefs;

  // ── 정책 한도 (출시 시 RevenueCat / 원격 설정에서 동적 가져올 수 있음) ─────
  /// 무료 사용자 월 회의 시작 제한.
  static const int freeMonthlyMeetingLimit = 3;

  /// 무료 사용자 회의당 시간 제한 (분).
  static const int freeMeetingDurationLimitMinutes = 30;

  /// 무료 사용자 단어집 최대 항목 수.
  static const int freeGlossaryLimit = 10;

  // ── 사용자 등급 ──────────────────────────────────────────────────
  /// 현재 등급. 결제 통합 전에는 항상 [EntitlementTier.pro].
  /// 출시 후엔 SharedPreferences + 결제 SDK 검증 결과에서 읽음.
  EntitlementTier get currentTier {
    // 출시 전 hardcoded — Phase 4(결제 통합)에서 SharedPreferences 키로 교체.
    return EntitlementTier.pro;
  }

  /// Pro / 체험 중인지 (= 모든 기능 잠금 해제 상태).
  bool get isUnlocked =>
      currentTier == EntitlementTier.pro ||
      currentTier == EntitlementTier.trialing;

  // ── 사용량 카운터 (출시 후 활용) ─────────────────────────────────
  /// 이번 달 사용자가 시작한 회의 수. 매월 1일에 자동 reset.
  /// (현재는 trial/pro 라 게이트가 차단하지 않지만, 키를 미리 트래킹해두면
  /// 출시 시점에 free tier 사용자에게 즉시 정확한 잔여 회수 표시 가능.)
  int get currentMonthMeetingCount {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final savedKey = _prefs.getString('_meetingCount.month');
    if (savedKey != monthKey) {
      // 다른 달 키 → reset 신호. 실제 reset 은 increment 시점에 처리.
      return 0;
    }
    return _prefs.getInt('_meetingCount.count') ?? 0;
  }

  /// 회의 시작 시 카운트 +1. 월이 바뀌면 1로 reset.
  Future<void> incrementMonthMeetingCount() async {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final savedKey = _prefs.getString('_meetingCount.month');
    final newCount = savedKey == monthKey
        ? (_prefs.getInt('_meetingCount.count') ?? 0) + 1
        : 1;
    await _prefs.setString('_meetingCount.month', monthKey);
    await _prefs.setInt('_meetingCount.count', newCount);
  }

  // ── 게이트 ─────────────────────────────────────────────────────
  /// 새 회의 시작 가능?
  /// Pro/trialing: 항상 허용. Free: 월 [freeMonthlyMeetingLimit] 회까지.
  EntitlementDecision canStartMeeting() {
    if (isUnlocked) return EntitlementDecision.allowed();
    if (currentMonthMeetingCount >= freeMonthlyMeetingLimit) {
      return EntitlementDecision.blocked(PaywallTrigger.monthlyMeetingLimit);
    }
    return EntitlementDecision.allowed();
  }

  /// 녹음 [elapsedMinutes] 분 경과 시점에 계속 진행 가능?
  /// Pro/trialing: 항상 허용. Free: [freeMeetingDurationLimitMinutes] 분까지.
  EntitlementDecision canContinueRecording(int elapsedMinutes) {
    if (isUnlocked) return EntitlementDecision.allowed();
    if (elapsedMinutes >= freeMeetingDurationLimitMinutes) {
      return EntitlementDecision.blocked(PaywallTrigger.meetingDurationLimit);
    }
    return EntitlementDecision.allowed();
  }

  /// 정확 음성 인식 모드(Whisper Large V3 Q5) 사용 가능?
  /// Pro/trialing: 항상 허용. Free: 항상 차단.
  EntitlementDecision canUseAccurateMode() {
    if (isUnlocked) return EntitlementDecision.allowed();
    return EntitlementDecision.blocked(PaywallTrigger.accurateSttMode);
  }

  /// 내보내기에서 적자생존 워터마크 제거 가능?
  /// Pro/trialing: 항상 허용. Free: 차단 → 워터마크 포함 export.
  EntitlementDecision canExportWithoutWatermark() {
    if (isUnlocked) return EntitlementDecision.allowed();
    return EntitlementDecision.blocked(PaywallTrigger.exportWithoutWatermark);
  }

  /// 고급 요약 (재생성 스타일, 주제별 보고 등) 사용 가능?
  /// Pro/trialing: 항상 허용. Free: 차단 → 일반 요약만.
  EntitlementDecision canUseAdvancedSummary() {
    if (isUnlocked) return EntitlementDecision.allowed();
    return EntitlementDecision.blocked(PaywallTrigger.advancedSummary);
  }

  /// 단어집에 새 항목 등록 가능? Pro/trialing: 무제한, Free: [freeGlossaryLimit] 까지.
  EntitlementDecision canAddGlossaryEntry(int currentCount) {
    if (isUnlocked) return EntitlementDecision.allowed();
    if (currentCount >= freeGlossaryLimit) {
      return EntitlementDecision.blocked(PaywallTrigger.glossarySize);
    }
    return EntitlementDecision.allowed();
  }

  // ── 사용자 표시용 헬퍼 ──────────────────────────────────────────
  /// 무료 사용자에게 잔여 회의 횟수 표시용. Pro 면 null.
  int? get remainingFreeMeetingsThisMonth {
    if (isUnlocked) return null;
    final used = currentMonthMeetingCount;
    final remaining = freeMonthlyMeetingLimit - used;
    return remaining < 0 ? 0 : remaining;
  }
}

/// 페이월 트리거를 사용자 친화 한국어 메시지로.
/// PaywallScreen / 다이얼로그가 표시.
extension PaywallTriggerLabel on PaywallTrigger {
  String get title => switch (this) {
    PaywallTrigger.monthlyMeetingLimit => '이번 달 무료 회의를 모두 사용하셨습니다',
    PaywallTrigger.meetingDurationLimit => '무료 회의 시간 제한에 도달했습니다',
    PaywallTrigger.accurateSttMode => '정확 음성 인식 모드는 Pro 기능입니다',
    PaywallTrigger.exportWithoutWatermark => '워터마크 없이 내보내기는 Pro 기능입니다',
    PaywallTrigger.advancedSummary => '고급 요약·재생성 스타일은 Pro 기능입니다',
    PaywallTrigger.glossarySize => '단어집 무제한 등록은 Pro 기능입니다',
  };

  String get description => switch (this) {
    PaywallTrigger.monthlyMeetingLimit => 'Pro 로 업그레이드하면 월 무제한 회의를 녹음할 수 있습니다.',
    PaywallTrigger.meetingDurationLimit =>
      'Pro 는 회의 시간 제한이 없습니다. 14일 무료 체험으로 시작해 보세요.',
    PaywallTrigger.accurateSttMode => '정확 모델은 무료보다 인식 정확도가 높지만 처리 시간이 더 걸립니다.',
    PaywallTrigger.exportWithoutWatermark =>
      'Pro 는 PDF/DOCX 내보내기에 워터마크 없이 깔끔한 보고서를 제공합니다.',
    PaywallTrigger.advancedSummary =>
      '재생성 스타일(더 자세히/임원 보고용 등)과 주제별 보고서는 Pro 전용입니다.',
    PaywallTrigger.glossarySize => '회사 전용 용어를 무제한으로 등록해 자동 교정에 활용할 수 있습니다.',
  };
}
