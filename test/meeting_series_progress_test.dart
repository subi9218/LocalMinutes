import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/meeting_series_progress.dart';
import 'package:local_minutes/domain/entities/meeting.dart';
import 'package:local_minutes/domain/entities/summary.dart';
import 'package:local_minutes/domain/repositories/meeting_repository.dart';

void main() {
  test('empty group returns empty report', () async {
    final report = await MeetingSeriesProgress.analyze(
      groupId: 99,
      meetingRepo: _FakeMeetingRepo([]),
      summaryRepo: _FakeSummaryRepo({}),
    );
    expect(report.isEmpty, isTrue);
    expect(report.meetingCount, 0);
  });

  test(
    'aggregates pending actions, recent decisions, recurring issues',
    () async {
      // 같은 그룹의 회의 3회 (오래된 것 → 최신 순으로 m1 → m2 → m3)
      final m1 = _meeting(1, '주간 회의 1차', DateTime(2026, 4, 1));
      final m2 = _meeting(2, '주간 회의 2차', DateTime(2026, 4, 8));
      final m3 = _meeting(3, '주간 회의 3차', DateTime(2026, 4, 15));

      // m3가 최신 — repo는 sortByCreatedAtDesc 흉내내어 m3, m2, m1 순으로 반환
      final repo = _FakeMeetingRepo([m3, m2, m1]);
      final summaries = _FakeSummaryRepo({
        1: _summary(
          1,
          decisions: const ['배포 일정 4월 말로 확정'],
          actionItems: const [
            {'task': 'API 문서 작성', 'owner': '민지', 'completed': false},
            {'task': '디자인 리뷰', 'owner': '준호', 'completed': true},
          ],
          openQuestions: const ['QA 인력 확보 여부 확인 필요'],
        ),
        2: _summary(
          2,
          decisions: const ['디자인 시스템 v2 채택'],
          actionItems: const [
            {'task': '문서 검토', 'owner': '준호', 'completed': false},
          ],
          openQuestions: const ['QA 인력 확보 여부 확인 필요', '런칭 후 KPI 정의 필요'],
        ),
        3: _summary(
          3,
          decisions: const ['MVP 범위 축소'],
          actionItems: const [
            {'task': '추가 채용 공고 작성', 'owner': '민지', 'completed': false},
          ],
          openQuestions: const ['QA 인력 확보 여부 확인 필요'],
        ),
      });

      final report = await MeetingSeriesProgress.analyze(
        groupId: 1,
        meetingRepo: repo,
        summaryRepo: summaries,
      );

      expect(report.meetingCount, 3);
      expect(report.averageIntervalDays, 7); // 7일 + 7일
      expect(report.lastMeetingAt, m3.createdAt);

      // 미완료 액션은 3개(완료된 디자인 리뷰 제외)
      final pendingTasks = report.pendingActionItems
          .map((p) => p.item.task)
          .toList();
      expect(pendingTasks, containsAll(['API 문서 작성', '문서 검토', '추가 채용 공고 작성']));
      expect(pendingTasks, isNot(contains('디자인 리뷰')));

      // 최근 결정은 최신 회의(m3)부터 채운다
      expect(report.recentDecisions, isNotEmpty);
      expect(report.recentDecisions.first.text, 'MVP 범위 축소');

      // QA 인력 확보 이슈는 3회 등장 → recurring으로 잡힘
      expect(report.recurringIssues, isNotEmpty);
      final qa = report.recurringIssues.first;
      expect(qa.count, 3);
      expect(qa.firstSeen, m1.createdAt);
      expect(qa.lastSeen, m3.createdAt);

      // 1회만 등장한 KPI 이슈는 recurring에 포함되지 않음
      final kpi = report.recurringIssues
          .where((i) => i.text.contains('KPI'))
          .toList();
      expect(kpi, isEmpty);
    },
  );

  test('partial match merges similar issues across meetings', () async {
    // 같은 이슈를 회의마다 약간 다르게 표현 — 부분 일치로 묶여야 함.
    final m1 = _meeting(11, '주간 1차', DateTime(2026, 4, 1));
    final m2 = _meeting(12, '주간 2차', DateTime(2026, 4, 8));
    final m3 = _meeting(13, '주간 3차', DateTime(2026, 4, 15));

    // m2가 m1/m3을 부분 포함(8자 이상): "QA 인력 확보 여부 확인" + "검토" 추가
    final repo = _FakeMeetingRepo([m3, m2, m1]);
    final summaries = _FakeSummaryRepo({
      11: _summary(11, openQuestions: const ['QA 인력 확보 여부 확인']),
      12: _summary(12, openQuestions: const ['QA 인력 확보 여부 확인 검토']),
      13: _summary(13, openQuestions: const ['QA 인력 확보 여부 확인']),
    });

    final report = await MeetingSeriesProgress.analyze(
      groupId: 1,
      meetingRepo: repo,
      summaryRepo: summaries,
    );

    // 표현이 살짝 달라도 같은 이슈로 묶여 3회 등장 — recurring 1개로 잡혀야 함.
    expect(report.recurringIssues, hasLength(1));
    expect(report.recurringIssues.first.count, 3);
    // 가장 긴 표현이 대표 텍스트로 보존됨.
    expect(report.recurringIssues.first.text, 'QA 인력 확보 여부 확인 검토');
  });

  test('action timeline — 같은 task 회차별 추적 + 변경 감지', () async {
    final m1 = _meeting(31, '주간 1차', DateTime(2026, 4, 1));
    final m2 = _meeting(32, '주간 2차', DateTime(2026, 4, 8));
    final m3 = _meeting(33, '주간 3차', DateTime(2026, 4, 15));

    final repo = _FakeMeetingRepo([m3, m2, m1]);
    final summaries = _FakeSummaryRepo({
      31: _summary(
        31,
        actionItems: const [
          {'task': 'API 문서 작성', 'owner': '민지', 'deadline': '4/10'},
          {
            'task': 'QA 테스트',
            'owner': '준호',
            'deadline': '4/15',
            'completed': false,
          },
        ],
      ),
      32: _summary(
        32,
        actionItems: const [
          // owner 변경
          {'task': 'API 문서 작성', 'owner': '준호', 'deadline': '4/10'},
          // QA 테스트 누락 → dropped
        ],
      ),
      33: _summary(
        33,
        actionItems: const [
          // 완료 마킹
          {
            'task': 'API 문서 작성',
            'owner': '준호',
            'deadline': '4/10',
            'completed': true,
          },
        ],
      ),
    });

    final report = await MeetingSeriesProgress.analyze(
      groupId: 1,
      meetingRepo: repo,
      summaryRepo: summaries,
    );

    expect(report.actionTimeline, hasLength(1));
    final api = report.actionTimeline.firstWhere((t) => t.task.contains('API'));
    expect(api.appearances, hasLength(3));
    expect(api.hasOwnerChange, isTrue);
    expect(api.hasDeadlineChange, isFalse);
    expect(api.status, TrackedActionStatus.resolved);

    // 1회만 등장한 task는 timeline에 포함되지 않음 (변화 추적 카드의 목적상)
    final qa = report.actionTimeline.where((t) => t.task.contains('QA'));
    expect(qa, isEmpty);
  });

  test('action timeline — 최신 회의에 여전히 등장 + 미완료 → ongoing', () async {
    final m1 = _meeting(41, '주간 1차', DateTime(2026, 4, 1));
    final m2 = _meeting(42, '주간 2차', DateTime(2026, 4, 8));

    final repo = _FakeMeetingRepo([m2, m1]);
    final summaries = _FakeSummaryRepo({
      41: _summary(
        41,
        actionItems: const [
          {'task': '디자인 시안 검토', 'owner': '민지', 'deadline': '4/5'},
        ],
      ),
      42: _summary(
        42,
        actionItems: const [
          {'task': '디자인 시안 검토', 'owner': '민지', 'deadline': '4/5'},
        ],
      ),
    });

    final report = await MeetingSeriesProgress.analyze(
      groupId: 1,
      meetingRepo: repo,
      summaryRepo: summaries,
    );

    expect(report.actionTimeline, hasLength(1));
    expect(report.actionTimeline.first.status, TrackedActionStatus.ongoing);
  });

  test('짧은 텍스트(8자 미만)는 부분 일치로 묶지 않음 — 노이즈 방지', () async {
    final m1 = _meeting(21, '주간 1차', DateTime(2026, 4, 1));
    final m2 = _meeting(22, '주간 2차', DateTime(2026, 4, 8));
    final m3 = _meeting(23, '주간 3차', DateTime(2026, 4, 15));

    final repo = _FakeMeetingRepo([m3, m2, m1]);
    final summaries = _FakeSummaryRepo({
      21: _summary(21, openQuestions: const ['예산']),
      22: _summary(22, openQuestions: const ['예산 검토']),
      23: _summary(23, openQuestions: const ['예산 확정']),
    });

    final report = await MeetingSeriesProgress.analyze(
      groupId: 1,
      meetingRepo: repo,
      summaryRepo: summaries,
    );

    // 8자 미만 키들은 부분 일치 비활성 → 모두 별개 이슈, recurring 없음
    expect(report.recurringIssues, isEmpty);
  });
}

Meeting _meeting(int id, String title, DateTime createdAt) {
  return Meeting()
    ..id = id
    ..title = title
    ..createdAt = createdAt
    ..endedAt = createdAt.add(const Duration(minutes: 30))
    ..status = MeetingStatus.done
    ..groupId = 1;
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

// ── Fake repos ─────────────────────────────────────────────────

class _FakeMeetingRepo implements MeetingRepository {
  final List<Meeting> _all;
  _FakeMeetingRepo(this._all);

  @override
  Future<List<Meeting>> getMeetingsByGroupId(int groupId) async =>
      _all.where((m) => m.groupId == groupId).toList();

  @override
  Future<List<Meeting>> getAllMeetings() async => _all;

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
