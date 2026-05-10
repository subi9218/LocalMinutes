import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant2/core/services/series_overview.dart';
import 'package:meeting_assistant2/domain/entities/meeting.dart';
import 'package:meeting_assistant2/domain/entities/meeting_group.dart';
import 'package:meeting_assistant2/domain/entities/summary.dart';
import 'package:meeting_assistant2/domain/repositories/meeting_repository.dart';

void main() {
  test('빈 그룹 → 빈 결과', () async {
    final result = await SeriesOverview.analyze(
      groups: const [],
      meetingRepo: _FakeMeetingRepo(const []),
      summaryRepo: _FakeSummaryRepo(const {}),
    );
    expect(result, isEmpty);
  });

  test('회의가 0회인 그룹은 제외', () async {
    final g1 = _group(1, '주간 회의');
    final result = await SeriesOverview.analyze(
      groups: [g1],
      meetingRepo: _FakeMeetingRepo(const []),
      summaryRepo: _FakeSummaryRepo(const {}),
    );
    expect(result, isEmpty);
  });

  test('각 그룹의 report 수집 + 마지막 회의 최신순 정렬', () async {
    final g1 = _group(1, '주간 A');
    final g2 = _group(2, '월간 B');
    final g3 = _group(3, '회고 C');

    final m1 = _meeting(11, '주간 A 1차', DateTime(2026, 4, 1), groupId: 1);
    final m2 = _meeting(
      12,
      '주간 A 2차',
      DateTime(2026, 5, 1),
      groupId: 1,
    ); // g1 last
    final m3 = _meeting(
      21,
      '월간 B',
      DateTime(2026, 5, 8),
      groupId: 2,
    ); // g2 last (가장 최신)
    final m4 = _meeting(
      31,
      '회고 C',
      DateTime(2026, 4, 20),
      groupId: 3,
    ); // g3 last

    final result = await SeriesOverview.analyze(
      groups: [g1, g2, g3],
      meetingRepo: _FakeMeetingRepo([m1, m2, m3, m4]),
      summaryRepo: _FakeSummaryRepo(const {}),
    );

    expect(result, hasLength(3));
    // 마지막 회의 최신순: g2(5/8) > g1(5/1) > g3(4/20)
    expect(result[0].group.id, 2);
    expect(result[1].group.id, 1);
    expect(result[2].group.id, 3);
  });

  test('각 그룹의 누적 미완료 액션/지속 이슈 카운트가 report에 담김', () async {
    final g1 = _group(1, '주간 A');
    final m1 = _meeting(11, 'A 1차', DateTime(2026, 4, 1), groupId: 1);
    final m2 = _meeting(12, 'A 2차', DateTime(2026, 4, 8), groupId: 1);

    final result = await SeriesOverview.analyze(
      groups: [g1],
      meetingRepo: _FakeMeetingRepo([m1, m2]),
      summaryRepo: _FakeSummaryRepo({
        11: _summary(
          11,
          actionItems: const [
            {'task': '문서 작성', 'owner': '민지', 'completed': false},
          ],
          openQuestions: const ['QA 확보 필요'],
        ),
        12: _summary(
          12,
          actionItems: const [
            {'task': '검토', 'owner': '준호', 'completed': false},
          ],
          openQuestions: const ['QA 확보 필요'],
        ),
      }),
    );

    expect(result, hasLength(1));
    final item = result.first;
    expect(item.report.meetingCount, 2);
    expect(item.report.pendingActionItems, hasLength(2));
    expect(item.report.recurringIssues, hasLength(1)); // QA 확보 필요 2회
  });

  test('daysSinceLastMeeting — reference 주입 반영', () async {
    final g1 = _group(1, '주간 A');
    final m1 = _meeting(11, 'A', DateTime(2026, 5, 1), groupId: 1);
    final result = await SeriesOverview.analyze(
      groups: [g1],
      meetingRepo: _FakeMeetingRepo([m1]),
      summaryRepo: _FakeSummaryRepo(const {}),
    );
    final days = result.first.daysSinceLastMeeting(DateTime(2026, 5, 9));
    expect(days, 8);
  });
}

MeetingGroup _group(int id, String name) {
  return MeetingGroup()
    ..id = id
    ..name = name
    ..createdAt = DateTime(2026, 4, 1);
}

Meeting _meeting(
  int id,
  String title,
  DateTime createdAt, {
  required int groupId,
}) {
  return Meeting()
    ..id = id
    ..title = title
    ..createdAt = createdAt
    ..endedAt = createdAt.add(const Duration(minutes: 30))
    ..status = MeetingStatus.done
    ..groupId = groupId;
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
