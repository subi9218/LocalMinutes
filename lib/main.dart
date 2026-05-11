import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import 'core/constants/app_constants.dart';
import 'core/ffi/on_device_model_manager.dart';
import 'core/services/app_settings.dart';
import 'core/services/auto_delete_service.dart';
import 'core/services/crash_log_service.dart';
import 'core/services/entitlement_service.dart';
import 'core/services/isar_service.dart';
import 'core/services/menu_bar_service.dart';
import 'core/services/native_appearance.dart';
import 'core/services/security_scoped_bookmark_service.dart';
import 'data/datasources/llm_service.dart';
import 'data/datasources/microphone_service.dart';
import 'presentation/providers/meeting_providers.dart';
import 'presentation/providers/settings_providers.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/setup_screen.dart';
import 'presentation/screens/storage_setup_screen.dart';

void main() async {
  // 충돌·예외 캡처 핸들러 — 모든 init보다 먼저 설치
  CrashLogService.instance.installGlobalHandlers();

  // 비동기 영역까지 잡으려면 runZonedGuarded로 감싸야 함
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (Platform.isMacOS) {
        await windowManager.ensureInitialized();
      }
      await IsarService.instance.init();
      await AppSettings.init(); // 설정 로드
      await SecurityScopedBookmarkService.restoreRecordingsFolderAccess();
      await EntitlementService.init(); // 무료/유료 게이트 (현재 hardcode pro)
      final modelsOk = await _checkModels();
      await _runAutoDelete(); // 자동 삭제 (설정된 경우)
      runApp(ProviderScope(child: MeetingAssistantApp(modelsOk: modelsOk)));
    },
    (error, stack) {
      CrashLogService.instance.recordCaught(
        error,
        stack,
        context: 'runZonedGuarded',
      );
    },
  );
}

/// STT + LLM 모델 파일 존재 여부 확인
Future<bool> _checkModels() async {
  try {
    final base = await getApplicationSupportDirectory();
    final dir = '${base.path}/models';
    final sttFast = await File(
      '$dir/${AppConstants.sttModelFileFast}',
    ).exists();
    final sttAccurate = await File(
      '$dir/${AppConstants.sttModelFileAccurate}',
    ).exists();
    final llmGemma = await File(
      '$dir/${AppConstants.llmModelFileGemma4E2B}',
    ).exists();
    final llmQwen = await File(
      '$dir/${AppConstants.llmModelFileQwen25_7B}',
    ).exists();
    return (sttFast || sttAccurate) && (llmGemma || llmQwen);
  } catch (_) {
    return false;
  }
}

/// 앱 시작 시 오래된 녹음 WAV 파일만 삭제 (회의록·전사·요약은 유지)
/// 실제 로직은 AutoDeleteService로 이전 (settings_screen과 공유).
Future<void> _runAutoDelete() async {
  await AutoDeleteService.run(AppSettings.instance.autoDeleteDays);
}

class MeetingAssistantApp extends ConsumerStatefulWidget {
  final bool modelsOk;
  const MeetingAssistantApp({super.key, required this.modelsOk});

  @override
  ConsumerState<MeetingAssistantApp> createState() =>
      _MeetingAssistantAppState();
}

