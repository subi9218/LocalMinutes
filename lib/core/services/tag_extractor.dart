import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/datasources/llm_service.dart';
import '../../domain/entities/summary.dart' as entity;

/// 회의 요약 내용을 분석해 검색·필터링용 태그를 자동 추출.
///
/// LLM이 이미 로드된 상태에서만 호출 (별도 모델 로드 안 함).
/// 짧고 빠른 호출 — 출력 200토큰 이내 / temperature 낮춤.
class TagExtractor {
  TagExtractor._();

  /// 기존 태그를 보존하면서 새 추천 태그를 뒤에 붙인다.
  ///
  /// 사용자가 직접 붙인 태그가 재요약/자동 추천 과정에서 사라지지 않도록
  /// 모든 자동 적용 경로에서 이 메서드를 사용한다.
  static List<String> mergeTags(
    List<String> existing,
    List<String> suggested, {
    int maxTags = 8,
  }) {
    final merged = <String>[];
    final seen = <String>{};

    void add(String value) {
      final tag = value.trim();
      if (tag.isEmpty || _isTooGeneric(tag) || tag.length > 14) return;
      final key = normalizeTagKey(tag);
      if (seen.contains(key)) return;
      seen.add(key);
      merged.add(tag);
    }

    for (final tag in existing) {
      add(tag);
    }
    for (final tag in suggested) {
      if (merged.length >= maxTags) break;
      add(tag);
    }
    return merged;
  }

  static String normalizeTagKey(String tag) =>
      tag.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// LLM이 로드된 상태에서 [summary]로부터 3~5개의 태그를 추출.
  /// 실패 시 빈 리스트 반환 (예외 던지지 않음).
  static Future<List<String>> extractFromSummary(
    entity.Summary summary, {
    String notes = '',
    String agenda = '',
    int maxTags = 5,
  }) async {
    final title = summary.meetingTitle.trim();
    final discussions = summary.keyDiscussions.take(8).join('\n- ');
    final decisions = summary.decisions.take(5).join('\n- ');
    final openQuestions = summary.openQuestions.take(3).join('\n- ');

    final ctxParts = <String>[];
    if (title.isNotEmpty) ctxParts.add('제목: $title');
    if (agenda.trim().isNotEmpty) {
      ctxParts.add('어젠다:\n${agenda.trim()}');
    }
    if (discussions.isNotEmpty) ctxParts.add('주요 논의:\n- $discussions');
    if (decisions.isNotEmpty) ctxParts.add('결정사항:\n- $decisions');
    if (openQuestions.isNotEmpty) {
      ctxParts.add('미해결 이슈:\n- $openQuestions');
    }
    if (notes.trim().isNotEmpty) {
      ctxParts.add('메모:\n${notes.trim()}');
    }

    if (ctxParts.isEmpty) return const [];

    final prompt =
        '''
아래 회의 요약을 보고, 회의 검색·분류에 유용한 짧은 태그를 정확히 $maxTags개 이하로 추출하세요.

[태그 작성 규칙]
- 한 태그는 1~10자 한글/영문 단어 또는 짧은 명사구.
- 사람 이름·회사 내 고유명사는 들어가도 좋음.
- 너무 일반적인 단어("회의", "논의", "이야기", "주간", "미팅") 단독 사용 금지.
- 같은 의미 태그 중복 금지 (예: "기획", "기획팀" 동시 출력 금지 — 더 구체적인 것 1개).
- 영어와 한국어 혼용 가능. 약어(QA, KPI 등) 허용.
- 형용사·부사 제외, 명사 위주.

JSON 배열만 출력. 다른 설명·머리말·따옴표·코드블록 금지.
형식 예시: ["로그 수집", "QA", "결제 모듈"]

[회의 정보]
${ctxParts.join('\n\n')}

JSON:''';

    final buf = StringBuffer();
    try {
      await for (final tok in LlmService.instance.generate(
        userMessage: prompt,
        maxTokens: 200,
        temperature: 0.2,
        topP: 0.8,
      )) {
        buf.write(tok);
      }
    } catch (e) {
      debugPrint('[TagExtractor] generate error: $e');
      return const [];
    }

    return _parseTags(buf.toString(), maxTags: maxTags);
  }

  /// LLM 출력에서 JSON 배열만 추출해 태그 리스트로 변환.
  static List<String> _parseTags(String raw, {int maxTags = 5}) {
    if (raw.trim().isEmpty) return const [];
    String? jsonStr;

    // 1) ```json ... ``` 코드블록
    final cb = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(raw);
    if (cb != null) jsonStr = cb.group(1)?.trim();

    // 2) 첫 [ ~ 마지막 ] 추출
    if (jsonStr == null) {
      final s = raw.indexOf('[');
      final e = raw.lastIndexOf(']');
      if (s != -1 && e > s) jsonStr = raw.substring(s, e + 1);
    }

    if (jsonStr == null) return const [];

    try {
      final list = jsonDecode(jsonStr) as List;
      final tags = <String>[];
      final seen = <String>{};
      for (final v in list) {
        final raw = v.toString().trim();
        if (raw.isEmpty) continue;
        // 너무 일반적인 단어 필터
        if (_isTooGeneric(raw)) continue;
        // 길이 검증
        if (raw.length > 14) continue;
        final key = normalizeTagKey(raw);
        if (seen.contains(key)) continue;
        seen.add(key);
        tags.add(raw);
        if (tags.length >= maxTags) break;
      }
      return tags;
    } catch (e) {
      debugPrint('[TagExtractor] parse error: $e (rawLength=${raw.length})');
      return const [];
    }
  }

  static const _genericBlocked = {
    '회의',
    '미팅',
    '논의',
    '이야기',
    '대화',
    '회의록',
    '주간',
    '월간',
    '일간',
    '정기',
    '내용',
    '주제',
    'meeting',
    'discussion',
    'note',
    'notes',
  };

  static bool _isTooGeneric(String tag) {
    final norm = tag.trim().toLowerCase();
    return _genericBlocked.contains(norm);
  }
}
