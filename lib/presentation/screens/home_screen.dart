import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/l10n/app_tr.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/recovery_service.dart';
import '../../data/datasources/microphone_service.dart';
import '../../domain/entities/meeting.dart';
import '../providers/meeting_providers.dart';
import '../providers/settings_providers.dart';
import '../widgets/app_version_credit.dart';
import '../widgets/meeting_sidebar.dart';
import '../widgets/meeting_detail_view.dart';
import '../widgets/recording_view.dart';
import '../widgets/series_dashboard_view.dart';
import 'settings_screen.dart' show showSettingsDialog;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const double _minSidebarWidth = 260;
  static const double _defaultSidebarWidth = 320;
  static const double _maxSidebarWidth = 480;

  // Phase 2c: ToolBar 의 사이드바 토글 액션이 이 상태를 변경.
  bool _sidebarCollapsed = false;
  late double _sidebarWidth;
  bool _recoveryChecked = false;
  List<Meeting> _recoverable = const [];

  @override
  void initState() {
    super.initState();
    _sidebarWidth = AppSettings.instance.sidebarWidth
        .clamp(_minSidebarWidth, _maxSidebarWidth)
        .toDouble();
    // 첫 빌드 후 비정상 종료된 녹음 검사 — 모달 다이얼로그 대신
    // 비차단 배너로 표시 (앱 클릭이 막히지 않도록)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_recoveryChecked) return;
      _recoveryChecked = true;
      final recoverable = await RecoveryService.findRecoverable();
      if (!mounted) return;
      setState(() => _recoverable = recoverable);
    });
  }

  Future<void> _openRecoveryDialog() async {
    debugPrint(
      '[Recovery] _openRecoveryDialog tapped, count=${_recoverable.length}',
    );
    if (_recoverable.isEmpty) return;
    // 일단 즉시 일괄 복구 — 모달 다이얼로그 사용을 피해 click 차단 사고 방지.
    // 사용자가 더 세밀히 선택하고 싶으면 추후 별도 화면으로 이전 가능.
    final messenger = ScaffoldMessenger.of(context);
    final list = List<Meeting>.from(_recoverable);
    int recovered = 0;
    Meeting? last;
    for (final m in list) {
      try {
        await RecoveryService.markAsRecovered(m);
        recovered++;
        last = m;
      } catch (e) {
        debugPrint('[Recovery] markAsRecovered failed for ${m.id}: $e');
      }
    }
    if (!mounted) return;
    ref.invalidate(meetingsProvider);
    if (last != null) {
      ref.read(selectedMeetingIdProvider.notifier).state = last.id;
    }
    setState(() => _recoverable = const []);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          recovered == list.length
              ? '$recovered개 회의를 복구했습니다 — 일반 목록에서 요약 가능'
              : '$recovered/${list.length}개 회의를 복구했습니다 (일부 실패)',
        ),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  void _startRecordingFromToolbar() {
    final activeTask =
        OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (activeTask != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('현재 $activeTask 작업 중입니다. 완료 후 녹음을 시작해주세요.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    ref.read(isRecordingActiveProvider.notifier).state = true;
    ref.read(selectedMeetingIdProvider.notifier).state = null;
    ref.read(selectedGroupIdProvider.notifier).state = null;
  }

  void _dismissRecoveryBanner() {
    setState(() => _recoverable = const []);
  }

  void _resizeSidebar(double delta) {
    if (_sidebarCollapsed) return;
    setState(() {
      _sidebarWidth = (_sidebarWidth + delta)
          .clamp(_minSidebarWidth, _maxSidebarWidth)
          .toDouble();
    });
  }

  void _persistSidebarWidth() {
    AppSettings.instance.setSidebarWidth(_sidebarWidth);
  }

  void _resetSidebarWidth() {
    setState(() => _sidebarWidth = _defaultSidebarWidth);
    AppSettings.instance.setSidebarWidth(_sidebarWidth);
  }

  void _showShortcutSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.orange.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _canStartRecordingByShortcut() {
    final activeTask =
        OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (activeTask != null) {
      _showShortcutSnack('현재 $activeTask 작업 중입니다. 완료 후 녹음을 시작해주세요.');
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // ── 전역 단축키 신호 listen ──────────────────────────────
    // ⌘, → 설정 다이얼로그 열기
    ref.listen<int>(shortcutOpenSettingsSignalProvider, (prev, next) {
      showSettingsDialog(context, ref);
    });
    // ⌘⇧R → 녹음 토글
    ref.listen<int>(shortcutToggleRecordSignalProvider, (prev, next) {
      final mic = MicrophoneService.instance;
      if (mic.isRecording || mic.isPaused) {
        // 녹음 중이면 정지 신호
        ref.read(isRecordingActiveProvider.notifier).state = true;
        ref.read(selectedMeetingIdProvider.notifier).state = null;
        ref.read(selectedGroupIdProvider.notifier).state = null;
        ref.read(pendingTrayStopProvider.notifier).state = true;
        ref.read(trayStopRecordingSignalProvider.notifier).update((s) => s + 1);
      } else {
        if (!_canStartRecordingByShortcut()) return;
        // 녹음 시작
        ref.read(isRecordingActiveProvider.notifier).state = true;
        ref.read(selectedMeetingIdProvider.notifier).state = null;
        ref.read(selectedGroupIdProvider.notifier).state = null;
        ref.read(pendingTrayQuickStartProvider.notifier).state = true;
        ref.read(pendingTrayQuickStartFromTrayProvider.notifier).state = false;
        ref
            .read(trayStartRecordingSignalProvider.notifier)
            .update((s) => s + 1);
      }
    });

    // 사이드바 색을 themeMode 변화에 즉시 반영하려면 build 본문에서 직접 watch.
    // (헬퍼 안에서 watch 하면 Riverpod 의존성 추적이 build 재실행을 트리거하지 못하는 케이스 회피)
    final themeMode = ref.watch(themeModeProvider);

    // 색 100% 통제하기 위해 macos_ui Sidebar 사용 안 함.
    // 사이드바는 직접 Container 로 그리고, 메인 영역은 MacosScaffold(toolBar) 로 감싸
    // Phase 2c 의 macOS 표준 ToolBar(사이드바 토글/새 녹음/설정) 패턴을 적용.
    final sidebarColor = _resolveSidebarColor(context, themeMode);
    final visibleSidebarWidth = _sidebarCollapsed ? 0.0 : _sidebarWidth;

    return MacosWindow(
      disableWallpaperTinting: true,
      child: Row(
        children: [
          // ── 직접 그리는 사이드바 ──────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: visibleSidebarWidth,
            child: ClipRect(
              child: OverflowBox(
                maxWidth: _maxSidebarWidth,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _sidebarWidth,
                  child: Container(
                    color: sidebarColor,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          // traffic light 영역(36px) + 더블클릭 zoom
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: _toggleMaximize,
                            child: const SizedBox(
                              height: 36,
                              width: double.infinity,
                            ),
                          ),
                          const SidebarSearchTop(),
                          const Expanded(child: MeetingSidebar()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 사이드바와 메인 영역 사이 1px separator (사이드바 펼쳐진 경우만)
          if (!_sidebarCollapsed)
            _SidebarResizeHandle(
              onDrag: _resizeSidebar,
              onDragEnd: _persistSidebarWidth,
              onReset: _resetSidebarWidth,
            ),
          // ── 메인 영역 (MacosScaffold + ToolBar) ──────────────────
          Expanded(
            child: MacosScaffold(
              toolBar: ToolBar(
                titleWidth: 200,
                title: const Text('Local Minutes'),
                leading: MacosTooltip(
                  message: _sidebarCollapsed ? '사이드바 펼치기' : '사이드바 접기',
                  child: MacosIconButton(
                    icon: Icon(CupertinoIcons.sidebar_left, size: 19),
                    onPressed: () =>
                        setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                    boxConstraints: const BoxConstraints(
                      minHeight: 28,
                      minWidth: 28,
                      maxWidth: 28,
                      maxHeight: 28,
                    ),
                  ),
                ),
                actions: [
                  // macOS 표준 toolbar 는 아이콘 + tooltip 만으로 표기 (라벨 표시는 separator 와 충돌해 어색).
                  ToolBarIconButton(
                    label: tr('새 녹음', 'New recording'),
                    icon: const MacosIcon(CupertinoIcons.mic_circle),
                    onPressed: _startRecordingFromToolbar,
                    showLabel: false,
                    tooltipMessage: tr('새 회의 녹음 시작 (⌘⇧R)', 'Start a new recording (⌘⇧R)'),
                  ),
                  ToolBarIconButton(
                    label: tr('설정', 'Settings'),
                    icon: const MacosIcon(CupertinoIcons.gear),
                    onPressed: () => showSettingsDialog(context, ref),
                    showLabel: false,
                    tooltipMessage: '설정 (⌘,)',
                  ),
                ],
              ),
              children: [
                ContentArea(
                  builder: (context, scrollController) {
                    return Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Column(
                        children: [
                          if (_recoverable.isNotEmpty)
                            _RecoveryBanner(
                              count: _recoverable.length,
                              onOpen: _openRecoveryDialog,
                              onDismiss: _dismissRecoveryBanner,
                            ),
                          const Expanded(child: _MainArea()),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// titlebar 더블클릭 → NSWindow zoom 토글.
  /// fullSizeContentView 모드에서 NSWindow 가 자동 처리하지 못하는 표준 동작을 직접 호출.
  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 사이드바 배경색을 themeMode + system brightness 기준으로 직접 결정.
  /// macOS sidebar 표준 톤: 라이트 #F5F5F7, 다크 #2A2A2A.
  /// themeMode 는 호출자(build)가 ref.watch 로 받아서 인자로 넘긴다.
  Color _resolveSidebarColor(BuildContext context, ThemeMode mode) {
    final platform = MediaQuery.platformBrightnessOf(context);
    final brightness = mode == ThemeMode.light
        ? Brightness.light
        : mode == ThemeMode.dark
        ? Brightness.dark
        : platform;
    return brightness == Brightness.dark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFF5F5F7);
  }
}

class _SidebarResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  const _SidebarResizeHandle({
    required this.onDrag,
    required this.onDragEnd,
    required this.onReset,
  });

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.3);
    final activeColor = scheme.primary.withValues(alpha: 0.48);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        onHorizontalDragCancel: () {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        child: SizedBox(
          width: 7,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _hovered || _dragging ? 2 : 1,
              color: _hovered || _dragging ? activeColor : dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _MainArea extends ConsumerWidget {
  const _MainArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRecording = ref.watch(isRecordingActiveProvider);
    final selectedId = ref.watch(selectedMeetingIdProvider);
    final selectedGroupId = ref.watch(selectedGroupIdProvider);

    // 회의 선택이 시리즈 대시보드보다 우선
    if (selectedId != null) return MeetingDetailView(meetingId: selectedId);
    // 시리즈 대시보드 (그룹 헤더 시계열 아이콘 클릭)
    if (selectedGroupId != null) {
      return SeriesDashboardView(groupId: selectedGroupId);
    }
    // 녹음 중이고 선택된 회의가 없으면 → RecordingView
    if (isRecording) return const RecordingView();
    return const _WelcomeView();
  }
}

// ── 시작 화면 (회의 미선택 상태) ─────────────────────────────────
class _WelcomeView extends ConsumerWidget {
  const _WelcomeView();

  void _startRecording(BuildContext context, WidgetRef ref) {
    final activeTask =
        OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (activeTask != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('현재 $activeTask 작업 중입니다. 완료 후 녹음을 시작해주세요.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    ref.read(isRecordingActiveProvider.notifier).state = true;
    ref.read(selectedMeetingIdProvider.notifier).state = null;
    ref.read(selectedGroupIdProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final macosTheme = MacosTheme.of(context);
    final color = Theme.of(context).colorScheme;
    final accent = macosTheme.primaryColor;
    final secondaryText = macosTheme.typography.subheadline.color;

    return SafeArea(
      top: false,
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(0, -0.08),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(Icons.edit_note, size: 48, color: accent),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      tr('새 회의 녹음', 'New meeting recording'),
                      textAlign: TextAlign.center,
                      style: macosTheme.typography.largeTitle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color.onSurface,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('회의록이 아직 없습니다', 'No meetings yet'),
                      textAlign: TextAlign.center,
                      style: macosTheme.typography.subheadline.copyWith(
                        color: secondaryText,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 30),
                    PushButton(
                      controlSize: ControlSize.large,
                      secondary: false,
                      onPressed: () => _startRecording(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.fiber_manual_record,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(tr('새 녹음 시작', 'Start new recording')),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: Center(
              child: AppVersionCredit(
                badgeBackgroundColor: color.surfaceContainerHighest.withValues(
                  alpha: 0.75,
                ),
                badgeBorderColor: color.outlineVariant.withValues(alpha: 0.7),
                versionColor: color.onSurfaceVariant.withValues(alpha: 0.78),
                creditColor: color.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 비정상 종료 복구 배너 (앱 상단 비차단) ─────────────────────────
class _RecoveryBanner extends StatelessWidget {
  final int count;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _RecoveryBanner({
    required this.count,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.amber.shade50,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.amber.shade300)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.history_toggle_off,
              color: Colors.amber.shade800,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '비정상 종료된 녹음 $count개가 있습니다. '
                '복구하려면 오른쪽 버튼을 눌러주세요.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: Colors.amber.shade100,
                foregroundColor: Colors.amber.shade900,
              ),
              child: const Text('복구하기', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: '닫기',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: Colors.amber.shade800,
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
