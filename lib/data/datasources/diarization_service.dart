import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import '../../core/constants/app_constants.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/utils/wav_loader.dart';

/// 화자 분리 결과 세그먼트
class DiarSegment {
  final double startSec;
  final double endSec;
  final int speaker; // 0-based 클러스터 id
  const DiarSegment(this.startSec, this.endSec, this.speaker);
}

class DiarizationTimeoutException implements Exception {
  final String message;
  const DiarizationTimeoutException([
    this.message = '발화자 구분 시간이 너무 오래 걸려 중단했습니다.',
  ]);

  @override
  String toString() => message;
}

String friendlyDiarizationFailureMessage({required String nextStep}) =>
    '발화자 구분에 실패했습니다. $nextStep\n'
    '나중에 음성 인식을 다시 실행하면 발화자 라벨도 다시 만들 수 있습니다.';

class _DiarizeParams {
  final SendPort sendPort;
  final String wavPath;
  final String segPath;
  final String embPath;
  final int numSpeakersHint;

  const _DiarizeParams({
    required this.sendPort,
    required this.wavPath,
    required this.segPath,
    required this.embPath,
    required this.numSpeakersHint,
  });
}

/// 화자 분리(Speaker Diarization) 래퍼.
/// sherpa-onnx의 pyannote segmentation + 3d-speaker embedding + 클러스터링.
///
/// 사용:
///   1. [modelsReady] 로 모델 파일 존재 확인
///   2. [diarizeWav] 호출 — WAV 경로 → 화자 세그먼트 리스트
///   3. [assignLabelsTo] — STT 세그먼트(ms)에 화자 라벨 매칭
class DiarizationService {
  static final DiarizationService instance = DiarizationService._();
  DiarizationService._();

  static bool _libInitialized = false;

  /// sherpa-onnx 네이티브 바이너리 초기화 (macOS에서는 dylib 자동 로드).
  static void _ensureLibInitialized() {
    if (_libInitialized) return;
    so.initBindings();
    _libInitialized = true;
  }

  /// 모델 디렉토리 경로
  Future<String> _modelsDir() async {
    final base = await getApplicationSupportDirectory();
    return '${base.path}/models';
  }

  /// 두 모델 파일 존재 여부
  Future<bool> modelsReady() async {
    final dir = await _modelsDir();
    final seg = File('$dir/${AppConstants.diarSegModelFile}');
    final emb = File('$dir/${AppConstants.diarEmbModelFile}');
    return await seg.exists() && await emb.exists();
  }

  /// WAV 파일에서 화자 세그먼트 추출.
  ///
  /// [numSpeakersHint] 0 = auto (threshold 사용), 2~6 = 클러스터 수 명시.
  /// [onProgress] 0~100 진행률 콜백.
  Future<List<DiarSegment>> diarizeWav(
    String wavPath, {
    int numSpeakersHint = 0,
    void Function(double percent)? onProgress,
    Duration timeout = const Duration(minutes: 8),
  }) => OnDeviceModelManager.instance.runExclusiveNativeTask(
    '발화자 라벨 생성',
    () => _diarizeWavUnlocked(
      wavPath,
      numSpeakersHint: numSpeakersHint,
      onProgress: onProgress,
      timeout: timeout,
    ),
  );

  Future<List<DiarSegment>> _diarizeWavUnlocked(
    String wavPath, {
    int numSpeakersHint = 0,
    void Function(double percent)? onProgress,
    Duration timeout = const Duration(minutes: 8),
  }) async {
    final dir = await _modelsDir();
    final segPath = '$dir/${AppConstants.diarSegModelFile}';
    final embPath = '$dir/${AppConstants.diarEmbModelFile}';

    if (!await File(segPath).exists() || !await File(embPath).exists()) {
      throw StateError('Diarization 모델이 설치되지 않았습니다.');
    }

    final receivePort = ReceivePort();
    // exitPort: isolate가 완전히 종료됐을 때 수신 → 네이티브 리소스 정리 완료 확인
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();
    await Isolate.spawn(
      _diarizeInIsolate,
      _DiarizeParams(
        sendPort: receivePort.sendPort,
        wavPath: wavPath,
        segPath: segPath,
        embPath: embPath,
        numSpeakersHint: numSpeakersHint,
      ),
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
    );

    Timer? timeoutTimer;
    final done = Completer<List<DiarSegment>>();
    final exited = Completer<void>();
    bool timedOut = false;

    timeoutTimer = Timer(timeout, () {
      if (!done.isCompleted) {
        timedOut = true;
        done.completeError(const DiarizationTimeoutException());
      }
    });

    late StreamSubscription sub;
    late StreamSubscription errorSub;
    late StreamSubscription exitSub;
    sub = receivePort.listen((msg) {
      if (msg is Map) {
        final type = msg['type'];
        if (type == 'progress') {
          final value = msg['value'];
          if (value is num) onProgress?.call(value.toDouble());
        } else if (type == 'result') {
          final raw = msg['segments'] as List? ?? const [];
          final segments = raw.map((e) {
            final m = e as Map;
            return DiarSegment(
              (m['start'] as num).toDouble(),
              (m['end'] as num).toDouble(),
              (m['speaker'] as num).toInt(),
            );
          }).toList();
          if (!done.isCompleted) done.complete(segments);
        } else if (type == 'error') {
          if (!done.isCompleted) {
            done.completeError(Exception(msg['message'] ?? '화자 분리 실패'));
          }
        }
      }
    });
    errorSub = errorPort.listen((msg) {
      if (!done.isCompleted) {
        done.completeError(Exception('화자 분리 작업 오류: $msg'));
      }
    });
    exitSub = exitPort.listen((_) {
      if (!exited.isCompleted) exited.complete();
      if (!done.isCompleted) {
        done.completeError(Exception('화자 분리 작업이 결과 없이 종료되었습니다.'));
      }
    });

    try {
      final result = await done.future;
      // 정상 종료 — isolate가 자연스럽게 끝날 때까지 대기 (FFI 리소스 정리 보장)
      // 네이티브 FFI 실행 중인 isolate를 즉시 kill하면 런타임 abort가 날 수 있어
      // 앱 안정성을 우선해 자연 종료를 기다린다.
      if (!timedOut) {
        try {
          await exited.future.timeout(const Duration(seconds: 15));
        } catch (_) {
          // 이미 결과는 받았으므로 UI 진행은 계속한다. isolate는 정리 완료 후 종료된다.
        }
      }
      return result;
    } finally {
      timeoutTimer.cancel();
      await sub.cancel();
      await errorSub.cancel();
      await exitSub.cancel();
      receivePort.close();
      exitPort.close();
      errorPort.close();
    }
  }

