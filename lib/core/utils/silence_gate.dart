import 'dart:typed_data';

/// RMS 기반 간이 VAD(무음 게이트).
///
/// Whisper가 저음량/묵음 구간에서 환각(hallucination cascade)을 일으키는 문제
/// — 예: "오픈클로우가" 7분 반복 — 를 근원에서 차단한다. 무음이 충분히 길게
/// 이어지면 해당 구간을 순수 0.0 으로 덮어써서 whisper 디코더가 "아무것도
/// 없음"으로 확실히 판단하도록 강제한다.
///
/// 왜 Silero ONNX가 아닌 RMS인가:
///   - 의존성 0 (onnxruntime, VAD 모델 파일 배포 불필요)
///   - M3 기준 49분 녹음 처리 ~100ms (무시 가능)
///   - 회의 환경에서 "음성 vs 묵음"은 충분히 단순 — 말소리 구간을 버리지만
///     않으면 된다. 정밀한 VAD 모델은 오히려 기침·웃음 버리는 부작용 위험.
///
/// 보정 특성:
///   - 프레임 20ms (16kHz @ 320 샘플)
///   - 적응적 임계치: 전체 프레임 RMS의 20퍼센타일 × 2.5 (하한 0.003)
///   - [minSilenceSec] 이상 연속 무음만 제로화 → 짧은 숨·정적은 보존
///   - 음성 구간 앞뒤 [hangoverMs] 유지 → 어미 잘림 방지
class SilenceGate {
  /// [samples] 를 제자리에서 수정하지 않고 새 Float32List 반환.
  /// [samples] 는 16kHz 모노 float32 PCM이라고 가정.
  static Float32List apply(
    Float32List samples, {
    double minSilenceSec = 2.0,
    int hangoverMs = 200,
  }) {
    const sampleRate = 16000;
    const frameSize = 320; // 20ms @ 16kHz

    if (samples.length < frameSize * 8) return samples;

    // ── 1. 프레임별 RMS 계산 ────────────────────────────────────────
    final nFrames = samples.length ~/ frameSize;
    final rms = Float32List(nFrames);
    for (int f = 0; f < nFrames; f++) {
      double sum = 0;
      final base = f * frameSize;
      for (int j = 0; j < frameSize; j++) {
        final v = samples[base + j];
        sum += v * v;
      }
      rms[f] = (sum / frameSize);
    }

    // ── 2. 적응적 임계치 (20퍼센타일 × 2.5) ──────────────────────────
    final sorted = Float32List.fromList(rms)..sort();
    final p20 = sorted[(nFrames * 0.20).floor().clamp(0, nFrames - 1)];
    // RMS^2 기준이므로 임계치도 제곱 스케일
    final threshold = (p20 * 6.25).clamp(0.000009, 0.01); // 0.003^2 = 0.000009

    // ── 3. voiced/silent 프레임 마스크 ──────────────────────────────
    final voiced = List<bool>.filled(nFrames, false);
    for (int f = 0; f < nFrames; f++) {
      voiced[f] = rms[f] > threshold;
    }

    // ── 4. hangover: 음성 전후로 [hangoverMs]ms 유지 ────────────────
    final hangFrames = (hangoverMs / 20).ceil();
    final expanded = List<bool>.from(voiced);
    for (int f = 0; f < nFrames; f++) {
      if (voiced[f]) {
        final lo = (f - hangFrames).clamp(0, nFrames - 1);
        final hi = (f + hangFrames).clamp(0, nFrames - 1);
        for (int k = lo; k <= hi; k++) { expanded[k] = true; }
      }
    }

    // ── 5. minSilenceSec 이상 연속 무음 구간만 제로화 ────────────────
    final minSilenceFrames = (minSilenceSec * sampleRate / frameSize).ceil();
    final out = Float32List.fromList(samples);

    int runStart = -1;
    void zeroRun(int fromFrame, int toFrameExclusive) {
      final from = fromFrame * frameSize;
      final to = (toFrameExclusive * frameSize).clamp(0, out.length);
      for (int k = from; k < to; k++) { out[k] = 0.0; }
    }

    for (int f = 0; f <= nFrames; f++) {
      final isSilent = f < nFrames && !expanded[f];
      if (isSilent) {
        if (runStart < 0) runStart = f;
      } else {
        if (runStart >= 0) {
          final len = f - runStart;
          if (len >= minSilenceFrames) zeroRun(runStart, f);
          runStart = -1;
        }
      }
    }

    return out;
  }
}
