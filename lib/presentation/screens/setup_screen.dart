import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_build_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/crash_log_service.dart';
import '../../core/services/model_download_service.dart';
import '../../core/services/user_error_message.dart';

/// 모델 파일 설치 안내 + 자동 다운로드 화면
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
  String _modelsDir = '';

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
    _check();
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
  Future<void> _check() async {
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
    if (mounted) setState(() => _checking = false);
  }

  Future<Directory> _modelsDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/models');
  }

  // ── 다운로드 ─────────────────────────────────────────────────────
  Future<void> _startDownload({required _Target target}) async {
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
        await _check();
      }
    } on ModelDownloadException catch (e) {
      if (!mounted) return;
      if (e.isCancelled) {
        _setDl(target, const _DlState());
        return;
      }
      if (e.needsAuth) {
        _setDl(target, _DlState(status: _Status.error, errorMsg: e.message));
        if (!AppBuildConfig.appStoreComplianceMode) {
          setState(() => _showTokenField = true);
        }
        _showSnack(e.message, isError: true);
        return;
      }
      _setDl(target, _DlState(status: _Status.error, errorMsg: e.message));
    } catch (e, st) {
      if (!mounted) return;
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
            fallbackTitle: '모델을 설치하지 못했습니다',
            fallbackMessage: '다운로드 또는 파일 저장 중 문제가 발생했습니다.',
            nextStep: '네트워크, 저장 공간, 모델 폴더 권한을 확인한 뒤 다시 시도해주세요.',
          ),
        ),
      );
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

  // ── 확인 완료 ────────────────────────────────────────────────────
  Future<void> _confirmCheck() async {
    await _check();
    // STT/LLM 각각 최소 하나 이상 설치 필요
    final anyStt = _sttFastOk || _sttAccurateOk;
    final anyLlm = _llmGemmaOk || _llmQwenOk;
    if (anyStt && anyLlm) {
      // 설치된 LLM 중 하나를 기본으로 설정 (아직 미설정 시)
      final current = AppSettings.instance.selectedLlmModel;
      final installed = {
        if (_llmGemmaOk) 'gemma4_e2b',
        if (_llmQwenOk) 'qwen25_7b',
      };
      if (!installed.contains(current)) {
        await AppSettings.instance.setSelectedLlmModel(installed.first);
      }
      widget.onComplete();
    } else {
      _showSnack(
        '${[if (!anyStt) '음성 인식 모델 없음 (빠른 또는 정확도 높음 중 하나 이상 필요)', if (!anyLlm) '요약 모델 없음 (최소 하나 이상 필요)'].join(', ')} — 설치 후 다시 시도하세요.',
        isError: true,
      );
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
    _showSnack('경로가 클립보드에 복사되었습니다.');
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anyStt = _sttFastOk || _sttAccurateOk;
    final anyLlm = _llmGemmaOk || _llmQwenOk;
    final allOk = anyStt && anyLlm;
    final anyDownloading =
        _sttFastDl.status == _Status.downloading ||
        _sttAccurateDl.status == _Status.downloading ||
        _llmGemmaDl.status == _Status.downloading ||
        _llmQwenDl.status == _Status.downloading ||
        _diarSegDl.status == _Status.downloading ||
        _diarEmbDl.status == _Status.downloading;

    return MacosWindow(
      disableWallpaperTinting: true,
      child: MacosScaffold(
        children: [
          ContentArea(
            builder: (context, scrollController) => Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 타이틀 ────────────────────────────────────────
                        Row(
                          children: [
                            Icon(
                              Icons.settings_outlined,
                              size: 32,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '초기 설정',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '음성 인식과 요약 모델을 설치하세요. 자동 다운로드 또는 직접 복사할 수 있습니다.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── STT 안내 문구 ─────────────────────────────────
                        Text(
                          '음성 인식 모델은 "빠른"과 "정확" 두 종류가 있습니다. 둘 중 '
                          '하나만 설치해도 앱 시작이 가능하며, 둘 다 설치 시 회의별로 '
                          '전환해서 사용할 수 있습니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ── STT 빠른 모델 카드 ────────────────────────────
                        _ModelDownloadCard(
                          label: '빠른 음성 인식 모델',
                          filename: AppConstants.sttModelFileFast,
                          size: '~900 MB',
                          isOk: _sttFastOk,
                          dlState: _sttFastDl,
                          urlCtrl: _sttFastUrlCtrl,
                          showUrl: _showSttFastUrl,
                          onToggleUrl: () => setState(
                            () => _showSttFastUrl = !_showSttFastUrl,
                          ),
                          onInstall: () =>
                              _startDownload(target: _Target.sttFast),
                          onCancel: () =>
                              _cancelDownload(target: _Target.sttFast),
                        ),
                        const SizedBox(height: 12),
                        _ModelDownloadCard(
                          label: '빠른 음성 인식 가속팩',
                          filename: AppConstants.sttCoreMlEncoderFileFast,
                          size: '~1.2 GB',
                          tooltip:
                              'Apple Silicon에서 긴 녹음 전사를 더 빠르게 처리합니다. 없어도 앱은 기존 방식으로 동작합니다.',
                          isOk: _sttFastCoreMlOk,
                          dlState: _sttFastCoreMlDl,
                          urlCtrl: _sttFastCoreMlUrlCtrl,
                          showUrl: _showSttFastCoreMlUrl,
                          onToggleUrl: () => setState(
                            () =>
                                _showSttFastCoreMlUrl = !_showSttFastCoreMlUrl,
                          ),
                          onInstall: () =>
                              _startDownload(target: _Target.sttFastCoreMl),
                          onCancel: () =>
                              _cancelDownload(target: _Target.sttFastCoreMl),
                        ),
                        const SizedBox(height: 12),

                        // ── STT 정확 모델 카드 ────────────────────────────
                        _ModelDownloadCard(
                          label: '정확도 높은 음성 인식 모델',
                          filename: AppConstants.sttModelFileAccurate,
                          size: '~1.1 GB',
                          isOk: _sttAccurateOk,
                          dlState: _sttAccurateDl,
                          urlCtrl: _sttAccurateUrlCtrl,
                          showUrl: _showSttAccurateUrl,
                          onToggleUrl: () => setState(
                            () => _showSttAccurateUrl = !_showSttAccurateUrl,
                          ),
                          onInstall: () =>
                              _startDownload(target: _Target.sttAccurate),
                          onCancel: () =>
                              _cancelDownload(target: _Target.sttAccurate),
                        ),
                        const SizedBox(height: 12),

                        // ── LLM 안내 문구 ─────────────────────────────────
                        const SizedBox(height: 20),
                        Text(
                          '요약 모델은 최소 하나만 설치하면 됩니다. 회의록 요약 시 '
                          '어떤 모델을 쓸지 선택할 수 있습니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ── LLM Gemma 4 E2B (빠른/기본) ──────────────────
                        _ModelDownloadCard(
                          label: '기본 요약 모델',
                          filename: AppConstants.llmModelFileGemma4E2B,
                          size: '~3 GB',
                          tooltip:
                              '크기: 약 3GB\n'
                              '속도: 매우 빠름\n'
                              '짧은 회의·메모 요약에 적합',
                          isOk: _llmGemmaOk,
                          dlState: _llmGemmaDl,
                          urlCtrl: _llmGemmaUrlCtrl,
                          showUrl: _showLlmGemmaUrl,
                          onToggleUrl: () => setState(
                            () => _showLlmGemmaUrl = !_showLlmGemmaUrl,
                          ),
                          onInstall: () =>
                              _startDownload(target: _Target.llmGemma),
                          onCancel: () =>
                              _cancelDownload(target: _Target.llmGemma),
                        ),
                        const SizedBox(height: 12),

                        // ── LLM Qwen 2.5 7B ───────────────────────────────
                        _ModelDownloadCard(
                          label: '고품질 요약 모델',
                          filename: AppConstants.llmModelFileQwen25_7B,
                          size: '~4.7 GB',
                          tooltip:
                              '크기: 약 4.7GB\n'
                              '속도: 보통\n'
                              '액션아이템/결정사항 구조화에 적합',
                          isOk: _llmQwenOk,
                          dlState: _llmQwenDl,
                          urlCtrl: _llmQwenUrlCtrl,
                          showUrl: _showLlmQwenUrl,
                          onToggleUrl: () => setState(
                            () => _showLlmQwenUrl = !_showLlmQwenUrl,
                          ),
                          onInstall: () =>
                              _startDownload(target: _Target.llmQwen),
                          onCancel: () =>
                              _cancelDownload(target: _Target.llmQwen),
                        ),
                        const SizedBox(height: 12),

                        const SizedBox(height: 8),

                        // ── 발화자 라벨 (선택) ────────────────────────────
                        Text(
                          '발화자 라벨 모델 (선택). 설치 후 설정에서 활성화하면 전사에 '
                          'A/B/C... 라벨이 자동 부여됩니다. 사람 이름을 자동 식별하지는 않습니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ModelDownloadCard(
                          label: '발화자 라벨 · 세그멘테이션',
                          filename: AppConstants.diarSegModelFile,
                          size: '~6 MB',
                          tooltip:
                              'pyannote-segmentation-3.0 (ONNX)\n'
                              '음성 활동/발화 경계 검출',
                          isOk: _diarSegOk,
                          dlState: _diarSegDl,
                          urlCtrl: _diarSegUrlCtrl,
                          showUrl: _showDiarSegUrl,
                          onToggleUrl: () => setState(
                            () => _showDiarSegUrl = !_showDiarSegUrl,
                          ),
                          onInstall: () =>
                              _startDownload(target: _Target.diarSeg),
                          onCancel: () =>
                              _cancelDownload(target: _Target.diarSeg),
                        ),
                        const SizedBox(height: 12),
                        _ModelDownloadCard(
                          label: '발화자 라벨 · 스피커 임베딩',
                          filename: AppConstants.diarEmbModelFile,
                          size: '~26 MB',
                          tooltip:
                              '3D-Speaker eres2net base (ONNX)\n'
                              '화자별 벡터 임베딩 추출 → 클러스터링',
                          isOk: _diarEmbOk,
                          dlState: _diarEmbDl,
                          urlCtrl: _diarEmbUrlCtrl,
                          showUrl: _showDiarEmbUrl,
                          onToggleUrl: () => setState(
                            () => _showDiarEmbUrl = !_showDiarEmbUrl,
                          ),
                          onInstall: () =>
                              _startDownload(target: _Target.diarEmb),
                          onCancel: () =>
                              _cancelDownload(target: _Target.diarEmb),
                        ),
                        const SizedBox(height: 20),

                        if (!AppBuildConfig.appStoreComplianceMode) ...[
                          // ── HuggingFace 토큰 ──────────────────────────────
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            child: _showTokenField
                                ? _buildTokenField(scheme)
                                : const SizedBox.shrink(),
                          ),
                          if (!_showTokenField)
                            TextButton.icon(
                              onPressed: () => setState(
                                () => _showTokenField = !_showTokenField,
                              ),
                              icon: const Icon(Icons.key, size: 16),
                              label: const Text('HuggingFace 토큰 입력'),
                            ),
                          const SizedBox(height: 16),
                        ],

                        // ── 설치 경로 ─────────────────────────────────────
                        Text(
                          '설치 경로',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
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
                                      ? '경로 확인 중...'
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
                                tooltip: '경로 복사',
                                onPressed: _modelsDir.isEmpty
                                    ? null
                                    : _copyPath,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── 액션 버튼 ─────────────────────────────────────
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _modelsDir.isEmpty
                                  ? null
                                  : _openFolder,
                              icon: const Icon(Icons.folder_open, size: 18),
                              label: const Text('폴더 열기'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _checking || anyDownloading
                                  ? null
                                  : _check,
                              icon: _checking
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh, size: 18),
                              label: const Text('다시 확인'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _checking || anyDownloading
                                  ? null
                                  : _confirmCheck,
                              icon: allOk
                                  ? const Icon(
                                      Icons.check_circle_outline,
                                      size: 18,
                                    )
                                  : const Icon(Icons.arrow_forward, size: 18),
                              label: const Text('확인 완료 → 앱 시작'),
                              style: FilledButton.styleFrom(
                                backgroundColor: allOk
                                    ? Colors.green.shade600
                                    : null,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildTokenField(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key, size: 16, color: Colors.amber.shade800),
              const SizedBox(width: 6),
              Text(
                'HuggingFace 토큰',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
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
            '일부 모델 제공 사이트가 권한 확인을 요구할 때만 사용합니다.\n'
            'huggingface.co → Settings → Access Tokens에서 발급할 수 있습니다.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.amber.shade900,
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
                tooltip: 'HuggingFace 토큰 발급 페이지',
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
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDownloading = dlState.status == _Status.downloading;
    final hasError = dlState.status == _Status.error;
    const allowUrlEditing = !AppBuildConfig.appStoreComplianceMode;

    Color borderColor = scheme.outlineVariant;
    Color bgColor = scheme.surfaceContainerLow;
    if (isOk) {
      borderColor = Colors.green.shade300;
      bgColor = Colors.green.shade50;
    } else if (hasError) {
      borderColor = Colors.red.shade300;
      bgColor = Colors.red.shade50;
    } else if (isDownloading) {
      borderColor = scheme.primary.withValues(alpha: 0.4);
      bgColor = scheme.primaryContainer.withValues(alpha: 0.15);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단: 상태 아이콘 + 이름 + 설치 버튼 ──────────────
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
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 버튼
              if (isOk)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '설치됨',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                )
              else if (isDownloading)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('취소'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: onInstall,
                  icon: const Icon(Icons.download, size: 16),
                  label: Text(hasError ? '재시도' : '설치'),
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

          // ── 다운로드 진행바 ────────────────────────────────────
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
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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

          // ── 오류 메시지 ────────────────────────────────────────
          if (hasError) ...[
            const SizedBox(height: 8),
            Text(
              dlState.errorMsg,
              style: TextStyle(
                fontSize: 11,
                color: Colors.red.shade700,
                height: 1.4,
              ),
            ),
          ],

          // ── URL 편집 토글 + 입력 필드 ─────────────────────────
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
                    showUrl ? 'URL 닫기' : '다운로드 URL 변경',
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
