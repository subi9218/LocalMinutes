import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/services/meeting_series_detector.dart';
import 'package:local_minutes/domain/entities/meeting.dart';
import 'package:local_minutes/domain/entities/summary.dart';

void main() {
  test('suggests a recurring series from title and participants', () {
    final meetings = [
      _meeting(1, '제품 주간 회의 2026-05-01', DateTime(2026, 5, 1)),
      _meeting(2, '제품 주간 회의 2026-05-08', DateTime(2026, 5, 8)),
      _meeting(3, '채용 인터뷰', DateTime(2026, 5, 8)),
    ];
    final summaries = [
      _summary(1, participants: const ['민지', '준호']),
      _summary(2, participants: const ['민지', '준호']),
      _summary(3, participants: const ['지원자 A']),
    ];

    final suggestions = MeetingSeriesDetector.suggestSeries(
      meetings: meetings,
      summaries: summaries,
    );

    expect(suggestions, hasLength(1));
    expect(suggestions.single.suggestedName, '제품 주간 회의');
    expect(suggestions.single.meetings.map((m) => m.id), containsAll([1, 2]));
    expect(suggestions.single.sharedParticipants, const ['민지', '준호']);
  });

  test('ignores meetings that already belong to a group', () {
    final grouped = _meeting(1, '운영 정기 회의', DateTime(2026, 5, 1))..groupId = 10;
    final meetings = [grouped, _meeting(2, '운영 정기 회의', DateTime(2026, 5, 8))];

    final suggestions = MeetingSeriesDetector.suggestSeries(
      meetings: meetings,
      summaries: const [],
    );

    expect(suggestions, isEmpty);
  });

  test('does not group generic one-word meeting titles by title alone', () {
    final meetings = [
      _meeting(1, '회의', DateTime(2026, 5, 1)),
      _meeting(2, '회의', DateTime(2026, 5, 8)),
    ];

    final suggestions = MeetingSeriesDetector.suggestSeries(
      meetings: meetings,
      summaries: const [],
    );

    expect(suggestions, isEmpty);
  });
}

Meeting _meeting(int id, String title, DateTime createdAt) {
  return Meeting()
    ..id = id
    ..title = title
    ..createdAt = createdAt
    ..endedAt = createdAt.add(const Duration(minutes: 30))
    ..status = MeetingStatus.done;
}

Summary _summary(int meetingId, {List<String> participants = const []}) {
  return Summary()
    ..meetingId = meetingId
    ..meetingTitle = ''
    ..meetingDate = DateTime(2026, 5, 1)
    ..participants = participants
    ..keyDiscussions = const []
    ..decisions = const []
    ..actionItemsJson = '[]'
    ..openQuestions = const []
    ..createdAt = DateTime(2026, 5, 1);
}
