/// 요약 프롬프트에 넣기 전 전사 텍스트를 가볍게 정리한다.
///
/// 저장된 원본 전사본은 보존하고, LLM 입력에서만 반복/오버랩 문장을 줄여
/// 중복 발화가 요약에서 과대표현되는 문제를 완화한다.
class TranscriptTextCleaner {
  TranscriptTextCleaner._();

  static String cleanForSummary(String transcript) {
    if (transcript.trim().isEmpty) return transcript;
    final lines = transcript
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length <= 1) return transcript.trim();

    final kept = <String>[];
    final recent = <_LineSig>[];

    for (final line in lines) {
      final sig = _LineSig.fromLine(line);
      if (sig.body.length < 4) {
        kept.add(line);
        continue;
      }

      final duplicate = recent.any((prev) => _isNearDuplicate(prev, sig));
      if (!duplicate) {
        kept.add(line);
        recent.add(sig);
        if (recent.length > 10) recent.removeAt(0);
      }
    }

    return kept.join('\n');
  }

  static String _lineBody(String line) {
    var out = line.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
    out = out.replaceFirst(RegExp(r'^화자\s+[A-Z0-9가-힣]+:\s*'), '');
    return out.trim();
  }

  static String _norm(String input) => input
      .replaceAll(RegExp(r'[\s.,!?…·"“”‘’()\[\]{}:;~\-]+'), '')
      .toLowerCase();

  static bool _isNearDuplicate(_LineSig a, _LineSig b) {
    if (!_isTimeClose(a, b)) return false;
    if (!_sameNumbers(a.body, b.body)) return false;

    final an = _norm(a.body);
    final bn = _norm(b.body);
    if (an.isEmpty || bn.isEmpty) return false;
    if (an == bn) return true;
    if (an.length >= 8 && bn.contains(an)) return true;
    if (bn.length >= 8 && an.contains(bn)) return true;
    final shorter = an.length < bn.length ? an : bn;
    if (shorter.length < 10) return false;
    return _charBigramSimilarity(an, bn) >= 0.76 ||
        _longestCommonSubstringRatio(an, bn) >= 0.88;
  }

  static bool _isTimeClose(_LineSig a, _LineSig b) {
    if (a.startMs == null || b.startMs == null) return true;
    final overlap = b.startMs! <= (a.endMs ?? a.startMs!) + 6000;
    final startClose = (b.startMs! - a.startMs!).abs() <= 8000;
    return overlap || startClose;
  }

  static bool _sameNumbers(String a, String b) {
    final ar = RegExp(r'\d+').allMatches(a).map((m) => m.group(0)).toList();
    final br = RegExp(r'\d+').allMatches(b).map((m) => m.group(0)).toList();
    if (ar.isEmpty && br.isEmpty) return true;
    if (ar.length != br.length) return false;
    for (var i = 0; i < ar.length; i++) {
      if (ar[i] != br[i]) return false;
    }
    return true;
  }

  static double _charBigramSimilarity(String a, String b) {
    final aSet = _bigrams(a);
    final bSet = _bigrams(b);
    if (aSet.isEmpty || bSet.isEmpty) return 0;
    var hit = 0;
    for (final gram in aSet) {
      if (bSet.contains(gram)) hit++;
    }
    final union = {...aSet, ...bSet}.length;
    return union == 0 ? 0 : hit / union;
  }

  static Set<String> _bigrams(String input) {
    if (input.length < 2) return {input};
    final grams = <String>{};
    for (var i = 0; i < input.length - 1; i++) {
      grams.add(input.substring(i, i + 2));
    }
    return grams;
  }

  static double _longestCommonSubstringRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    var best = 0;
    for (var i = 0; i < a.length; i++) {
      for (var j = 0; j < b.length; j++) {
        var k = 0;
        while (i + k < a.length && j + k < b.length && a[i + k] == b[j + k]) {
          k++;
        }
        if (k > best) best = k;
      }
    }
    final shorter = a.length < b.length ? a.length : b.length;
    return shorter == 0 ? 0 : best / shorter;
  }
}

class _LineSig {
  final String body;
  final int? startMs;
  final int? endMs;

  const _LineSig({
    required this.body,
    required this.startMs,
    required this.endMs,
  });

  factory _LineSig.fromLine(String line) {
    final times = RegExp(
      r'^\[(\d{1,2}):(\d{2})\s*(?:→|->)\s*(\d{1,2}):(\d{2})\]',
    ).firstMatch(line);
    int? start;
    int? end;
    if (times != null) {
      start =
          ((int.parse(times.group(1)!) * 60) + int.parse(times.group(2)!)) *
          1000;
      end =
          ((int.parse(times.group(3)!) * 60) + int.parse(times.group(4)!)) *
          1000;
    }
    return _LineSig(
      body: TranscriptTextCleaner._lineBody(line),
      startMs: start,
      endMs: end,
    );
  }
}