class _MeetingAssistantAppState extends ConsumerState<MeetingAssistantApp>
    with WindowListener {
  late bool _showHome;
  late bool _storageReady;
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<NativeModelTaskSnapshot>? _nativeTaskSub;
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _exitPromptShowing = false;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _showHome = widget.modelsOk;
    _storageReady = AppSettings.instance.recordingsSavePath.isNotEmpty;

    // 앱 종료 직전 모델 정리 — ggml/Metal destructor abort 방지
    // (백그라운드 Metal init 중에 process exit하면 ggml_abort 발생)
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
      onDetach: _gracefulShutdown,
    );

    // 메뉴바 트레이 초기화 + 콜백 → Riverpod signal로 변환
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isMacOS) {
        windowManager.addListener(this);
        await windowManager.setPreventClose(true);
      }
      final svc = MenuBarService.instance;
      svc.onStartRecord = () => unawaited(_handleTrayStartRecord());
      svc.onStopRecord = () {
        ref.read(isRecordingActiveProvider.notifier).state = true;
        ref.read(selectedMeetingIdProvider.notifier).state = null;
        ref.read(pendingTrayStopProvider.notifier).state = true;
        ref.read(trayStopRecordingSignalProvider.notifier).update((s) => s + 1);
      };
      svc.onBookmark = () {
        ref.read(isRecordingActiveProvider.notifier).state = true;
        ref.read(selectedMeetingIdProvider.notifier).state = null;
        ref
            .read(pendingTrayBookmarkCountProvider.notifier)
            .update((count) => count + 1);
        ref.read(trayBookmarkSignalProvider.notifier).update((s) => s + 1);
      };
      svc.onShowWindow = () => unawaited(_showAppWindow());
      svc.onQuit = () => unawaited(_requestAppExit());
      await svc.init();
      await _syncTrayStartState();
      _nativeTaskSub = OnDeviceModelManager.instance.nativeTaskStream.listen((
        _,
      ) {
        unawaited(_syncTrayStartState());
      });
    });
  }

  Future<AppExitResponse> _onExitRequested() async {
    if (!_isExiting && !await _confirmExitIfNeeded()) {
      return AppExitResponse.cancel;
    }
    _isExiting = true;
    await _gracefulShutdown();
    return AppExitResponse.exit;
  }

  @override
  void onWindowClose() {
    unawaited(_handleWindowClose());
  }

  Future<void> _handleWindowClose() async {
    if (_isExiting) return;
    if (!Platform.isMacOS) return;
    final shouldClose = !await windowManager.isPreventClose()
        ? true
        : await _confirmExitIfNeeded();
    if (!shouldClose) return;
    _isExiting = true;
    await _gracefulShutdown();
    await windowManager.destroy();
  }

  Future<void> _requestAppExit() async {
    await _showAppWindow();
    if (!_isExiting && !await _confirmExitIfNeeded()) return;
    _isExiting = true;
    await _gracefulShutdown();
    SystemNavigator.pop();
  }

  String? _activeWorkLabel() {
    final mic = MicrophoneService.instance;
    if (mic.isRecording) return '녹음';
    if (mic.isPaused) return '일시 정지된 녹음';
    final native = OnDeviceModelManager.instance.nativeTaskSnapshot;
    if (native.activeLabel != null) return native.activeLabel;
    if (LlmService.instance.isGenerationActive) return '요약 생성';
    if (native.queuedLabel != null) return '대기 중인 ${native.queuedLabel}';
    return null;
  }

  Future<bool> _confirmExitIfNeeded() async {
    if (_isExiting) return true;
    final label = _activeWorkLabel();
    if (label == null) return true;
    if (_exitPromptShowing) return false;
    final ctx = _navigatorKey.currentContext;
    if (!mounted || ctx == null) return false;

    _exitPromptShowing = true;
    try {
      final confirmed = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Flexible(child: Text('작업이 진행 중입니다')),
            ],
          ),
          content: Text(
            '현재 $label 작업 중입니다.\n'
            '종료하면 진행 중인 작업이 중단되거나 결과가 저장되지 않을 수 있습니다.\n\n'
            '앱을 종료할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              child: const Text('종료'),
            ),
          ],
        ),
      );
      return confirmed == true;
    } finally {
      _exitPromptShowing = false;
    }
  }

  Future<void> _showAppWindow() async {
    if (!Platform.isMacOS) return;
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[showAppWindow] $e');
    }
  }

  Future<void> _handleTrayStartRecord() async {
    await _showAppWindow();
    if (!_storageReady) {
      await _showTrayStartBlockedDialog(
        title: '저장 폴더 선택이 필요합니다',
        message: '회의 녹음을 시작하려면 먼저 녹음 파일을 저장할 폴더를 선택해주세요.',
      );
      return;
    }
    if (!_showHome) {
      await _showTrayStartBlockedDialog(
        title: 'AI 모델 준비가 필요합니다',
        message: '트레이에서 바로 녹음하려면 먼저 음성 인식 모델과 요약 모델을 준비해주세요.',
      );
      return;
    }
    final activeTask =
        OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (activeTask != null) {
      await _showTrayStartBlockedDialog(
        title: 'AI 작업이 진행 중입니다',
        message: '현재 $activeTask 작업 중입니다. 작업이 끝난 뒤 빠른 녹음을 시작해주세요.',
      );
      await _syncTrayStartState();
      return;
    }

    // 빠른 녹음 시작: HomeScreen이 RecordingView로 전환되도록 신호
    ref.read(isRecordingActiveProvider.notifier).state = true;
    ref.read(selectedMeetingIdProvider.notifier).state = null;
    // 콜드 스타트(첫 마운트) 케이스: RecordingView initState가 소비
    ref.read(pendingTrayQuickStartProvider.notifier).state = true;
    ref.read(pendingTrayQuickStartFromTrayProvider.notifier).state = true;
    // 웜 스타트(이미 마운트): 카운터 listener가 픽업
    ref.read(trayStartRecordingSignalProvider.notifier).update((s) => s + 1);
  }

  Future<void> _showTrayStartBlockedDialog({
    required String title,
    required String message,
  }) async {
    final ctx = _navigatorKey.currentContext;
    if (!mounted || ctx == null) return;
    await showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded),
            const SizedBox(width: 8),
            Flexible(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncTrayStartState() {
    final activeTask =
        OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    final state = activeTask != null
        ? TrayStartState.busy
        : !_storageReady
        ? TrayStartState.storageRequired
        : !_showHome
        ? TrayStartState.modelsRequired
        : TrayStartState.ready;
    return MenuBarService.instance.setStartState(
      state,
      busyLabel: activeTask == null ? null : '$activeTask 중...',
    );
  }

  Future<void> _gracefulShutdown() async {
    try {
      // 1) 녹음 중이면 안전하게 정지 (Whisper unload 포함)
      try {
        await MicrophoneService.instance.stopRecording();
      } catch (_) {}
      // 2) 로드된 LLM/STT 모델 명시적 해제 — Metal/ggml 컨텍스트 정상 정리
      try {
        LlmService.instance.requestCancelActiveGeneration();
        await OnDeviceModelManager.instance.unloadLlm();
      } catch (_) {}
      try {
        await OnDeviceModelManager.instance.unloadStt();
      } catch (_) {}
      // 3) 메뉴바 트레이 아이콘 제거
      try {
        await MenuBarService.instance.dispose();
      } catch (_) {}
      try {
        await SecurityScopedBookmarkService.stopAccessingBookmark(
          AppSettings.instance.recordingsSaveBookmark,
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('[gracefulShutdown] $e');
    }
  }

  @override
  void dispose() {
    _nativeTaskSub?.cancel();
    if (Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // themeModeProvider를 watch → 설정 화면에서 즉시 반영
    final themeMode = ref.watch(themeModeProvider);
    // themeMode 변경을 native 측에 전파해 NSAppearance/traffic light 도 동기화.
    ref.listen<ThemeMode>(themeModeProvider, (_, next) {
      NativeAppearance.setMode(next);
    });
    // 첫 빌드에도 1회 강제 호출 (앱 시작 시 저장된 themeMode 반영)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NativeAppearance.setMode(themeMode);
    });

    // 결과 brightness 를 themeMode + system platform 으로 직접 계산.
    // (MacosTheme.of(context).brightness 가 themeMode 변경 직후 stale 하게 잡히는 케이스 회피.)
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectiveBrightness = themeMode == ThemeMode.light
        ? Brightness.light
        : themeMode == ThemeMode.dark
        ? Brightness.dark
        : platformBrightness;

    // Phase 1b: root 를 MacosApp 으로 교체. 본문은 여전히 Material 위젯이라
    // builder 안에서 Theme(ThemeData) 도 함께 제공해 호환을 유지한다.
    return MacosApp(
      navigatorKey: _navigatorKey,
      title: '적자생존',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: effectiveBrightness,
            ),
            useMaterial3: true,
            brightness: effectiveBrightness,
            // 라이트: 흰색, 다크: 차분한 회색
            scaffoldBackgroundColor: effectiveBrightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
          ),
          // MacosApp 은 자동으로 ScaffoldMessenger 를 제공하지 않는다 (MaterialApp 과 차이).
          // SnackBar 호출이 죽지 않도록 root 에 ScaffoldMessenger 를 명시 추가.
          child: ScaffoldMessenger(
            child: Material(
              type: MaterialType.transparency,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      // Phase 2b: MacosWindow 를 각 화면이 자체 root 로 가지도록 이전.
      //   - HomeScreen: MacosWindow(sidebar: ..., child: MacosScaffold(...))
      //   - StorageSetupScreen / SetupScreen: 자체 MacosWindow (사이드바 없음)
      // 화면 간 전환은 root MacosWindow 가 새로 만들어지지만 macos_ui 가 traffic light/chrome 을 일관되게 처리.
      home: _GlobalShortcuts(
        ref: ref,
        child: !_storageReady
            ? StorageSetupScreen(
                onComplete: () {
                  setState(() => _storageReady = true);
                  unawaited(_syncTrayStartState());
                },
              )
            : _showHome
            ? const HomeScreen()
            : SetupScreen(
                onComplete: () {
                  setState(() => _showHome = true);
                  unawaited(_syncTrayStartState());
                },
              ),
      ),
    );
  }
}

/// 앱 전역 키보드 단축키 — 어떤 화면에서도 동작
class _GlobalShortcuts extends StatelessWidget {
  final WidgetRef ref;
  final Widget child;

  const _GlobalShortcuts({required this.ref, required this.child});

  void _bump(StateProvider<int> provider) {
    ref.read(provider.notifier).update((s) => s + 1);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // ⌘⇧R : 녹음 시작/중지 (앱 어디서든)
        const SingleActivator(
          LogicalKeyboardKey.keyR,
          meta: true,
          shift: true,
        ): () =>
            _bump(shortcutToggleRecordSignalProvider),
        // ⌘F : 사이드바 검색 포커스
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _bump(shortcutFocusSearchSignalProvider),
        // ⌘⇧S : 요약 실행 (현재 회의 / 녹음 직후)
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          meta: true,
          shift: true,
        ): () =>
            _bump(shortcutRunSummarySignalProvider),
        // ⌘, : 설정 열기 (macOS 표준)
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
            _bump(shortcutOpenSettingsSignalProvider),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
