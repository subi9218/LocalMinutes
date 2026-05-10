import 'package:flutter_test/flutter_test.dart';
import 'package:meeting_assistant2/core/services/meeting_keyword_search.dart';
import 'package:meeting_assistant2/domain/entities/meeting.dart';
import 'package:meeting_assistant2/domain/entities/summary.dart';

void main() {
  test('키워드 매칭 점수로 정렬 — 빅쿼리 언급 회의가 위로', () {
    final m1 = _meeting(1, '주간 회의')..transcriptPreview = '오늘은 디자인 검토를 했고...';
    final m2 = _meeting(2, '데이터 분석 회의')
      ..transcriptPreview = '빅쿼리 마이그레이션 계획을 논의함...';
    final m3 = _meeting(3, '디자인 동기화')..transcriptPreview = '시안 검토와 컴포넌트 정리';

    final ranked = MeetingKeywordSearch.rank(
      query: '빅쿼리 관련 회의 찾아줘',
      meetings: [m1, m2, m3],
      summaries: const [],
    );

    expect(ranked, isNotEmpty);
    expect(ranked.first.id, 2); // 빅쿼리 매칭한 회의
  });

  test('키워드 매칭 0인 회의는 결과에서 제외', () {
    final m1 = _meeting(1, '빅쿼리 검토');
    final m2 = _meeting(2, '디자인 회의');
    final ranked = MeetingKeywordSearch.rank(
      query: '빅쿼리',
      meetings: [m1, m2],
      summaries: const [],
    );
    expect(ranked, hasLength(1));
    expect(ranked.first.id, 1);
  });

  test('키워드가 모두 없는 단어로만 구성되면 입력 순서 유지(폴백)', () {
    final m1 = _meeting(1, '빅쿼리');
    final m2 = _meeting(2, '디자인');
    final ranked = MeetingKeywordSearch.rank(
      query: 'xyz nonexistent',
      meetings: [m1, m2],
      summaries: const [],
    );
    expect(ranked, hasLength(2));
    expect(ranked[0].id, 1);
    expect(ranked[1].id, 2);
  });

  test('빈 쿼리 — 입력 순서 그대로 + topN 컷', () {
    final list = [_meeting(1, 'a'), _meeting(2, 'b'), _meeting(3, 'c')];
    final ranked = MeetingKeywordSearch.rank(
      query: '   ',
      meetings: list,
      summaries: const [],
      topN: 2,
    );
    expect(ranked, hasLength(2));
    expect(ranked.map((m) => m.id).toList(), [1, 2]);
  });

  test('topN으로 결과 컷 — 점수 높은 회의만 상위 N', () {
    final list = [
      _meeting(1, '빅쿼리 빅쿼리 빅쿼리'), // 3 hits
      _meeting(2, '빅쿼리 회의'), // 1 hit
      _meeting(3, '빅쿼리 빅쿼리'), // 2 hits
      _meeting(4, '디자인'), // 0 hits
    ];
    final ranked = MeetingKeywordSearch.rank(
      query: '빅쿼리',
      meetings: list,
      summaries: const [],
      topN: 2,
    );
    expect(ranked, hasLength(2));
    expect(ranked[0].id, 1);
    expect(ranked[1].id, 3);
  });

  test('summary 필드(decisions, keyDiscussions, openQuestions)도 매칭', () {
    final m1 = _meeting(1, '주간 회의');
    final s1 = _summary(meetingId: 1, keyDiscussions: ['빅쿼리 마이그레이션 일정 논의']);
    final m2 = _meeting(2, '주간 회의');
    final ranked = MeetingKeywordSearch.rank(
      query: '빅쿼리',
      meetings: [m1, m2],
      summaries: [s1],
    );
    expect(ranked, hasLength(1));
    expect(ranked.first.id, 1);
  });

  test('태그도 haystack에 포함', () {
    final m1 = _meeting(1, '주간 회의')..tags = ['빅쿼리'];
    final m2 = _meeting(2, '주간 회의')..tags = ['디자인'];
    final ranked = MeetingKeywordSearch.rank(
      query: '빅쿼리',
      meetings: [m1, m2],
      summaries: const [],
    );
    expect(ranked, hasLength(1));
    expect(ranked.first.id, 1);
  });

  test('대소문자 무관 매칭', () {
    final m1 = _meeting(1, 'BigQuery 마이그레이션');
    final ranked = MeetingKeywordSearch.rank(
      query: 'bigquery',
      meetings: [m1],
      summaries: const [],
    );
    expect(ranked, hasLength(1));
  });

  test('1글자 키워드는 무시 — 노이즈 방지', () {
    // 'a'는 너무 자주 나타나는 noise → 제거
    final m1 = _meeting(1, 'apple banana');
    final m2 = _meeting(2, '빅쿼리');
    final ranked = MeetingKeywordSearch.rank(
      query: 'a',
      meetings: [m1, m2],
      summaries: const [],
    );
    // 키워드가 없는 것과 동일 → 입력 순서
    expect(ranked, hasLength(2));
    expect(ranked.map((m) => m.id).toList(), [1, 2]);
  });
}

Meeting _meeting(int id, String title) {
  return Meeting()
    ..id = id
    ..title = title
    ..createdAt = DateTime(2026, 5, 1)
    ..endedAt = DateTime(2026, 5, 1, 0, 30);
}

Summary _summary({
  required int meetingId,
  List<String> keyDiscussions = const [],
  List<String> decisions = const [],
  List<String> openQuestions = const [],
}) {
  return Summary()
    ..meetingId = meetingId
    ..meetingTitle = ''
    ..meetingDate = DateTime(2026, 5, 1)
    ..participants = const []
    ..keyDiscussions = keyDiscussions
    ..decisions = decisions
    ..actionItemsJson = '[]'
    ..openQuestions = openQuestions
    ..createdAt = DateTime(2026, 5, 1);
}
