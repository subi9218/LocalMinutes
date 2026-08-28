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
import 'core/l10n/app_tr.dart';
import 'core/ffi/on_device_model_manager.dart';
import 'core/services/app_settings.dart';
import 'core/services/auto_delete_service.dart';
import 'core/services/backup_service.dart';
import 'core/services/crash_log_service.dart';
import 'core/services/entitlement_service.dart';
import 'core/services/isar_service.dart';
import 'core/services/menu_bar_service.dart';
import 'core/services/model_prewarm_service.dart';
import 'core/services/native_appearance.dart';
import 'core/services/processing_status_service.dart';
import 'core/services/security_scoped_bookmark_service.dart';
import 'data/datasources/llm_service.dart';
import 'data/datasources/microphone_service.dart';
import 'data/datasources/system_audio_service.dart';
import 'presentation/providers/global_container.dart';
import 'presentation/providers/meeting_providers.dart';
import 'presentation/providers/settings_providers.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/language_setup_screen.dart';
import 'presentation/screens/setup_screen.dart';
import 'presentation/screens/storage_setup_screen.dart';
import 'presentation/widgets/app_notice.dart';

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
      await AppSettings.init(); // 설정 로드
      final storageRestored =
          await SecurityScopedBookmarkService.restoreRecordingsFolderAccess();
      final hasStoragePath =
          AppSettings.instance.recordingsSavePath.trim().isNotEmpty;
      var storageReady = hasStoragePath && storageRestored;
      // 사용자 폴더 준비 전엔 Isar를 열지 않음 (컨테이너 폴백 금지).
      // Apple App Sandbox 2.4.5(i): user data must live in a user-accessible
      // location, not the hidden app container.
      // I7: init 실패(손상/잠금 DB 등)가 부팅을 죽이지 않도록 보호. 실패하면
      // 저장 폴더 미준비로 간주해 저장 폴더 화면을 보여준다(창은 항상 렌더).
      if (storageReady) {
        try {
          // 복원 도중 강제종료된 흔적이 있으면 원본 라이브러리를 먼저 되살린다.
          await BackupService.recoverInterruptedRestoreIfNeeded(
            AppSettings.instance.recordingsSavePath.trim(),
          );
          await IsarService.instance.init();
        } catch (e, st) {
          CrashLogService.instance.recordCaught(e, st, context: 'isarInit');
        }
        if (!IsarService.instance.isOpen) {
          storageReady = false;
        }
      }
      // I1: 저장 경로는 있는데 접근/열기에 실패한 '재연결 필요' 상태.
      // 이 경우 기존 회의록을 잃지 않도록 같은 폴더 재선택을 안내한다.
      final reconnectPath = (hasStoragePath && !storageReady)
          ? AppSettings.instance.recordingsSavePath.trim()
          : '';
      await EntitlementService.init(); // 무료/유료 게이트 (현재 hardcode pro)
      final modelsOk = await _checkModels();
      if (storageReady) {
        await _runAutoDelete(); // 자동 삭제 (설정된 경우)
      }
      runApp(
        UncontrolledProviderScope(
          container: globalProviderContainer,
          child: MeetingAssistantApp(
            modelsOk: modelsOk,
            storageReady: storageReady,
            reconnectPath: reconnectPath,
          ),
        ),
      );
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
    return AppSettings.instance.modelsSetupComplete;
  }
}

/// 앱 시작 시 오래된 녹음 WAV 파일만 삭제 (회의록·전사·요약은 유지)
/// 실제 로직은 AutoDeleteService로 이전 (settings_screen과 공유).
Future<void> _runAutoDelete() async {
  await AutoDeleteService.run(AppSettings.instance.autoDeleteDays);
}

class MeetingAssistantApp extends ConsumerStatefulWidget {
  final bool modelsOk;
  final bool storageReady;

  /// 저장 경로는 있으나 접근/열기에 실패해 재연결이 필요한 경우의 이전 폴더 경로.
  /// 비어 있지 않으면 저장 폴더 화면에서 '같은 폴더 재선택' 안내를 표시한다(I1).
  final String reconnectPath;

  const MeetingAssistantApp({
    super.key,
    required this.modelsOk,
    required this.storageReady,
    this.reconnectPath = '',
  });

  @override
  ConsumerState<MeetingAssistantApp> createState() =>
      _MeetingAssistantAppState();
}

