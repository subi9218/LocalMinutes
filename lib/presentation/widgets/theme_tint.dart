import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

/// 라이트·다크 양쪽에서 자연스러운 색 틴트 헬퍼.
///
/// 파스텔 고정색(Colors.X.shade50/100)은 다크 모드에서 형광 패치처럼 떠서
/// 테마가 반만 적용된 인상을 준다. 대신 기준색의 반투명 틴트를 쓰면
/// 배경 위에 자연스럽게 얹힌다 (meeting_detail의 기존 amber 패턴을 일반화).
bool _isDark(BuildContext context) =>
    (MacosTheme.maybeOf(context)?.brightness ??
        Theme.of(context).brightness) ==
    Brightness.dark;

/// 배너·칩 배경용 틴트.
Color tintBg(BuildContext context, MaterialColor color) =>
    color.withValues(alpha: _isDark(context) ? 0.16 : 0.10);

/// 배너·칩 보더용 틴트.
Color tintBorder(BuildContext context, MaterialColor color) =>
    color.withValues(alpha: _isDark(context) ? 0.45 : 0.30);

/// 틴트 배경 위 텍스트/아이콘 색 — 라이트는 진하게, 다크는 밝게.
Color tintFg(BuildContext context, MaterialColor color) =>
    _isDark(context) ? color.shade300 : color.shade800;

/// 틴트 배경 위 보조 텍스트 색.
Color tintFgMuted(BuildContext context, MaterialColor color) =>
    _isDark(context) ? color.shade400 : color.shade700;

/// 보조 텍스트/아이콘 색 — grey.shade600~800 고정색 대체 (다크 대응).
Color mutedText(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
