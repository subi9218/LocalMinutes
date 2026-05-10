// VAD sanity check — SilenceGate를 실제 WAV에 적용하고 통계 출력.
// 실행: dart run tool/vad_sanity.dart "<wav_path>"
import 'dart:io';
import 'package:meeting_assistant2/core/utils/silence_gate.dart';
import 'package:meeting_assistant2/core/utils/wav_loader.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? args[0]
      : '${Platform.environment['HOME']}/Library/Application Support/com.example.meetingAssistant2/recordings/meeting_1776841360361.wav';

  stdout.writeln('[1/3] WAV 로드: $path');
  final sw = Stopwatch()..start();
  final raw = await WavLoader.load(path);
  final loadMs = sw.elapsedMilliseconds;
  final durSec = raw.length / 16000;
  stdout.writeln(
    '     샘플 ${raw.length} (${durSec.toStringAsFixed(1)}s), 로드 ${loadMs}ms',
  );

  stdout.writeln('[2/3] SilenceGate 적용 (minSilenceSec=2.0)');
  sw.reset();
  final gated = SilenceGate.apply(raw);
  final gateMs = sw.elapsedMilliseconds;
  stdout.writeln('     게이트 ${gateMs}ms');

  // 제로화된 샘플 비율
  int zeroed = 0;
  for (int i = 0; i < gated.length; i++) {
    if (gated[i] == 0.0 && raw[i] != 0.0) zeroed++;
  }
  final zeroSec = zeroed / 16000;
  final pct = 100.0 * zeroed / raw.length;

  stdout.writeln('[3/3] 결과');
  stdout.writeln(
    '     제로화 샘플: $zeroed (${zeroSec.toStringAsFixed(1)}s, ${pct.toStringAsFixed(1)}%)',
  );
  stdout.writeln(
    '     통과 샘플(음성 포함 구간): ${raw.length - zeroed} (${((raw.length - zeroed) / 16000).toStringAsFixed(1)}s)',
  );

  // 1분 단위 타임라인
  stdout.writeln('\n시간대별 무음 비율 (1분 버킷):');
  const bucketSec = 60;
  const bucketSamples = bucketSec * 16000;
  for (int b = 0; b * bucketSamples < gated.length; b++) {
    final s = b * bucketSamples;
    final e = (s + bucketSamples).clamp(0, gated.length);
    int zc = 0;
    for (int i = s; i < e; i++) {
      if (gated[i] == 0.0 && raw[i] != 0.0) zc++;
    }
    final p = 100.0 * zc / (e - s);
    final bar = '█' * (p / 5).round();
    stdout.writeln(
      '  ${(b * bucketSec).toString().padLeft(4)}s  ${p.toStringAsFixed(0).padLeft(3)}% $bar',
    );
  }
}
