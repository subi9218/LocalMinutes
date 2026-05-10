import '../../data/datasources/llm_service.dart';
import '../../domain/entities/meeting.dart' show Bookmark;
import '../utils/summary_parser.dart';

class SummaryCancelledException implements Exception {
  final String message;
  const SummaryCancelledException([this.message = '요약 작업이 중지되었습니다.']);

  @override
  String toString() => message;
}

class _SummaryTuning {
  final int singlePassThreshold;
  final int chunkSize;
  final int partialMaxTokens;
  final int finalMaxTokens;
  final int bulletsPerChunk;

  const _SummaryTuning({
    required this.singlePassThreshold,
    required this.chunkSize,
    required this.partialMaxTokens,
    required this.finalMaxTokens,
    required this.bulletsPerChunk,
  });
}

/// 긴 회의 전사본을 map-reduce 방식으로 요약.
///
/// 흐름:
///   - 전사본이 [_singlePassThreshold] 이하 → 기존 단일 프롬프트 그대로
///   - 초과 → `_chunkSize` 단위로 분할 → 각 구간 bullet 요약 (map)
///            → 구간 요약을 합쳐 최종 JSON 요약 (reduce)
///
/// 이유: 27분 회의의 경우 전사본 ~18,000자 인데 단일 프롬프트 trunc(5500자)로
/// 중반부 내용이 통째로 잘려 나감. 청크 방식은 모든 구간을 LLM이 한 번씩
/// 보게 하므로 디테일 손실이 최소화된다.
class ChunkedSummarizer {
  /// 이 이하 길이면 기존 단일 프롬프트 플로우 사용
  static const int _singlePassThreshold = 6000;

  /// 각 청크의 최대 글자수 — nCtx=8192 토큰 예산 내 안전 범위
  static const int _chunkSize = 4500;

  /// 구간 요약 시 토큰 상한 (구간당 최대 ~600 토큰 ≈ bullet 10개)
  static const int _partialMaxTokens = 800;

  static _SummaryTuning _tuningFor(String speedMode, int requestedMaxTokens) {
    switch (speedMode) {
      case 'balanced':
        return _SummaryTuning(
          singlePassThreshold: 7000,
          chunkSize: 5500,
          partialMaxTokens: 520,
          finalMaxTokens: requestedMaxTokens.clamp(1000, 1800).toInt(),
          bulletsPerChunk: 7,
        );
      case 'detailed':
        return _SummaryTuning(
          singlePassThreshold: _singlePassThreshold,
          chunkSize: _chunkSize,
          partialMaxTokens: _partialMaxTokens,
          finalMaxTokens: requestedMaxTokens,
          bulletsPerChunk: 10,
        );
      case 'fast':
      default:
        return _SummaryTuning(
          singlePassThreshold: 9000,
          chunkSize: 7000,
          partialMaxTokens: 360,
          finalMaxTokens: requestedMaxTokens.clamp(800, 1300).toInt(),
          bulletsPerChunk: 5,
        );
    }
  }

  /// 청크 요약 진행도 콜백
  /// 0.0 ~ 0.9 구간은 map 단계, 0.9 ~ 1.0 은 reduce 단계.
  ///
  /// [onPreview]: 토큰 단위로 누적된 현재 생성 중인 텍스트를 라이브 전달.
  ///   - 단일 패스: 최종 응답 텍스트가 실시간으로 흘러 들어감
  ///   - map 단계: 각 구간의 bullet 응답이 흘러 들어감 (구간 전환 시 리셋)
  ///   - reduce 단계: 최종 JSON 응답이 흘러 들어감
  static Future<String> summarize({
    required String transcript,
    required String dateStr,
    String notes = '',
    List<String> participants = const [],
    String glossary = '',
    String instruction = '',
    String agenda = '',
    List<Bookmark> bookmarks = const [],
    int maxTokens = 2500,
    String speedMode = 'fast',
    void Function(String phase, double progress)? onProgress,
    void Function(String partial)? onPreview,
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() == true) {
        throw const SummaryCancelledException();
      }
    }

