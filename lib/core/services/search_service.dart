import 'dart:convert';

import 'package:isar/isar.dart';

import '../../domain/entities/meeting.dart';
import '../../domain/entities/summary.dart';
import '../../domain/entities/transcript.dart';
import 'isar_service.dart';

/// 검색 매치가 발견된 필드 종류
enum SearchField {
  title,
  notes,
  tags,
  summaryTitle,
  participants,
  keyDiscussions,
  decisions,
  actionItems,
  openQuestions,
  transcript,
}

extension SearchFieldLabel on SearchField {
  String get label {
    switch (this) {
      case SearchField.title:
        return '제목';
      case SearchField.notes:
        return '메모';
      case SearchField.tags:
        return '태그';
      case SearchField.summaryTitle:
        return '요약 제목';
      case SearchField.participants:
        return '참석자';
      case SearchField.keyDiscussions:
        return '논의';
      case SearchField.decisions:
        return '결정';
      case SearchField.actionItems:
        return '액션';
      case SearchField.openQuestions:
        return '미결';
      case SearchField.transcript:
        return '전사';
    }
  }
}

class SearchMatch {
  final SearchField field;
  final String snippet;

  const SearchMatch({required this.field, required this.snippet});
}

class MeetingSearchHit {
  final int meetingId;
  final int totalMatches;
  final List<SearchMatch> topMatches;

  const MeetingSearchHit({
    required this.meetingId,
    required this.totalMatches,
    required this.topMatches,
  });
}

/// 회의 전반(제목/메모/태그/요약/전사)에 대한 full-text search.
///
/// Isar는 네이티브 FTS를 제공하지 않지만, 전사본은 meetingId 인덱스 + textContains
/// 쿼리로 DB단 1차 필터링한 뒤, 나머지 필드는 이미 메모리에 로드된 meetings/
/// summaries 리스트 대상으로 검사한다.
class SearchService {
  SearchService._();

  static const int _snippetRadius = 32; // 매치 전후 문자 수
  static const int _maxMatchesPerHit = 4;

  /// [query] 는 공백으로 AND 토큰화. 빈 쿼리는 빈 결과.
  static Future<List<MeetingSearchHit>> search({
    required String query,
    required List<Meeting> meetings,
    required List<Summary> summaries,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final tokens = q
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return const [];

    // 1. 전사본 DB 측 필터링 — 각 토큰별로 contains 쿼리, 교집합
    final transcriptHitsByMeeting =
        await _fetchTranscriptHits(tokens);

    // 2. 메타 필드 (제목/메모/태그/요약) 메모리 스캔
    final summaryByMeetingId = <int, Summary>{
      for (final s in summaries) s.meetingId: s,
    };

    final hits = <MeetingSearchHit>[];
    for (final m in meetings) {
      final matches = <SearchMatch>[];
      int total = 0;

      void addMatch(SearchField field, String text) {
        if (text.isEmpty) return;
        final snippet = _firstSnippet(text, tokens);
        if (snippet == null) return;
        total++;
        if (matches.length < _maxMatchesPerHit) {
          matches.add(SearchMatch(field: field, snippet: snippet));
        }
      }

      addMatch(SearchField.title, m.title);
      if (m.notes.isNotEmpty) addMatch(SearchField.notes, m.notes);
      if (m.tags.isNotEmpty) {
        addMatch(SearchField.tags, m.tags.join(', '));
      }

      final s = summaryByMeetingId[m.id];
      if (s != null) {
        addMatch(SearchField.summaryTitle, s.meetingTitle);
        if (s.participants.isNotEmpty) {
          addMatch(SearchField.participants, s.participants.join(', '));
        }
        for (final d in s.keyDiscussions) {
          addMatch(SearchField.keyDiscussions, d);
        }
        for (final d in s.decisions) {
          addMatch(SearchField.decisions, d);
        }
        for (final oq in s.openQuestions) {
          addMatch(SearchField.openQuestions, oq);
        }
        // actionItems는 JSON 문자열로 저장 — 파싱해서 task/owner 검색
        try {
          final items = (jsonDecode(s.actionItemsJson) as List)
              .cast<Map<String, dynamic>>();
          for (final it in items) {
            final combined =
                '${it['task'] ?? ''} ${it['owner'] ?? ''} ${it['deadline'] ?? ''}';
            addMatch(SearchField.actionItems, combined);
          }
        } catch (_) {}
      }

      // 전사본 매칭 — 세그먼트별 첫 스니펫
      final transcriptSegments = transcriptHitsByMeeting[m.id];
      if (transcriptSegments != null) {
        for (final seg in transcriptSegments) {
          addMatch(SearchField.transcript, seg);
        }
      }

      if (total > 0) {
        hits.add(MeetingSearchHit(
          meetingId: m.id,
          totalMatches: total,
          topMatches: matches,
        ));
      }
    }

    // 매치 수 내림차순, 동률이면 최신순
    hits.sort((a, b) {
      final c = b.totalMatches.compareTo(a.totalMatches);
      if (c != 0) return c;
      final ma = meetings.firstWhere((m) => m.id == a.meetingId);
      final mb = meetings.firstWhere((m) => m.id == b.meetingId);
      return mb.createdAt.compareTo(ma.createdAt);
    });

    return hits;
  }

  /// Isar textContains로 각 토큰 매칭 세그먼트 조회 후 교집합으로 meetingId 축소.
  /// 반환: meetingId → 매칭된 세그먼트 text 리스트 (세그먼트별 중복 없음)
  static Future<Map<int, List<String>>> _fetchTranscriptHits(
      List<String> tokens) async {
    final db = IsarService.instance.db;
    Set<int>? commonSegmentIds;
    final segmentTexts = <int, Transcript>{};

    for (final t in tokens) {
      final segs = await db.transcripts
          .filter()
          .textContains(t, caseSensitive: false)
          .findAll();
      final ids = segs.map((e) => e.id).toSet();
      for (final s in segs) {
        segmentTexts[s.id] = s;
      }
      commonSegmentIds = (commonSegmentIds == null)
          ? ids
          : commonSegmentIds.intersection(ids);
      if (commonSegmentIds.isEmpty) break;
    }

    final result = <int, List<String>>{};
    if (commonSegmentIds == null) return result;
    for (final id in commonSegmentIds) {
      final seg = segmentTexts[id]!;
      result.putIfAbsent(seg.meetingId, () => []).add(seg.text);
    }
    return result;
  }

  /// 텍스트에서 모든 토큰이 등장하면 첫 매치 주변 스니펫 생성.
  /// 한 토큰이라도 빠지면 null.
  static String? _firstSnippet(String text, List<String> tokens) {
    final lower = text.toLowerCase();
    int firstIdx = -1;
    for (final t in tokens) {
      final idx = lower.indexOf(t);
      if (idx < 0) return null;
      if (firstIdx < 0 || idx < firstIdx) firstIdx = idx;
    }
    final start = (firstIdx - _snippetRadius).clamp(0, text.length);
    final end = (firstIdx + _snippetRadius * 2).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end).replaceAll('\n', ' ')}$suffix';
  }
}
