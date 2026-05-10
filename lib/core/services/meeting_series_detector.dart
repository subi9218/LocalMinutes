import 'dart:convert';
import 'dart:math';

import '../../domain/entities/meeting.dart';
import '../../domain/entities/summary.dart';

class MeetingSeriesSuggestion {
  final String suggestedName;
  final List<Meeting> meetings;
  final double confidence;
  final List<String> reasons;
  final List<String> sharedTags;
  final List<String> sharedParticipants;

  const MeetingSeriesSuggestion({
    required this.suggestedName,
    required this.meetings,
    required this.confidence,
    required this.reasons,
    this.sharedTags = const [],
    this.sharedParticipants = const [],
  });
}

class MeetingSeriesDetector {
  static List<MeetingSeriesSuggestion> suggestSeries({
    required List<Meeting> meetings,
    required List<Summary> summaries,
    int minMeetings = 2,
  }) {
    final candidates =
        meetings
            .where(
              (m) => m.groupId == null && m.status != MeetingStatus.recording,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (candidates.length < minMeetings) return const [];

    final summariesByMeetingId = {for (final s in summaries) s.meetingId: s};
    final profiles = {
      for (final m in candidates)
        m.id: _MeetingSeriesProfile.from(m, summariesByMeetingId[m.id]),
    };

    final parent = {for (final m in candidates) m.id: m.id};

    int find(int id) {
      final p = parent[id]!;
      if (p == id) return id;
      final root = find(p);
      parent[id] = root;
      return root;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    for (var i = 0; i < candidates.length; i++) {
      for (var j = i + 1; j < candidates.length; j++) {
        final a = profiles[candidates[i].id]!;
        final b = profiles[candidates[j].id]!;
        if (_pairConfidence(a, b) >= 0.72) {
          union(a.meeting.id, b.meeting.id);
        }
      }
    }

    final clusters = <int, List<_MeetingSeriesProfile>>{};
    for (final profile in profiles.values) {
      clusters.putIfAbsent(find(profile.meeting.id), () => []).add(profile);
    }

    final suggestions = <MeetingSeriesSuggestion>[];
    for (final cluster in clusters.values) {
      if (cluster.length < minMeetings) continue;
      final confidence = _clusterConfidence(cluster);
      if (confidence < 0.72) continue;
      cluster.sort(
        (a, b) => b.meeting.createdAt.compareTo(a.meeting.createdAt),
      );
      suggestions.add(
        MeetingSeriesSuggestion(
          suggestedName: _suggestName(cluster),
          meetings: cluster.map((p) => p.meeting).toList(),
          confidence: confidence,
          reasons: _reasons(cluster),
          sharedTags: _sharedValues(cluster.map((p) => p.tags).toList()),
          sharedParticipants: _sharedValues(
            cluster.map((p) => p.participants).toList(),
          ),
        ),
      );
    }

    suggestions.sort((a, b) {
      final size = b.meetings.length.compareTo(a.meetings.length);
      if (size != 0) return size;
      return b.confidence.compareTo(a.confidence);
    });
    return suggestions;
  }

  static double _pairConfidence(
    _MeetingSeriesProfile a,
    _MeetingSeriesProfile b,
  ) {
    final title = _titleSimilarity(a, b);
    final tags = _jaccard(a.tags, b.tags);
    final participants = _jaccard(a.participants, b.participants);
    final closeCadence = _cadenceBoost(
      a.meeting.createdAt,
      b.meeting.createdAt,
    );
    final score =
        title * 0.62 + participants * 0.22 + tags * 0.16 + closeCadence;
    if (a.titleKey.isNotEmpty && a.titleKey == b.titleKey) {
      return max(score, 0.82 + min(0.12, (participants + tags) * 0.06));
    }
    if (title >= 0.78 && (participants >= 0.34 || tags >= 0.34)) {
      return max(score, 0.76);
    }
    return score.clamp(0.0, 1.0);
  }

  static double _clusterConfidence(List<_MeetingSeriesProfile> cluster) {
    if (cluster.length < 2) return 0;
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < cluster.length; i++) {
      for (var j = i + 1; j < cluster.length; j++) {
        sum += _pairConfidence(cluster[i], cluster[j]);
        count++;
      }
    }
    return count == 0 ? 0 : (sum / count).clamp(0.0, 1.0);
  }

  static double _titleSimilarity(
    _MeetingSeriesProfile a,
    _MeetingSeriesProfile b,
  ) {
    if (a.titleKey.isEmpty || b.titleKey.isEmpty) return 0;
    if (a.titleKey == b.titleKey) return 1;
    final tokenScore = _jaccard(a.titleTokens, b.titleTokens);
    final containsScore =
        a.titleKey.contains(b.titleKey) || b.titleKey.contains(a.titleKey)
        ? 0.82
        : 0.0;
    return max(tokenScore, containsScore);
  }

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }

  static double _cadenceBoost(DateTime a, DateTime b) {
    final days = a.difference(b).inDays.abs();
    if (days <= 10) return 0.04;
    if (days <= 38) return 0.025;
    return 0;
  }

