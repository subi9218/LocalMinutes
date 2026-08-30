import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_build_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_tr.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/crash_log_service.dart';
import '../../core/services/model_download_service.dart';
import '../../core/services/user_error_message.dart';
import 'home_screen.dart';
import '../widgets/app_notice.dart';
import '../widgets/theme_tint.dart';

PageRouteBuilder<void> _instantRoute(Widget child) => PageRouteBuilder<void>(
  pageBuilder: (_, _, _) => child,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);

/// 모델 파일 설치 안내 + 자동 다운로드 화면
///
/// 핵심 동작: "필수 모델 받고 시작" 버튼 한 번으로 음성 인식 + 요약 모델을
/// 순차 다운로드하고, 완료되면 자동으로 홈 화면으로 진입한다.
/// 개별 모델 선택은 '고급' 영역으로 접어 두어, 사용자가 한 모델만 받고
/// 막히는 상황을 만들지 않는다.
class SetupScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupScreen({super.key, required this.onComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  // ── 모델 존재 여부 ──────────────────────────────────────────────
  // STT는 Fast/Accurate 각각 독립. 최소 둘 중 하나는 설치 필요.
  // LLM은 지원 모델 중 최소 하나 필요.
  bool _sttFastOk = false;
  bool _sttFastCoreMlOk = false;
  bool _sttAccurateOk = false;
  bool _llmGemmaOk = false;
  bool _llmQwenOk = false;
  bool _diarSegOk = false;
  bool _diarEmbOk = false;
  bool _checking = false;
  bool _starting = false;
  bool _completing = false;
  String? _startError;
  String _modelsDir = '';
  bool _showAdvanced = false;

  // ── 일괄(한 번에 받기) 다운로드 상태 ─────────────────────────────
  bool _bulkActive = false;
  List<_Target> _bulkSteps = const [];
  int _bulkStepIndex = 0;

  // ── 다운로드 상태 ───────────────────────────────────────────────
  final _sttFastService = ModelDownloadService();
  final _sttFastCoreMlService = ModelDownloadService();
  final _sttAccurateService = ModelDownloadService();
  final _llmGemmaService = ModelDownloadService();
  final _llmQwenService = ModelDownloadService();
  final _diarSegService = ModelDownloadService();
  final _diarEmbService = ModelDownloadService();

  _DlState _sttFastDl = const _DlState();
  _DlState _sttFastCoreMlDl = const _DlState();
  _DlState _sttAccurateDl = const _DlState();
  _DlState _llmGemmaDl = const _DlState();
  _DlState _llmQwenDl = const _DlState();
  _DlState _diarSegDl = const _DlState();
  _DlState _diarEmbDl = const _DlState();

  // ── HuggingFace 토큰 ────────────────────────────────────────────
  final _tokenCtrl = TextEditingController();
  bool _showTokenField = false;

  // ── 다운로드 URL (수정 가능) ─────────────────────────────────────
  late final TextEditingController _sttFastUrlCtrl;
  late final TextEditingController _sttFastCoreMlUrlCtrl;
  late final TextEditingController _sttAccurateUrlCtrl;
  late final TextEditingController _llmGemmaUrlCtrl;
  late final TextEditingController _llmQwenUrlCtrl;
  late final TextEditingController _diarSegUrlCtrl;
  late final TextEditingController _diarEmbUrlCtrl;
  bool _showSttFastUrl = false;
  bool _showSttFastCoreMlUrl = false;
  bool _showSttAccurateUrl = false;
  bool _showLlmGemmaUrl = false;
  bool _showLlmQwenUrl = false;
  bool _showDiarSegUrl = false;
  bool _showDiarEmbUrl = false;

  @override
  void initState() {
    super.initState();
    _sttFastUrlCtrl = TextEditingController(
      text: AppConstants.sttDownloadUrlFast,
    );
    _sttFastCoreMlUrlCtrl = TextEditingController(
      text: AppConstants.sttCoreMlEncoderDownloadUrlFast,
    );
    _sttAccurateUrlCtrl = TextEditingController(
      text: AppConstants.sttDownloadUrlAccurate,
    );
    _llmGemmaUrlCtrl = TextEditingController(
      text: AppConstants.llmDownloadUrlGemma4E2B,
    );
    _llmQwenUrlCtrl = TextEditingController(
      text: AppConstants.llmDownloadUrlQwen25_7B,
    );
    _diarSegUrlCtrl = TextEditingController(
      text: AppConstants.diarSegDownloadUrl,
    );
    _diarEmbUrlCtrl = TextEditingController(
      text: AppConstants.diarEmbDownloadUrl,
    );
    _check(autoComplete: true);
  }

  @override
  void dispose() {
    _sttFastService.cancel();
    _sttFastCoreMlService.cancel();
    _sttAccurateService.cancel();
    _llmGemmaService.cancel();
    _llmQwenService.cancel();
    _diarSegService.cancel();
    _diarEmbService.cancel();
    _tokenCtrl.dispose();
    _sttFastUrlCtrl.dispose();
    _sttFastCoreMlUrlCtrl.dispose();
    _sttAccurateUrlCtrl.dispose();
    _llmGemmaUrlCtrl.dispose();
    _llmQwenUrlCtrl.dispose();
    _diarSegUrlCtrl.dispose();
    _diarEmbUrlCtrl.dispose();
    super.dispose();
  }

  // ── 파일 존재 확인 ───────────────────────────────────────────────
  Future<void> _check({bool autoComplete = false}) async {
    setState(() => _checking = true);
    try {
      final dir = await _modelsDirectory();
      _modelsDir = dir.path;
      _sttFastOk = await File(
        '${dir.path}/${AppConstants.sttModelFileFast}',
      ).exists();
      _sttFastCoreMlOk = await Directory(
        '${dir.path}/${AppConstants.sttCoreMlEncoderFileFast}',
      ).exists();
      _sttAccurateOk = await File(
        '${dir.path}/${AppConstants.sttModelFileAccurate}',
      ).exists();
      _llmGemmaOk = await File(
        '${dir.path}/${AppConstants.llmModelFileGemma4E2B}',
      ).exists();
      _llmQwenOk = await File(
        '${dir.path}/${AppConstants.llmModelFileQwen25_7B}',
      ).exists();
      _diarSegOk = await File(
        '${dir.path}/${AppConstants.diarSegModelFile}',
      ).exists();
      _diarEmbOk = await File(
        '${dir.path}/${AppConstants.diarEmbModelFile}',
      ).exists();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _checking = false);
    if (autoComplete && !_anyDownloading && !_bulkActive && _hasRequiredModels) {
      await _completeSetup();
    }
  }

  Future<Directory> _modelsDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/models');
  }

  bool get _anyDownloading =>
      _sttFastDl.status == _Status.downloading ||
      _sttFastCoreMlDl.status == _Status.downloading ||
      _sttAccurateDl.status == _Status.downloading ||
      _llmGemmaDl.status == _Status.downloading ||
      _llmQwenDl.status == _Status.downloading ||
      _diarSegDl.status == _Status.downloading ||
      _diarEmbDl.status == _Status.downloading;

  bool get _anyStt => _sttFastOk || _sttAccurateOk;
  bool get _anyLlm => _llmGemmaOk || _llmQwenOk;
  bool get _hasRequiredModels => _anyStt && _anyLlm;

  // ── 한 번에 받기: 음성 인식 + 요약 모델 순차 다운로드 후 자동 진입 ──
  Future<void> _downloadAllRequired() async {
    if (_bulkActive || _anyDownloading) return;
    await _check();
    if (_hasRequiredModels) {
      await _completeSetup();
      return;
    }
    final steps = <_Target>[
      if (!_anyStt) _Target.sttFast,
      if (!_anyLlm) _Target.llmGemma,
    ];
    if (steps.isEmpty) {
      await _completeSetup();
      return;
    }
    if (!mounted) return;
    setState(() {
      _bulkActive = true;
      _bulkSteps = steps;
      _bulkStepIndex = 0;
      _startError = null;
    });
    for (var i = 0; i < steps.length; i++) {
      if (!mounted) return;
      setState(() => _bulkStepIndex = i);
      final ok = await _startDownload(
        target: steps[i],
        completeWhenReady: false,
      );
      // _startDownload 성공 경로의 inter-step 윈도우 동안 사용자가 취소하면
      // (_cancelBulk → _bulkActive=false) 다음 모델을 시작하지 않고 중단한다.
      if (!mounted || !_bulkActive) return;
      if (!ok) {
        if (!mounted) return;
        // 실패/취소 시 hero 카드에 에러를 노출한다.
        // (개별 모델 카드의 에러 메시지는 '고급' 영역이 접혀 있어 안 보이므로,
        //  기본 경로에서도 사용자가 실패 원인을 볼 수 있도록 _startError로 끌어올림.)
        final dl = _dlFor(steps[i]);
        final failed = dl.status == _Status.error;
        setState(() {
          _bulkActive = false;
          if (failed) {
            _startError = dl.errorMsg.isNotEmpty
                ? dl.errorMsg
                : tr(
                    '모델을 받지 못했습니다. 네트워크와 저장 공간을 확인한 뒤 다시 시도해주세요.',
                    'Could not download the model. Check your network and disk space, then try again.',
                  );
          }
        });
        return; // 오류/취소 시 중단
      }
    }
    if (!mounted) return;
    setState(() => _bulkActive = false);
    await _check(autoComplete: true); // 둘 다 준비됨 → 자동 진입
  }

  void _cancelBulk() {
    if (_bulkSteps.isNotEmpty && _bulkStepIndex < _bulkSteps.length) {
      _cancelDownload(target: _bulkSteps[_bulkStepIndex]);
    }
    if (mounted) setState(() => _bulkActive = false);
  }

  /// 현재 일괄 단계의 다운로드 진행 상태.
  _DlState get _bulkCurrentDl {
    if (_bulkSteps.isEmpty || _bulkStepIndex >= _bulkSteps.length) {
      return const _DlState();
    }
    return _dlFor(_bulkSteps[_bulkStepIndex]);
  }

  _DlState _dlFor(_Target t) => switch (t) {
    _Target.sttFast => _sttFastDl,
    _Target.sttFastCoreMl => _sttFastCoreMlDl,
    _Target.sttAccurate => _sttAccurateDl,
    _Target.llmGemma => _llmGemmaDl,
    _Target.llmQwen => _llmQwenDl,
    _Target.diarSeg => _diarSegDl,
    _Target.diarEmb => _diarEmbDl,
  };

  Future<void> _completeSetup() async {
    if (_completing) return;
    _completing = true;
    try {
      final installed = {
        if (_llmGemmaOk) 'gemma4_e2b',
        if (_llmQwenOk) 'qwen25_7b',
      };
      if (installed.isNotEmpty &&
          !installed.contains(AppSettings.instance.selectedLlmModel)) {
        await AppSettings.instance.setSelectedLlmModel(installed.first);
      }
      await AppSettings.instance.setModelsSetupComplete(true);
      if (!mounted) return;
      // 루트 상태 동기화 (트레이/플래그).
      widget.onComplete();
      // 실제 화면 전환은 pushReplacement로 처리한다.
      // 이 MacosApp 구조에서는 home: 위젯 스왑만으로는 표시 화면이
      // 즉시 바뀌지 않으므로, storage_setup_screen과 동일하게 명시 전환한다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
          rootNavigator: true,
        ).pushReplacement(_instantRoute(const HomeScreen()));
      });
    } catch (e, st) {
      _completing = false;
      CrashLogService.instance.recordCaught(
        e,
        st,
        context: 'setupCompleteSetup',
      );
      if (!mounted) return;
      setState(() {
        _startError = friendlyErrorText(
          e,
          fallbackTitle: tr('시작 준비 중 문제가 발생했습니다', 'Could not start the app'),
          fallbackMessage: tr(
            '설정 저장 또는 화면 전환에 실패했습니다.',
            'Saving settings or switching screens failed.',
          ),
          nextStep: tr(
            "잠시 후 다시 '앱 시작' 버튼을 눌러주세요.",
            'Please tap Start app again in a moment.',
          ),
        );
      });
    }
  }

  // ── 개별 다운로드 ────────────────────────────────────────────────
  /// 성공하면 true, 오류/취소면 false 반환.
  Future<bool> _startDownload({
    required _Target target,
    bool completeWhenReady = true,
  }) async {
    if (_anyDownloading) {
      _showSnack(
        tr(
          '이미 다운로드 중인 모델이 있습니다. 완료 후 다음 모델을 설치하세요.',
          'A model is already downloading. Please wait for it to finish.',
        ),
      );
      return false;
    }

    final dir = await _modelsDirectory();
    await dir.create(recursive: true);

    final String filename;
    final String url;
    final ModelDownloadService service;
    var extractZip = false;
    String? markerPath;
    switch (target) {
      case _Target.sttFast:
        filename = AppConstants.sttModelFileFast;
        url = _sttFastUrlCtrl.text.trim();
        service = _sttFastService;
      case _Target.sttFastCoreMl:
        filename = AppConstants.sttCoreMlEncoderZipFast;
        url = _sttFastCoreMlUrlCtrl.text.trim();
        service = _sttFastCoreMlService;
        extractZip = true;
        markerPath = '${dir.path}/${AppConstants.sttCoreMlEncoderFileFast}';
      case _Target.sttAccurate:
        filename = AppConstants.sttModelFileAccurate;
        url = _sttAccurateUrlCtrl.text.trim();
        service = _sttAccurateService;
      case _Target.llmGemma:
        filename = AppConstants.llmModelFileGemma4E2B;
        url = _llmGemmaUrlCtrl.text.trim();
        service = _llmGemmaService;
      case _Target.llmQwen:
        filename = AppConstants.llmModelFileQwen25_7B;
        url = _llmQwenUrlCtrl.text.trim();
        service = _llmQwenService;
      case _Target.diarSeg:
        filename = AppConstants.diarSegModelFile;
        url = _diarSegUrlCtrl.text.trim();
        service = _diarSegService;
      case _Target.diarEmb:
        filename = AppConstants.diarEmbModelFile;
        url = _diarEmbUrlCtrl.text.trim();
        service = _diarEmbService;
    }
    final destPath = '${dir.path}/$filename';
    final token =
        !AppBuildConfig.appStoreComplianceMode &&
            _tokenCtrl.text.trim().isNotEmpty
        ? _tokenCtrl.text.trim()
        : null;

    _setDl(target, const _DlState(status: _Status.downloading));

    try {
      void onProgress(int received, int total, double speed) {
        if (!mounted) return;
        _setDl(
          target,
          _DlState(
            status: _Status.downloading,
            received: received,
            total: total,
            speedMBps: speed,
          ),
        );
      }

      if (extractZip) {
        await service.downloadAndExtractZip(
          url: url,
          destZipPath: destPath,
          extractDir: dir.path,
          markerPath: markerPath!,
          bearerToken: token,
          expectedBytes: AppConstants.expectedModelBytes(filename),
          onProgress: onProgress,
        );
      } else {
        await service.download(
          url: url,
          destPath: destPath,
          bearerToken: token,
          expectedBytes: AppConstants.expectedModelBytes(filename),
          onProgress: onProgress,
        );
      }

      if (mounted) {
        _setDl(target, const _DlState(status: _Status.done));
        await _check(autoComplete: completeWhenReady);
      }
      return true;
    } on ModelDownloadException catch (e) {
      if (!mounted) return false;
      if (e.isCancelled) {
        _setDl(target, const _DlState());
        return false;
      }
      if (e.needsAuth) {
        _setDl(target, _DlState(status: _Status.error, errorMsg: e.message));
        if (!AppBuildConfig.appStoreComplianceMode) {
          setState(() => _showTokenField = true);
        }
        _showSnack(e.message, isError: true);
        return false;
      }
      _setDl(target, _DlState(status: _Status.error, errorMsg: e.message));
      return false;
    } catch (e, st) {
      if (!mounted) return false;
      CrashLogService.instance.recordCaught(
        e,
        st,
        context: 'setupModelDownload',
      );
      _setDl(
        target,
        _DlState(
          status: _Status.error,
          errorMsg: friendlyErrorText(
            e,
            fallbackTitle: tr('모델을 설치하지 못했습니다', 'Could not install the model'),
            fallbackMessage: tr(
              '다운로드 또는 파일 저장 중 문제가 발생했습니다.',
              'A problem occurred while downloading or saving the file.',
            ),
            nextStep: tr(
              '네트워크, 저장 공간, 모델 폴더 권한을 확인한 뒤 다시 시도해주세요.',
              'Check your network, disk space, and folder permissions, then try again.',
            ),
          ),
        ),
      );
      return false;
    }
  }

  void _cancelDownload({required _Target target}) {
    switch (target) {
      case _Target.sttFast:
        _sttFastService.cancel();
      case _Target.sttFastCoreMl:
        _sttFastCoreMlService.cancel();
      case _Target.sttAccurate:
        _sttAccurateService.cancel();
      case _Target.llmGemma:
        _llmGemmaService.cancel();
      case _Target.llmQwen:
        _llmQwenService.cancel();
      case _Target.diarSeg:
        _diarSegService.cancel();
      case _Target.diarEmb:
        _diarEmbService.cancel();
    }
    _setDl(target, const _DlState());
  }

  void _setDl(_Target target, _DlState state) {
    if (!mounted) return;
    setState(() {
      switch (target) {
        case _Target.sttFast:
          _sttFastDl = state;
        case _Target.sttFastCoreMl:
          _sttFastCoreMlDl = state;
        case _Target.sttAccurate:
          _sttAccurateDl = state;
        case _Target.llmGemma:
          _llmGemmaDl = state;
        case _Target.llmQwen:
          _llmQwenDl = state;
        case _Target.diarSeg:
          _diarSegDl = state;
        case _Target.diarEmb:
          _diarEmbDl = state;
      }
    });
  }

  // ── 확인 완료 (앱 시작 버튼) ─────────────────────────────────────
  Future<void> _confirmCheck() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _startError = null;
    });

    try {
      await _check().timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
            throw TimeoutException(tr('모델 파일 확인 시간이 초과되었습니다.', 'Model check timed out.')),
      );

      if (_hasRequiredModels) {
        await _completeSetup();
        return;
      }

      final missing = <String>[
        if (!_anyStt) tr('음성 인식 모델', 'a speech recognition model'),
        if (!_anyLlm) tr('요약 모델', 'a summary model'),
      ].join(tr('과(와) ', ' and '));
      final message = tr(
        "$missing을(를) 받아야 시작할 수 있습니다. '필수 모델 받고 시작' 버튼을 눌러주세요.",
        "You still need $missing. Tap 'Get required models & start'.",
      );
      if (!mounted) return;
      setState(() => _startError = message);
    } catch (e, st) {
      CrashLogService.instance.recordCaught(e, st, context: 'setupConfirmCheck');
      final message = friendlyErrorText(
        e,
        fallbackTitle: tr('앱을 시작하지 못했습니다', 'Could not start the app'),
        fallbackMessage: tr('모델 확인 중 문제가 발생했습니다.', 'A problem occurred while checking models.'),
        nextStep: tr(
          '다시 확인을 누르거나 앱을 재실행한 뒤 한 번 더 시도해주세요.',
          'Tap re-check or restart the app and try again.',
        ),
      );
      if (!mounted) return;
      setState(() => _startError = message);
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  // ── 폴더 열기 ────────────────────────────────────────────────────
  Future<void> _openFolder() async {
    final dir = await _modelsDirectory();
    await dir.create(recursive: true);
    await launchUrl(Uri.parse('file://${dir.path}'));
  }

  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: _modelsDir));
    _showSnack(tr('경로가 클립보드에 복사되었습니다.', 'Path copied to clipboard.'));
  }

  void _showSnack(String msg, {bool isError = false}) {
    AppNotice.show(
      msg,
      kind: isError ? NoticeKind.error : NoticeKind.info,
      duration: const Duration(seconds: 5),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allOk = _hasRequiredModels;

    return MacosWindow(
      disableWallpaperTinting: true,
      child: MacosScaffold(
        children: [
          ContentArea(
            builder: (context, scrollController) => Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context, scheme),
                        const SizedBox(height: 24),
                        _buildHeroCard(context, scheme, allOk),
                        if (_startError != null) ...[
                          const SizedBox(height: 16),
                          _buildErrorBox(scheme),
                        ],
                        const SizedBox(height: 20),
                        _buildAdvancedSection(context, scheme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
          ),
          child: Icon(Icons.edit_note, size: 24, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Local Minutes',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tr('회의록을 위한 AI 모델 준비', 'Set up the on-device AI models'),
                style: TextStyle(fontSize: 13, color: mutedText(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 중심 카드 — 필수 모델 상태 + 단일 기본 동작(받고 시작 / 앱 시작).
  Widget _buildHeroCard(
    BuildContext context,
    ColorScheme scheme,
    bool allOk,
  ) {
    final bulkDl = _bulkCurrentDl;
    final bulkLabel = _bulkSteps.isEmpty || _bulkStepIndex >= _bulkSteps.length
        ? ''
        : _targetDisplayName(_bulkSteps[_bulkStepIndex]);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: allOk
            ? Colors.green.withValues(alpha: 0.06)
            : scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allOk
              ? Colors.green.shade300.withValues(alpha: 0.6)
              : scheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('필수 모델', 'Required models'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              '회의를 받아쓰는 음성 인식 모델 1개와, 요약을 만드는 요약 모델 1개가 모두 필요합니다.',
              'You need both: one speech recognition model (to transcribe) and one summary model (to summarize).',
            ),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: mutedText(context),
            ),
          ),
          const SizedBox(height: 14),

          // 두 필수 항목 상태
          _RequiredRow(
            label: tr('음성 인식', 'Speech recognition'),
            ok: _anyStt,
            scheme: scheme,
          ),
          const SizedBox(height: 8),
          _RequiredRow(
            label: tr('요약 (회의록 생성)', 'Summary'),
            ok: _anyLlm,
            scheme: scheme,
          ),
          const SizedBox(height: 18),

          // 진행 상태 / 기본 버튼
          if (_bulkActive) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(
                      '($bulkLabel) 다운로드 중... (${_bulkStepIndex + 1}/${_bulkSteps.length})',
                      'Downloading $bulkLabel... (${_bulkStepIndex + 1}/${_bulkSteps.length})',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (bulkDl.speedStr.isNotEmpty)
                  Text(
                    bulkDl.speedStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: bulkDl.progress < 0 ? null : bulkDl.progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${bulkDl.receivedStr} / ${bulkDl.totalStr}',
                  style: TextStyle(fontSize: 11.5, color: mutedText(context)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _cancelBulk,
                  child: Text(tr('취소', 'Cancel')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                '큰 파일이라 시간이 걸릴 수 있습니다. 완료되면 자동으로 시작됩니다.',
                'These are large files and may take a while. The app starts automatically when done.',
              ),
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_checking || _starting || _anyDownloading)
                    ? null
                    : (allOk
                          ? () => unawaited(_confirmCheck())
                          : () => unawaited(_downloadAllRequired())),
                icon: Icon(
                  allOk ? Icons.play_arrow_rounded : Icons.download_rounded,
                  size: 20,
                ),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _starting
                        ? tr('시작 중...', 'Starting...')
                        : allOk
                        ? tr('앱 시작', 'Start app')
                        : tr(
                            '필수 모델 받고 시작 (약 3.9GB)',
                            'Get required models & start (~3.9 GB)',
                          ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            if (!allOk) ...[
              const SizedBox(height: 8),
              Text(
                tr(
                  '버튼 하나로 음성 인식·요약 모델을 모두 받습니다. 인터넷 연결이 필요합니다.',
                  'One tap downloads both the speech and summary models. An internet connection is required.',
                ),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: mutedText(context),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBox(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
      ),
      child: Text(
        _startError!,
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }

  /// 고급: 개별 모델 선택 (접힘 기본). 정확도/속도/발화자 라벨 모델 등.
  Widget _buildAdvancedSection(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _showAdvanced
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: mutedText(context),
                ),
                const SizedBox(width: 4),
                Text(
                  tr('고급: 개별 모델 선택', 'Advanced: choose models individually'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: mutedText(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 8),
          _buildModelCards(context, scheme),
          const SizedBox(height: 16),
          _buildInstallPath(context, scheme),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _modelsDir.isEmpty ? null : _openFolder,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(tr('폴더 열기', 'Open folder')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _checking || _anyDownloading || _bulkActive
                    ? null
                    : () => unawaited(_check(autoComplete: true)),
                icon: _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(tr('다시 확인', 'Re-check')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildModelCards(BuildContext context, ColorScheme scheme) {
    final anyDownloading = _anyDownloading || _bulkActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModelDownloadCard(
          label: tr('빠른 음성 인식', 'Fast speech recognition'),
          filename: AppConstants.sttModelFileFast,
          size: '~900 MB',
          isOk: _sttFastOk,
          dlState: _sttFastDl,
          urlCtrl: _sttFastUrlCtrl,
          showUrl: _showSttFastUrl,
          onToggleUrl: () => setState(() => _showSttFastUrl = !_showSttFastUrl),
          onInstall: () => unawaited(_startDownload(target: _Target.sttFast)),
          onCancel: () => _cancelDownload(target: _Target.sttFast),
          installDisabled: anyDownloading,
        ),
        const SizedBox(height: 10),
        _ModelDownloadCard(
          label: tr('기본 요약', 'Default summary'),
          filename: AppConstants.llmModelFileGemma4E2B,
          size: '~3 GB',
          tooltip: tr(
            '크기: 약 3GB\n속도: 매우 빠름\n짧은 회의·메모 요약에 적합',
            'Size: ~3 GB\nSpeed: very fast\nGood for short meetings and notes',
          ),
          isOk: _llmGemmaOk,
          dlState: _llmGemmaDl,
          urlCtrl: _llmGemmaUrlCtrl,
          showUrl: _showLlmGemmaUrl,
          onToggleUrl: () =>
              setState(() => _showLlmGemmaUrl = !_showLlmGemmaUrl),
          onInstall: () => unawaited(_startDownload(target: _Target.llmGemma)),
          onCancel: () => _cancelDownload(target: _Target.llmGemma),
          installDisabled: anyDownloading,
        ),
        const SizedBox(height: 16),
        Text(
          tr('선택 모델', 'Optional models'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            '정확도, 속도, 발화자 라벨이 필요할 때 추가합니다.',
            'Add these for higher accuracy, speed, or speaker labels.',
          ),
          style: TextStyle(fontSize: 12, color: mutedText(context)),
        ),
        const SizedBox(height: 10),
        _ModelDownloadCard(
          label: tr('정확도 높은 음성 인식', 'High-accuracy speech recognition'),
          filename: AppConstants.sttModelFileAccurate,
          size: '~1.1 GB',
          isOk: _sttAccurateOk,
          dlState: _sttAccurateDl,
          urlCtrl: _sttAccurateUrlCtrl,
          showUrl: _showSttAccurateUrl,
          onToggleUrl: () =>
              setState(() => _showSttAccurateUrl = !_showSttAccurateUrl),
          onInstall: () =>
              unawaited(_startDownload(target: _Target.sttAccurate)),
          onCancel: () => _cancelDownload(target: _Target.sttAccurate),
          installDisabled: anyDownloading,
        ),
        const SizedBox(height: 10),
        _ModelDownloadCard(
          label: tr('빠른 음성 인식 가속팩', 'Fast STT acceleration pack'),
          filename: AppConstants.sttCoreMlEncoderFileFast,
          size: '~1.2 GB',
          tooltip: tr(
            'Apple Silicon에서 긴 녹음 전사를 더 빠르게 처리합니다. 없어도 앱은 기존 방식으로 동작합니다.',
            'Speeds up long transcriptions on Apple Silicon. The app still works without it.',
          ),
          isOk: _sttFastCoreMlOk,
          dlState: _sttFastCoreMlDl,
          urlCtrl: _sttFastCoreMlUrlCtrl,
          showUrl: _showSttFastCoreMlUrl,
          onToggleUrl: () =>
              setState(() => _showSttFastCoreMlUrl = !_showSttFastCoreMlUrl),
          onInstall: () =>
              unawaited(_startDownload(target: _Target.sttFastCoreMl)),
          onCancel: () => _cancelDownload(target: _Target.sttFastCoreMl),
          installDisabled: anyDownloading,
        ),
        const SizedBox(height: 10),
        _ModelDownloadCard(
          label: tr('고품질 요약', 'High-quality summary'),
          filename: AppConstants.llmModelFileQwen25_7B,
          size: '~4.7 GB',
          tooltip: tr(
            '크기: 약 4.7GB\n속도: 보통\n액션아이템/결정사항 구조화에 적합',
            'Size: ~4.7 GB\nSpeed: moderate\nGood for structured action items and decisions',
          ),
          isOk: _llmQwenOk,
          dlState: _llmQwenDl,
          urlCtrl: _llmQwenUrlCtrl,
          showUrl: _showLlmQwenUrl,
          onToggleUrl: () => setState(() => _showLlmQwenUrl = !_showLlmQwenUrl),
          onInstall: () => unawaited(_startDownload(target: _Target.llmQwen)),
          onCancel: () => _cancelDownload(target: _Target.llmQwen),
          installDisabled: anyDownloading,
        ),
        const SizedBox(height: 10),
        _ModelDownloadCard(
          label: tr('발화자 라벨 · 세그멘테이션', 'Speaker labels · segmentation'),
          filename: AppConstants.diarSegModelFile,
          size: '~6 MB',
          tooltip: tr(
            'pyannote-segmentation-3.0 (ONNX)\n음성 활동/발화 경계 검출',
            'pyannote-segmentation-3.0 (ONNX)\nVoice activity / speech boundary detection',
          ),
          isOk: _diarSegOk,
          dlState: _diarSegDl,
          urlCtrl: _diarSegUrlCtrl,
          showUrl: _showDiarSegUrl,
          onToggleUrl: () => setState(() => _showDiarSegUrl = !_showDiarSegUrl),
          onInstall: () => unawaited(_startDownload(target: _Target.diarSeg)),
          onCancel: () => _cancelDownload(target: _Target.diarSeg),
          installDisabled: anyDownloading,
        ),
        const SizedBox(height: 10),
        _ModelDownloadCard(
          label: tr('발화자 라벨 · 스피커 임베딩', 'Speaker labels · embedding'),
          filename: AppConstants.diarEmbModelFile,
          size: '~26 MB',
          tooltip: tr(
            '3D-Speaker eres2net base (ONNX)\n화자별 벡터 임베딩 추출 → 클러스터링',
            '3D-Speaker eres2net base (ONNX)\nPer-speaker embeddings → clustering',
          ),
          isOk: _diarEmbOk,
          dlState: _diarEmbDl,
          urlCtrl: _diarEmbUrlCtrl,
          showUrl: _showDiarEmbUrl,
          onToggleUrl: () => setState(() => _showDiarEmbUrl = !_showDiarEmbUrl),
          onInstall: () => unawaited(_startDownload(target: _Target.diarEmb)),
          onCancel: () => _cancelDownload(target: _Target.diarEmb),
          installDisabled: anyDownloading,
        ),
        if (!AppBuildConfig.appStoreComplianceMode) ...[
          const SizedBox(height: 16),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _showTokenField
                ? _buildTokenField(scheme)
                : const SizedBox.shrink(),
          ),
          if (!_showTokenField)
            TextButton.icon(
              onPressed: () =>
                  setState(() => _showTokenField = !_showTokenField),
              icon: const Icon(Icons.key, size: 16),
              label: Text(tr('HuggingFace 토큰 입력', 'Enter HuggingFace token')),
            ),
        ],
      ],
    );
  }

  Widget _buildInstallPath(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('설치 경로', 'Install path'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _modelsDir.isEmpty
                      ? tr('경로 확인 중...', 'Resolving path...')
                      : _modelsDir,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: tr('경로 복사', 'Copy path'),
                onPressed: _modelsDir.isEmpty ? null : _copyPath,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTokenField(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tintBg(context, Colors.amber),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tintBorder(context, Colors.amber)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key, size: 16, color: tintFg(context, Colors.amber)),
              const SizedBox(width: 6),
              Text(
                tr('HuggingFace 토큰', 'HuggingFace token'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: tintFg(context, Colors.amber),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _showTokenField = false),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              '일부 모델 제공 사이트가 권한 확인을 요구할 때만 사용합니다.\n'
                  'huggingface.co → Settings → Access Tokens에서 발급할 수 있습니다.',
              'Only needed when a model host requires authentication.\n'
                  'Create one at huggingface.co → Settings → Access Tokens.',
            ),
            style: TextStyle(
              fontSize: 11,
              color: tintFg(context, Colors.amber),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenCtrl,
            obscureText: true,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'hf_xxxxxxxxxxxxxxxx',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.open_in_browser, size: 18),
                tooltip: tr('HuggingFace 토큰 발급 페이지', 'Open HuggingFace tokens page'),
                onPressed: () => launchUrl(
                  Uri.parse('https://huggingface.co/settings/tokens'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _targetDisplayName(_Target t) => switch (t) {
    _Target.sttFast => tr('음성 인식', 'speech model'),
    _Target.sttFastCoreMl => tr('가속팩', 'acceleration pack'),
    _Target.sttAccurate => tr('음성 인식', 'speech model'),
    _Target.llmGemma => tr('요약', 'summary model'),
    _Target.llmQwen => tr('요약', 'summary model'),
    _Target.diarSeg => tr('발화자 라벨', 'speaker labels'),
    _Target.diarEmb => tr('발화자 라벨', 'speaker labels'),
  };
}

/// 필수 항목 상태 한 줄 (체크/대기).
class _RequiredRow extends StatelessWidget {
  final String label;
  final bool ok;
  final ColorScheme scheme;

  const _RequiredRow({
    required this.label,
    required this.ok,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: ok ? Colors.green.shade600 : Colors.grey.shade400,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: ok ? Colors.green.shade800 : scheme.onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          ok ? tr('설치됨', 'installed') : tr('필요', 'required'),
          style: TextStyle(
            fontSize: 11.5,
            color: ok ? Colors.green.shade600 : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }
}

// ── 다운로드 상태 ─────────────────────────────────────────────────────────────

enum _Target {
  sttFast,
  sttFastCoreMl,
  sttAccurate,
  llmGemma,
  llmQwen,
  diarSeg,
  diarEmb,
}

enum _Status { idle, downloading, done, error }

class _DlState {
  final _Status status;
  final int received;
  final int total; // -1 이면 미확인
  final double speedMBps;
  final String errorMsg;

  const _DlState({
    this.status = _Status.idle,
    this.received = 0,
    this.total = -1,
    this.speedMBps = 0,
    this.errorMsg = '',
  });

  double get progress => (total > 0) ? (received / total).clamp(0.0, 1.0) : -1;

  String get receivedStr => _fmtBytes(received);
  String get totalStr => total > 0 ? _fmtBytes(total) : '?';
  String get speedStr =>
      speedMBps > 0 ? '${speedMBps.toStringAsFixed(1)} MB/s' : '';

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ── 모델 다운로드 카드 ────────────────────────────────────────────────────────

class _ModelDownloadCard extends StatelessWidget {
  final String label;
  final String filename;
  final String size;
  final String? tooltip;
  final bool isOk;
  final _DlState dlState;
  final TextEditingController urlCtrl;
  final bool showUrl;
  final VoidCallback onToggleUrl;
  final VoidCallback onInstall;
  final VoidCallback onCancel;
  final bool installDisabled;

  const _ModelDownloadCard({
    required this.label,
    required this.filename,
    required this.size,
    this.tooltip,
    required this.isOk,
    required this.dlState,
    required this.urlCtrl,
    required this.showUrl,
    required this.onToggleUrl,
    required this.onInstall,
    required this.onCancel,
    this.installDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDownloading = dlState.status == _Status.downloading;
    final hasError = dlState.status == _Status.error;
    const allowUrlEditing = !AppBuildConfig.appStoreComplianceMode;

    Color borderColor = scheme.outlineVariant.withValues(alpha: 0.8);
    Color bgColor = scheme.surfaceContainerLowest;
    if (isOk) {
      borderColor = Colors.green.shade300.withValues(alpha: 0.75);
      bgColor = Colors.green.withValues(alpha: 0.05);
    } else if (hasError) {
      borderColor = Colors.red.shade300.withValues(alpha: 0.75);
      bgColor = Colors.red.withValues(alpha: 0.05);
    } else if (isDownloading) {
      borderColor = scheme.primary.withValues(alpha: 0.4);
      bgColor = scheme.primary.withValues(alpha: 0.06);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _statusIcon(isDownloading),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _maybeTooltip(
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isOk ? Colors.green.shade800 : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          size,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        if (tooltip != null) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: tooltip!,
                            child: Icon(
                              Icons.info_outline,
                              size: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      filename,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isOk)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tr('설치됨', 'Installed'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tintFg(context, Colors.green),
                    ),
                  ),
                )
              else if (isDownloading)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop, size: 16),
                  label: Text(tr('취소', 'Cancel')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: tintBorder(context, Colors.red)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: installDisabled ? null : onInstall,
                  icon: const Icon(Icons.download, size: 16),
                  label: Text(
                    hasError ? tr('재시도', 'Retry') : tr('설치', 'Install'),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: dlState.progress < 0 ? null : dlState.progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${dlState.receivedStr} / ${dlState.totalStr}',
                  style: TextStyle(fontSize: 11, color: mutedText(context)),
                ),
                const Spacer(),
                if (dlState.speedStr.isNotEmpty)
                  Text(
                    dlState.speedStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
          if (hasError) ...[
            const SizedBox(height: 8),
            Text(
              dlState.errorMsg,
              style: TextStyle(
                fontSize: 11,
                color: tintFg(context, Colors.red),
                height: 1.4,
              ),
            ),
          ],
          if (!isDownloading && allowUrlEditing) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onToggleUrl,
              child: Row(
                children: [
                  Icon(
                    showUrl ? Icons.expand_less : Icons.link,
                    size: 13,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    showUrl
                        ? tr('URL 닫기', 'Close URL')
                        : tr('다운로드 URL 변경', 'Change download URL'),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (showUrl) ...[
              const SizedBox(height: 6),
              TextField(
                controller: urlCtrl,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'https://huggingface.co/...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _maybeTooltip(Widget child) =>
      tooltip == null ? child : Tooltip(message: tooltip!, child: child);

  Widget _statusIcon(bool downloading) {
    if (downloading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isOk) {
      return Icon(Icons.check_circle, size: 20, color: Colors.green.shade600);
    }
    if (dlState.status == _Status.error) {
      return Icon(Icons.error_outline, size: 20, color: Colors.red.shade600);
    }
    return Icon(
      Icons.radio_button_unchecked,
      size: 20,
      color: Colors.grey.shade400,
    );
  }
}
