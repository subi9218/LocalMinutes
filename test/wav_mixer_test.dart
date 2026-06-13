import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_minutes/core/utils/wav_loader.dart';
import 'package:local_minutes/core/utils/wav_mixer.dart';

void main() {
  group('WavMixer.mixFloat', () {
    test('빈 입력 → 빈 결과', () {
      expect(WavMixer.mixFloat([]).length, 0);
      expect(WavMixer.mixFloat([Float32List(0)]).length, 0);
    });

    test('단일 트랙은 그대로 반환', () {
      final t = Float32List.fromList([0.1, -0.2, 0.3]);
      final out = WavMixer.mixFloat([t]);
      expect(out, equals(t));
    });

    test('두 트랙 샘플 단위 합산', () {
      final a = Float32List.fromList([0.1, 0.2, 0.3]);
      final b = Float32List.fromList([0.2, 0.1, 0.0]);
      final out = WavMixer.mixFloat([a, b]);
      // 피크 0.3+0.0=0.3? 실제 합: [0.3,0.3,0.3] 피크 0.3 ≤ 1.0 → 정규화 없음
      expect(out.length, 3);
      expect(out[0], closeTo(0.3, 1e-6));
      expect(out[1], closeTo(0.3, 1e-6));
      expect(out[2], closeTo(0.3, 1e-6));
    });

    test('길이가 다르면 짧은 쪽을 0으로 패딩', () {
      final a = Float32List.fromList([0.5, 0.5, 0.5, 0.5]);
      final b = Float32List.fromList([0.1, 0.1]);
      final out = WavMixer.mixFloat([a, b]);
      expect(out.length, 4);
      expect(out[0], closeTo(0.6, 1e-6));
      expect(out[1], closeTo(0.6, 1e-6));
      expect(out[2], closeTo(0.5, 1e-6)); // b 패딩 구간
      expect(out[3], closeTo(0.5, 1e-6));
    });

    test('피크가 1.0을 넘으면 균일 게인으로 정규화', () {
      final a = Float32List.fromList([0.8, 0.0]);
      final b = Float32List.fromList([0.8, 0.0]);
      final out = WavMixer.mixFloat([a, b]);
      // 합: [1.6, 0.0], 피크 1.6 → gain 1/1.6 → [1.0, 0.0]
      expect(out[0], closeTo(1.0, 1e-6));
      expect(out[1], closeTo(0.0, 1e-6));
    });
  });

  group('WavMixer.encodeMonoWav', () {
    test('WavLoader로 다시 읽으면 동일 길이/근사 샘플', () async {
      final samples = Float32List.fromList([
        0.0, 0.25, -0.25, 0.5, -0.5, 1.0, -1.0,
      ]);
      final bytes = WavMixer.encodeMonoWav(samples);
      // 헤더 44 + 7*2 데이터
      expect(bytes.length, 44 + 7 * 2);

      // 임시 파일로 써서 WavLoader 왕복 검증 (16kHz라 리샘플 없음)
      final tmp =
          '${Directory.systemTemp.path}/wav_mixer_test_${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(tmp).writeAsBytes(bytes, flush: true);
      try {
        final loaded = await WavLoader.load(tmp);
        expect(loaded.length, samples.length);
        for (var i = 0; i < samples.length; i++) {
          // 16-bit 양자화 오차 허용
          expect(loaded[i], closeTo(samples[i], 1e-3));
        }
      } finally {
        await File(tmp).delete().catchError((_) => File(tmp));
      }
    });
  });
}