    checkCancelled();
    final tuning = _tuningFor(speedMode, maxTokens);

    // ── 짧은 회의 → 기존 단일 패스 ─────────────────────────
    if (transcript.length <= tuning.singlePassThreshold) {
      onProgress?.call('요약 생성 중... (0 토큰)', 0.0);
      final prompt = SummaryParser.buildPrompt(
        transcript,
        dateStr,
        notes: notes,
        participants: participants,
        glossary: glossary,
        instruction: instruction,
        agenda: agenda,
        bookmarks: bookmarks,
      );
      return _runLlm(
        prompt,
        tuning.finalMaxTokens,
        temperature: 0.25,
        topP: 0.85,
        isCancelled: isCancelled,
        onToken: (partial, tokCount) {
          checkCancelled();
          onPreview?.call(partial);
          onProgress?.call(
            '요약 생성 중... ($tokCount 토큰)',
            (tokCount / tuning.finalMaxTokens).clamp(0.0, 0.99),
          );
        },
      );
    }

    // ── 긴 회의 → map-reduce ─────────────────────────────
    final chunks = _splitByNewline(transcript, tuning.chunkSize);
    final partials = <String>[];

    for (int i = 0; i < chunks.length; i++) {
      checkCancelled();
      final base = i / chunks.length * 0.9;
      final span = 1.0 / chunks.length * 0.9;
      onProgress?.call('구간 요약 ${i + 1}/${chunks.length} (0 토큰)', base);
      final chunkPrompt = _buildChunkPrompt(
        chunks[i],
        i + 1,
        chunks.length,
        glossary,
        instruction,
        tuning.bulletsPerChunk,
      );
      final partial = await _runLlm(
        chunkPrompt,
        tuning.partialMaxTokens,
        temperature: 0.3,
        topP: 0.85,
        isCancelled: isCancelled,
        onToken: (text, tokCount) {
          checkCancelled();
          onPreview?.call(text);
          final frac = (tokCount / tuning.partialMaxTokens).clamp(0.0, 1.0);
          onProgress?.call(
            '구간 요약 ${i + 1}/${chunks.length} ($tokCount 토큰)',
            base + span * frac,
          );
        },
      );
      partials.add(_extractBullets(partial));
    }

    checkCancelled();
    onProgress?.call('구간 통합 중... (0 토큰)', 0.92);

    // 구간 요약들을 하나의 "전사본"으로 합쳐서 최종 JSON 요약
    final mergedText = StringBuffer();
    for (int i = 0; i < partials.length; i++) {
      mergedText.writeln('## 구간 ${i + 1}');
      mergedText.writeln(partials[i].trim());
      mergedText.writeln();
    }

