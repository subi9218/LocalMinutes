import 'dart:io';
import 'dart:typed_data';

// whisper.cpp 요구사항: 16kHz, 모노, float32 PCM [-1.0, 1.0]
// 지원 입력: int16/int32/float32 PCM, 임의 샘플레이트, 모노/스테레오

class WavLoadException implements Exception {
  final String message;
  const WavLoadException(this.message);
  @override
  String toString() => 'WavLoadException: $message';
}

class WavLoader {
  static const int targetSampleRate = 16000;

  // WAV 파일 → 16kHz 모노 float32 PCM
  static Future<Float32List> load(String path) async {
    final bytes = await File(path).readAsBytes();
    return _parse(bytes);
  }

  static Float32List _parse(Uint8List bytes) {
    if (bytes.length < 44) throw const WavLoadException('파일이 너무 짧습니다');

    final data = ByteData.sublistView(bytes);

    if (_fourcc(bytes, 0) != 'RIFF') throw const WavLoadException('RIFF 마커 없음');
    if (_fourcc(bytes, 8) != 'WAVE') throw const WavLoadException('WAVE 마커 없음');

    // fmt / data 청크 스캔 (순서 무관)
    int? audioFormat, channels, sampleRate, bitsPerSample;
    int? dataOffset, dataSize;

    int pos = 12;
    while (pos + 8 <= bytes.length) {
      final chunkId   = _fourcc(bytes, pos);
      final chunkSize = data.getUint32(pos + 4, Endian.little);

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) throw const WavLoadException('fmt 청크가 너무 짧습니다');
        audioFormat   = data.getUint16(pos + 8,  Endian.little);
        channels      = data.getUint16(pos + 10, Endian.little);
        sampleRate    = data.getUint32(pos + 12, Endian.little);
        bitsPerSample = data.getUint16(pos + 22, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = pos + 8;
        dataSize   = chunkSize;
        break; // data 청크를 찾으면 중단
      }

      pos += 8 + chunkSize;
      if (chunkSize.isOdd) pos++; // 2바이트 정렬 패딩
    }

    if (audioFormat == null || channels == null || sampleRate == null ||
        bitsPerSample == null) {
      throw const WavLoadException('fmt 청크를 찾을 수 없습니다');
    }
    if (dataOffset == null || dataSize == null) {
      throw const WavLoadException('data 청크를 찾을 수 없습니다');
    }
    if (audioFormat != 1 && audioFormat != 3) {
      throw WavLoadException(
          '지원하지 않는 오디오 형식 (format=$audioFormat). PCM(1) 또는 IEEE Float(3)만 지원');
    }

    // ── 샘플 읽기 → float32 모노 변환 ─────────────────────────────
    final bytesPerSample = bitsPerSample ~/ 8;
    final nFrames = dataSize ~/ (channels * bytesPerSample);
    final Float32List mono;

    if (audioFormat == 1 && bitsPerSample == 16) {
      mono = _int16ToMono(data, dataOffset, nFrames, channels);
    } else if (audioFormat == 1 && bitsPerSample == 32) {
      mono = _int32ToMono(data, dataOffset, nFrames, channels);
    } else if (audioFormat == 3 && bitsPerSample == 32) {
      mono = _float32ToMono(data, dataOffset, nFrames, channels);
    } else {
      throw WavLoadException('지원하지 않는 비트 깊이: $bitsPerSample bit');
    }

    // ── 리샘플링 (필요 시) ─────────────────────────────────────────
    if (sampleRate == targetSampleRate) return mono;
    return _resample(mono, sampleRate, targetSampleRate);
  }

  // ── 채널 병합 헬퍼 ─────────────────────────────────────────────

  static Float32List _int16ToMono(
      ByteData data, int offset, int nFrames, int channels) {
    final result = Float32List(nFrames);
    for (int i = 0; i < nFrames; i++) {
      double sum = 0;
      for (int c = 0; c < channels; c++) {
        sum += data.getInt16(offset + (i * channels + c) * 2, Endian.little)
            / 32768.0;
      }
      result[i] = sum / channels;
    }
    return result;
  }

  static Float32List _int32ToMono(
      ByteData data, int offset, int nFrames, int channels) {
    final result = Float32List(nFrames);
    for (int i = 0; i < nFrames; i++) {
      double sum = 0;
      for (int c = 0; c < channels; c++) {
        sum += data.getInt32(offset + (i * channels + c) * 4, Endian.little)
            / 2147483648.0;
      }
      result[i] = sum / channels;
    }
    return result;
  }

  static Float32List _float32ToMono(
      ByteData data, int offset, int nFrames, int channels) {
    final result = Float32List(nFrames);
    for (int i = 0; i < nFrames; i++) {
      double sum = 0;
      for (int c = 0; c < channels; c++) {
        sum += data.getFloat32(offset + (i * channels + c) * 4, Endian.little);
      }
      result[i] = (sum / channels).clamp(-1.0, 1.0);
    }
    return result;
  }

  // ── 선형 보간 리샘플링 ─────────────────────────────────────────
  static Float32List _resample(Float32List input, int srcRate, int dstRate) {
    final ratio = srcRate / dstRate;
    final nOut = (input.length / ratio).ceil();
    final output = Float32List(nOut);
    final lastIdx = input.length - 1;

    for (int i = 0; i < nOut; i++) {
      final srcPos = i * ratio;
      final lo = srcPos.floor().clamp(0, lastIdx);
      final hi = (lo + 1).clamp(0, lastIdx);
      final frac = srcPos - lo;
      output[i] = input[lo] * (1.0 - frac) + input[hi] * frac;
    }
    return output;
  }

  static String _fourcc(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
}
