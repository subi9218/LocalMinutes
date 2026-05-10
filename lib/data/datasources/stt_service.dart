import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import '../../core/ffi/whisper_ffi.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/isar_service.dart';
import '../../core/utils/silence_gate.dart';
import '../../core/utils/transcript_corrector.dart';
import '../../core/utils/wav_loader.dart';
import '../repositories/glossary_repository_impl.dart';

// 전사 결과 세그먼트 (Isolate 간 Map으로 전달 후 변환)
class SttSegment {
  final String text;
  final int startMs;
  final int endMs;

  const SttSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  String get timestampStr {
    String fmt(int ms) {
      final s = ms ~/ 1000;
      return '${(s ~/ 60).toString().padLeft(2, '0')}:'
          '${(s % 60).toString().padLeft(2, '0')}';
    }

    return '[${fmt(startMs)} → ${fmt(endMs)}]';
  }

  SttSegment copyWith({String? text}) =>
      SttSegment(text: text ?? this.text, startMs: startMs, endMs: endMs);

  @override
  String toString() => '$timestampStr $text';
}

class SttCancelledException implements Exception {
  final String message;
  const SttCancelledException([this.message = 'STT 작업이 중지되었습니다.']);

  @override
  String toString() => message;
}

// Isolate 간 전달 파라미터 (SendPort 호환 타입만 사용)
class _TranscribeParams {
  final SendPort sendPort;
  final int ctxAddr; // Pointer<Void>.address
  final TransferableTypedData samplesTransferable; // Zero-copy 전달
  final String language; // 'ko', 'en', 'ja', 'zh' 등
  final int nThreads;
  final String initialPrompt; // Whisper 컨텍스트 힌트 (빈 문자열 허용)
  final int decodeMode; // 0=greedy, 1=beam2, 2=beam5
  final SendPort? progressPort; // 세그먼트 진행률 이벤트 수신처 (null=미사용)

  const _TranscribeParams({
    required this.sendPort,
    required this.ctxAddr,
    required this.samplesTransferable,
    this.language = 'ko',
    this.nThreads = 6,
    this.initialPrompt = '',
    this.decodeMode = 1,
    this.progressPort,
  });
}

class SttService {
  static final SttService instance = SttService._();
  SttService._();

  static const int _sampleRate = 16000;
  static const int _longFileThresholdSamples = _sampleRate * 90;
  static const int _fileChunkSamples = _sampleRate * 30;
  static const int _fileChunkOverlapSamples = _sampleRate * 2;

