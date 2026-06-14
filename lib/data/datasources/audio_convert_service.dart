import 'dart:io';

import 'package:flutter/services.dart';

/// 업로드한 임의 오디오/영상 파일을 온디바이스 STT 입력 규격(16kHz 모노 16-bit WAV)
/// 으로 변환하는 네이티브 브리지.
///
/// 네이티브: macos/Runner/SystemAudioRecorder.swift 의 `AudioFileConverter`
/// (채널 `app/audio_convert`). AVFoundation 이 컨테이너/코덱 디코딩·리샘플·
/// 다운믹스를 처리하므로 외부 의존성 없이 광범위한 포맷을 지원한다.
class AudioConvertService {
  AudioConvertService._();
  static final instance = AudioConvertService._();

  static const _channel = MethodChannel('app/audio_convert');

  /// 변환 없이 바로 사용할 수 있는(이미 WAV) 확장자.
  static const wavExtensions = {'wav'};

  /// 네이티브 변환을 거쳐야 하는 입력 확장자(소문자, 점 없음).
  static const convertibleExtensions = {
    'm4a',
    'mp3',
    'aac',
    'mp4',
    'mov',
    'm4v',
    'caf',
    'aif',
    'aiff',
    'wma', // AVFoundation 지원 시
    'mp2',
  };

  /// 파일 선택 다이얼로그에 노출할 전체 허용 확장자(WAV + 변환 대상).
  static List<String> get pickerExtensions =>
      [...wavExtensions, ...convertibleExtensions];

  /// [inputPath] 파일을 [outputPath] 의 16kHz 모노 WAV 로 변환한다.
  /// 성공 시 true. 실패 시 [PlatformException] 을 던진다(메시지에 사용자용 사유 포함).
  Future<bool> toWav16kMono({
    required String inputPath,
    required String outputPath,
  }) async {
    if (!Platform.isMacOS) {
      throw PlatformException(
        code: 'unsupported',
        message: 'macOS 에서만 지원됩니다.',
      );
    }
    final ok = await _channel.invokeMethod<bool>('toWav16kMono', {
      'input': inputPath,
      'output': outputPath,
    });
    return ok ?? false;
  }
}