class _MeetingAssistantAppState extends ConsumerState<MeetingAssistantApp>
    with WindowListener {
  late bool _showHome;
  late bool _storageReady;
  late bool _languageChosen;
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<NativeModelTaskSnapshot>? _nativeTaskSub;
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _exitPromptShowing = false;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    AppNotice.attach(_navigatorKey); // 전역 알림(HUD) 오버레이 연결
    _showHome = widget.modelsOk || AppSettings.instance.modelsSetupComplete;
    _storageReady = widget.storageReady;
    _languageChosen = AppSettings.instance.languageChosen;

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

      // 모델 프리워밍 — macOS 업데이트 후 첫 녹음이 ANE 재컴파일로 몇 분씩
      // 대기하지 않도록, 시작 15초 뒤 유휴 상태에서 미리 컴파일해 둔다.
      // (온보딩 중이거나 모델 미설치면 서비스가 알아서 건너뛴다)
      if (_showHome && _storageReady) {
        unawaited(
          Future<void>.delayed(const Duration(seconds: 15))
              .then((_) => ModelPrewarmService.maybePrewarm()),
        );
      }
    });
  }

  Future<AppExitResponse> _onExitRequested() async {
    // A1: 종료 확인 다이얼로그가 최소화/숨겨진 창 뒤에 떠 앱이 멈춘 것처럼
    // 보이지 않도록, 먼저 창을 보이고 포커스한다.
    if (!_isExiting) {
      await _showAppWindow();
    }
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
    if (mic.isRecording) return tr('녹음', 'recording');
    if (mic.isPaused) return tr('일시 정지된 녹음', 'paused recording');
    // 상세 화면의 다시 전사/재요약은 모델 로드·화자분리·DB 저장 구간에서
    // native task가 잠시 비활성일 수 있으므로 전역 처리상태를 우선 확인.
    final job = ProcessingStatus.instance.active.value;
    if (job != null) {
      return job.kind == 'transcribe'
          ? tr('전사', 'transcription')
          : tr('요약', 'summarization');
    }
    final native = OnDeviceModelManager.instance.nativeTaskSnapshot;
    if (native.activeLabel != null) return native.activeLabel;
    if (LlmService.instance.isGenerationActive) {
      return tr('요약 생성', 'summary generation');
    }
    if (native.queuedLabel != null) {
      return tr('대기 중인 ${native.queuedLabel}', 'queued ${native.queuedLabel}');
    }
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
      final confirmed = await showMacosAlertDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogCtx) => MacosAlertDialog(
          appIcon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 48,
          ),
          title: Text(tr('작업이 진행 중입니다', 'A task is in progress')),
          message: Text(
            tr(
              '현재 $label 작업 중입니다.\n'
                  '종료하면 진행 중인 작업이 중단되거나 결과가 저장되지 않을 수 있습니다.\n\n'
                  '앱을 종료할까요?',
              'A $label task is currently running.\n'
                  'Quitting now may interrupt it or lose unsaved results.\n\n'
                  'Quit the app?',
            ),
            textAlign: TextAlign.center,
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(tr('종료', 'Quit')),
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(tr('취소', 'Cancel')),
          ),
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
        title: tr('저장 폴더 선택이 필요합니다', 'Choose a save folder first'),
        message: tr('회의 녹음을 시작하려면 먼저 녹음 파일을 저장할 폴더를 선택해주세요.',
            'To start recording, please choose a folder for your recordings first.'),
      );
      return;
    }
    if (!_showHome) {
      await _showTrayStartBlockedDialog(
        title: tr('AI 모델 준비가 필요합니다', 'AI models need to be set up'),
        message: tr('트레이에서 바로 녹음하려면 먼저 음성 인식 모델과 요약 모델을 준비해주세요.',
            'To record from the menu bar, please set up the speech and summary models first.'),
      );
      return;
    }
    if (BackupService.isBusy) {
      await _showTrayStartBlockedDialog(
        title: tr('백업/복원이 진행 중입니다', 'A backup or restore is in progress'),
        message: tr('백업/복원이 끝난 뒤 녹음을 시작해주세요.',
            'Please start recording after the backup or restore finishes.'),
      );
      return;
    }
    final activeTask =
        OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (activeTask != null) {
      await _showTrayStartBlockedDialog(
        title: tr('AI 작업이 진행 중입니다', 'An AI task is in progress'),
        message: tr('현재 $activeTask 작업 중입니다. 작업이 끝난 뒤 빠른 녹음을 시작해주세요.',
            '$activeTask is currently running. Please start quick recording after it finishes.'),
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
    await showMacosAlertDialog<void>(
      context: ctx,
      builder: (dialogCtx) => MacosAlertDialog(
        appIcon: const Icon(
          Icons.info_outline_rounded,
          color: Colors.blueGrey,
          size: 48,
        ),
        title: Text(title),
        message: Text(message, textAlign: TextAlign.center),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: Text(tr('확인', 'OK')),
        ),
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
      busyLabel: activeTask == null
          ? null
          : tr('$activeTask 중...', '$activeTask...'),
    );
  }

  Future<void> _gracefulShutdown() async {
    try {
      // 1) 녹음 중이면 안전하게 정지 (Whisper unload 포함)
      try {
        await MicrophoneService.instance.stopRecording();
      } catch (_) {}
      // 시스템 오디오 캡처도 정지 — 안 하면 ExtAudioFile이 닫히지 않아
      // 손상된 _system.wav가 저장 폴더에 남는다.
      try {
        await SystemAudioService.instance.stop();
      } catch (_) {}
      // 2) 로드된 LLM/STT 모델 명시적 해제 — Metal/ggml 컨텍스트 정상 정리.
      // 모델 로드(콜드 시 몇 분)가 진행 중이면 unload가 lease 큐 뒤에 걸려
      // 종료가 조용히 수 분 지연될 수 있으므로 5초 상한을 둔다
      // (프로세스 종료 시 OS가 메모리를 회수하므로 미해제여도 무해).
      try {
        LlmService.instance.requestCancelActiveGeneration();
        await OnDeviceModelManager.instance
            .unloadLlm()
            .timeout(const Duration(seconds: 5), onTimeout: () {});
      } catch (_) {}
      try {
        await OnDeviceModelManager.instance
            .unloadStt()
            .timeout(const Duration(seconds: 5), onTimeout: () {});
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

  /// 언어 선택 화면 (첫 실행 + 온보딩에서 '이전'으로 되돌아올 때 재사용).
  Widget _buildLanguageScreen() {
    return LanguageSetupScreen(
      onSelected: (code) {
        ref.read(languageProvider.notifier).state =
            AppSettings.instance.effectiveLanguageCode;
        setState(() => _languageChosen = true);
      },
      nextScreen: _nextAfterLanguage(),
    );
  }

  /// 저장 폴더 설정(온보딩) 화면. 첫 단계에서 '이전'을 누르면 언어 선택으로
  /// 되돌아간다. home: 스왑과 pushReplacement 양쪽에서 동일하게 쓰이도록 헬퍼로 둔다.
  Widget _buildStorageScreen() {
    return StorageSetupScreen(
      // I1: 재연결 필요 시 이전 폴더 경로를 전달해 '같은 폴더 재선택' 안내 표시.
      reconnectPath: widget.reconnectPath,
      onComplete: (path) {
        setState(() => _storageReady = true);
        unawaited(_syncTrayStartState());
      },
      // 저장 폴더 설정 → 곧바로 모델 준비 화면으로 넘어가는 경로에서,
      // 모델 준비 완료 시 루트 상태/트레이 동기화 (안 그러면 트레이 빠른 녹음이
      // 첫 세션 내내 '모델 필요' 상태로 막힘).
      onModelsComplete: () {
        setState(() => _showHome = true);
        unawaited(_syncTrayStartState());
      },
      onBack: () {
        setState(() => _languageChosen = false);
        // _GlobalShortcuts는 MacosApp builder에서 전 라우트를 감싸므로
        // 여기서 다시 감싸지 않는다(S1).
        _navigatorKey.currentState?.pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => _buildLanguageScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      },
    );
  }

  Widget _buildSetupScreen() {
    return SetupScreen(
      onComplete: () async {
        await AppSettings.instance.setModelsSetupComplete(true);
        if (!mounted) return;
        setState(() => _showHome = true);
        unawaited(_syncTrayStartState());
      },
    );
  }

  /// 언어 선택 후 전환할 다음 화면. 보통 첫 실행이라 저장 폴더 설정으로 가지만,
  /// 이미 준비된 상태라면 그 다음 단계로 바로 넘어간다.
  Widget _nextAfterLanguage() {
    if (!_storageReady) return _buildStorageScreen();
    if (!_showHome) return _buildSetupScreen();
    return const HomeScreen();
  }

  @override
  Widget build(BuildContext context) {
    // themeModeProvider를 watch → 설정 화면에서 즉시 반영
    final themeMode = ref.watch(themeModeProvider);
    // languageProvider를 watch → 설정에서 언어 변경 시 앱 전체 다시 렌더.
    ref.watch(languageProvider);
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

    const systemBlue = Color(0xFF007AFF);

    // Phase 1b: root 를 MacosApp 으로 교체. 본문은 여전히 Material 위젯이라
    // builder 안에서 Theme(ThemeData) 도 함께 제공해 호환을 유지한다.
    return MacosApp(
      navigatorKey: _navigatorKey,
      title: 'Local Minutes',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MacosThemeData(
        brightness: Brightness.light,
        primaryColor: systemBlue,
      ),
      darkTheme: MacosThemeData(
        brightness: Brightness.dark,
        primaryColor: systemBlue,
      ),
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: systemBlue,
              brightness: effectiveBrightness,
            ),
            useMaterial3: true,
            brightness: effectiveBrightness,
            // 라이트: 흰색, 다크: 차분한 회색
            scaffoldBackgroundColor: effectiveBrightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
          ),
          // S1: _GlobalShortcuts 를 Navigator 위(builder)에 두어 모든 라우트
          // (pushReplacement 로 전환된 화면 포함)에서 전역 단축키가 살아 있도록 한다.
          // (알림은 AppNotice(HUD)로 통일되어 루트 ScaffoldMessenger는 제거 — 2.3)
          child: _AppMenuBar(
            ref: ref,
            child: _GlobalShortcuts(
              ref: ref,
              child: Material(
                type: MaterialType.transparency,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      // Phase 2b: MacosWindow 를 각 화면이 자체 root 로 가지도록 이전.
      //   - HomeScreen: MacosWindow(sidebar: ..., child: MacosScaffold(...))
      //   - StorageSetupScreen / SetupScreen: 자체 MacosWindow (사이드바 없음)
      // 화면 간 전환은 root MacosWindow 가 새로 만들어지지만 macos_ui 가 traffic light/chrome 을 일관되게 처리.
      home: !_languageChosen
          ? _buildLanguageScreen()
          : !_storageReady
          ? _buildStorageScreen()
          : _showHome
          ? const HomeScreen()
          : _buildSetupScreen(),
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

/// macOS 메뉴바(NSMenu)에 앱 명령을 등록한다.
///
/// 예전에는 명령이 CallbackShortcuts로만 존재해 메뉴바가 빈 템플릿
/// 그대로였다 — 사용자가 메뉴에서 기능을 발견할 수 없고, 죽은
/// 'Preferences…' 항목이 남는 등 Mac 앱의 기본 요건에 미달했다.
class _AppMenuBar extends StatelessWidget {
  final WidgetRef ref;
  final Widget child;

  const _AppMenuBar({required this.ref, required this.child});

  void _bump(StateProvider<int> provider) {
    ref.read(provider.notifier).update((s) => s + 1);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Local Minutes',
          menus: [
            PlatformMenuItemGroup(
              members: [
                if (PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.about))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.about,
                  ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: tr('설정…', 'Settings…'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: () =>
                      _bump(shortcutOpenSettingsSignalProvider),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                if (PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.hide))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.hide,
                  ),
                if (PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.hideOtherApplications))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.hideOtherApplications,
                  ),
              ],
            ),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.quit))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.quit,
              ),
          ],
        ),
        PlatformMenu(
          label: tr('파일', 'File'),
          menus: [
            PlatformMenuItem(
              label: tr('새 녹음', 'New Recording'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyR,
                meta: true,
                shift: true,
              ),
              onSelected: () => _bump(shortcutToggleRecordSignalProvider),
            ),
            PlatformMenuItem(
              label: tr('요약 실행', 'Run Summary'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                shift: true,
              ),
              onSelected: () => _bump(shortcutRunSummarySignalProvider),
            ),
          ],
        ),
        PlatformMenu(
          label: tr('편집', 'Edit'),
          menus: [
            PlatformMenuItem(
              label: tr('검색', 'Find'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
              ),
              onSelected: () => _bump(shortcutFocusSearchSignalProvider),
            ),
          ],
        ),
        PlatformMenu(
          label: tr('윈도우', 'Window'),
          menus: [
            PlatformMenuItemGroup(
              members: [
                if (PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.minimizeWindow))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.minimizeWindow,
                  ),
                if (PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.zoomWindow))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.zoomWindow,
                  ),
              ],
            ),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.toggleFullScreen))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.toggleFullScreen,
              ),
          ],
        ),
      ],
      child: child,
    );
  }
}
