import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/meeting_comparison.dart';
import 'package:local_minutes/domain/entities/meeting.dart';
import 'package:local_minutes/domain/entities/summary.dart';

void main() {
  test('두 요약이 모두 비어있으면 hasContent false', () {
    final r = MeetingComparison.compare(
      earlier: _meeting(1, '1차'),
      later: _meeting(2, '2차'),
      earlierSummary: _summary(1),
      laterSummary: _summary(2),
    );
    expect(r.hasContent, isFalse);
  });

  test('decisions diff — added/removed/shared 분류', () {
    final r = MeetingComparison.compare(
      earlier: _meeting(1, '1차'),
      later: _meeting(2, '2차'),
      earlierSummary: _summary(1, decisions: const ['MVP 일정 확정', '디자인 시스템 채택']),
      laterSummary: _summary(2, decisions: const ['MVP 일정 확정', 'QA 인력 추가']),
    );
    expect(r.decisions.shared, hasLength(1));
    expect(r.decisions.shared.first.text, 'MVP 일정 확정');
    expect(r.decisions.removed, ['디자인 시스템 채택']);
    expect(r.decisions.added, ['QA 인력 추가']);
  });

  test('decisions — 부분 일치(8자 이상 substring)도 shared로 묶임', () {
    final r = MeetingComparison.compare(
      earlier: _meeting(1, '1차'),
      later: _meeting(2, '2차'),
      earlierSummary: _summary(1, decisions: const ['QA 인력 확보 필요']),
      laterSummary: _summary(2, decisions: const ['QA 인력 확보 필요 검토']),
    );
    expect(r.decisions.shared, hasLength(1));
    // 더 긴 텍스트가 대표
    expect(r.decisions.shared.first.text, 'QA 인력 확보 필요 검토');
    expect(r.decisions.added, isEmpty);
    expect(r.decisions.removed, isEmpty);
  });

  test('openQuestions — 양쪽 모두 등장하면 shared', () {
    final r = MeetingComparison.compare(
      earlier: _meeting(1, '1차'),
      later: _meeting(2, '2차'),
      earlierSummary: _summary(1, openQuestions: const ['QA 인력 검토']),
      laterSummary: _summary(2, openQuestions: const ['QA 인력 검토']),
    );
    expect(r.openQuestions.shared, hasLength(1));
    expect(r.openQuestions.added, isEmpty);
    expect(r.openQuestions.removed, isEmpty);
  });

  test('actions — 미완료 → 완료 전이 감지(ActionTransition.completed)', () {
    final r = MeetingComparison.compare(
      earlier: _meeting(1, '1차'),
      later: _meeting(2, '2차'),
      earlierSummary: _summary(
        1,
        actions: const [
          {'task': 'API 문서 작성', 'owner': '민지', 'completed': false},
        ],
      ),
      laterSummary: _summary(
        2,
        actions: const [
          {'task': 'API 문서 작성', 'owner': '민지', 'completed': true},
        ],
      ),
    );
    expect(r.actions.shared, hasLength(1));
    expect(r.actions.shared.first.status, ActionTransition.completed);
  });

  test('actions — 양쪽 미완료면 stillOpen + owner 변경 감지', () {
    final r = MeetingComparison.compare(
      earlier: _meeting(1, '1차'),
      later: _meeting(2, '2차'),
      earlierSummary: _summary(
        1,
        actions: const [
          {'task': '문서 검토', 'owner': '민지', 'completed': false},
        ],
      ),
      laterSummary: _summary(
        2,
        actions: const [
          {'task': '문서 검토', 'owner': '준호', 'completed': false},
        ],
      ),
    );
    expect(r.actions.shared, hasLength(1));
    expect(r.actions.shared.first.status, ActionTransition.stillOpen);
    expect(r.actions.shared.first.ownerChanged, isTrue);
    expect(r.actions.shared.first.deadlineChanged, isFalse);
  });

  test('actions — earlier에만 있으면 removed, later에만 있으면 added', () {
    final r = MeetingComparison.compare(
      earlier: _meeting(1, '1차'),
      later: _meeting(2, '2차'),
      earlierSummary: _summary(
        1,
        actions: const [
          {'task': '디자인 시안 검토', 'owner': '준호', 'completed': false},
        ],
      ),
      laterSummary: _summary(
        2,
        actions: const [
          {'task': '추가 채용 공고', 'owner': '민지', 'completed': false},
        ],
      ),
    );
    expect(r.actions.shared, isEmpty);
    expect(r.actions.removed, hasLength(1));
    expect(r.actions.removed.first.task, '디자인 시안 검토');
    expect(r.actions.added, hasLength(1));
    expect(r.actions.added.first.task, '추가 채용 공고');
  });

  test('summary 둘 다 null이면 모두 빈 결과', () {
    final r = MeetingComparison.compare(
      earlier: _meeting(1, '1차'),
      later: _meeting(2, '2차'),
      earlierSummary: null,
      laterSummary: null,
    );
    expect(r.hasContent, isFalse);
  });
}

Meeting _meeting(int id, String title) {
  return Meeting()
    ..id = id
    ..title = title
    ..createdAt = DateTime(2026, 5, 1)
    ..endedAt = DateTime(2026, 5, 1, 0, 30);
}

Summary _summary(
  int meetingId, {
  List<String> keyDiscussions = const [],
  List<String> decisions = const [],
  List<String> openQuestions = const [],
  List<Map<String, dynamic>> actions = const [],
}) {
  return Summary()
    ..meetingId = meetingId
    ..meetingTitle = ''
    ..meetingDate = DateTime(2026, 5, 1)
    ..participants = const []
    ..keyDiscussions = keyDiscussions
    ..decisions = decisions
    ..actionItemsJson = jsonEncode(actions)
    ..openQuestions = openQuestions
    ..createdAt = DateTime(2026, 5, 1);
}
