import '../../domain/entities/meeting.dart';
import '../../domain/entities/summary.dart';

/// 회의 목록을 키워드 점수로 정렬해 좁히는 헬퍼.
///
/// AI 검색이 LLM에 전달할 후보를 선별할 때 사용한다 — 회의가 매우 많을 때
/// 모든 회의를 LLM 컨텍스트에 넣으면 nCtx 초과가 생기므로 키워드로 먼저 좁힌다.
///
/// 매칭 규칙:
/// - 쿼리를 공백으로 토크나이즈, 2글자 미만 제거
/// - 회의의 title/notes/tags/agenda/transcriptPreview + 요약 필드를 합친 haystack
/// - 각 키워드의 등장 횟수 합계로 점수
/// - 점수 0인 회의는 제외 (단, 키워드가 없으면 모두 통과)
/// - 점수 동률은 입력 순서 유지(stable sort)
class MeetingKeywordSearch {
  MeetingKeywordSearch._();

  static List<Meeting> rank({
    required String query,
    required List<Meeting> meetings,
    required List<Summary> summaries,
    int? topN,
  }) {
    final keywords = _tokenize(query);
    if (keywords.isEmpty) {
      // 키워드 없음 — 입력 순서 그대로(상위 topN만 컷)
      return _cap(meetings, topN);
    }

    final summariesByMeeting = <int, Summary>{
      for (final s in summaries) s.meetingId: s,
    };

    final scored = <_Scored>[];
    for (var i = 0; i < meetings.length; i++) {
      final m = meetings[i];
      final hay = _haystack(m, summariesByMeeting[m.id]).toLowerCase();
      var score = 0;
      for (final kw in keywords) {
        score += _countOccurrences(hay, kw.toLowerCase());
      }
      if (score > 0) {
        scored.add(_Scored(meeting: m, score: score, originalIndex: i));
      }
    }

    if (scored.isEmpty) {
      // 키워드 매칭이 하나도 안 되면 — 빈 결과 반환하지 않고
      // 가장 최근 회의 일부로 폴백 (사용자가 자연어로 던진 질문이라
      //  모든 키워드가 noise일 수 있으므로 LLM에 판단 위임)
      return _cap(meetings, topN);
    }

    // 점수 내림차순, 동률은 원래 순서 유지(stable)
    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.originalIndex.compareTo(b.originalIndex);
    });

    final ranked = scored.map((e) => e.meeting).toList();
    return _cap(ranked, topN);
  }

  static List<Meeting> _cap(List<Meeting> list, int? topN) {
    if (topN == null || list.length <= topN) return list;
    return list.sublist(0, topN);
  }

  /// 공백 분리 + 2글자 미만 제거.
  /// "찾아줘"/"보여줘"/"뭐였지" 같은 conversational 토큰도 그대로 들어가지만,
  /// 회의 텍스트에는 거의 안 나오므로 점수에 영향 없음.
  static List<String> _tokenize(String query) {
    final out = <String>[];
    final seen = <String>{};
    for (final piece in query.split(RegExp(r'\s+'))) {
      final t = piece.trim();
      if (t.length < 2) continue;
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  static String _haystack(Meeting m, Summary? s) {
    final sb = StringBuffer(m.title);
    if (m.tags.isNotEmpty) sb.write(' ${m.tags.join(' ')}');
    if (m.notes.isNotEmpty) sb.write(' ${m.notes}');
    if (m.agenda.isNotEmpty) sb.write(' ${m.agenda}');
    final preview = m.transcriptPreview;
    if (preview != null && preview.isNotEmpty) sb.write(' $preview');
    if (s != null) {
      if (s.keyDiscussions.isNotEmpty) {
        sb.write(' ${s.keyDiscussions.join(' ')}');
      }
      if (s.decisions.isNotEmpty) sb.write(' ${s.decisions.join(' ')}');
      if (s.openQuestions.isNotEmpty) {
        sb.write(' ${s.openQuestions.join(' ')}');
      }
    }
    return sb.toString();
  }

  static int _countOccurrences(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    var count = 0;
    var idx = 0;
    while (true) {
      final found = haystack.indexOf(needle, idx);
      if (found == -1) return count;
      count++;
      idx = found + needle.length;
    }
  }
}

class _Scored {
  final Meeting meeting;
  final int score;
  final int originalIndex;
  const _Scored({
    required this.meeting,
    required this.score,
    required this.originalIndex,
  });
}
