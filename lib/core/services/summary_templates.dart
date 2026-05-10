import 'app_settings.dart';

/// 요약 프롬프트 템플릿 프리셋
///
/// 분석 "지침"만 템플릿별로 다르게 하고, JSON 출력 스키마·파서 호환 키 목록·
/// glossary/notes/participants 주입은 SummaryParser.buildPrompt가 담당한다.
/// instruction은 단일 프롬프트와 긴 회의 map/reduce 양쪽에 주입된다.
class SummaryTemplate {
  final String id;
  final String name;
  final String description;
  final String instruction;

  const SummaryTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.instruction,
  });
}

class SummaryTemplates {
  SummaryTemplates._();

  static const String defaultId = 'general';

  /// 사용자 커스텀 슬롯 두 개 (가벼운 다중 프로필).
  /// 마이그레이션: 기존 'custom' 저장값은 AppSettings.init에서 'custom1'로 변경됨.
  static const String customId1 = 'custom1';
  static const String customId2 = 'custom2';

  /// 하위 호환 — 코드에서 SummaryTemplates.customId 를 참조하던 자리를
  /// 일괄 보강하기 전까지 customId1 으로 alias.
  static const String customId = customId1;

  static const SummaryTemplate general = SummaryTemplate(
    id: 'general',
    name: '일반 회의',
    description: '범용 회의록. 논의·결정·액션을 고르게 정리합니다.',
    instruction: '''
아래 한국어 업무 회의 전사본을 "실무자가 바로 공유할 수 있는 회의록"으로 분석하세요. JSON만 출력하고 설명 문장은 쓰지 마세요.

[일반 회의 요약 목표]
- meetingTitle: 회의의 실제 주제와 업무 맥락이 드러나는 제목. "회의 요약", "분석 불가" 같은 일반 제목 금지.
- keyDiscussions: 단순 주제명이 아니라 "주제 — 쟁점/대안/근거/우려" 형태로 구체적으로 작성.
- decisions: 실제로 합의·확정·방향 결정된 내용만 작성. 논의만 된 내용은 decisions에 넣지 않음.
- actionItems: 담당자나 기한이 명확하지 않아도 후속 조치라면 포함하고, owner/deadline이 불명확하면 "(미언급)" 사용.
- openQuestions: 결론이 나지 않았거나 추가 확인이 필요한 리스크·의존성·질문을 작성.

[우선순위]
1. 결정사항과 액션아이템을 누락하지 않는다.
2. 수치, 일정, 버전, 시스템명, 제품명, 회사명, 용어는 원문 그대로 보존한다.
3. 반복 발언과 잡담은 제거하고 업무상 의미가 있는 내용만 남긴다.

[좋은 항목 예시]
- keyDiscussions: "QA 일정 — 1차 일정은 7월 유지하되 개발 지연 시 조정 가능성이 논의됨"
- decisions: "게임 시작 시점은 CDN 다운로드 완료 후 첫 서버 통신 시점으로 정의"
- actionItems: {"task":"로그 스키마 초안 공유","owner":"화자 A","deadline":"(미언급)"}
''',
  );

