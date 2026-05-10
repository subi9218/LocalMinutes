import '../../data/datasources/stt_service.dart';
import '../../domain/entities/glossary_entry.dart';

/// 전사 결과 후처리 교정기.
///
/// 단어집 엔트리의 `aliases` (콤마 구분)를 **역방향 치환 규칙**으로 재해석한다.
/// 예: GlossaryEntry(term="빅쿼리", aliases="비커리, 빅커리")
///   → 전사에서 "비커리" / "빅커리" 등장 시 "빅쿼리"로 자동 교정.
///
/// 이렇게 하면 Whisper initial_prompt(인식 전 유도)와 후처리(인식 후 교정)가
/// **같은 단어집 한 벌**을 공유 — 사용자는 한 번만 등록하면 된다.
///
/// 적용 범위:
///   - 긴 별칭(길이 내림차순)부터 적용 → 부분 겹침 방지
///   - 한글은 단어 경계 개념이 모호하므로 **단순 문자열 치환** 사용
///   - 영문 별칭만 대소문자 무시
///   - 비어 있거나 1글자 별칭은 스킵 (오버매칭 위험)
class TranscriptCorrector {
  final List<_Rule> _rules;

  TranscriptCorrector._(this._rules);

  static const List<_Rule> _builtInRules = [
    _Rule(alias: 'GQ팀', term: '지표팀', caseInsensitive: false),
    _Rule(alias: 'gq팀', term: '지표팀', caseInsensitive: true),
    _Rule(alias: '로고 설계', term: '로그 설계', caseInsensitive: false),
    _Rule(alias: '로고 아이디', term: '로그 아이디', caseInsensitive: false),
    _Rule(alias: '로고 디테일', term: '로그 디테일', caseInsensitive: false),
    _Rule(alias: '로고 관련', term: '로그 관련', caseInsensitive: false),
    _Rule(alias: '로고 개발', term: '로그 개발', caseInsensitive: false),
    _Rule(alias: '로고 조회', term: '로그 조회', caseInsensitive: false),
    _Rule(alias: '로고를 쏴', term: '로그를 쏴', caseInsensitive: false),
    _Rule(alias: '로고를 한번', term: '로그를 한번', caseInsensitive: false),
    _Rule(alias: 'S로고', term: 'S로그', caseInsensitive: false),
    _Rule(alias: 's로고', term: 'S로그', caseInsensitive: true),
    _Rule(alias: 'Q&A 1차', term: 'QA 1차', caseInsensitive: false),
    _Rule(alias: 'Q&A를', term: 'QA를', caseInsensitive: false),
    _Rule(alias: 'Q&A만', term: 'QA만', caseInsensitive: false),
    _Rule(alias: 'Q&A 같이', term: 'QA 같이', caseInsensitive: false),
  ];

  /// 단어집 엔트리 → 교정 규칙 빌드.
  factory TranscriptCorrector.fromGlossary(List<GlossaryEntry> entries) {
    final rules = <_Rule>[..._builtInRules];
    for (final e in entries) {
      final term = e.term.trim();
      if (term.isEmpty) continue;
      for (final raw in e.aliasList) {
        final alias = raw.trim();
        if (alias.length < 2) continue; // 1글자 alias는 오버매칭 위험
        if (alias == term) continue;
        // 영문만 포함된 alias는 대소문자 무시
        final isAscii = RegExp(r'^[\x20-\x7E]+$').hasMatch(alias);
        rules.add(_Rule(alias: alias, term: term, caseInsensitive: isAscii));
      }
    }
    // 긴 별칭 먼저 적용 — "몽길2"가 "몽길"보다 먼저 매치되어야 함
    rules.sort((a, b) => b.alias.length.compareTo(a.alias.length));
    return TranscriptCorrector._(rules);
  }

  bool get isEmpty => _rules.isEmpty;

  /// 세그먼트 리스트 전체에 치환 적용. 시간/원본 순서는 보존.
  List<SttSegment> apply(List<SttSegment> segments) {
    if (_rules.isEmpty) return segments;
    return segments.map((s) {
      final fixed = correctText(s.text);
      return fixed == s.text ? s : s.copyWith(text: fixed);
    }).toList();
  }

  /// 단일 문자열에 치환 적용 (요약 프롬프트 용도로도 노출).
  String correctText(String input) {
    if (_rules.isEmpty || input.isEmpty) return input;
    var out = input;
    for (final r in _rules) {
      if (r.caseInsensitive) {
        // 영문 alias: i 플래그로 치환
        out = out.replaceAll(
          RegExp(RegExp.escape(r.alias), caseSensitive: false),
          r.term,
        );
      } else {
        out = out.replaceAll(r.alias, r.term);
      }
    }
    return out;
  }
}

class _Rule {
  final String alias;
  final String term;
  final bool caseInsensitive;
  const _Rule({
    required this.alias,
    required this.term,
    required this.caseInsensitive,
  });
}
