import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant2/core/services/digest_report.dart';
import 'package:meeting_assistant2/domain/entities/meeting.dart';
import 'package:meeting_assistant2/domain/entities/summary.dart';
import 'package:meeting_assistant2/domain/repositories/meeting_repository.dart';

void main() {
  test('week range — 월요일 시작, 다음 월요일 미포함', () {
    // 2026-05-09는 토요일
    final ref = DateTime(2026, 5, 9, 14);
    final (start, end) = DigestPeriod.week.range(ref);
    expect(start, DateTime(2026, 5, 4)); // 월
    expect(end, DateTime(2026, 5, 11)); // 다음 월
  });

  test('week range — 일요일이 포함된 주의 시작은 그 전 월요일', () {
    // 2026-05-10은 일요일
    final ref = DateTime(2026, 5, 10, 23);
    final (start, end) = DigestPeriod.week.range(ref);
    expect(start, DateTime(2026, 5, 4));
    expect(end, DateTime(2026, 5, 11));
  });

  test('month range — 1일 0:00:00 ~ 다음달 1일 0:00:00', () {
    final ref = DateTime(2026, 5, 9);
    final (start, end) = DigestPeriod.month.range(ref);
    expect(start, DateTime(2026, 5, 1));
    expect(end, DateTime(2026, 6, 1));
  });

  test('month range — 12월은 다음 해 1월로 넘어감', () {
    final ref = DateTime(2026, 12, 15);
    final (start, end) = DigestPeriod.month.range(ref);
    expect(start, DateTime(2026, 12, 1));
    expect(end, DateTime(2027, 1, 1));
  });

  test('빈 기간 → empty report', () async {
    final report = await DigestReport.generate(
      period: DigestPeriod.week,
      meetingRepo: _FakeMeetingRepo(const []),
      summaryRepo: _FakeSummaryRepo(const {}),
      now: DateTime(2026, 5, 9),
    );
    expect(report.meetingCount, 0);
    expect(report.isEmpty, isTrue);
  });

  test('주간 다이제스트 — 기간 내 회의만 집계', () async {
    final ref = DateTime(2026, 5, 9); // 토요일 → 5/4~5/10 주
    // 5/3 (전 주, 일) - 제외
    final m0 = _meeting(1, '지난 주 회의', DateTime(2026, 5, 3, 10));
    // 5/5 (이번 주, 화)
    final m1 = _meeting(2, '주간 1차', DateTime(2026, 5, 5, 10));
    // 5/8 (이번 주, 금)
    final m2 = _meeting(3, '주간 2차', DateTime(2026, 5, 8, 10));
    // 5/11 (다음 주, 월) - 제외
    final m3 = _meeting(4, '다음 주 회의', DateTime(2026, 5, 11, 10));

    final report = await DigestReport.generate(
      period: DigestPeriod.week,
      meetingRepo: _FakeMeetingRepo([m0, m1, m2, m3]),
      summaryRepo: _FakeSummaryRepo({
        2: _summary(
          2,
          decisions: const ['MVP 일정 확정'],
          actionItems: const [
            {'task': '문서 작성', 'owner': '민지', 'completed': false},
          ],
          openQuestions: const ['QA 인력 검토'],
        ),
        3: _summary(
          3,
          decisions: const ['디자인 톤 결정'],
          actionItems: const [
            {'task': '시안 검토', 'owner': '준호', 'completed': true},
            {'task': '추가 조사', 'owner': '하영', 'completed': false},
          ],
          openQuestions: const [],
        ),
      }),
      now: ref,
    );

    expect(report.meetingCount, 2);
    expect(report.rangeStart, DateTime(2026, 5, 4));
    expect(report.rangeEnd, DateTime(2026, 5, 11));

    // 미완료 액션 2개 (완료된 시안 검토 제외)
    expect(report.pendingActions, hasLength(2));
    expect(
      report.pendingActions.map((a) => a.item.task),
      containsAll(['문서 작성', '추가 조사']),
    );

    // 결정 2건
    expect(report.decisions, hasLength(2));
    expect(
      report.decisions.map((d) => d.text),
      containsAll(['MVP 일정 확정', '디자인 톤 결정']),
    );

    // 미해결 이슈 1건 (m2의 openQuestions는 비어있음)
    expect(report.openIssues, hasLength(1));
    expect(report.openIssues.first.text, 'QA 인력 검토');
  });

  test('월간 다이제스트 — 같은 달 모든 회의 집계', () async {
    final ref = DateTime(2026, 5, 30);
    final m1 = _meeting(11, '5월 1차', DateTime(2026, 5, 1, 10));
    final m2 = _meeting(12, '5월 2차', DateTime(2026, 5, 15, 10));
    final m3 = _meeting(13, '5월 마지막', DateTime(2026, 5, 31, 23));
    final m4 = _meeting(14, '6월 첫 회의', DateTime(2026, 6, 1, 9));

    final report = await DigestReport.generate(
      period: DigestPeriod.month,
      meetingRepo: _FakeMeetingRepo([m1, m2, m3, m4]),
      summaryRepo: _FakeSummaryRepo(const {}),
      now: ref,
    );

    expect(report.meetingCount, 3); // m4 제외
  });
}

Meeting _meeting(int id, String title, DateTime createdAt) {
  return Meeting()
    ..id = id
    ..title = title
    ..createdAt = createdAt
    ..endedAt = createdAt.add(const Duration(minutes: 30));
}

Summary _summary(
  int meetingId, {
  List<String> decisions = const [],
  List<Map<String, dynamic>> actionItems = const [],
  List<String> openQuestions = const [],
}) {
  return Summary()
    ..meetingId = meetingId
    ..meetingTitle = ''
    ..meetingDate = DateTime(2026, 4, 1)
    ..participants = const []
    ..keyDiscussions = const []
    ..decisions = decisions
    ..actionItemsJson = jsonEncode(actionItems)
    ..openQuestions = openQuestions
    ..createdAt = DateTime(2026, 4, 1);
}

class _FakeMeetingRepo implements MeetingRepository {
  final List<Meeting> _all;
  _FakeMeetingRepo(this._all);

  @override
  Future<List<Meeting>> getAllMeetings() async => _all;

  @override
  Future<List<Meeting>> getMeetingsByGroupId(int groupId) async =>
      _all.where((m) => m.groupId == groupId).toList();

  @override
  Future<Meeting?> getMeetingById(int id) async =>
      _all.where((m) => m.id == id).firstOrNull;

  @override
  Future<int> saveMeeting(Meeting meeting) async => meeting.id;

  @override
  Future<void> updateMeeting(Meeting meeting) async {}

  @override
  Future<void> deleteMeeting(int id) async {}
}

class _FakeSummaryRepo implements SummaryRepository {
  final Map<int, Summary> _byMeetingId;
  _FakeSummaryRepo(this._byMeetingId);

  @override
  Future<Summary?> getSummaryByMeetingId(int meetingId) async =>
      _byMeetingId[meetingId];

  @override
  Future<int> saveSummary(Summary summary) async => summary.id;

  @override
  Future<void> deleteSummaryByMeetingId(int meetingId) async {}
}