  static const SummaryTemplate topicReport = SummaryTemplate(
    id: 'topic_report',
    name: '주제별 요약',
    description: '주제별로 재배치된 보고용 회의록. 명사형 개조식, 환각 방지 가드 포함.',
    instruction: '''
# Role
너는 IT 대기업의 수석 전략 기획자이자 전문 비서다. 난잡한 회의 전사본을 읽고,
비즈니스 맥락과 실무적 실행 방안이 완벽하게 정리된 회의록을 작성하는 것이 임무다.

# Task
제공된 한국어 업무 회의 전사본을 분석해 아래 JSON 스키마로만 출력하라.
설명 문장이나 마크다운은 일절 쓰지 말 것. JSON 외 텍스트 출력 금지.

[필드별 작성 지침]
- meetingTitle: 회의 명칭 + 핵심 안건이 보고서 톤으로 드러나는 한 줄.
- keyDiscussions[0]: 반드시 "가. 회의 개요 — {1~2문장으로 회의 명칭/주요 참석자 직함 추정/핵심 목적}".
- keyDiscussions[1..]: "나. {대주제명}" / "다. {대주제명}" 식으로 주제별 재배치.
  각 항목 본문은 "ㄴ {핵심 항목}: {1~2문장 — 우려 + 대안 + 근거}" 다중 줄로 작성.
  단순 시간순 나열 금지. 사업/개발/TPM/경영진 관점이 섞이면 주제별로 합칠 것.
- decisions: 회의에서 실제로 합의·확정·방향 결정된 내용만. 명사형 종결("~로 결정함", "~확정함", "~예정임").
- actionItems: 모든 후속 조치를 빠짐없이.
  - task: 동사로 시작하는 명확한 업무 ("~ 확인 및 공유", "~ 의사결정")
  - owner: 가능하면 역할 단위 ("TPM", "사업", "공통", "개발사", "PM"). 사람 이름이 명시되면 그대로.
    불명확하면 "(미언급)".
  - deadline: 명확한 시점이면 "2026-05-08 오전" 형태. 불명이면 "(미언급)".
- openQuestions: 회의 중 해결되지 않았거나 추후 리스크가 될 항목. "~ 확인 필요" / "~ 검토 필요" 종결.

[톤 & 스타일]
- 명사형 개조식 ("~함", "~임", "~예정임"). 구어체·존댓말 금지.
- 은어 → 비즈니스 용어 치환:
    "로그 뚫어놨다" → "로그 수집 경로 확보"
    "이것도 같이 본다" → "병행 검토"
    "한번 본다" → "검토함"
- 숫자, 일정, 시스템명(SDK, BI, MX, PID, S-log 등), 약어, 회사명, 팀명, UTC+8/UTC+9는 원문 그대로.
- 잡담·반복 발언·짧은 추임새는 무조건 제거.

[절대 금지 — 환각 방지]
- 본 instruction의 모든 예시(QA, RC 배포, API 문서, 화자 A, 빅쿼리, kofcn, NM, BI 등)는 형식 가이드일 뿐.
  본 회의 전사본에 명시적으로 등장하지 않은 결정/액션/담당자/일정/이슈를 만들어 추가하지 말 것.
- 의심스러우면 항목을 빼는 것이 지어내는 것보다 낫다.
- 전사본에 owner 이름이 등장하지 않으면 owner는 반드시 "(미언급)" 또는 역할명("TPM" 등 회의에서 실제 언급된 역할만).
''',
  );

