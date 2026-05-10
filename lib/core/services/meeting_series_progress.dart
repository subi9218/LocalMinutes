import 'dart:convert';

import '../../domain/entities/meeting.dart';
import '../../domain/entities/summary.dart';
import '../../domain/repositories/meeting_repository.dart';

/// 정기 회의 시리즈 진행 분석 (P2 #9)
///
/// 같은 그룹에 묶인 회의들을 가로로 보고
///   - 평균 주기 / 마지막 회의
///   - 누적 미완료 액션아이템 (담당자별)
///   - 최근 결정 사항
///   - 여러 회에 걸쳐 반복 등장한 미해결 이슈
/// 를 한 번에 추출한다.
///
/// LLM을 추가로 호출하지 않는다 — 이미 저장된 Summary를 그대로 활용.
class MeetingSeriesProgress {
  MeetingSeriesProgress._();

  /// [groupId] 회의들을 분석해 [SeriesProgressReport] 반환.
  /// 회의가 없으면 [SeriesProgressReport.empty()].
  static Future<SeriesProgressReport> analyze({
    required int groupId,
    required MeetingRepository meetingRepo,
    required SummaryRepository summaryRepo,
    int recentDecisionsLimit = 5,
    int recurringIssueMinAppearances = 2,
  }) async {
    final meetings = await meetingRepo.getMeetingsByGroupId(groupId);
    if (meetings.isEmpty) return SeriesProgressReport.empty();

    // 최신 → 과거 순으로 정렬되어 있다고 가정 (sortByCreatedAtDesc).
    // 통계용으로 옛날 → 최신 순 정렬도 준비.
    final byOldFirst = [...meetings]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // ── 평균 주기 ──────────────────────────────────────────────
    int? avgIntervalDays;
    if (byOldFirst.length >= 2) {
      var sum = 0;
      for (var i = 1; i < byOldFirst.length; i++) {
        sum += byOldFirst[i].createdAt
            .difference(byOldFirst[i - 1].createdAt)
            .inDays;
      }
      avgIntervalDays = (sum / (byOldFirst.length - 1)).round();
    }

    // ── 회의별 요약 로드 ───────────────────────────────────────
    final summaries = <int, Summary>{};
    for (final m in meetings) {
      final s = await summaryRepo.getSummaryByMeetingId(m.id);
      if (s != null) summaries[m.id] = s;
    }

    // ── 누적 미완료 액션 ───────────────────────────────────────
    final pendingActions = <PendingActionItem>[];
    for (final m in meetings) {
      final s = summaries[m.id];
      if (s == null) continue;
      final items = _parseActionItems(s.actionItemsJson);
      for (final it in items) {
        if (it.completed) continue;
        if (it.task.trim().isEmpty) continue;
        pendingActions.add(
          PendingActionItem(
            meetingId: m.id,
            meetingTitle: m.title,
            meetingDate: m.createdAt,
            item: it,
          ),
        );
      }
    }

    // ── 최근 결정 사항 ─────────────────────────────────────────
    final recentDecisions = <RecentDecision>[];
    for (final m in meetings) {
      if (recentDecisions.length >= recentDecisionsLimit) break;
      final s = summaries[m.id];
      if (s == null) continue;
      for (final text in s.decisions) {
        if (text.trim().isEmpty) continue;
        recentDecisions.add(
          RecentDecision(
            meetingId: m.id,
            meetingTitle: m.title,
            meetingDate: m.createdAt,
            text: text,
          ),
        );
        if (recentDecisions.length >= recentDecisionsLimit) break;
      }
    }

    // ── 반복 등장 미해결 이슈 ──────────────────────────────────
    // 같은 이슈가 여러 회에 등장하면 "지속 이슈"로 표시한다.
    // 한국어 부분 일치(8자 이상에서 한쪽이 다른 쪽을 포함)도 같은 이슈로 묶는다.
    // 예: "QA 인력 확보 필요" ↔ "QA 인력 확보 여부 확인 필요" → 같은 이슈
    final buckets = <_IssueBucket>[];
    for (final m in meetings) {
      final s = summaries[m.id];
      if (s == null) continue;
      // 같은 회의 안에서 같은 이슈를 두 번 카운트하지 않기 위해 회의별 처리한 bucket을 추적.
      final seenInThisMeeting = <_IssueBucket>{};
      for (final raw in s.openQuestions) {
        final text = raw.trim();
        if (text.isEmpty) continue;
        final key = _normKey(text);
        if (key.isEmpty) continue;
        // 기존 bucket과 부분 일치하는지 확인
        _IssueBucket? matched;
        for (final b in buckets) {
          if (_roughlySame(key, b.normKey)) {
            matched = b;
            break;
          }
        }
        matched ??= _IssueBucket(text: text, normKey: key);
        if (!buckets.contains(matched)) buckets.add(matched);
        if (!seenInThisMeeting.add(matched)) continue; // 같은 회의 중복 방지
        matched.appearances.add(IssueAppearance(m.id, m.title, m.createdAt));
        // 가장 긴 표현을 대표 텍스트로 보존 (사용자 가독성 우선)
        if (text.length > matched.text.length) {
          matched.text = text;
          matched.normKey = key;
        }
      }
    }
    final recurringIssues = <RecurringIssue>[];
    for (final b in buckets) {
      if (b.appearances.length < recurringIssueMinAppearances) continue;
      b.appearances.sort((a, c) => a.date.compareTo(c.date));
      recurringIssues.add(
        RecurringIssue(
          text: b.text,
          appearances: List.unmodifiable(b.appearances),
        ),
      );
    }
    recurringIssues.sort((a, b) {
      // 등장 횟수 많은 순 → 최근 등장 빠른 순
      final byCount = b.appearances.length.compareTo(a.appearances.length);
      if (byCount != 0) return byCount;
      return b.appearances.last.date.compareTo(a.appearances.last.date);
    });

    // ── 액션아이템 회차별 변화 추적 ──────────────────────────────
    // 같은 task가 회의를 가로질러 어떻게 변하는지 (owner/deadline/완료/사라짐)
    final actionTimeline = _buildActionTimeline(byOldFirst, summaries);

    return SeriesProgressReport(
      meetingCount: meetings.length,
      averageIntervalDays: avgIntervalDays,
      lastMeetingAt: byOldFirst.last.createdAt,
      pendingActionItems: List.unmodifiable(pendingActions),
      recentDecisions: List.unmodifiable(recentDecisions),
      recurringIssues: List.unmodifiable(recurringIssues),
      actionTimeline: List.unmodifiable(actionTimeline),
    );
  }

