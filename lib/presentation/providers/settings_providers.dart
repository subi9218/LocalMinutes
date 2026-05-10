import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/app_settings.dart';

/// 앱 테마 모드 Provider
///
/// 사이드바 또는 설정 화면에서 setThemeMode() 호출 후
/// ref.read(themeModeProvider.notifier).state = ... 로 즉시 반영
final themeModeProvider = StateProvider<ThemeMode>((ref) {
  switch (AppSettings.instance.themeMode) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});
