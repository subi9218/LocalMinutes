import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/meeting_quality.dart';
import 'package:local_minutes/domain/entities/summary.dart';
import 'package:local_minutes/domain/entities/transcript.dart';

void main() {
  test('null summary → empty report', () {
    final r = MeetingQuality.analyze(summary: null, transcripts: const []);
    expect(r.isEmpty, isTrue);
    expect(r.overallScore, 0);
    expect(r.hints, isEmpty);
  });

  test('빈 결정사항은 경고 힌트 + decisionsScore 0', () {
    final s = _summary(decisions: const []);
    final r = MeetingQuality.analyze(summary: s, transcripts: const []);
    expect(r.decisionsScore, 0);
    expect(
      r.hints.where((h) => h.category == QualityCategory.decisions),
      isNotEmpty,
    );
  });

  test('충실한 결정 3개 + 충분한 길이 → decisionsScore 높음', () {
    final s = _summary(
      decisions: const [
        '4월 말까지 베타 출시 일정으로 확정',
        'QA 인력 2명 추가 채용 진행',
        '디자인 시스템 v2 채택 결정',
      ],
    );
    final r = MeetingQuality.analyze(summary: s, transcripts: const []);
    expect(r.decisionsScore, greaterThanOrEqualTo(90));
  });

  test('액션 owner/deadline 미지정 → 경고 힌트 발생', () {
    final s = _summary(
      actionItems: [
        {'task': 'API 문서 작성', 'owner': '', 'deadline': ''},
        {'task': '디자인 리뷰', 'owner': '', 'deadline': ''},
      ],
    );
    final r = MeetingQuality.analyze(summary: s, transcripts: const []);
    expect(r.actionsScore, lessThan(40));
    final actionHints = r.hints
        .where((h) => h.category == QualityCategory.actions)
        .toList();
    expect(actionHints, hasLength(2)); // owner + deadline
    expect(
      actionHints.every((h) => h.severity == QualityHintSeverity.warning),
      isTrue,
    );
  });

  test('완벽한 액션 — 모든 owner/deadline + confirmed', () {
    final s = _summary(
      actionItems: [
        {
          'task': 'API 문서 작성',
          'owner': '민지',
          'deadline': '2026-04-30',
          'ownerConfirmed': true,
          'deadlineConfirmed': true,
        },
        {
          'task': '디자인 리뷰',
          'owner': '준호',
          'deadline': '2026-04-25',
          'ownerConfirmed': true,
          'deadlineConfirmed': true,
        },
      ],
    );
    final r = MeetingQuality.analyze(summary: s, transcripts: const []);
    expect(r.actionsScore, 100);
    expect(
      r.hints.where((h) => h.category == QualityCategory.actions),
      isEmpty,
    );
  });

  test('"(미언급)" owner는 미지정으로 감지', () {
    final s = _summary(
      actionItems: [
        {'task': '용역 검토', 'owner': '(미언급)', 'deadline': '2026-04-30'},
      ],
    );
    final r = MeetingQuality.analyze(summary: s, transcripts: const []);
    final actionHints = r.hints.where(
      (h) => h.category == QualityCategory.actions && h.message.contains('담당자'),
    );
    expect(actionHints, isNotEmpty);
  });

  test('한 화자 75% 이상 점유 → 경고 힌트 + balanceScore 낮음', () {
    final transcripts = [_transcript(0, 90, 'A'), _transcript(90, 100, 'B')];
    final s = _summary();
    final r = MeetingQuality.analyze(summary: s, transcripts: transcripts);
    expect(r.balanceScore, lessThanOrEqualTo(60));
    expect(
      r.hints.where((h) => h.category == QualityCategory.balance),
      isNotEmpty,
    );
  });

  test('균형 잡힌 화자 — A 50% / B 50%', () {
    final transcripts = [_transcript(0, 50, 'A'), _transcript(50, 100, 'B')];
    final s = _summary();
    final r = MeetingQuality.analyze(summary: s, transcripts: transcripts);
    expect(r.balanceScore, 100);
  });

  test('evidence 채움률에 따라 evidenceScore 변동', () {
    final s = _summary(
      keyDiscussions: const ['논의 1', '논의 2'],
      decisions: const ['결정 1'],
      evidence: {
        'keyDiscussions': ['02:55', ''],
        'decisions': [''],
      },
    );
    final r = MeetingQuality.analyze(summary: s, transcripts: const []);
    // 3개 중 1개만 채움 → 33점
    expect(r.evidenceScore, 33);
    expect(
      r.hints.where((h) => h.category == QualityCategory.evidence),
      isNotEmpty,
    );
  });

  test('grade label은 점수 구간을 따른다', () {
    final s = _summary(
      decisions: const [
        '4월 말까지 베타 출시 일정으로 확정한다고 정리',
        'QA 인력 2명 추가 채용을 분기 내에 진행',
        '디자인 시스템 v2 채택을 다음 스프린트부터 적용',
      ],
      actionItems: [
        {
          'task': 'API 문서 작성',
          'owner': '민지',
          'deadline': '2026-04-30',
          'ownerConfirmed': true,
          'deadlineConfirmed': true,
        },
      ],
      evidence: {
        'decisions': ['02:55', '04:10', '08:20'],
      },
    );
    final r = MeetingQuality.analyze(summary: s, transcripts: const []);
    expect(r.gradeLabel, anyOf('우수', '양호'));
  });
}

Summary _summary({
  List<String> keyDiscussions = const [],
  List<String> decisions = const [],
  List<Map<String, dynamic>> actionItems = const [],
  List<String> openQuestions = const [],
  Map<String, List<String>>? evidence,
}) {
  return Summary()
    ..meetingId = 1
    ..meetingTitle = '테스트 회의'
    ..meetingDate = DateTime(2026, 4, 1)
    ..participants = const []
    ..keyDiscussions = keyDiscussions
    ..decisions = decisions
    ..actionItemsJson = jsonEncode(actionItems)
    ..openQuestions = openQuestions
    ..evidenceJson = evidence == null ? '{}' : jsonEncode(evidence)
    ..createdAt = DateTime(2026, 4, 1);
}

Transcript _transcript(double start, double end, String speaker) {
  return Transcript()
    ..meetingId = 1
    ..text = ''
    ..startTimeSeconds = start
    ..endTimeSeconds = end
    ..speakerLabel = speaker;
}
