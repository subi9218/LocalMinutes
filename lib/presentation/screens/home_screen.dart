import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/ffi/on_device_model_manager.dart';
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
  // Phase 2c: ToolBar 의 사이드바 토글 액션이 이 상태를 변경.
  bool _sidebarCollapsed = false;
  bool _recoveryChecked = false;
  List<Meeting> _recoverable = const [];

  @override
  void initState() {
    super.initState();
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

    return MacosWindow(
      disableWallpaperTinting: true,
      child: Row(
        children: [
          // ── 직접 그리는 사이드바 ──────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: _sidebarCollapsed ? 0 : 280,
            child: ClipRect(
              child: OverflowBox(
                maxWidth: 280,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 280,
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
            Container(
              width: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
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
                    label: '새 녹음',
                    icon: const MacosIcon(CupertinoIcons.mic_circle),
                    onPressed: _startRecordingFromToolbar,
                    showLabel: false,
                    tooltipMessage: '새 회의 녹음 시작 (⌘⇧R)',
                  ),
                  ToolBarIconButton(
                    label: '설정',
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

// Phase 2b 에서 _CollapsedSidebarRail / _SidebarResizeHandle 제거됨.
// macos_ui Sidebar 가 폭 조절을 자체 처리. 사이드바 토글은 Phase 2c 에서 ToolBar 액션으로 도입 예정.

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = MacosTheme.of(context).primaryColor;
    final secondaryText = MacosTheme.of(context).typography.subheadline.color;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.16)),
            ),
            child: Icon(Icons.edit_note, size: 42, color: accent),
          ),
          const SizedBox(height: 20),

          Text(
            'Local Minutes',
            style: MacosTheme.of(context).typography.title1.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '내 Mac에서 정리하는 로컬 회의록',
            style: MacosTheme.of(
              context,
            ).typography.subheadline.copyWith(color: secondaryText),
          ),
          const SizedBox(height: 28),

          PushButton(
            controlSize: ControlSize.large,
            secondary: false,
            onPressed: () {
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
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fiber_manual_record,
                    size: 14,
                    color: Colors.white,
                  ),
                  SizedBox(width: 8),
                  Text('새 녹음 시작'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 48),

          AppVersionCredit(
            badgeBackgroundColor: Colors.grey.shade100,
            badgeBorderColor: Colors.grey.shade300,
            versionColor: Colors.grey.shade500,
            creditColor: Colors.grey.shade400,
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