  static const SummaryTemplate lecture = SummaryTemplate(
    id: 'lecture',
    name: '강의/세미나',
    description: '강의·세미나 전사본을 지식 정리 + 인사이트 + 액션으로 구조화합니다.',
    instruction: '''
# Role
너는 지식 큐레이터이자 비즈니스 전략 분석가다. 방대한 양의 강의/세미나 전사본을 분석하여,
핵심 지식은 체계적으로 정리하고 실무에 적용할 인사이트를 날카롭게 뽑아내는 것이 임무다.

# Task
제공된 한국어 강의/세미나 전사본을 분석해 아래 JSON 스키마로만 출력하라.
설명 문장이나 마크다운은 일절 쓰지 말 것. JSON 외 텍스트 출력 금지.

[필드별 작성 지침]
- meetingTitle: 강의/세미나의 실제 주제. 발표자나 소속이 명시되면 함께 반영
  (예: "데이터 거버넌스 입문 — 김지표 강사", "OO 컨퍼런스 키노트").

- keyDiscussions[0]: 반드시 "가. 지식 테마 — {전체를 관통하는 주제 한 문장}".
  본문은 다중 줄 허용 — "ㄴ 대상 독자: {누가 들으면 좋은가}\\nㄴ 학습 목표: {3줄 이내}".

- keyDiscussions[1..N-1]: "나. {커리큘럼 섹션명}" / "다. {커리큘럼 섹션명}" 식으로
  강의 흐름을 논리적 섹션으로 분할. 각 섹션 본문은
  "ㄴ {핵심 항목}: {1~2문장 — 수치/사례/근거 포함}" 다중 줄.
  강사가 강조한 '골든 룰' 또는 '핵심 원칙'은
  "ㄴ ★ 골든 룰: {원칙 문장}" 형태로 별도 강조.

- keyDiscussions[N] (마지막 항목): "X. 용어 사전" 섹션.
  "ㄴ {term}: {정의}" 형태로 강의에서 등장한 기술 용어/약어/고유명사 정리.
  문맥상 명백한 오타가 있으면 올바른 용어로 교정해 사전에 기록 (단, 강의에 등장한 용어만).

- decisions: 강사가 강조한 "핵심 시사점 / Key Takeaway / 우리가 주목해야 할 점" 3~5개.
  단순 요약이 아니라 "~이 중요함", "~로 해석됨", "~가 시사점으로 도출됨" 등 분석 톤의 명사형 종결.

- actionItems: 강의 내용을 바탕으로 시청자/실무자가 즉시 실행해볼 수 있는 액션 제안.
  - task: 동사로 시작 ("~ 도입 검토", "~ 자료 정리 후 팀 공유", "~ 적용 사례 조사").
  - owner: 강의에 명시된 대상이 있으면 그 역할. 없으면 "(시청자)" 또는 "(미언급)".
  - deadline: 강의에서 권장한 시점이 있으면 그대로. 없으면 "(미언급)".

- openQuestions: 더 깊은 이해를 위한 Self-Reflection 질문 2~3개.
  의문형 종결 허용 ("~인가?", "~를 어떻게 적용할 것인가?", "~의 한계는 무엇인가?").

[톤 & 스타일]
- 명사형 개조식 ("~함", "~임", "~예정임"). 구어체·존댓말 금지.
  단, openQuestions 의 Self-Reflection 질문은 의문형 종결("~인가?") 허용.
- 강사의 구어체("자, 그러면…", "이게 사실 좀…")는 문어체로 정제.
  은어·축약·말 흐름은 정확한 비즈니스 용어로 치환.
- 수치, 통계, 연구/사례명, 시스템명, 약어, 회사명, 인용된 책/논문은 원문 그대로 보존.
- 잡담·반복 발언·짧은 추임새("네", "어", "음", "그") 무조건 제거.

[절대 금지 — 환각 방지]
- 본 instruction의 모든 예시(데이터 거버넌스, 김지표, OO 컨퍼런스 등)는 형식 가이드일 뿐.
  본 강의 전사본에 명시적으로 등장하지 않은 사례·수치·인용·용어를 만들어 추가하지 말 것.
- 의심스러우면 항목을 빼는 것이 지어내는 것보다 낫다.
- 용어 사전에 강의에서 언급되지 않은 일반 상식 용어를 추가하지 말 것 — 강의 내 등장 용어만.
- Self-Reflection 질문은 강의 내용과 명확히 연결되어야 함. 일반론 질문 금지.
''',
  );

  static const List<SummaryTemplate> presets = [general, topicReport, lecture];

  static SummaryTemplate byId(String id) {
    for (final t in presets) {
      if (t.id == id) return t;
    }
    return general;
  }

  /// 커스텀 편집 시 기본값 (general 지침을 시작점으로)
  static String get defaultCustomInstruction => general.instruction;

  /// 현재 적용될 instruction 문자열을 조회.
  /// [overrideId] 가 주어지면 전역 설정을 무시하고 해당 프리셋 사용.
  /// custom1/custom2 인 경우 AppSettings 의 해당 슬롯 instruction 사용 (회의별 커스텀은 지원 안 함).
  /// 슬롯이 비어있으면 general 로 폴백.
  /// [styleMode] 가 standard 가 아니면 modifier 지침을 instruction 뒤에 붙임.
  static String resolveInstruction({
    String? overrideId,
    SummaryStyleMode styleMode = SummaryStyleMode.standard,
  }) {
    final settings = AppSettings.instance;
    final id = overrideId ?? settings.summaryTemplateId;
    String base;
    if (id == customId1) {
      final custom = settings.customSummaryInstruction1.trim();
      base = custom.isNotEmpty ? custom : general.instruction;
    } else if (id == customId2) {
      final custom = settings.customSummaryInstruction2.trim();
      base = custom.isNotEmpty ? custom : general.instruction;
    } else {
      base = byId(id).instruction;
    }
    final modifier = styleMode.modifier;
    if (modifier.isEmpty) return base;
    return '$base\n\n$modifier';
  }
}

/// 재요약 시 같은 전사본을 다른 스타일로 다시 분석하기 위한 modifier.
/// 회의 유형(general/topic_report/custom1/custom2) 위에 누적 적용된다.
enum SummaryStyleMode {
  /// 회의 유형 그대로 (기본). modifier 없음.
  standard,

  /// 더 자세히 — 맥락/근거/대안까지 길게.
  detailed,