    final finalPrompt = SummaryParser.buildPrompt(
      mergedText.toString().trim(),
      dateStr,
      notes: notes,
      participants: participants,
      glossary: glossary,
      instruction: instruction.isEmpty
          ? '아래는 긴 회의를 구간별로 미리 요약한 결과입니다. 전체 회의를 종합해 JSON만 출력하세요.'
          : '$instruction\n\n아래는 긴 회의를 구간별로 미리 요약한 결과입니다. 전체 회의를 종합해 JSON만 출력하세요.',
      agenda: agenda,
      bookmarks: bookmarks,
    );
    return _runLlm(
      finalPrompt,
      tuning.finalMaxTokens,
      temperature: 0.2,
      topP: 0.85,
      isCancelled: isCancelled,
      onToken: (text, tokCount) {
        checkCancelled();
        onPreview?.call(text);
        final frac = (tokCount / tuning.finalMaxTokens).clamp(0.0, 1.0);
        onProgress?.call('최종 요약 중... ($tokCount 토큰)', 0.92 + 0.07 * frac);
      },
    );
  }

  // ── 내부 유틸 ────────────────────────────────────────────

  /// [onToken]: (누적 텍스트, 현재까지 토큰 수) 를 스트리밍으로 전달.
  static Future<String> _runLlm(
    String prompt,
    int maxTokens, {
    double temperature = 0.3,
    double topP = 0.85,
    bool Function()? isCancelled,
    void Function(String partial, int tokCount)? onToken,
  }) async {
    final buf = StringBuffer();
    int tokCount = 0;
    var cancelled = false;
    await for (final tok in LlmService.instance.generate(
      userMessage: prompt,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      isCancelled: isCancelled,
    )) {
      if (cancelled || isCancelled?.call() == true) {
        cancelled = true;
        continue;
      }
      buf.write(tok);
      tokCount++;
      onToken?.call(buf.toString(), tokCount);
    }
    if (cancelled || isCancelled?.call() == true) {
      throw const SummaryCancelledException();
    }
    return buf.toString();
  }

  /// 줄바꿈 경계 우선으로 [maxChars] 크기로 분할.
  /// 세그먼트 한 줄 ( `[mm:ss → mm:ss] text` ) 가 깨지지 않게 유지.
  static List<String> _splitByNewline(String text, int maxChars) {
    final chunks = <String>[];
    int i = 0;
    while (i < text.length) {
      int end = i + maxChars;
      if (end >= text.length) {
        chunks.add(text.substring(i));
        break;
      }
      // 75% 지점 이후의 마지막 '\n' 에서 끊기
      final lastNewline = text.lastIndexOf('\n', end);
      if (lastNewline > i + (maxChars * 0.75).toInt()) {
        end = lastNewline;
      }
      chunks.add(text.substring(i, end));
      i = end;
      // 앞쪽 공백/개행 건너뛰기
      while (i < text.length && (text[i] == '\n' || text[i] == ' ')) {
        i++;
      }
    }
    return chunks;
  }

  /// 구간 단위 요약 프롬프트 — bullet list만 뽑는 경량 요청.
  static String _buildChunkPrompt(
    String chunk,
    int idx,
    int total,
    String glossary,
    String instruction,
    int maxBullets,
  ) {
    final presetGuide = instruction.trim().isEmpty
        ? ''
        : '''

[적용할 회의 유형 지침]
$instruction
''';

    return '''아래는 회의 전사본의 $idx/$total 구간입니다. 이 구간에서 실제로 논의된 내용을 한국어 bullet list로 정리하세요.

규칙:
- 수치·고유명사·인용된 표현은 원문 그대로 보존 (추상화 금지).
- "~에 대해 논의" 같은 모호한 서술 대신, 실제 발언·결론을 구체적으로 쓰세요.
- 항목당 한 줄, 최대 $maxBullets개 bullet.
- 각 줄은 "- " 로 시작. JSON이나 다른 포맷 쓰지 마세요.
- 이 구간에 결정 사항·액션 아이템·미해결 질문이 있으면 문장 앞에 [결정], [액션], [질문] 태그를 붙이세요.
- 담당자나 기한이 불명확해도 후속 조치라면 [액션]으로 남기고 "(미언급)"을 함께 적으세요.
- 회의 유형 지침이 Keep/Problem/Try 또는 Q/A 구조를 요구하면, 구간 요약 bullet에서도 그 구조를 유지하세요.
$glossary
$presetGuide
전사본 구간:
$chunk

요약:''';
  }

  /// LLM 응답에서 bullet 영역만 추출 (사족 제거).
  static String _extractBullets(String raw) {
    // 채팅 템플릿 잔재 제거
    final cleaned = raw.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    final lines = cleaned.split('\n');
    final bullets = <String>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('-') || t.startsWith('•') || t.startsWith('*')) {
        bullets.add(
          t.startsWith('•') || t.startsWith('*')
              ? '- ${t.substring(1).trim()}'
              : t,
        );
      }
    }
    if (bullets.isNotEmpty) return bullets.join('\n');
    // bullet 감지 실패 → 원문 그대로 (파서가 다음 단계에서 처리)
    return cleaned;
  }
}