  /// 같은 task가 여러 회의에 등장하면 한 [TrackedAction]으로 묶고, 변화를 추출.
  /// `byOldFirst` — 옛날 → 최신 순 회의 목록.
  static List<TrackedAction> _buildActionTimeline(
    List<Meeting> byOldFirst,
    Map<int, Summary> summaries,
  ) {
    // bucket: 정규화 키 또는 부분 일치로 묶음.
    final buckets = <_ActionBucket>[];
    for (final m in byOldFirst) {
      final s = summaries[m.id];
      if (s == null) continue;
      final items = _parseActionItems(s.actionItemsJson);
      for (final it in items) {
        final task = it.task.trim();
        if (task.isEmpty) continue;
        final key = _normKey(task);
        if (key.isEmpty) continue;

        _ActionBucket? matched;
        for (final b in buckets) {
          if (_roughlySame(key, b.normKey)) {
            matched = b;
            break;
          }
        }
        matched ??= _ActionBucket(task: task, normKey: key);
        if (!buckets.contains(matched)) buckets.add(matched);

        matched.appearances.add(
          ActionAppearance(
            meetingId: m.id,
            meetingTitle: m.title,
            meetingDate: m.createdAt,
            owner: it.owner,
            deadline: it.deadline,
            completed: it.completed,
          ),
        );
        // 가장 긴 표현 보존
        if (task.length > matched.task.length) {
          matched.task = task;
          matched.normKey = key;
        }
      }
    }

    // 최신 회의 ID
    final latestMeetingId = byOldFirst.isEmpty ? null : byOldFirst.last.id;

    final out = <TrackedAction>[];
    for (final b in buckets) {
      // 단발 등장은 의미가 적음 — "변화 추적"이라는 카드 목적상 2회 이상만.
      if (b.appearances.length < 2) continue;
      out.add(
        TrackedAction(
          task: b.task,
          appearances: List.unmodifiable(b.appearances),
          latestMeetingId: latestMeetingId,
        ),
      );
    }
    // 가장 최근 활동(마지막 등장) 우선, 동률이면 등장 횟수 많은 순.
    out.sort((a, b) {
      final cmp = b.lastAppearance.meetingDate.compareTo(
        a.lastAppearance.meetingDate,
      );
      if (cmp != 0) return cmp;
      return b.appearances.length.compareTo(a.appearances.length);
    });
    return out;
  }

  static List<ActionItem> _parseActionItems(String json) {
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

  /// 이슈 매칭용 정규화 — 공백/구두점 제거, 소문자.
  /// SummaryParser._normKey와 같은 규칙.
  static String _normKey(String s) {
    return s.toLowerCase().replaceAll(
      RegExp(r'[\s·.,·、。,!?~\-–—\[\]\(\)\{\}:;"]+'),
      '',
    );
  }

  /// 두 정규화 키가 사실상 같은 이슈인지 — 완전 일치 또는 8자 이상에서 한쪽이 다른 쪽을 포함.
  /// SummaryParser._roughlySame과 같은 규칙.
  static bool _roughlySame(String na, String nb) {
    if (na.isEmpty || nb.isEmpty) return na == nb;
    if (na == nb) return true;
    if (na.length >= 8 && nb.length >= 8) {
      if (na.contains(nb) || nb.contains(na)) return true;
    }
    return false;
  }
}

class SeriesProgressReport {
  final int meetingCount;
  final int? averageIntervalDays; // null = 1회뿐 또는 0회
  final DateTime? lastMeetingAt;
  final List<PendingActionItem> pendingActionItems;
  final List<RecentDecision> recentDecisions;
  final List<RecurringIssue> recurringIssues;