  static String _suggestName(List<_MeetingSeriesProfile> cluster) {
    final titleCounts = <String, int>{};
    for (final profile in cluster) {
      if (profile.displayTitle.isEmpty) continue;
      titleCounts[profile.displayTitle] =
          (titleCounts[profile.displayTitle] ?? 0) + 1;
    }
    if (titleCounts.isEmpty) return '정기 회의';
    final sorted = titleCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.length.compareTo(b.key.length);
      });
    return sorted.first.key;
  }

  static List<String> _reasons(List<_MeetingSeriesProfile> cluster) {
    final reasons = <String>[];
    final titleKeys = cluster
        .map((p) => p.titleKey)
        .where((k) => k.isNotEmpty)
        .toSet();
    if (titleKeys.length == 1) {
      reasons.add('비슷한 회의 제목');
    } else {
      final maxTitleSimilarity = _maxPair(cluster, _titleSimilarity);
      if (maxTitleSimilarity >= 0.78) reasons.add('제목 패턴 유사');
    }

    final sharedTags = _sharedValues(cluster.map((p) => p.tags).toList());
    if (sharedTags.isNotEmpty) {
      reasons.add('공통 태그 ${sharedTags.take(3).map((t) => '#$t').join(', ')}');
    }

    final sharedParticipants = _sharedValues(
      cluster.map((p) => p.participants).toList(),
    );
    if (sharedParticipants.isNotEmpty) {
      reasons.add('반복 참석자 ${sharedParticipants.take(3).join(', ')}');
    }
    if (reasons.isEmpty) reasons.add('제목과 메타데이터가 반복됨');
    return reasons;
  }

  static double _maxPair(
    List<_MeetingSeriesProfile> cluster,
    double Function(_MeetingSeriesProfile, _MeetingSeriesProfile) score,
  ) {
    var best = 0.0;
    for (var i = 0; i < cluster.length; i++) {
      for (var j = i + 1; j < cluster.length; j++) {
        best = max(best, score(cluster[i], cluster[j]));
      }
    }
    return best;
  }

  static List<String> _sharedValues(List<Set<String>> sets) {
    if (sets.length < 2) return const [];
    var shared = Set<String>.from(sets.first);
    for (final set in sets.skip(1)) {
      shared = shared.intersection(set);
    }
    final values = shared.toList()..sort();
    return values;
  }
}

class _MeetingSeriesProfile {
  final Meeting meeting;
  final String titleKey;
  final String displayTitle;
  final Set<String> titleTokens;
  final Set<String> tags;
  final Set<String> participants;

  const _MeetingSeriesProfile({
    required this.meeting,
    required this.titleKey,
    required this.displayTitle,
    required this.titleTokens,
    required this.tags,
    required this.participants,
  });

  factory _MeetingSeriesProfile.from(Meeting meeting, Summary? summary) {
    final title = _normalizeTitle(meeting.title);
    return _MeetingSeriesProfile(
      meeting: meeting,
      titleKey: title.key,
      displayTitle: title.display,
      titleTokens: title.tokens,
      tags: meeting.tags.map(_normalizeValue).where(_isUsefulValue).toSet(),
      participants: _participants(meeting, summary),
    );
  }

  static Set<String> _participants(Meeting meeting, Summary? summary) {
    final names = <String>{};
    if (summary != null) {
      names.addAll(summary.participants);
    }
    if (meeting.speakerNamesJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(meeting.speakerNamesJson);
        if (decoded is Map) {
          names.addAll(decoded.values.map((v) => v.toString()));
        }
      } catch (_) {}
    }
    return names.map(_normalizeValue).where(_isUsefulParticipant).toSet();
  }
}

({String key, String display, Set<String> tokens}) _normalizeTitle(String raw) {
  var title = raw
      .replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '')
      .replaceAll(RegExp(r'\.(wav|mp3|m4a)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\b\d{4}[-./년]\s*\d{1,2}[-./월]\s*\d{1,2}일?\b'), ' ')
      .replaceAll(RegExp(r'\b\d{1,2}[-./]\d{1,2}\b'), ' ')
      .replaceAll(RegExp(r'\b\d{1,2}:\d{2}\b'), ' ')
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim();
  title = title.replaceAll(RegExp(r'\s+'), ' ');

  final key = _normalizeValue(title);
  final tokens = key
      .split(' ')
      .where((t) => t.length >= 2 && !_genericTitleTokens.contains(t))
      .toSet();
  final usefulKey = tokens.isEmpty || _genericTitleKeys.contains(key)
      ? ''
      : key;
  return (
    key: usefulKey,
    display: title.isEmpty ? raw.trim() : title,
    tokens: tokens,
  );
}

String _normalizeValue(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w가-힣]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _isUsefulValue(String value) =>
    value.length >= 2 && !_genericTagValues.contains(value);

bool _isUsefulParticipant(String value) =>
    _isUsefulValue(value) &&
    !RegExp(r'^(화자|speaker|참석자|발표자)\s*[a-z0-9가-힣]?$').hasMatch(value);

const _genericTitleKeys = {'회의', '미팅', '정기 회의', '회의록', '새 회의'};

const _genericTitleTokens = {'회의', '미팅', '정기', '회의록', '녹음', '불러옴'};

const _genericTagValues = {'회의', '미팅', '업무', '논의', '요약'};
