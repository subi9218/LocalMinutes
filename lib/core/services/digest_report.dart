import 'dart:convert';

import '../../domain/entities/summary.dart';
import '../../domain/repositories/meeting_repository.dart';

/// 주간/월간 다이제스트 (P2 업무 흐름 확장).
///
/// 지정 기간 안의 모든 회의를 가로질러 미완료 액션/결정사항/미해결 이슈를 집계.
/// LLM 추가 호출 없이 저장된 [Summary]만 활용.
class DigestReport {
  DigestReport._();

  /// [now] 기준의 주간/월간 다이제스트.
  /// [now]는 테스트 주입용 — 기본은 `DateTime.now()`.
  static Future<DigestReportData> generate({
    required DigestPeriod period,
    required MeetingRepository meetingRepo,
    required SummaryRepository summaryRepo,
    DateTime? now,
  }) async {
    final reference = now ?? DateTime.now();
    final (start, end) = period.range(reference);

    final all = await meetingRepo.getAllMeetings();
    final inRange =
        all
            .where(
              (m) => !m.createdAt.isBefore(start) && m.createdAt.isBefore(end),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (inRange.isEmpty) {
      return DigestReportData(
        period: period,
        rangeStart: start,
        rangeEnd: end,
        meetingCount: 0,
        pendingActions: const [],
        decisions: const [],
        openIssues: const [],
      );
    }

    // 회의별 요약 로드
    final summaries = <int, Summary>{};
    for (final m in inRange) {
      final s = await summaryRepo.getSummaryByMeetingId(m.id);
      if (s != null) summaries[m.id] = s;
    }

    final pending = <DigestActionItem>[];
    final decisions = <DigestEntry>[];
    final issues = <DigestEntry>[];

    for (final m in inRange) {
      final s = summaries[m.id];
      if (s == null) continue;

      // 미완료 액션
      final items = _parseActionItems(s.actionItemsJson);
      for (final it in items) {
        if (it.completed) continue;
        if (it.task.trim().isEmpty) continue;
        pending.add(
          DigestActionItem(
            meetingId: m.id,
            meetingTitle: m.title,
            meetingDate: m.createdAt,
            item: it,
          ),
        );
      }

      // 결정사항
      for (final d in s.decisions) {
        if (d.trim().isEmpty) continue;
        decisions.add(
          DigestEntry(
            meetingId: m.id,
            meetingTitle: m.title,
            meetingDate: m.createdAt,
            text: d,
          ),
        );
      }

      // 미해결 이슈
      for (final q in s.openQuestions) {
        if (q.trim().isEmpty) continue;
        issues.add(
          DigestEntry(
            meetingId: m.id,
            meetingTitle: m.title,
            meetingDate: m.createdAt,
            text: q,
          ),
        );
      }
    }

    return DigestReportData(
      period: period,
      rangeStart: start,
      rangeEnd: end,
      meetingCount: inRange.length,
      pendingActions: List.unmodifiable(pending),
      decisions: List.unmodifiable(decisions),
      openIssues: List.unmodifiable(issues),
    );
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
}

/// 다이제스트 기간.
enum DigestPeriod {
  /// 이번 주 (월 0:00:00 ~ 다음 월 0:00:00, 월요일 시작).
  week,

  /// 이번 달 (1일 0:00:00 ~ 다음 달 1일 0:00:00).
  month;

  /// [reference]를 포함하는 기간의 [start, end) 범위 반환.
  /// `start`는 inclusive, `end`는 exclusive.
  (DateTime, DateTime) range(DateTime reference) {
    switch (this) {
      case DigestPeriod.week:
        // 월요일 시작. weekday: 1=월 ~ 7=일.
        final weekday = reference.weekday;
        final monday = DateTime(
          reference.year,
          reference.month,
          reference.day,
        ).subtract(Duration(days: weekday - 1));
        final nextMonday = monday.add(const Duration(days: 7));
        return (monday, nextMonday);
      case DigestPeriod.month:
        final start = DateTime(reference.year, reference.month, 1);
        final nextMonth = reference.month == 12
            ? DateTime(reference.year + 1, 1, 1)
            : DateTime(reference.year, reference.month + 1, 1);
        return (start, nextMonth);
    }
  }

  String get label => switch (this) {
    DigestPeriod.week => '이번 주',
    DigestPeriod.month => '이번 달',
  };
}

class DigestReportData {
  final DigestPeriod period;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final int meetingCount;
  final List<DigestActionItem> pendingActions;
  final List<DigestEntry> decisions;
  final List<DigestEntry> openIssues;

  const DigestReportData({
    required this.period,
    required this.rangeStart,
    required this.rangeEnd,
    required this.meetingCount,
    required this.pendingActions,
    required this.decisions,
    required this.openIssues,
  });

  bool get isEmpty =>
      meetingCount == 0 &&
      pendingActions.isEmpty &&
      decisions.isEmpty &&
      openIssues.isEmpty;
}

class DigestActionItem {
  final int meetingId;
  final String meetingTitle;
  final DateTime meetingDate;
  final ActionItem item;

  const DigestActionItem({
    required this.meetingId,
    required this.meetingTitle,
    required this.meetingDate,
    required this.item,
  });
}

class DigestEntry {
  final int meetingId;
  final String meetingTitle;
  final DateTime meetingDate;
  final String text;

  const DigestEntry({
    required this.meetingId,
    required this.meetingTitle,
    required this.meetingDate,
    required this.text,
  });
}