  /// 같은 액션 task가 여러 회의에 걸쳐 어떻게 변했는지 (owner/deadline/완료/사라짐).
  /// 2회 이상 등장한 task만 포함. 가장 최근 활동이 위에 옴.
  final List<TrackedAction> actionTimeline;

  const SeriesProgressReport({
    required this.meetingCount,
    required this.averageIntervalDays,
    required this.lastMeetingAt,
    required this.pendingActionItems,
    required this.recentDecisions,
    required this.recurringIssues,
    required this.actionTimeline,
  });

  factory SeriesProgressReport.empty() => const SeriesProgressReport(
    meetingCount: 0,
    averageIntervalDays: null,
    lastMeetingAt: null,
    pendingActionItems: [],
    recentDecisions: [],
    recurringIssues: [],
    actionTimeline: [],
  );

  bool get isEmpty => meetingCount == 0;
}

class PendingActionItem {
  final int meetingId;
  final String meetingTitle;
  final DateTime meetingDate;
  final ActionItem item;

  const PendingActionItem({
    required this.meetingId,
    required this.meetingTitle,
    required this.meetingDate,
    required this.item,
  });
}

class RecentDecision {
  final int meetingId;
  final String meetingTitle;
  final DateTime meetingDate;
  final String text;

  const RecentDecision({
    required this.meetingId,
    required this.meetingTitle,
    required this.meetingDate,
    required this.text,
  });
}

class RecurringIssue {
  final String text;
  final List<IssueAppearance> appearances;

  const RecurringIssue({required this.text, required this.appearances});

  int get count => appearances.length;
  DateTime get firstSeen => appearances.first.date;
  DateTime get lastSeen => appearances.last.date;
}

class IssueAppearance {
  final int meetingId;
  final String meetingTitle;
  final DateTime date;
  const IssueAppearance(this.meetingId, this.meetingTitle, this.date);
}

class _IssueBucket {
  String text;
  String normKey;
  final List<IssueAppearance> appearances = [];
  _IssueBucket({required this.text, required this.normKey});
}

/// 한 액션 task의 회차별 등장 기록.
class TrackedAction {
  /// 가장 긴 표현으로 보존된 대표 task 텍스트.
  final String task;

  /// 옛날 → 최신 순 등장 기록.
  final List<ActionAppearance> appearances;

  /// 시리즈 안 가장 최근 회의 ID (마지막 회의에서 등장 여부 판정용).
  final int? latestMeetingId;

  const TrackedAction({
    required this.task,
    required this.appearances,
    required this.latestMeetingId,
  });

  ActionAppearance get firstAppearance => appearances.first;
  ActionAppearance get lastAppearance => appearances.last;

  /// 마지막 등장에서 완료로 마킹됐는지.
  bool get isCompleted => lastAppearance.completed;

  /// 가장 최근 회의에 등장했는지 (false = 어느 시점부터 사라짐).
  bool get isInLatestMeeting =>
      latestMeetingId == null || lastAppearance.meetingId == latestMeetingId;

  /// 사용자 노출 상태:
  ///   - resolved  : 마지막 등장에서 완료 표시됨
  ///   - dropped   : 최신 회의에서 더 이상 안 보임 (완료 표시 없음, 추정)
  ///   - ongoing   : 최신 회의에 여전히 등장 (미완료)
  TrackedActionStatus get status {
    if (isCompleted) return TrackedActionStatus.resolved;
    if (!isInLatestMeeting) return TrackedActionStatus.dropped;
    return TrackedActionStatus.ongoing;
  }

  /// owner가 회차 사이에 변경됐는지 (마지막 변경만 감지).
  bool get hasOwnerChange {
    String? prev;
    for (final a in appearances) {
      final cur = a.owner.trim();
      if (cur.isEmpty) continue;
      if (prev != null && prev != cur) return true;
      prev = cur;
    }
    return false;
  }

  /// deadline이 회차 사이에 변경됐는지 (마지막 변경만 감지).
  bool get hasDeadlineChange {
    String? prev;
    for (final a in appearances) {
      final cur = a.deadline.trim();
      if (cur.isEmpty) continue;
      if (prev != null && prev != cur) return true;
      prev = cur;
    }
    return false;
  }
}

enum TrackedActionStatus { ongoing, resolved, dropped }

class ActionAppearance {
  final int meetingId;
  final String meetingTitle;
  final DateTime meetingDate;
  final String owner;
  final String deadline;
  final bool completed;

  const ActionAppearance({
    required this.meetingId,
    required this.meetingTitle,
    required this.meetingDate,
    required this.owner,
    required this.deadline,
    required this.completed,
  });
}

class _ActionBucket {
  String task;
  String normKey;
  final List<ActionAppearance> appearances = [];
  _ActionBucket({required this.task, required this.normKey});
}
