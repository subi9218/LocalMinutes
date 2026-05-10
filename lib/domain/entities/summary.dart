import 'package:isar/isar.dart';

part 'summary.g.dart';

// 피크 메모리: Gemma 4 추론 중 ~7–9 GB (Q8_0 모델 ~6–8 GB + KV 캐시 ~1 GB @ n_ctx=8192)
// 저장 후 모델 즉시 언로드 → 메모리 반환

@collection
class Summary {
  Id id = Isar.autoIncrement;

  /// 소속 회의 ID (Meeting.id), 회의당 요약 1개
  @Index(unique: true)
  late int meetingId;

  // ── Gemma 4 JSON 출력 스키마 필드 ──────────────────────────
  late String meetingTitle;
  late DateTime meetingDate;

  /// 참석자 목록 (화자 식별 또는 수동 입력)
  late List<String> participants;

  /// 주요 논의 사항
  late List<String> keyDiscussions;

  /// 결정 사항
  late List<String> decisions;

  /// 액션 아이템 JSON 문자열
  /// 스키마: [{"task":"...", "owner":"...", "deadline":"..."}]
  /// Isar는 중첩 객체 리스트를 지원하지 않으므로 JSON 직렬화 저장
  late String actionItemsJson;

  /// 미해결 이슈
  late List<String> openQuestions;

  /// 요약 항목별 LLM-명시 근거 타임스탬프 JSON (v2 신뢰도 표시).
  /// 스키마: {
  ///   "keyDiscussions":["02:55","03:14",""],   // 빈 문자열 = LLM이 근거 명시 못 함 → "확인 필요" 표시
  ///   "decisions":["..."],
  ///   "openQuestions":["..."],
  ///   "actionItems":["..."]
  /// }
  /// 각 배열은 동일 인덱스의 main 배열 항목과 1:1 매칭.
  /// 비어있거나 누락 시 v1 키워드/유사도 매칭으로 폴백.
  String evidenceJson = '{}';

  late DateTime createdAt;
}

/// 요약 항목의 LLM-명시 근거 타임스탬프 (v2)
class SummaryEvidence {
  final List<String> keyDiscussions;
  final List<String> decisions;
  final List<String> openQuestions;
  final List<String> actionItems;

  const SummaryEvidence({
    this.keyDiscussions = const [],
    this.decisions = const [],
    this.openQuestions = const [],
    this.actionItems = const [],
  });

  /// "02:55" 또는 "02:55-03:24" 형식 → 시작 초 (double).
  /// 파싱 실패 시 null.
  static double? parseStartSec(String ts) {
    if (ts.trim().isEmpty) return null;
    final clean = ts.split('-').first.trim().replaceAll(RegExp(r'[\[\]]'), '');
    final parts = clean.split(':');
    try {
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60.0 + int.parse(parts[1]);
      }
      if (parts.length == 3) {
        return int.parse(parts[0]) * 3600.0 +
            int.parse(parts[1]) * 60.0 +
            int.parse(parts[2]);
      }
    } catch (_) {}
    return null;
  }
}

/// actionItemsJson 파싱용 헬퍼 클래스 (Isar 저장 불필요, 런타임 전용)
class ActionItem {
  final String task;
  final String owner;
  final String deadline;
  final bool completed;
  final bool ownerConfirmed;
  final bool deadlineConfirmed;

  const ActionItem({
    required this.task,
    required this.owner,
    required this.deadline,
    this.completed = false,
    this.ownerConfirmed = true,
    this.deadlineConfirmed = true,
  });

  bool get ownerNeedsConfirmation => !ownerConfirmed || _isUnconfirmed(owner);
  bool get deadlineNeedsConfirmation =>
      !deadlineConfirmed || _isUnconfirmed(deadline);

  ActionItem copyWith({
    bool? completed,
    bool? ownerConfirmed,
    bool? deadlineConfirmed,
  }) => ActionItem(
    task: task,
    owner: owner,
    deadline: deadline,
    completed: completed ?? this.completed,
    ownerConfirmed: ownerConfirmed ?? this.ownerConfirmed,
    deadlineConfirmed: deadlineConfirmed ?? this.deadlineConfirmed,
  );

  factory ActionItem.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'] as String? ?? '';
    final deadline = json['deadline'] as String? ?? '';
    return ActionItem(
      task: json['task'] as String? ?? '',
      owner: owner,
      deadline: deadline,
      completed: json['completed'] as bool? ?? false,
      ownerConfirmed: json['ownerConfirmed'] as bool? ?? !_isUnconfirmed(owner),
      deadlineConfirmed:
          json['deadlineConfirmed'] as bool? ?? !_isUnconfirmed(deadline),
    );
  }

  Map<String, dynamic> toJson() => {
    'task': task,
    'owner': owner,
    'deadline': deadline,
    'completed': completed,
    'ownerConfirmed': ownerConfirmed,
    'deadlineConfirmed': deadlineConfirmed,
  };

  static bool _isUnconfirmed(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return true;
    return {
      '(미언급)',
      '미언급',
      '미정',
      '없음',
      'n/a',
      'na',
      'unknown',
      'unassigned',
      'tbd',
      '-',
    }.contains(v);
  }
}
