import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// macOS NSApp.appearance 를 Flutter themeMode 와 동기화하는 platform channel 래퍼.
///
/// macos/Runner/MainFlutterWindow.swift 의 'app/appearance' 채널 'setMode' 메서드를 호출.
/// - light / dark / system 셋 중 하나로 NSAppearance 토글.
/// - NSWindow.backgroundColor 는 NSColor.windowBackgroundColor 라서 자동 light/dark 적응.
/// - traffic light 색·NSToolbar·system menu 모두 native 적응.
class NativeAppearance {
  NativeAppearance._();

  static const _channel = MethodChannel('app/appearance');

  /// 안전하게 호출. macOS 외 플랫폼은 무시. 채널이 없으면 silently skip.
  static Future<void> setMode(ThemeMode mode) async {
    if (!Platform.isMacOS) return;
    final raw = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    try {
      await _channel.invokeMethod<void>('setMode', raw);
    } catch (_) {
      // native 채널 미연결(테스트 환경 등)은 silently skip.
    }
  }
}