  /// 단어집 + (옵션) 참석자 이름으로 Whisper initial_prompt 문자열 생성.
  /// Whisper 프롬프트 토큰은 제한(~224)이 있으므로 용어는 앞에서부터 잘라낸다.
  ///
  /// 예시 출력: "용어: 넷마블, Gemma, Isar, Riverpod. 참석자: 민수, 지수."
  Future<String> _buildInitialPrompt({
    List<String> participants = const [],
    String? language,
  }) async {
    try {
      final lang = language ?? AppSettings.instance.sttLanguage;
      final repo = GlossaryRepositoryImpl(IsarService.instance.db);
      final all = await repo.getAllEntries();
      final terms = all
          .map((e) => e.term.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final parts = <String>[];
      if (terms.isNotEmpty) {
        // v1.9.8: 120→400자 확장 (Whisper ~224 토큰 예산 내 한글 기준 안전 범위).
        // 고유명사 혼동(빅쿼리→비커리, 패스워드→페소드 등) 완화 목적.
        final limited = <String>[];
        int charCount = 0;
        for (final t in terms) {
          if (charCount + t.length + 2 > 400) break;
          limited.add(t);
          charCount += t.length + 2;
        }
        if (limited.isNotEmpty) {
          parts.add(
            lang == 'ko'
                ? '용어: ${limited.join(', ')}.'
                : 'Terms: ${limited.join(', ')}.',
          );
        }
      }
      final names = participants
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .take(10)
          .toList();
      if (names.isNotEmpty) {
        parts.add(
          lang == 'ko'
              ? '참석자: ${names.join(', ')}.'
              : 'Participants: ${names.join(', ')}.',
        );
      }
      // Generic task prompts like "회의록 전사." can leak into the transcript
      // during low-confidence/silent spans. Only inject concrete hints.
      return parts.join(' ');
    } catch (_) {
      // 단어집 로드 실패해도 STT는 계속 진행 — 빈 프롬프트 반환
      return '';
    }
  }

  /// 단어집 → TranscriptCorrector 빌드. 실패 시 empty corrector 반환.
  /// v1.9.9 후처리: 단어집 alias 역방향 치환 (비커리→빅쿼리 등).
  Future<TranscriptCorrector> _buildCorrector() async {
    try {
      final repo = GlossaryRepositoryImpl(IsarService.instance.db);
      final all = await repo.getAllEntries();
      return TranscriptCorrector.fromGlossary(all);
    } catch (_) {
      return TranscriptCorrector.fromGlossary(const []);
    }
  }

  /// WAV 파일 전사 (전체 파일, 비스트리밍)
  ///
  /// [wavPath]: WAV 파일 경로 (임의 샘플레이트/채널 → 16kHz 모노 자동 변환)
  ///
  /// 피크 메모리: Whisper 모델 ~2 GB + 추론 중 ~500 MB
  /// Step 4에서 마이크 스트리밍 30초 윈도우 방식으로 확장 예정
  /// [onProgress]: 세그먼트가 디코딩될 때마다 (processedMs, totalMs) 호출.
  ///   processedMs는 현재까지 처리된 오디오 타임(마지막 세그먼트 t1),
  ///   totalMs는 전체 오디오 길이(samples / 16kHz).
  ///   % 계산은 UI가 (processedMs / totalMs).
  Future<List<SttSegment>> transcribeFile(
    String wavPath, {
    int? decodeMode,
    void Function(int processedMs, int totalMs)? onProgress,
    bool Function()? isCancelled,
  }) => OnDeviceModelManager.instance.runExclusiveNativeTask(
    '음성 인식 전사',
    () => _transcribeFileUnlocked(
      wavPath,
      decodeMode: decodeMode,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
  );

  Future<List<SttSegment>> _transcribeFileUnlocked(
    String wavPath, {
    int? decodeMode,
    void Function(int processedMs, int totalMs)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final manager = OnDeviceModelManager.instance;
    if (!manager.isSttLoaded) {
      throw StateError('STT 모델 로드 후 호출하세요 (OnDeviceModelManager.loadStt)');
    }

    void checkCancelled() {
      if (isCancelled?.call() == true) throw const SttCancelledException();
    }

    checkCancelled();

    // WAV 로드는 메인 Isolate에서 (File I/O + 리샘플링)
    final rawSamples = await WavLoader.load(wavPath);
    checkCancelled();

    // v1.9.8: RMS 기반 무음 게이트 — 저음량 구간에서의 환각 캐스케이드 차단.
    // 2초 이상 연속 무음을 순수 0.0으로 덮어써 whisper가 "아무것도 없음"으로 확정하게 유도.
    final samples = SilenceGate.apply(rawSamples);
    final totalMs = (samples.length / 16).round(); // 16kHz → samples/16 = ms

    // 단어집 기반 initial_prompt (고유명사 인식률 ↑)
    final sttLanguage = AppSettings.instance.sttLanguage;
    final initialPrompt = await _buildInitialPrompt(language: sttLanguage);
    final corrector = await _buildCorrector();
    onProgress?.call(0, totalMs);

    if (samples.length > _longFileThresholdSamples) {
      final sw = Stopwatch()..start();
      final rawSegments = await _transcribeLongFileInChunks(
        samples,
        totalMs,
        initialPrompt,
        decodeMode ?? AppSettings.instance.sttDecodeModeCode,
        onProgress,
        isCancelled,
      );
      sw.stop();
      _logPerf('file-chunked', samples.length, sw.elapsed);
      final cleaned = _cleanSegments(_dedupeOverlaps(rawSegments));
      return corrector.apply(cleaned);
    }

    final sw = Stopwatch()..start();
    final rawSegments = await _transcribeSamples(
      samples,
      baseOffsetMs: 0,
      initialPrompt: initialPrompt,
      decodeMode: decodeMode ?? AppSettings.instance.sttDecodeModeCode,
      onProgress: onProgress == null
          ? null
          : (processedMs) => onProgress(processedMs, totalMs),
    );
    checkCancelled();
    sw.stop();
    _logPerf('file', samples.length, sw.elapsed);
    final cleaned = _cleanSegments(rawSegments);
    return corrector.apply(cleaned);
  }

  Future<List<SttSegment>> _transcribeLongFileInChunks(
    Float32List samples,
    int totalMs,
    String initialPrompt,
    int decodeMode,
    void Function(int processedMs, int totalMs)? onProgress,
    bool Function()? isCancelled,
  ) async {
    final all = <SttSegment>[];
    int start = 0;
    int chunkIndex = 0;
    final advance = _fileChunkSamples - _fileChunkOverlapSamples;

    while (start < samples.length) {
      if (isCancelled?.call() == true) throw const SttCancelledException();

      final nextEnd = start + _fileChunkSamples;
      final end = nextEnd > samples.length ? samples.length : nextEnd;
      final chunk = Float32List.sublistView(samples, start, end);
      final baseOffsetMs = (start / 16).round();

      final chunkSegments = await _transcribeSamples(
        chunk,
        baseOffsetMs: baseOffsetMs,
        initialPrompt: initialPrompt,
        decodeMode: decodeMode,
        onProgress: onProgress == null
            ? null
            : (localProcessedMs) {
                final nextProcessed = baseOffsetMs + localProcessedMs;
                final processed = nextProcessed > totalMs
                    ? totalMs
                    : nextProcessed < 0
                    ? 0
                    : nextProcessed;
                onProgress(processed, totalMs);
              },
      );
      if (isCancelled?.call() == true) throw const SttCancelledException();
      all.addAll(chunkSegments);

      final endMs = (end / 16).round();
      final processedMs = endMs > totalMs ? totalMs : endMs;
      onProgress?.call(processedMs, totalMs);
      debugPrint(
        '[STT CHUNK] ${chunkIndex + 1} '
        'range=${(start / _sampleRate).toStringAsFixed(1)}s'
        '-${(end / _sampleRate).toStringAsFixed(1)}s '
        'segments=${chunkSegments.length}',
      );

      if (end >= samples.length) break;
      start += advance;
      chunkIndex++;
    }

    onProgress?.call(totalMs, totalMs);
    return all;
  }

  Future<List<SttSegment>> _transcribeSamples(
    Float32List samples, {
    required int baseOffsetMs,
    required String initialPrompt,
    int? decodeMode,
    void Function(int processedMs)? onProgress,
  }) async {
    final manager = OnDeviceModelManager.instance;
    if (!manager.isSttLoaded) {
      throw StateError('STT 모델 로드 후 호출하세요 (OnDeviceModelManager.loadStt)');
    }

    // Float32List → TransferableTypedData (Zero-copy Isolate 전달)
    final transferable = TransferableTypedData.fromList([samples]);

    final receivePort = ReceivePort();
    final progressPort = ReceivePort();
    StreamSubscription? progressSub;
    if (onProgress != null) {
      progressSub = progressPort.listen((msg) {
        if (msg is Map && msg['t1Ms'] is int) {
          onProgress(msg['t1Ms'] as int);
        }
      });
    }

    await Isolate.spawn(
      _transcribeInIsolate,
      _TranscribeParams(
        sendPort: receivePort.sendPort,
        ctxAddr: manager.whisperCtx.address,
        samplesTransferable: transferable,
        language: AppSettings.instance.sttLanguage,
        nThreads: 6,
        initialPrompt: initialPrompt,
        decodeMode: decodeMode ?? AppSettings.instance.sttDecodeModeCode,
        progressPort: onProgress != null ? progressPort.sendPort : null,
      ),
    );

    try {
      final result = await receivePort.first;
      if (result is Exception) throw result;

      final rawList = result as List;
      return rawList.map((m) {
        final map = m as Map;
        return SttSegment(
          text: map['text'] as String,
          startMs: baseOffsetMs + (map['t0'] as int),
          endMs: baseOffsetMs + (map['t1'] as int),
        );
      }).toList();
    } finally {
      await progressSub?.cancel();
      progressPort.close();
      receivePort.close();
    }
  }

  /// 세그먼트 정리 파이프라인 (2단계):
  ///   1. 반복 환각 병합 (_collapseRepeatedShort) — "네.네.네."
  ///   2. 과분할 병합 (_mergeShortFragments)      — 1초 미만 조각 병합
  static List<SttSegment> _cleanSegments(List<SttSegment> segments) {
    final deduped = _collapseRepeatedShort(segments);
    return _mergeShortFragments(deduped);
  }

  /// 파일 청크 오버랩 구간에서 같은 문장이 두 번 잡히는 것을 제거.
  static List<SttSegment> _dedupeOverlaps(List<SttSegment> segments) {
    if (segments.length <= 1) return segments;

    String norm(String s) => s
        .replaceAll(RegExp(r'[\s.,!?…·"“”‘’()\[\]{}:;~\-]+'), '')
        .toLowerCase();

    double similarity(String a, String b) {
      final at = norm(a);
      final bt = norm(b);
      if (at.isEmpty || bt.isEmpty) return 0;
      if (at == bt) return 1;
      if (at.length >= 8 && bt.contains(at)) return 0.95;
      if (bt.length >= 8 && at.contains(bt)) return 0.95;
      if (at.length < 10 || bt.length < 10) return 0;

      Set<String> grams(String input) {
        final out = <String>{};
        for (var i = 0; i < input.length - 1; i++) {
          out.add(input.substring(i, i + 2));
        }
        return out;
      }

      final ag = grams(at);
      final bg = grams(bt);
      if (ag.isEmpty || bg.isEmpty) return 0;
      var hit = 0;
      for (final gram in ag) {
        if (bg.contains(gram)) hit++;
      }
      final union = {...ag, ...bg}.length;
      return union == 0 ? 0 : hit / union;
    }

    bool sameNumbers(String a, String b) {
      final ar = RegExp(r'\d+').allMatches(a).map((m) => m.group(0)).toList();
      final br = RegExp(r'\d+').allMatches(b).map((m) => m.group(0)).toList();
      if (ar.isEmpty && br.isEmpty) return true;
      if (ar.length != br.length) return false;
      for (var i = 0; i < ar.length; i++) {
        if (ar[i] != br[i]) return false;
      }
      return true;
    }

    bool isDuplicate(SttSegment a, SttSegment b) {
      final closeInTime = b.startMs <= a.endMs + 6500;
      if (!closeInTime) return false;
      if (!sameNumbers(a.text, b.text)) return false;
      return similarity(a.text, b.text) >= 0.82;
    }

    final sorted = [...segments]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final result = <SttSegment>[];
    for (final seg in sorted) {
      if (result.isEmpty) {
        result.add(seg);
        continue;
      }
      var duplicateIndex = -1;
      final scanStart = (result.length - 8).clamp(0, result.length);
      for (var i = result.length - 1; i >= scanStart; i--) {
        if (isDuplicate(result[i], seg)) {
          duplicateIndex = i;
          break;
        }
      }

      if (duplicateIndex >= 0) {
        final prev = result[duplicateIndex];
        final keep = seg.text.length > prev.text.length ? seg : prev;
        result[duplicateIndex] = SttSegment(
          text: keep.text,
          startMs: prev.startMs < seg.startMs ? prev.startMs : seg.startMs,
          endMs: prev.endMs > seg.endMs ? prev.endMs : seg.endMs,
        );
      } else {
        result.add(seg);
      }
    }
    return result;
  }

  /// 과분할(oversegmentation) 보정.
  ///
  /// Whisper가 회의 음성의 짧은 멈춤마다 "그래서.", "그니까.", "응."
  /// 같은 1초 미만 조각으로 끊는 현상 대응. 연속된 짧은 조각을 하나로
  /// 병합해서 가독성과 요약 품질을 복구한다.
  ///
  /// 규칙:
  ///   - fragment 조건: 지속시간 < [maxDurMs]ms AND 텍스트 ≤ [maxCharLen]자
  ///   - 연속 fragment 들은 공백으로 join → 하나의 세그먼트로
  ///   - 누적 텍스트 길이가 [flushAtChars] 자를 넘으면 거기서 확정
  ///   - 병합 결과가 여전히 매우 짧으면(<8자) 뒤 정상 세그먼트에 prepend
  static List<SttSegment> _mergeShortFragments(
    List<SttSegment> segments, {
    int maxDurMs = 1000,
    int maxCharLen = 10,
    int flushAtChars = 40,
  }) {
    if (segments.length <= 1) return segments;

    bool isFragment(SttSegment s) {
      final dur = s.endMs - s.startMs;
      final text = s.text.trim();
      return dur < maxDurMs && text.length <= maxCharLen;
    }

    final result = <SttSegment>[];
    int i = 0;
    while (i < segments.length) {
      final cur = segments[i];

      if (!isFragment(cur)) {
        result.add(cur);
        i++;
        continue;
      }

      // 연속 fragment 구간 [i..j) 수집
      int j = i;
      final buf = StringBuffer();
      while (j < segments.length && isFragment(segments[j])) {
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(segments[j].text.trim());
        j++;
        if (buf.length >= flushAtChars) break;
      }

      final merged = SttSegment(
        text: buf.toString(),
        startMs: cur.startMs,
        endMs: segments[j - 1].endMs,
      );

      // merged가 여전히 매우 짧고 다음이 정상 세그먼트면 prepend
      if (j < segments.length &&
          !isFragment(segments[j]) &&
          merged.text.length < 8) {
        final next = segments[j];
        result.add(
          SttSegment(
            text: '${merged.text} ${next.text}',
            startMs: merged.startMs,
            endMs: next.endMs,
          ),
        );
        i = j + 1;
      } else {
        result.add(merged);
        i = j;
      }
    }
    return result;
  }

  /// 연속된 짧은 반복 세그먼트를 하나로 병합 (환각 캐스케이드 방어).
  ///
  /// Whisper가 묵음/저음량 구간에서 "네.", "어", "음", "오픈클로우가" 같은
  /// 짧은 단어를 매 초 반복 출력하는 현상 대응.
  ///
  /// v1.9.8 강화:
  ///   - maxCharLen 6 → 12 (실제 환각은 "오픈클로우가"(6자), "감사합니다"(5자),
  ///     "수고하셨습니다"(7자)까지 흔함).
  ///   - 연속 반복 지속시간이 [dropAfterMs]ms 이상이면 전체 드롭(흔적만 남김).
  ///     → "오픈클로우가" 7분 캐스케이드처럼 전 구간을 오염시키는 케이스 차단.
  static List<SttSegment> _collapseRepeatedShort(
    List<SttSegment> segments, {
    int threshold = 3,
    int maxCharLen = 12,
    int dropAfterMs = 10000,
    int longRunThreshold = 8,
  }) {
    if (segments.length < threshold) return segments;

    String norm(String s) =>
        s.replaceAll(RegExp(r'[\s.,!?…]+'), '').toLowerCase();

    final result = <SttSegment>[];
    int i = 0;
    while (i < segments.length) {
      final cur = segments[i];
      final curNorm = norm(cur.text);

      if (curNorm.isEmpty) {
        result.add(cur);
        i++;
        continue;
      }

      // 같은 텍스트가 이어지는 구간 찾기 (길이 무관 — run 카운트 후 정책 결정)
      int j = i + 1;
      while (j < segments.length && norm(segments[j].text) == curNorm) {
        j++;
      }

      final run = j - i;
      final isShort = cur.text.length <= maxCharLen;
      // v1.9.9: 긴 문장도 8회 이상 동일 반복이면 환각으로 간주
      //   (예: "예전에는 계속 비교를 했었죠" 30+회 — Whisper의 대표적 long-run 환각)
      final isLongRun = run >= longRunThreshold;

      if (!isShort && !isLongRun) {
        // 일반적인 긴 문장의 자연스러운 반복은 유지
        for (int k = i; k < j; k++) {
          result.add(segments[k]);
        }
        i = j;
        continue;
      }

      if (run >= threshold) {
        final durMs = segments[j - 1].endMs - cur.startMs;
        if (durMs >= dropAfterMs || isLongRun) {
          // 장시간 캐스케이드: 흔적 마커 한 줄만 남기고 드롭
          result.add(
            SttSegment(
              text: '[반복 환각 구간 제거: "${cur.text.trim()}" ×$run]',
              startMs: cur.startMs,
              endMs: segments[j - 1].endMs,
            ),
          );
        } else {
          // 병합: 첫 세그먼트의 text는 유지, 시간은 첫~마지막으로 확장
          result.add(
            SttSegment(
              text: cur.text,
              startMs: cur.startMs,
              endMs: segments[j - 1].endMs,
            ),
          );
        }
      } else {
        // threshold 미만이면 그대로 유지
        for (int k = i; k < j; k++) {
          result.add(segments[k]);
        }
      }
      i = j;
    }
    return result;
  }

  /// Float32List 직접 전사 (MicrophoneService 전용)
  ///
  /// [samples]      : 16kHz 모노 float32 PCM (WavLoader 없이 바로 전달)
  /// [baseOffsetMs] : 녹음 시작 기준 누적 오프셋 — 세그먼트 타임스탬프 보정에 사용
  ///
  /// 예) 첫 번째 30초 윈도우: baseOffsetMs=0
  ///     두 번째 윈도우(5초 오버랩): baseOffsetMs=(30-5)*1000=25000
  Future<List<SttSegment>> transcribeFromSamples(
    Float32List samples,
    int baseOffsetMs,
  ) => OnDeviceModelManager.instance.runExclusiveNativeTask(
    '음성 인식 실시간 전사',
    () => _transcribeFromSamplesUnlocked(samples, baseOffsetMs),
  );

  Future<List<SttSegment>> _transcribeFromSamplesUnlocked(
    Float32List samples,
    int baseOffsetMs,
  ) async {
    final manager = OnDeviceModelManager.instance;
    if (!manager.isSttLoaded) {
      throw StateError('STT 모델 로드 후 호출하세요 (OnDeviceModelManager.loadStt)');
    }

    // v1.9.9+5: SilenceGate 보강. 기존 1.2s → 1.0s 로 타이트하게 잡아
    // 문장 사이 짧은 간격에서 whisper가 "네." / "음" 류 환각을 찍는 현상을
    // 더 적극적으로 차단. 1초 미만 자연스러운 쉼은 여전히 유지되므로
    // 화자의 발화 경계가 잘리는 부작용은 거의 없음.
    final gated = SilenceGate.apply(samples, minSilenceSec: 1.0);
    final sttLanguage = AppSettings.instance.sttLanguage;
    final initialPrompt = await _buildInitialPrompt(language: sttLanguage);
    final sw = Stopwatch()..start();
    final segments = await _transcribeSamples(
      gated,
      baseOffsetMs: baseOffsetMs,
      initialPrompt: initialPrompt,
    );
    sw.stop();
    _logPerf('window@$baseOffsetMs', gated.length, sw.elapsed);
    final cleaned = _cleanSegments(segments);
    final corrector = await _buildCorrector();
    return corrector.apply(cleaned);
  }

  static void _logPerf(String label, int sampleCount, Duration elapsed) {
    final audioSec = sampleCount / 16000.0;
    final elapsedSec = elapsed.inMilliseconds / 1000.0;
    final rtf = audioSec <= 0 ? 0.0 : elapsedSec / audioSec;
    debugPrint(
      '[STT PERF] $label audio=${audioSec.toStringAsFixed(1)}s '
      'elapsed=${elapsedSec.toStringAsFixed(1)}s '
      'RTF=${rtf.toStringAsFixed(2)}x',
    );
  }

  // ── 워커 Isolate ────────────────────────────────────────────────
  // 피크 메모리: Whisper 추론 중 +~500 MB (모델 자체는 이미 로드됨)
  static void _transcribeInIsolate(_TranscribeParams p) {
    NativeCallable<WhisperSegmentCb>? nativeCb;
    WhisperFfi? ffiForCleanup;
    Pointer<Void>? ctxForCleanup;
    try {
      final ffi = WhisperFfi.instance;
      final ctx = Pointer<Void>.fromAddress(p.ctxAddr);
      ffiForCleanup = ffi;
      ctxForCleanup = ctx;

      // 진행률 콜백 등록 (progressPort 제공 시) — NativeCallable.listener
      // 로 whisper.cpp 워커 스레드에서 안전하게 이벤트 수신.
      if (p.progressPort != null) {
        final port = p.progressPort!;
        nativeCb = NativeCallable<WhisperSegmentCb>.listener((
          int nNew,
          int t1Ms,
        ) {
          // 최신 t1(ms)만 전달하면 UI에서 processed/total 로 % 계산 가능
          port.send({'nNew': nNew, 't1Ms': t1Ms});
        });
        ffi.setSegmentCallback(ctx, nativeCb.nativeFunction);
      }

      // TransferableTypedData → Float32List (zero-copy)
      final samples = p.samplesTransferable.materialize().asFloat32List();
      final n = samples.length;

      // Float32List → 네이티브 float 버퍼
      final buf = calloc<Float>(n);
      try {
        // asTypedList로 네이티브 메모리를 Float32List로 래핑 후 일괄 복사
        buf.asTypedList(n).setAll(0, samples);

        final langPtr = p.language.toNativeUtf8(allocator: calloc);
        // initial_prompt: 빈 문자열이면 nullptr 전달 → 래퍼에서 미주입
        final promptPtr = p.initialPrompt.isEmpty
            ? Pointer<Utf8>.fromAddress(0)
            : p.initialPrompt.toNativeUtf8(allocator: calloc);
        try {
          // n_threads: M3는 성능코어 4 + 효율코어 여유분 포함 6 권장
          final ret = ffi.transcribe(
            ctx,
            buf,
            n,
            langPtr,
            p.nThreads,
            promptPtr,
            p.decodeMode,
          );
          if (ret != 0) throw Exception('Whisper 전사 실패 (코드: $ret)');
        } finally {
          calloc.free(langPtr);
          if (promptPtr.address != 0) calloc.free(promptPtr);
        }
      } finally {
        calloc.free(buf);
      }

      // 콜백 해제 (다음 호출에 영향 없도록)
      ffi.setSegmentCallback(ctx, Pointer.fromAddress(0));

      // 세그먼트 수집 (segmentText 포인터는 이 시점에 유효)
      final nSeg = ffi.nSegments(ctx);
      final segments = <Map<String, dynamic>>[];
      for (int i = 0; i < nSeg; i++) {
        segments.add({
          'text': _safeUtf8(ffi.segmentText(ctx, i)),
          't0': ffi.segmentT0Ms(ctx, i),
          't1': ffi.segmentT1Ms(ctx, i),
        });
      }

      p.sendPort.send(segments);
    } catch (e) {
      p.sendPort.send(e is Exception ? e : Exception('STT 오류: $e'));
    } finally {
      if (ffiForCleanup != null && ctxForCleanup != null) {
        ffiForCleanup.setSegmentCallback(ctxForCleanup, Pointer.fromAddress(0));
      }
      // NativeCallable 자원 해제 (미해제 시 Isolate 종료 시점까지 누수)
      nativeCb?.close();
    }
  }

  /// Whisper FFI 포인터 → Dart String (잘못된 UTF-8 바이트 허용)
  ///
  /// toDartString()은 내부적으로 utf8.decode를 strict 모드로 호출하므로
  /// Whisper가 비정상 바이트를 반환하면 FormatException이 발생한다.
  /// allowMalformed: true 로 대체 문자(U+FFFD)로 치환하여 크래시를 방지한다.
  static String _safeUtf8(Pointer<Utf8> ptr) {
    try {
      return ptr.toDartString();
    } catch (_) {
      // 포인터에서 null terminator까지 바이트 수 계산
      int len = 0;
      final bytePtr = ptr.cast<Uint8>();
      while (bytePtr[len] != 0) {
        len++;
      }
      final bytes = bytePtr.asTypedList(len);
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}