  /// 더 간결하게 — 핵심만.
  concise,

  /// 액션아이템 중심 — 결정/할 일/마감 위주.
  actionFocused,

  /// 임원 보고용 — 1페이지 요약, 우선순위/리스크 강조.
  executive,
}

extension SummaryStyleModeX on SummaryStyleMode {
  String get id => switch (this) {
    SummaryStyleMode.standard => 'standard',
    SummaryStyleMode.detailed => 'detailed',
    SummaryStyleMode.concise => 'concise',
    SummaryStyleMode.actionFocused => 'action_focused',
    SummaryStyleMode.executive => 'executive',
  };

  String get displayName => switch (this) {
    SummaryStyleMode.standard => '기본',
    SummaryStyleMode.detailed => '더 자세히',
    SummaryStyleMode.concise => '더 간결하게',
    SummaryStyleMode.actionFocused => '액션아이템 중심',
    SummaryStyleMode.executive => '임원 보고용',
  };

  String get description => switch (this) {
    SummaryStyleMode.standard => '회의 유형 기본 지침을 그대로 적용합니다.',
    SummaryStyleMode.detailed => '맥락·대안·근거·우려까지 항목당 1~2문장 더 길게 작성합니다.',
    SummaryStyleMode.concise => '한 줄 단위로 핵심만 남기고 부연 설명을 제거합니다.',
    SummaryStyleMode.actionFocused => '결정사항·액션아이템·마감을 우선 추출하고, 논의 내용은 짧게.',
    SummaryStyleMode.executive => '임원 보고 1페이지 — 핵심 결정/리스크/투자/일정 영향 중심.',
  };

  /// 회의 유형 instruction 뒤에 누적되는 추가 지침.
  /// 빈 문자열이면 base instruction을 그대로 사용한다.
  String get modifier => switch (this) {
    SummaryStyleMode.standard => '',
    SummaryStyleMode.detailed =>
      '''
[재요약 스타일: 더 자세히]
- keyDiscussions, decisions, openQuestions를 한 항목당 2~3문장으로 작성.
- 각 항목에 "왜 그런 결정/논의가 나왔는지" 근거나 대안을 함께 남길 것.
- actionItems는 task 한 줄 + (배경) 1줄 형태로, 담당자가 보고 바로 이해할 수 있게.
- 단, 전사본에 없는 내용을 추측해 추가하지 말 것.
''',
    SummaryStyleMode.concise =>
      '''
[재요약 스타일: 더 간결하게]
- keyDiscussions: 항목당 한 줄(40자 이내). 형용사·부연 제거.
- decisions: 결정 동작만 남길 것 — "X를 Y로 변경", "Z 일정 확정" 식.
- actionItems: task는 동사로 시작, 30자 이내. 부연은 빼고 핵심만.
- openQuestions: 질문 한 줄.
- 가능하면 전체 항목 수를 줄여 핵심만 남길 것.
''',
    SummaryStyleMode.actionFocused =>
      '''
[재요약 스타일: 액션아이템 중심]
- decisions와 actionItems 우선 추출. 누락 절대 금지.
- keyDiscussions는 결정/액션과 직접 연결된 핵심 논의 3~5개로 축소.
- actionItems의 owner/deadline이 전사본에 등장하면 반드시 채워 넣을 것 ("(미언급)" 남발 금지).
- openQuestions는 결정에 필요한 미해결 질문만.
- 단순 정보 공유나 잡담성 발언은 모두 제외.
''',
    SummaryStyleMode.executive =>
      '''
[재요약 스타일: 임원 보고용]
- 임원이 1분 안에 읽을 수 있도록 작성.
- meetingTitle: 보고 주제와 의사결정 안건이 드러나도록.
- keyDiscussions: 3~5개. 핵심 의사결정/리스크/투자/일정 영향 중심.
- decisions: 비즈니스/제품 영향이 있는 결정만 남기고, 영향 범위(예: "전사 영향", "팀 단위")를 한 줄에 포함.
- actionItems: 임원 차원에서 추적할 만한 항목만. 세부 실무 태스크는 제외.
- openQuestions: 의사결정자(임원)가 알아야 할 미해결 리스크나 추가 의사결정 필요 항목만.
- 형용사·미사여구 제거. 보고서 톤 유지.
''',
  };
}
