import 'dart:convert';

import '../../domain/entities/meeting.dart';
import '../../domain/entities/summary.dart';

/// 같은 시리즈의 두 회의를 비교 (P2 업무 흐름).
///
/// LLM 추가 호출 없이 저장된 [Summary] 의 keyDiscussions/decisions/openQuestions/actionItems만 사용.
/// 매칭은 `_roughlySame` 부분 일치(8자 이상에서 한쪽이 다른 쪽을 포함)로
/// `MeetingSeriesProgress` 와 동일 규칙. 짧은 텍스트는 정확 일치.
///
/// 두 회의는 시간순으로 [earlier] (이전) → [later] (이후) 로 전달한다.
class MeetingComparison {
  MeetingComparison._();

  static MeetingComparisonReport compare({
    required Meeting earlier,
    required Meeting later,
    required Summary? earlierSummary,
    required Summary? laterSummary,
  }) {
    return MeetingComparisonReport(
      earlier: earlier,
      later: later,
      keyDiscussions: _diffStrings(
        earlierSummary?.keyDiscussions ?? const [],
        laterSummary?.keyDiscussions ?? const [],
      ),
      decisions: _diffStrings(
        earlierSummary?.decisions ?? const [],
        laterSummary?.decisions ?? const [],
      ),
      openQuestions: _diffStrings(
        earlierSummary?.openQuestions ?? const [],
        laterSummary?.openQuestions ?? const [],
      ),
      actions: _diffActions(
        _parseActions(earlierSummary?.actionItemsJson ?? ''),
        _parseActions(laterSummary?.actionItemsJson ?? ''),
      ),
    );
  }

  // ── string-list diff ─────────────────────────────────────────────
  static StringDiff _diffStrings(List<String> a, List<String> b) {
    final cleanA = a.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final cleanB = b.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final usedB = List<bool>.filled(cleanB.length, false);
    final shared = <SharedString>[];
    final removed = <String>[];

    for (final ai in cleanA) {
      final keyA = _normKey(ai);
      var matchedIdx = -1;
      for (var j = 0; j < cleanB.length; j++) {
        if (usedB[j]) continue;
        if (_roughlySame(keyA, _normKey(cleanB[j]))) {
          matchedIdx = j;
          break;
        }
      }
      if (matchedIdx == -1) {
        removed.add(ai);
      } else {
        usedB[matchedIdx] = true;
        // 더 긴 표현이 더 정보가 많다고 가정
        final longer = cleanB[matchedIdx].length >= ai.length
            ? cleanB[matchedIdx]
            : ai;
        shared.add(SharedString(text: longer));
      }
    }
    final added = <String>[];
    for (var j = 0; j < cleanB.length; j++) {
      if (!usedB[j]) added.add(cleanB[j]);
    }
    return StringDiff(
      added: List.unmodifiable(added),
      removed: List.unmodifiable(removed),
      shared: List.unmodifiable(shared),
    );
  }

  // ── action diff ──────────────────────────────────────────────────
  static ActionDiff _diffActions(List<ActionItem> a, List<ActionItem> b) {
    final usedB = List<bool>.filled(b.length, false);
    final shared = <SharedAction>[];
    final removed = <ActionItem>[];

    for (final ai in a) {
      if (ai.task.trim().isEmpty) continue;
      final keyA = _normKey(ai.task);
      var matchedIdx = -1;
      for (var j = 0; j < b.length; j++) {
        if (usedB[j]) continue;
        if (b[j].task.trim().isEmpty) continue;
        if (_roughlySame(keyA, _normKey(b[j].task))) {
          matchedIdx = j;
          break;
        }
      }
      if (matchedIdx == -1) {
        removed.add(ai);
      } else {
        usedB[matchedIdx] = true;
        shared.add(_buildSharedAction(ai, b[matchedIdx]));
      }
    }
    final added = <ActionItem>[];
    for (var j = 0; j < b.length; j++) {
      if (!usedB[j] && b[j].task.trim().isEmpty == false) added.add(b[j]);
    }
    return ActionDiff(
      added: List.unmodifiable(added),
      removed: List.unmodifiable(removed),
      shared: List.unmodifiable(shared),
    );
  }

