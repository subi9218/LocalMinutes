import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../core/l10n/app_tr.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/processing_status_service.dart';
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
import '../widgets/app_notice.dart';

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
    // 작업(전사/요약) 완료 시 — 작업 화면이 이미 dispose됐더라도 — 결과가
    // 보이도록 상주 화면인 HomeScreen이 대신 관련 provider를 새로고침한다.
    ProcessingStatus.instance.completionTick.addListener(_onJobCompleted);
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

  @override
  void dispose() {
    ProcessingStatus.instance.completionTick.removeListener(_onJobCompleted);
    super.dispose();
  }

  /// 작업 완료 시 끝난 회의의 전사/요약 provider를 새로고침.
  void _onJobCompleted() {
    final job = ProcessingStatus.instance.lastCompleted;
    ref.invalidate(meetingsProvider);
    if (job != null) {
      ref.invalidate(meetingTranscriptProvider(job.meetingId));
      ref.invalidate(meetingSummaryProvider(job.meetingId));
      ref.invalidate(summaryVersionsProvider(job.meetingId));
    }
  }

  Future<void> _openRecoveryDialog() async {
    debugPrint(
      '[Recovery] _openRecoveryDialog tapped, count=${_recoverable.length}',
    );
    if (_recoverable.isEmpty) return;
    // 일단 즉시 일괄 복구 — 모달 다이얼로그 사용을 피해 click 차단 사고 방지.
    // 사용자가 더 세밀히 선택하고 싶으면 추후 별도 화면으로 이전 가능.
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
    AppNotice.show(
      recovered == list.length
              ? tr('$recovered개 회의를 복구했습니다 — 일반 목록에서 요약 가능',
                  'Recovered $recovered meeting(s) — you can summarize them from the list')
              : tr('$recovered/${list.length}개 회의를 복구했습니다 (일부 실패)',
                  'Recovered $recovered of ${list.length} meeting(s) (some failed)'),
      kind: NoticeKind.success,
      duration: const Duration(seconds: 3),
    );
  }

  /// 전사/요약 진행 중이면 녹음·업로드를 막을 사유 문구(없으면 null).
  String? _busyBlockReason() {
    // 백업/복원 중 — DB가 닫히거나 스냅샷 중이므로 녹음 시작 금지.
    if (BackupService.isBusy) {
      return tr('백업/복원이 진행 중입니다. 완료 후 다시 시도해주세요.',
          'A backup or restore is in progress. Please try again after it finishes.');
    }
    // 녹음(마이크) 진행 중 — 툴바/단축키로 중복 시작 방지.
    final mic = MicrophoneService.instance;
    if (mic.isRecording || mic.isPaused) {
      return tr('이미 녹음이 진행 중입니다.', 'A recording is already in progress.');
    }
    // 녹음 직후 요약(recording_view의 isSummarizingProvider) 진행 중.
    if (ref.read(isSummarizingProvider)) {
      return tr('요약 작업이 진행 중입니다. 완료 후 다시 시도해주세요.',
          'A summary task is running. Please try again after it finishes.');
    }
    final job = ProcessingStatus.instance.active.value;
    if (job != null) {
      final what = job.kind == 'transcribe'
          ? tr('전사', 'transcription')
          : tr('요약', 'summarization');
      return tr('현재 $what 작업이 진행 중입니다. 완료 후 다시 시도해주세요.',
          'A $what task is running. Please try again after it finishes.');
    }
    final activeTask =
        OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (activeTask != null) {
      return tr('현재 $activeTask 작업 중입니다. 완료 후 다시 시도해주세요.',
          '$activeTask is currently running. Please try again after it finishes.');
    }
    return null;
  }

  void _startRecordingFromToolbar() {
    final reason = _busyBlockReason();
    if (reason != null) {
      AppNotice.show(
        reason,
        kind: NoticeKind.warning,
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
    AppNotice.show(
      message,
      kind: isError ? NoticeKind.error : NoticeKind.warning,
    );
  }

  bool _canStartRecordingByShortcut() {
    // 툴바 버튼과 동일 게이트 사용 — ProcessingStatus(전사/요약)도 검사.
    // (예전엔 activeLabel만 봐서 전사 lease 사이 공백에 단축키가 통과했음)
    final reason = _busyBlockReason();
    if (reason != null) {
      _showShortcutSnack(reason);
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
    // 처리 배너에서 "현재 보고 있는 회의"인지 판단용.
    final selectedId = ref.watch(selectedMeetingIdProvider);

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
                  message: _sidebarCollapsed
                      ? tr('사이드바 펼치기', 'Show Sidebar')
                      : tr('사이드바 접기', 'Hide Sidebar'),
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
                    tooltipMessage: tr('설정 (⌘,)', 'Settings (⌘,)'),
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
                          // 어느 화면에 있든 진행 중인 전사/요약을 보여주는 영구 배너.
                          // (작업 화면을 떠나도 진행이 사라지지 않도록)
                          ValueListenableBuilder<ProcessingJob?>(
                            valueListenable: ProcessingStatus.instance.active,
                            builder: (context, job, _) {
                              if (job == null) return const SizedBox.shrink();
                              return _ProcessingBanner(
                                job: job,
                                isCurrent: selectedId == job.meetingId,
                                onJump: () {
                                  ref
                                      .read(isRecordingActiveProvider.notifier)
                                      .state = false;
                                  ref
                                      .read(selectedGroupIdProvider.notifier)
                                      .state = null;
                                  ref
                                      .read(selectedMeetingIdProvider.notifier)
                                      .state = job.meetingId;
                                },
                                onCancel: () {
                                  ProcessingStatus.instance.requestCancel();
                                  AppNotice.show(
                                    tr(
                                          '중지를 요청했습니다. 현재 단계를 마무리하고 멈춥니다.',
                                          'Stop requested. Finishing the current step before stopping.'),
                                    kind: NoticeKind.warning,
                                  );
                                },
                              );
                            },
                          ),
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
    final job = ProcessingStatus.instance.active.value;
    final mic = MicrophoneService.instance;
    final busy = (mic.isRecording || mic.isPaused)
        ? tr('녹음', 'recording')
        : ref.read(isSummarizingProvider)
            ? tr('요약', 'summarization')
            : job != null
                ? (job.kind == 'transcribe'
                    ? tr('전사', 'transcription')
                    : tr('요약', 'summarization'))
                : OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (busy != null) {
      AppNotice.show(
        tr('현재 $busy 작업이 진행 중입니다. 완료 후 녹음을 시작해주세요.',
              'A $busy task is running. Please start recording after it finishes.'),
        kind: NoticeKind.warning,
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
    // 회의가 이미 있으면 '빈 상태'가 아니라 '미선택 상태' — 문구를 분기한다.
    // (예전엔 회의가 있어도 "회의록이 아직 없습니다"라고 표시해 사이드바와
    //  모순되는 인상을 줬다)
    final hasMeetings =
        ref.watch(meetingsProvider).asData?.value.isNotEmpty ?? false;

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
                      hasMeetings
                          ? tr('회의를 선택하세요', 'Select a meeting')
                          : tr('새 회의 녹음', 'New meeting recording'),
                      textAlign: TextAlign.center,
                      style: macosTheme.typography.largeTitle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color.onSurface,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasMeetings
                          ? tr('왼쪽 목록에서 회의를 선택하거나 새 녹음을 시작하세요',
                              'Choose a meeting from the sidebar, or start a new recording')
                          : tr('회의록이 아직 없습니다', 'No meetings yet'),
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
                tr(
                  '비정상 종료된 녹음 $count개가 있습니다. '
                      '복구하려면 오른쪽 버튼을 눌러주세요.',
                  'Found $count recording(s) from an unexpected quit. '
                      'Click the button on the right to recover them.',
                ),
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
              child: Text(tr('복구하기', 'Recover'), style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: tr('닫기', 'Dismiss'),
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

// ── 처리 중(전사/요약) 영구 진행 배너 ──────────────────────────────
// 작업 화면을 떠나도 진행 상황이 사라지지 않도록 앱 상단에 항상 표시한다.
class _ProcessingBanner extends StatelessWidget {
  final ProcessingJob job;

  /// 지금 그 회의를 보고 있는지 여부(맞으면 '보기' 버튼 숨김).
  final bool isCurrent;
  final VoidCallback onJump;
  final VoidCallback onCancel;

  const _ProcessingBanner({
    required this.job,
    required this.isCurrent,
    required this.onJump,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isTranscribe = job.kind == 'transcribe';
    final kindLabel = isTranscribe
        ? tr('전사 중', 'Transcribing')
        : tr('요약 중', 'Summarizing');
    final title = job.meetingTitle.trim();
    final hasPct = job.progress >= 0;
    final pctStr = hasPct ? ' ${(job.progress * 100).toStringAsFixed(0)}%' : '';

    return Material(
      color: Colors.indigo.shade50,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.indigo.shade200)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                value: hasPct && job.progress > 0 ? job.progress : null,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.indigo.shade600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.isEmpty
                        ? '$kindLabel$pctStr'
                        : '$kindLabel$pctStr · $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.indigo.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (job.label.trim().isNotEmpty)
                    Text(
                      job.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isCurrent)
              FilledButton.tonal(
                onPressed: onJump,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Colors.indigo.shade100,
                  foregroundColor: Colors.indigo.shade900,
                ),
                child: Text(tr('보기', 'View'),
                    style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
              ),
              child: Text(tr('중지', 'Stop'),
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
