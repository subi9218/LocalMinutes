import 'dart:io';
import 'dart:typed_data';

import 'wav_loader.dart';

/// 여러 오디오 트랙(마이크 + 시스템 오디오 등)을 하나의 WAV로 합치는 유틸.
///
/// 온라인 회의 녹음에서 내 목소리(마이크)와 상대 목소리(시스템 출력)를 각각
/// 캡처한 뒤 하나의 16kHz 모노 WAV로 합쳐 기존 Whisper 파이프라인에 투입한다.
///
/// 순수 함수(`mixFloat`)와 파일 I/O(`mixFiles`)를 분리해 단위 테스트가 쉽도록 했다.
class WavMixer {
  static const int sampleRate = WavLoader.targetSampleRate; // 16kHz

  /// 여러 모노 트랙을 샘플 단위로 합산한다.
  ///
  /// - 길이가 다르면 가장 긴 트랙에 맞춰 짧은 트랙 뒤를 0으로 패딩한다.
  /// - 합산 후 [-1.0, 1.0]을 넘으면 클리핑 왜곡을 줄이기 위해 전체에 균일한
  ///   게인을 적용해 피크를 1.0으로 정규화한다(피크가 1.0 이하이면 그대로).
  static Float32List mixFloat(List<Float32List> tracks) {
    final nonEmpty = tracks.where((t) => t.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return Float32List(0);
    if (nonEmpty.length == 1) return nonEmpty.first;

    var maxLen = 0;
    for (final t in nonEmpty) {
      if (t.length > maxLen) maxLen = t.length;
    }

    final mixed = Float32List(maxLen);
    var peak = 0.0;
    for (var i = 0; i < maxLen; i++) {
      var sum = 0.0;
      for (final t in nonEmpty) {
        if (i < t.length) sum += t[i];
      }
      mixed[i] = sum;
      final a = sum.abs();
      if (a > peak) peak = a;
    }

    // 피크가 1.0을 넘으면 균일 게인으로 정규화 (클리핑 방지)
    if (peak > 1.0) {
      final gain = 1.0 / peak;
      for (var i = 0; i < maxLen; i++) {
        mixed[i] = mixed[i] * gain;
      }
    }
    return mixed;
  }

  /// 44바이트 WAV 헤더 (16-bit PCM 모노).
  static Uint8List _monoWavHeader(int dataSize, int rate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = rate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final header = ByteData(44);

    void writeAscii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    header.setUint16(20, 1, Endian.little); // audioFormat = PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, rate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataSize, Endian.little);
    return header.buffer.asUint8List();
  }

  /// 16kHz 모노 float32 [-1,1] 샘플을 16-bit PCM WAV로 인코딩한다.
  static Uint8List encodeMonoWav(Float32List samples, {int rate = sampleRate}) {
    final dataSize = samples.length * 2;
    final out = BytesBuilder();
    out.add(_monoWavHeader(dataSize, rate));

    final pcm = ByteData(dataSize);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767.0).round();
      pcm.setInt16(i * 2, v, Endian.little);
    }
    out.add(pcm.buffer.asUint8List());
    return out.toBytes();
  }

  /// 입력 WAV 파일들을 16kHz 모노로 로드해 합치고 [outputPath]에 WAV로 쓴다.
  /// 존재하지 않거나 읽기 실패한 파일은 건너뛴다. 합칠 트랙이 없으면 false.
  static Future<bool> mixFiles(
    List<String> inputPaths,
    String outputPath,
  ) async {
    final tracks = <Float32List>[];
    for (final p in inputPaths) {
      if (p.isEmpty) continue;
      if (!await File(p).exists()) continue;
      try {
        tracks.add(await WavLoader.load(p));
      } catch (_) {
        // 손상/미지원 파일은 건너뜀
      }
    }
    if (tracks.isEmpty) return false;
    final mixed = mixFloat(tracks);
    if (mixed.isEmpty) return false;
    // 인코딩 결과를 통째로 메모리에 만들지 않고 청크 단위로 스트리밍 기록
    // (긴 회의에서 수백 MB의 이중 버퍼가 생기는 것을 방지).
    final sink = File(outputPath).openWrite();
    try {
      sink.add(_monoWavHeader(mixed.length * 2, sampleRate));
      const chunkFrames = 1 << 16; // 64k 샘플(≈4초)씩
      for (var i = 0; i < mixed.length; i += chunkFrames) {
        final end = (i + chunkFrames < mixed.length)
            ? i + chunkFrames
            : mixed.length;
        final pcm = ByteData((end - i) * 2);
        for (var j = i; j < end; j++) {
          final v = (mixed[j].clamp(-1.0, 1.0) * 32767.0).round();
          pcm.setInt16((j - i) * 2, v, Endian.little);
        }
        sink.add(pcm.buffer.asUint8List());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return true;
  }
}