  static SharedAction _buildSharedAction(ActionItem a, ActionItem b) {
    ActionTransition status;
    if (!a.completed && b.completed) {
      status = ActionTransition.completed;
    } else if (a.completed && !b.completed) {
      status = ActionTransition.reopened;
    } else if (a.completed && b.completed) {
      status = ActionTransition.stillCompleted;
    } else {
      status = ActionTransition.stillOpen;
    }
    final ownerChanged =
        a.owner.trim() != b.owner.trim() &&
        a.owner.trim().isNotEmpty &&
        b.owner.trim().isNotEmpty;
    final deadlineChanged =
        a.deadline.trim() != b.deadline.trim() &&
        a.deadline.trim().isNotEmpty &&
        b.deadline.trim().isNotEmpty;
    return SharedAction(
      earlier: a,
      later: b,
      status: status,
      ownerChanged: ownerChanged,
      deadlineChanged: deadlineChanged,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────
  static List<ActionItem> _parseActions(String json) {
    if (json.trim().isEmpty) return const [];
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ActionItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _normKey(String s) => s.toLowerCase().replaceAll(
    RegExp(r'[\s·.,·、。,!?~\-–—\[\]\(\)\{\}:;"]+'),
    '',
  );

  static bool _roughlySame(String na, String nb) {
    if (na.isEmpty || nb.isEmpty) return na == nb;
    if (na == nb) return true;
    if (na.length >= 8 && nb.length >= 8) {
      if (na.contains(nb) || nb.contains(na)) return true;
    }
    return false;
  }
}

class MeetingComparisonReport {
  final Meeting earlier;
  final Meeting later;
  final StringDiff keyDiscussions;
  final StringDiff decisions;
  final StringDiff openQuestions;
  final ActionDiff actions;

  const MeetingComparisonReport({
    required this.earlier,
    required this.later,
    required this.keyDiscussions,
    required this.decisions,
    required this.openQuestions,
    required this.actions,
  });

  /// 사용자에게 의미 있는 변화가 있는지 — 빈 비교(둘 다 비어있음) 판정용.
  bool get hasContent =>
      keyDiscussions.hasContent ||
      decisions.hasContent ||
      openQuestions.hasContent ||
      actions.hasContent;
}

class StringDiff {
  /// later 회의에만 있는 항목 (새로 등장)
  final List<String> added;

  /// earlier 회의에만 있는 항목 (이후 회의에서 사라짐)
  final List<String> removed;

  /// 양쪽 회의에 모두 있는 항목 (대표 텍스트 보존)
  final List<SharedString> shared;

  const StringDiff({
    required this.added,
    required this.removed,
    required this.shared,
  });

  bool get hasContent =>
      added.isNotEmpty || removed.isNotEmpty || shared.isNotEmpty;
}

class SharedString {
  final String text;
  const SharedString({required this.text});
}

class ActionDiff {
  final List<ActionItem> added;
  final List<ActionItem> removed;
  final List<SharedAction> shared;

  const ActionDiff({
    required this.added,
    required this.removed,
    required this.shared,
  });

  bool get hasContent =>
      added.isNotEmpty || removed.isNotEmpty || shared.isNotEmpty;
}

class SharedAction {
  final ActionItem earlier;
  final ActionItem later;
  final ActionTransition status;
  final bool ownerChanged;
  final bool deadlineChanged;

  const SharedAction({
    required this.earlier,
    required this.later,
    required this.status,
    required this.ownerChanged,
    required this.deadlineChanged,
  });

  bool get hasMetaChange => ownerChanged || deadlineChanged;
}

enum ActionTransition {
  /// earlier 미완료 → later 완료 (가장 흥미로운 변화)
  completed,

  /// earlier 완료 → later 미완료 (재오픈)
  reopened,

  /// 양쪽 미완료 (지속 중)
  stillOpen,

  /// 양쪽 완료 (이미 완료된 상태로 재등장)
  stillCompleted,
}