  static void _diarizeInIsolate(_DiarizeParams p) {
    _runDiarizeInIsolate(p);
  }

  static Future<void> _runDiarizeInIsolate(_DiarizeParams p) async {
    so.OfflineSpeakerDiarization? sd;
    try {
      _ensureLibInitialized();

      // 16kHz mono PCM float32 로드 (WavLoader.load가 이미 16kHz/mono/float32로 변환)
      final wav = await WavLoader.load(p.wavPath);

      final segConfig = so.OfflineSpeakerSegmentationModelConfig(
        pyannote: so.OfflineSpeakerSegmentationPyannoteModelConfig(
          model: p.segPath,
        ),
      );
      final embConfig = so.SpeakerEmbeddingExtractorConfig(model: p.embPath);
      final clusterConfig = so.FastClusteringConfig(
        numClusters: p.numSpeakersHint > 0 ? p.numSpeakersHint : -1,
        threshold: 0.5,
      );
      final config = so.OfflineSpeakerDiarizationConfig(
        segmentation: segConfig,
        embedding: embConfig,
        clustering: clusterConfig,
        minDurationOn: 0.2,
        minDurationOff: 0.5,
      );

      sd = so.OfflineSpeakerDiarization(config);
      if (sd.ptr == nullptr) {
        throw StateError('화자 분리 엔진 초기화 실패');
      }

      // sherpa-onnx의 processWithCallback 경로는 Dart FFI callback을 네이티브
      // worker thread에서 호출하다가 앱 전체가 abort되는 사례가 있어 사용하지 않는다.
      // 대신 callback-free process()로 안정성을 우선한다.
      p.sendPort.send({'type': 'progress', 'value': 5.0});
      final segments = sd.process(samples: wav);
      p.sendPort.send({'type': 'progress', 'value': 100.0});

      p.sendPort.send({
        'type': 'result',
        'segments': segments
            .map((s) => {'start': s.start, 'end': s.end, 'speaker': s.speaker})
            .toList(),
      });
    } catch (e) {
      p.sendPort.send({'type': 'error', 'message': e.toString()});
    } finally {
      // 반드시 sd.free() 먼저 호출해 네이티브 리소스를 정리한다.
      sd?.free();
      // microtask 한 사이클 양보 — sendPort가 메시지를 모두 flush하도록
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// STT 세그먼트(ms 단위)에 화자 라벨 할당.
  /// 시간 겹침이 가장 큰 화자의 id로 매칭 → 'A', 'B', 'C' ...
  ///
  /// [sttStartMs], [sttEndMs]는 병렬 리스트.
  /// 반환 리스트는 각 STT 세그먼트의 화자 라벨 ('A'/'B'/...) 또는 null(매칭 없음).
  static List<String?> assignLabels({
    required List<int> sttStartMs,
    required List<int> sttEndMs,
    required List<DiarSegment> diar,
  }) {
    final labels = List<String?>.filled(sttStartMs.length, null);
    if (diar.isEmpty) return labels;

    for (int i = 0; i < sttStartMs.length; i++) {
      final s = sttStartMs[i] / 1000.0;
      final e = sttEndMs[i] / 1000.0;

      int bestSpeaker = -1;
      double bestOverlap = 0;
      for (final d in diar) {
        final overlap =
            (e < d.endSec ? e : d.endSec) - (s > d.startSec ? s : d.startSec);
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          bestSpeaker = d.speaker;
        }
      }
      if (bestSpeaker >= 0) {
        // 0→'A', 1→'B', 2→'C', ...
        labels[i] = String.fromCharCode(65 + (bestSpeaker % 26));
      }
    }
    return labels;
  }
}
