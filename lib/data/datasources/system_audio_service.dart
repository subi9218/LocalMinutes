import 'dart:io';

import 'package:flutter/services.dart';

/// 온라인 회의(Zoom/Meet/Teams 등) 상대방 목소리를 포함한 **시스템 출력 오디오**를
/// 캡처하기 위한 네이티브 브리지. macOS 14.2+ Core Audio 프로세스 탭을 사용한다.
///
/// 네이티브: macos/Runner/SystemAudioRecorder.swift (채널 `app/system_audio`).
///
/// 주의: 이 기능은 2.2.0 후보로 개발 중이며, 아직 녹음 UI에 연결되어 있지 않다.
/// 실제 캡처 동작은 기기에서 실측이 필요하다.
class SystemAudioService {
  SystemAudioService._();
  static final instance = SystemAudioService._();

  static const _channel = MethodChannel('app/system_audio');

  bool _recording = false;
  bool get isRecording => _recording;

  /// 현재 OS/빌드에서 시스템 오디오 캡처가 지원되는지 (macOS 14.2+).
  Future<bool> isSupported() async {
    if (!Platform.isMacOS) return false;
    try {
      final v = await _channel
          .invokeMethod<bool>('isSupported')
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 시스템 오디오 캡처 시작. [outputPath]에 WAV(16-bit PCM)로 기록한다.
  /// 성공 시 true. 실패 시 [PlatformException]을 던진다(권한 거부/미지원 포함).
  Future<bool> start(String outputPath) async {
    if (!Platform.isMacOS) return false;
    final ok = await _channel.invokeMethod<bool>('start', {
      'path': outputPath,
    });
    _recording = ok ?? false;
    return _recording;
  }

  /// 마지막 호출 이후 캡처된 시스템 오디오 PCM(16kHz 모노 int16 LE)을 가져오고
  /// 네이티브 버퍼를 비운다. 실시간 전사 윈도우에 마이크와 믹스하기 위함.
  Future<Uint8List> drainPcm() async {
    if (!Platform.isMacOS || !_recording) return Uint8List(0);
    try {
      final data = await _channel.invokeMethod<Uint8List>('drainPcm');
      return data ?? Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  /// 캡처 중지 및 네이티브 자원 정리.
  Future<void> stop() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // 중지 실패는 치명적이지 않음.
    } finally {
      _recording = false;
    }
  }
}
