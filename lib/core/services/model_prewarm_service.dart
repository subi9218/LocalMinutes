import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/datasources/microphone_service.dart';
import '../constants/app_constants.dart';
import '../ffi/on_device_model_manager.dart';
import 'app_settings.dart';
import 'crash_log_service.dart';
import 'processing_status_service.dart';

/// macOS 업데이트 후 첫 STT 모델 로드는 CoreML 가속팩의 Neural Engine
/// 재컴파일(캐시 무효화) 때문에 수십 초~몇 분이 걸린다. 사용자가 그 대기를
/// 첫 녹음에서 겪지 않도록, OS 버전이 바뀐 뒤 첫 유휴 시점에 모델을 한 번
/// 로드→언로드해 컴파일을 미리 끝내둔다.
///
/// 안전 장치:
/// - 녹음/전사/요약 등 어떤 작업이라도 진행 중이면 건너뛴다(다음 실행에 재시도).
/// - 성공했을 때만 OS 버전 마커를 남긴다 — 실패하면 다음 실행에서 재시도.
/// - lease 큐(runExclusiveNativeTask)를 그대로 쓰므로, 프리워밍 도중
///   사용자가 녹음을 시작해도 충돌 없이 순서대로 처리된다(오디오는 마이크
///   스트림이 먼저 버퍼링하므로 유실 없음).
class ModelPrewarmService {
  ModelPrewarmService._();

  static bool _ranThisSession = false;

  /// 조건이 맞으면 프리워밍 실행. 앱 시작 후 유휴 시점에 호출한다.
  static Future<void> maybePrewarm() async {
    if (!Platform.isMacOS || _ranThisSession) return;

    final currentOs = Platform.operatingSystemVersion;
    if (AppSettings.instance.lastPrewarmOsVersion == currentOs) {
      return; // 이 OS 버전에서 이미 컴파일 완료
    }

    // 유휴 확인 — 무언가 진행 중이면 이번 기회는 포기 (다음 실행에서 재시도)
    final mic = MicrophoneService.instance;
    if (mic.isRecording || mic.isPaused) return;
    if (ProcessingStatus.instance.isBusy) return;
    final manager = OnDeviceModelManager.instance;
    if (manager.nativeTaskSnapshot.activeLabel != null) return;
    if (manager.isSttLoaded || manager.isLlmLoaded) return;

    // 녹음이 실제로 사용할 모델(빠름 우선)을 프리워밍
    String? modelPath;
    try {
      final base = await getApplicationSupportDirectory();
      final fast = File('${base.path}/models/${AppConstants.sttModelFileFast}');
      final accurate =
          File('${base.path}/models/${AppConstants.sttModelFileAccurate}');
      if (await fast.exists()) {
        modelPath = fast.path;
      } else if (await accurate.exists()) {
        modelPath = accurate.path;
      }
    } catch (_) {}
    if (modelPath == null) return; // 모델 미설치 — 설치 후 다음 실행에서

    _ranThisSession = true;
    CrashLogService.instance.info(
      'prewarm start (os: $currentOs)',
      context: 'prewarm',
    );
    try {
      await manager.loadStt(modelPath);
      await manager.unloadStt();
      await AppSettings.instance.setLastPrewarmOsVersion(currentOs);
      CrashLogService.instance.info('prewarm done', context: 'prewarm');
    } catch (e, st) {
      // 실패 시 마커를 남기지 않아 다음 실행에서 자동 재시도된다.
      CrashLogService.instance.recordCaught(e, st, context: 'prewarm');
    }
  }
}
