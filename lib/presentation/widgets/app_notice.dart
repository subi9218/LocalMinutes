import 'dart:async';

import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

/// 알림 종류 — 아이콘·색만 다르고 형태는 동일하다.
enum NoticeKind { info, success, warning, error }

/// macOS 스타일의 비침투 알림(HUD).
///
/// Android의 하단 SnackBar 대신, 창 상단 중앙에 잠시 떠 있다 사라지는
/// 캡슐형 배너를 쓴다 (Xcode·Things 등 Mac 앱들의 관례).
///
/// 전역 내비게이터 키를 통해 오버레이에 그리므로:
/// - 호출에 context가 필요 없다 → await 뒤·위젯 dispose 뒤에도 안전.
/// - 어떤 화면 위에서도 동일한 위치·형태로 표시된다.
///
/// main.dart에서 `AppNotice.attach(navigatorKey)`로 연결한다.
class AppNotice {
  AppNotice._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static OverlayEntry? _current;
  static Timer? _dismissTimer;

  static void attach(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// 알림 표시. [actionLabel]+[onAction]을 주면 우측에 액션 버튼이 붙는다.
  static void show(
    String message, {
    NoticeKind kind = NoticeKind.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return; // 앱 초기화 전 — 조용히 무시

    // 새 알림이 오면 기존 알림은 즉시 교체
    _dismissTimer?.cancel();
    _current?.remove();
    _current = null;

    final entry = OverlayEntry(
      builder: (context) => _NoticeOverlay(
        message: message,
        kind: kind,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                dismiss();
                onAction();
              },
      ),
    );
    _current = entry;
    overlay.insert(entry);

    final autoDismiss = duration ??
        switch (kind) {
          NoticeKind.error => const Duration(seconds: 6),
          NoticeKind.warning => const Duration(seconds: 5),
          _ => const Duration(seconds: 3),
        };
    _dismissTimer = Timer(autoDismiss, dismiss);
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _current?.remove();
    _current = null;
  }
}

class _NoticeOverlay extends StatefulWidget {
  final String message;
  final NoticeKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _NoticeOverlay({
    required this.message,
    required this.kind,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_NoticeOverlay> createState() => _NoticeOverlayState();
}

class _NoticeOverlayState extends State<_NoticeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  (IconData, Color) _iconFor(NoticeKind kind, bool isDark) => switch (kind) {
        NoticeKind.success => (
            Icons.check_circle_rounded,
            isDark ? Colors.green.shade400 : Colors.green.shade600
          ),
        NoticeKind.warning => (
            Icons.warning_amber_rounded,
            isDark ? Colors.orange.shade400 : Colors.orange.shade700
          ),
        NoticeKind.error => (
            Icons.error_rounded,
            isDark ? Colors.red.shade400 : Colors.red.shade600
          ),
        NoticeKind.info => (
            Icons.info_rounded,
            isDark ? Colors.blue.shade400 : Colors.blue.shade600
          ),
      };

  @override
  Widget build(BuildContext context) {
    final macosTheme = MacosTheme.maybeOf(context);
    final isDark = (macosTheme?.brightness ??
            MediaQuery.maybePlatformBrightnessOf(context) ??
            Brightness.light) ==
        Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.10);
    final textColor = isDark ? Colors.white.withValues(alpha: 0.92) : const Color(0xFF1D1D1F);
    final (icon, iconColor) = _iconFor(widget.kind, isDark);

    return Positioned(
      top: 52, // 툴바 바로 아래
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: widget.onAction == null,
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 17, color: iconColor),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          widget.message,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: textColor,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null) ...[
                        const SizedBox(width: 12),
                        PushButton(
                          controlSize: ControlSize.small,
                          secondary: true,
                          onPressed: widget.onAction,
                          child: Text(widget.actionLabel!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
