import 'dart:math';
import 'dart:typed_data';

/// RMS 에너지 기반 Voice Activity Detection (VAD)
///
/// 추가 패키지 없이 자체 구현.
/// 회의 환경 (배경 소음 낮음, 발화 명확) 에 최적화된 기본값 사용.
class VadFilter {
  /// 16kHz 모노 float32 오디오 청크에 음성이 포함됐는지 판단.
  ///
  /// [samples]     : Float32List (범위 -1.0 ~ 1.0)
  /// [frameSize]   : 분석 프레임 크기 (기본 1600 = 100ms @ 16kHz)
  /// [threshold]   : RMS 에너지 임계값 (기본 0.01 ≈ -40 dBFS)
  /// [speechRatio] : 음성 판정에 필요한 최소 프레임 비율 (기본 0.15 = 15%)
  ///
  /// 반환: 음성 포함 시 true, 무음/소음만 있을 때 false
  static bool hasSpeech(
    Float32List samples, {
    int frameSize = 1600,
    double threshold = 0.01,
    double speechRatio = 0.15,
  }) {
    if (samples.isEmpty) return false;

    int speechFrames = 0;
    int totalFrames = 0;

    for (int i = 0; i + frameSize <= samples.length; i += frameSize) {
      double sumSq = 0.0;
      for (int j = i; j < i + frameSize; j++) {
        sumSq += samples[j] * samples[j];
      }
      final rms = sqrt(sumSq / frameSize);
      if (rms > threshold) speechFrames++;
      totalFrames++;
    }

    return totalFrames > 0 &&
        (speechFrames / totalFrames) >= speechRatio;
  }

  /// 청크 전체의 평균 RMS 에너지 반환 (디버깅 / 임계값 튜닝 용도)
  static double averageRms(Float32List samples) {
    if (samples.isEmpty) return 0.0;
    double sumSq = 0.0;
    for (final s in samples) { sumSq += s * s; }
    return sqrt(sumSq / samples.length);
  }
}
