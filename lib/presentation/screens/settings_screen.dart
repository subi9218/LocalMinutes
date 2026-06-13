import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_build_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/legal_notices.dart';
import '../../core/l10n/app_tr.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/auto_delete_service.dart';
import '../../core/services/crash_log_service.dart';
import '../../core/services/diagnostic_export_service.dart';
import '../../core/services/isar_service.dart';
import '../../core/services/model_download_service.dart';
import '../../core/services/security_scoped_bookmark_service.dart';
import '../../core/services/summary_templates.dart';
import '../../core/services/user_error_message.dart';
import '../../core/ffi/on_device_model_manager.dart';
import '../../data/datasources/llm_service.dart';
import '../../data/datasources/microphone_service.dart';
import '../../data/datasources/system_audio_service.dart';
import '../providers/settings_providers.dart';

/// 설정 다이얼로그 열기 헬퍼
void showSettingsDialog(BuildContext context, WidgetRef ref) {
  showMacosSheet(
    context: context,
    builder: (_) => MacosSheet(child: _SettingsDialog(ref: ref)),
  );
}

// ── 내부 다이얼로그 ──────────────────────────────────────────────────────
class _SettingsDialog extends StatefulWidget {
  final WidgetRef ref;
  const _SettingsDialog({required this.ref});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final _settings = AppSettings.instance;

  // ── 저장 공간 ────────────────────────────────────────────────────
  double? _modelsMb;
  double? _recordingsMb;
  bool _loadingStorage = true;

  // ── 모델 다운로드 상태 ───────────────────────────────────────────
  // 음성 인식은 빠른/정확 모델을 각각 다운로드
  // 요약은 기본/고품질 모델을 각각 다운로드
  final _sttFastDlService = ModelDownloadService();
  final _sttFastCoreMlDlService = ModelDownloadService();
  final _sttAccurateDlService = ModelDownloadService();
  final _llmGemmaDlService = ModelDownloadService();
  final _llmQwenDlService = ModelDownloadService();
  final _diarSegDlService = ModelDownloadService();
  final _diarEmbDlService = ModelDownloadService();
  _DlState _sttFastDl = const _DlState();
  _DlState _sttFastCoreMlDl = const _DlState();
  _DlState _sttAccurateDl = const _DlState();
  _DlState _llmGemmaDl = const _DlState();
  _DlState _llmQwenDl = const _DlState();
  _DlState _diarSegDl = const _DlState();
  _DlState _diarEmbDl = const _DlState();
  bool _sttFastExists = false;
  bool _sttFastCoreMlExists = false;
  bool _sttAccurateExists = false;
  bool _llmGemmaExists = false;
  bool _llmQwenExists = false;
  bool _diarSegExists = false;
  bool _diarEmbExists = false;

  // ── 자동 삭제 결과 ───────────────────────────────────────────────
  String? _deleteResult;
  bool _exportingDiagnostics = false;
  int? _crashLogBytes;
  bool _loadingCrashLogInfo = true;

  bool _systemAudioSupported = false;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
    _checkModels();
    _loadCrashLogInfo();
    SystemAudioService.instance.isSupported().then((v) {
      if (mounted) setState(() => _systemAudioSupported = v);
    });
  }

  @override
  void dispose() {
    _sttFastDlService.cancel();
    _sttFastCoreMlDlService.cancel();
    _sttAccurateDlService.cancel();
    _llmGemmaDlService.cancel();
    _llmQwenDlService.cancel();
    _diarSegDlService.cancel();
    _diarEmbDlService.cancel();
    super.dispose();
  }

  // ── 저장 공간 계산 ────────────────────────────────────────────────
  Future<void> _loadStorageInfo() async {
    setState(() => _loadingStorage = true);
    try {
      final appSupport = await getApplicationSupportDirectory();
      _modelsMb = await _dirSizeMb('${appSupport.path}/models');
      _recordingsMb = await _dirSizeMb('${appSupport.path}/recordings');

      // 커스텀 저장 경로가 있으면 앱이 만든 산출물만 계산한다(E4).
      // (사용자가 고른 폴더 전체가 아니라 meeting_*.wav + 'Local Minutes Data'만)
      final custom = _settings.recordingsSavePath;
      if (custom.isNotEmpty) {
        final appDataMb = await _dirSizeMb('$custom/Local Minutes Data');
        final wavMb = await _wavFilesSizeMb(custom);
        _recordingsMb = (_recordingsMb ?? 0) + appDataMb + wavMb;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingStorage = false);
  }

  Future<double> _dirSizeMb(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    double total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length().catchError((_) => 0);
      }
    }
    return total / (1024 * 1024);
  }

  /// 사용자 선택 폴더 최상위의 앱 녹음 파일(meeting_*.wav)만 합산한다(E4).
  /// 사용자의 무관한 파일까지 저장 용량으로 계산하지 않기 위함.
  Future<double> _wavFilesSizeMb(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    double total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (name.startsWith('meeting_') && name.endsWith('.wav')) {
        total += await entity.length().catchError((_) => 0);
      }
    }
    return total / (1024 * 1024);
  }

  Future<void> _loadCrashLogInfo() async {
    setState(() => _loadingCrashLogInfo = true);
    try {
      final bytes = await CrashLogService.instance.sizeBytes();
      if (mounted) setState(() => _crashLogBytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _crashLogBytes = null);
    } finally {
      if (mounted) setState(() => _loadingCrashLogInfo = false);
    }
  }

  // ── 모델 파일 확인 ────────────────────────────────────────────────
  Future<void> _checkModels() async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = '${appSupport.path}/models';
    _sttFastExists = await File(
      '$dir/${AppConstants.sttModelFileFast}',
    ).exists();
    _sttFastCoreMlExists = await Directory(
      '$dir/${AppConstants.sttCoreMlEncoderFileFast}',
    ).exists();
    _sttAccurateExists = await File(
      '$dir/${AppConstants.sttModelFileAccurate}',
    ).exists();
    _llmGemmaExists = await File(
      '$dir/${AppConstants.llmModelFileGemma4E2B}',
    ).exists();
    _llmQwenExists = await File(
      '$dir/${AppConstants.llmModelFileQwen25_7B}',
    ).exists();
    _diarSegExists = await File(
      '$dir/${AppConstants.diarSegModelFile}',
    ).exists();
    _diarEmbExists = await File(
      '$dir/${AppConstants.diarEmbModelFile}',
    ).exists();
    if (mounted) setState(() {});
  }

  bool get _anyModelDownloading =>
      _sttFastDl.status == _DlStatus.downloading ||
      _sttFastCoreMlDl.status == _DlStatus.downloading ||
      _sttAccurateDl.status == _DlStatus.downloading ||
      _llmGemmaDl.status == _DlStatus.downloading ||
      _llmQwenDl.status == _DlStatus.downloading ||
      _diarSegDl.status == _DlStatus.downloading ||
      _diarEmbDl.status == _DlStatus.downloading;

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── 모델 재다운로드 ───────────────────────────────────────────────
  Future<void> _downloadModel({required _DlTarget target}) async {
    if (_anyModelDownloading) {
      _showSnack(tr('이미 다운로드 중인 모델이 있습니다. 완료 후 다음 모델을 다운로드하세요.',
          'A model is already downloading. Please download the next model after it finishes.'));
      return;
    }

    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory('${appSupport.path}/models');
    await dir.create(recursive: true);

    final String filename;
    final String url;
    final ModelDownloadService service;
    var extractZip = false;
    String? markerPath;
    switch (target) {
      case _DlTarget.sttFast:
        filename = AppConstants.sttModelFileFast;
        url = AppConstants.sttDownloadUrlFast;
        service = _sttFastDlService;
      case _DlTarget.sttFastCoreMl:
        filename = AppConstants.sttCoreMlEncoderZipFast;
        url = AppConstants.sttCoreMlEncoderDownloadUrlFast;
        service = _sttFastCoreMlDlService;
        extractZip = true;
        markerPath = '${dir.path}/${AppConstants.sttCoreMlEncoderFileFast}';
      case _DlTarget.sttAccurate:
        filename = AppConstants.sttModelFileAccurate;
        url = AppConstants.sttDownloadUrlAccurate;
        service = _sttAccurateDlService;
      case _DlTarget.llmGemma:
        filename = AppConstants.llmModelFileGemma4E2B;
        url = AppConstants.llmDownloadUrlGemma4E2B;
        service = _llmGemmaDlService;
      case _DlTarget.llmQwen:
        filename = AppConstants.llmModelFileQwen25_7B;
        url = AppConstants.llmDownloadUrlQwen25_7B;
        service = _llmQwenDlService;
      case _DlTarget.diarSeg:
        filename = AppConstants.diarSegModelFile;
        url = AppConstants.diarSegDownloadUrl;
        service = _diarSegDlService;
      case _DlTarget.diarEmb:
        filename = AppConstants.diarEmbModelFile;
        url = AppConstants.diarEmbDownloadUrl;
        service = _diarEmbDlService;
    }
    final destPath = '${dir.path}/$filename';

    _setDl(target, const _DlState(status: _DlStatus.downloading));

    try {
      void onProgress(int recv, int total, double speed) {
        if (!mounted) return;
        final pct = total > 0 ? (recv / total * 100).toStringAsFixed(1) : '?';
        final mb = (recv / (1024 * 1024)).toStringAsFixed(0);
        _setDl(
          target,
          _DlState(
            status: _DlStatus.downloading,
            progress: total > 0 ? recv / total : null,
            label: '${mb}MB · $pct% · ${speed.toStringAsFixed(1)}MB/s',
          ),
        );
      }

      if (extractZip) {
        await service.downloadAndExtractZip(
          url: url,
          destZipPath: destPath,
          extractDir: dir.path,
          markerPath: markerPath!,
          expectedBytes: AppConstants.expectedModelBytes(filename),
          onProgress: onProgress,
        );
      } else {
        await service.download(
          url: url,
          destPath: destPath,
          expectedBytes: AppConstants.expectedModelBytes(filename),
          onProgress: onProgress,
        );
      }
      if (mounted) {
        _setDl(target, const _DlState(status: _DlStatus.done));
        await _checkModels();
        await _loadStorageInfo();
      }
    } on ModelDownloadException catch (e) {
      if (!e.isCancelled && mounted) {
        _setDl(target, _DlState(status: _DlStatus.error, label: e.message));
      } else if (mounted) {
        _setDl(target, const _DlState());
      }
    } catch (e, st) {
      CrashLogService.instance.recordCaught(
        e,
        st,
        context: 'settingsModelDownload',
      );
      if (mounted) {
        _setDl(
          target,
          _DlState(
            status: _DlStatus.error,
            label: friendlyErrorText(
              e,
              fallbackTitle: tr('모델을 설치하지 못했습니다', 'Could not install the model'),
              fallbackMessage: tr('다운로드 또는 파일 저장 중 문제가 발생했습니다.',
                  'A problem occurred while downloading or saving the file.'),
              nextStep: tr('네트워크, 저장 공간, 모델 폴더 권한을 확인한 뒤 다시 시도해주세요.',
                  'Check your network, storage space, and model folder permissions, then try again.'),
            ),
          ),
        );
      }
    }
  }

  void _setDl(_DlTarget target, _DlState state) {
    if (!mounted) return;
    setState(() {
      switch (target) {
        case _DlTarget.sttFast:
          _sttFastDl = state;
        case _DlTarget.sttFastCoreMl:
          _sttFastCoreMlDl = state;
        case _DlTarget.sttAccurate:
          _sttAccurateDl = state;
        case _DlTarget.llmGemma:
          _llmGemmaDl = state;
        case _DlTarget.llmQwen:
          _llmQwenDl = state;
        case _DlTarget.diarSeg:
          _diarSegDl = state;
        case _DlTarget.diarEmb:
          _diarEmbDl = state;
      }
    });
  }

  /// 진행 중인 작업(녹음/요약/네이티브 모델 작업) 라벨. 없으면 null.
  String? _activeWorkLabel() {
    final mic = MicrophoneService.instance;
    if (mic.isRecording) return tr('녹음', 'recording');
    if (mic.isPaused) return tr('일시 정지된 녹음', 'a paused recording');
    final native = OnDeviceModelManager.instance.nativeTaskSnapshot.activeLabel;
    if (native != null) return native;
    if (LlmService.instance.isGenerationActive) {
      return tr('요약 생성', 'summary generation');
    }
    return null;
  }

  // ── 폴더 선택 ─────────────────────────────────────────────────────
  Future<void> _pickRecordingsFolder() async {
    // I8: 녹음/요약 등 진행 중 작업이 있으면 폴더 변경을 막는다(라이브 파이프라인이
    // 옛 폴더를 가리킨 채 DB가 새 폴더로 이전되는 것을 방지).
    final busy = _activeWorkLabel();
    if (busy != null) {
      _showSnack(
        tr(
          '$busy 작업 중에는 저장 폴더를 변경할 수 없습니다. 작업이 끝난 뒤 다시 시도하세요.',
          'Cannot change the storage folder while $busy is in progress. Try again after it finishes.',
        ),
        isError: true,
      );
      return;
    }

    final path = await getDirectoryPath(confirmButtonText: tr('선택', 'Select'));
    if (path == null) return;

    // E1/I3: 실패 시 이전 경로/북마크로 롤백하고 사용자에게 알린다.
    final oldPath = _settings.recordingsSavePath;
    final oldBookmark = _settings.recordingsSaveBookmark;
    try {
      await SecurityScopedBookmarkService.saveRecordingsFolderSelection(path);
      await IsarService.instance.relocateToUserSelectedDirectory();
      if (mounted) setState(() {});
      await _loadStorageInfo();
    } catch (e) {
      try {
        await _settings.setRecordingsSavePath(oldPath);
        await _settings.setRecordingsSaveBookmark(oldBookmark);
      } catch (_) {}
      if (!mounted) return;
      _showSnack(
        tr(
          '저장 폴더를 변경하지 못했습니다. 이전 폴더를 유지합니다.',
          'Could not change the storage folder. Keeping the previous folder.',
        ),
        isError: true,
      );
    }
  }

  // ── 오래된 녹음 WAV 파일만 삭제 (회의록·전사·요약은 유지) ──────────
  Future<void> _runAutoDelete(int days) async {
    final r = await AutoDeleteService.run(days);
    if (!mounted) return;
    setState(() {
      if (r.isEmpty) {
        _deleteResult = tr('삭제할 오래된 녹음 파일이 없습니다.',
            'There are no old recording files to delete.');
      } else if (r.deleted > 0 && r.missing == 0) {
        _deleteResult = tr('녹음 파일 ${r.deleted}개가 삭제되었습니다. (회의록·요약은 유지됩니다)',
            '${r.deleted} recording file(s) deleted. (Minutes and summaries are kept)');
      } else if (r.deleted == 0 && r.missing > 0) {
        _deleteResult = tr('파일은 이미 없었지만 DB 참조 ${r.missing}개를 정리했습니다.',
            'The files were already gone, but cleaned up ${r.missing} database reference(s).');
      } else {
        _deleteResult = tr('녹음 파일 ${r.deleted}개 삭제 + DB 참조 ${r.missing}개 정리.',
            'Deleted ${r.deleted} recording file(s) + cleaned up ${r.missing} database reference(s).');
      }
    });
    await _loadStorageInfo();
  }

  // ── BUILD ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 580,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 헤더 ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  tr('설정', 'Settings'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // ── 스크롤 가능한 설정 목록 ────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRecordingSection(),
                  const SizedBox(height: 20),
                  _buildRecordQualitySection(),
                  const SizedBox(height: 20),
                  _buildSummaryTemplateSection(),
                  const SizedBox(height: 20),
                  _buildDataSection(),
                  const SizedBox(height: 20),
                  _buildModelSection(),
                  const SizedBox(height: 20),
                  _buildDiarizationSection(),
                  const SizedBox(height: 20),
                  _buildDisplaySection(),
                  const SizedBox(height: 20),
                  _buildLegalSection(),
                  const SizedBox(height: 20),
                  _buildDebugSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. 녹음 설정 ──────────────────────────────────────────────────
  Widget _buildRecordingSection() {
    final settings = AppSettings.instance;
    final customPath = settings.recordingsSavePath;

    return _SectionCard(
      title: tr('녹음', 'Recording'),
      icon: Icons.mic,
      children: [
        // 언어 설정
        _SettingRow(
          title: tr('음성 인식 언어', 'Speech recognition language'),
          subtitle: AppSettings.sttLanguageDescription(settings.sttLanguage),
          trailing: DropdownButton<String>(
            value: settings.sttLanguage,
            underline: const SizedBox(),
            isDense: true,
            items: [
              for (final code in AppSettings.supportedSttLanguages)
                DropdownMenuItem(
                  value: code,
                  child: Text(AppSettings.sttLanguageLabel(code)),
                ),
            ],
            onChanged: (v) async {
              if (v != null) {
                await settings.setSttLanguage(v);
                setState(() {});
              }
            },
          ),
        ),

        // 녹음 소스 (온라인 회의 시스템 오디오 캡처) — 지원 OS에서만 표시
        if (_systemAudioSupported) ...[
          const Divider(height: 20),
          _SettingRow(
            title: tr('녹음 소스', 'Recording source'),
            subtitle: tr(
              '온라인 회의(Zoom 등) 상대 목소리를 함께 녹음하려면 시스템 오디오를 켜세요. 통화 녹음은 상대방 동의가 필요할 수 있습니다.',
              'Turn on system audio to also record the other party in online meetings (e.g. Zoom). Recording calls may require consent.',
            ),
            trailing: DropdownButton<String>(
              value: settings.recordingSource,
              underline: const SizedBox(),
              isDense: true,
              items: [
                DropdownMenuItem(
                  value: 'mic',
                  child: Text(tr('마이크만', 'Mic only')),
                ),
                DropdownMenuItem(
                  value: 'both',
                  child: Text(tr('마이크 + 시스템', 'Mic + system')),
                ),
                DropdownMenuItem(
                  value: 'system',
                  child: Text(tr('시스템 오디오만', 'System audio only')),
                ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await settings.setRecordingSource(v);
                setState(() {});
              },
            ),
          ),
        ],

        const Divider(height: 20),

        // 음성 인식 속도/품질 모드
        _SettingRow(
          title: tr('음성 인식 방식', 'Speech recognition mode'),
          subtitle: AppSettings.sttProcessingModeDescription(
            settings.sttProcessingMode,
          ),
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
            ),
            segments: [
              for (final mode in AppSettings.supportedSttProcessingModes)
                ButtonSegment(
                  value: mode,
                  label: Text(AppSettings.sttProcessingModeLabel(mode)),
                ),
            ],
            selected: {settings.sttProcessingMode},
            onSelectionChanged: (sel) async {
              final next = sel.first;
              if (next == settings.sttProcessingMode) return;
              await settings.setSttProcessingMode(next);
              if (mounted) {
                await _checkModels();
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr('${AppSettings.sttProcessingModeLabel(next)} 방식으로 전환했습니다.',
                          'Switched to ${AppSettings.sttProcessingModeLabel(next)} mode.'),
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
        ),

        const Divider(height: 20),

        // 녹음 저장 위치
        _SettingRow(
          title: tr('녹음 파일 저장 위치', 'Recording file location'),
          subtitle: customPath.isNotEmpty
              ? customPath
              : tr('저장 폴더가 선택되지 않았습니다.', 'No save folder selected.'),
          subtitleIsPath: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _pickRecordingsFolder,
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(tr('변경', 'Change')),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 1-0.5. 녹음 품질 ──────────────────────────────────────────────
  Widget _buildRecordQualitySection() {
    final settings = AppSettings.instance;
    return _SectionCard(
      title: tr('녹음 품질', 'Recording quality'),
      icon: Icons.tune,
      children: [
        _SettingRow(
          title: tr('자동 음량 조절 (AGC)', 'Automatic gain control (AGC)'),
          subtitle: tr('조용한 화자를 보정합니다. 배경 소음이 큰 곳에서는 꺼두는 편이 좋습니다.',
              'Boosts quiet speakers. Better turned off in noisy environments.'),
          trailing: Switch.adaptive(
            value: settings.recordAutoGain,
            onChanged: (v) async {
              await settings.setRecordAutoGain(v);
              setState(() {});
            },
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: tr('에코 제거', 'Echo cancellation'),
          subtitle: tr('스피커폰 통화에 유리합니다. 대면 회의에서는 기본적으로 꺼둡니다.',
              'Helpful for speakerphone calls. Off by default for in-person meetings.'),
          trailing: Switch.adaptive(
            value: settings.recordEchoCancel,
            onChanged: (v) async {
              await settings.setRecordEchoCancel(v);
              setState(() {});
            },
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: tr('녹음 정규화 (피크 -1dB)', 'Recording normalization (peak -1dB)'),
          subtitle: tr('저장 음량을 자동 정리합니다. 음성 인식 품질 안정화에 도움이 됩니다.',
              'Automatically levels the saved volume. Helps stabilize speech recognition quality.'),
          trailing: Switch.adaptive(
            value: settings.recordNormalize,
            onChanged: (v) async {
              await settings.setRecordNormalize(v);
              setState(() {});
            },
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: tr('마이크 가이드 다시 보기', 'Show mic guide again'),
          subtitle: settings.micGuideShown
              ? tr('다음 녹음 시작 시 마이크 가이드를 다시 표시합니다.',
                  'The mic guide will be shown again the next time you start recording.')
              : tr('아직 표시되지 않았습니다. 첫 녹음 시작 시 자동으로 안내됩니다.',
                  'Not shown yet. It will appear automatically when you first start recording.'),
          trailing: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(tr('리셋', 'Reset')),
            onPressed: settings.micGuideShown
                ? () async {
                    await settings.setMicGuideShown(false);
                    setState(() {});
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(tr('가이드가 초기화되었습니다. 다음 녹음 시작 시 다시 표시됩니다.',
                              'The guide has been reset. It will appear again the next time you start recording.')),
                        ),
                      );
                    }
                  }
                : null,
          ),
        ),
        if (AppBuildConfig.enableCalendarIntegration) ...[
          const Divider(height: 20),
          // ── macOS 캘린더 자동 등록 (내부 빌드 전용) ────────────────
          _SettingRow(
            title: tr('녹음 종료 후 macOS 캘린더에 자동 등록',
                'Add to macOS Calendar automatically after recording'),
            subtitle: tr(
                '회의 제목과 시작/종료 시각으로 Calendar.app에 새 이벤트가 추가됩니다. '
                '첫 활성화 시 macOS가 자동화 권한을 요청합니다.',
                'A new event is added to Calendar.app with the meeting title and start/end times. '
                'macOS will request automation permission the first time you enable this.'),
            trailing: Switch.adaptive(
              value: settings.autoAddToCalendar,
              onChanged: (v) async {
                await settings.setAutoAddToCalendar(v);
                setState(() {});
              },
            ),
          ),
        ],
      ],
    );
  }

  // ── 1-1. 요약 템플릿 ──────────────────────────────────────────────
  Widget _buildSummaryTemplateSection() {
    final settings = AppSettings.instance;
    final currentId = settings.summaryTemplateId;
    final isCustom1 = currentId == SummaryTemplates.customId1;
    final isCustom2 = currentId == SummaryTemplates.customId2;
    final isCustom = isCustom1 || isCustom2;
    final String preview;
    if (isCustom1) {
      final v = settings.customSummaryInstruction1.trim();
      preview = v.isEmpty ? SummaryTemplates.defaultCustomInstruction : v;
    } else if (isCustom2) {
      final v = settings.customSummaryInstruction2.trim();
      preview = v.isEmpty ? SummaryTemplates.defaultCustomInstruction : v;
    } else {
      preview = SummaryTemplates.byId(currentId).instruction;
    }

    return _SectionCard(
      title: tr('회의 유형', 'Meeting type'),
      icon: Icons.auto_awesome,
      children: [
        _SettingRow(
          title: tr('요약 방식', 'Summary mode'),
          subtitle: AppSettings.summaryModeDescription(
            settings.summarySpeedMode,
          ),
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
            ),
            segments: [
              for (final mode in AppSettings.supportedSummaryModes)
                ButtonSegment(
                  value: mode,
                  label: Text(AppSettings.summaryModeLabel(mode)),
                ),
            ],
            selected: {settings.summarySpeedMode},
            onSelectionChanged: (sel) async {
              final next = sel.first;
              if (next == settings.summarySpeedMode) return;
              await settings.setSummarySpeedMode(next);
              if (mounted) setState(() {});
            },
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: tr('기본 회의 유형', 'Default meeting type'),
          subtitle: tr('회의 성격에 맞춰 요약에서 강조할 항목이 달라집니다.',
              'The items emphasized in the summary change to match the meeting type.'),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in SummaryTemplates.presets)
                  ChoiceChip(
                    label: Text(t.name, style: const TextStyle(fontSize: 12)),
                    selected: currentId == t.id,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) async {
                      await settings.setSummaryTemplateId(t.id);
                      setState(() {});
                    },
                  ),
                ChoiceChip(
                  label: Text(tr('커스텀1', 'Custom 1'),
                      style: const TextStyle(fontSize: 12)),
                  selected: isCustom1,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) async {
                    await settings.setSummaryTemplateId(
                      SummaryTemplates.customId1,
                    );
                    if (settings.customSummaryInstruction1.trim().isEmpty) {
                      await settings.setCustomSummaryInstruction1(
                        SummaryTemplates.defaultCustomInstruction,
                      );
                    }
                    setState(() {});
                  },
                ),
                ChoiceChip(
                  label: Text(tr('커스텀2', 'Custom 2'),
                      style: const TextStyle(fontSize: 12)),
                  selected: isCustom2,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) async {
                    await settings.setSummaryTemplateId(
                      SummaryTemplates.customId2,
                    );
                    if (settings.customSummaryInstruction2.trim().isEmpty) {
                      await settings.setCustomSummaryInstruction2(
                        SummaryTemplates.defaultCustomInstruction,
                      );
                    }
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (!isCustom) ...[
          // 한 줄 설명만 노출
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 14,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    SummaryTemplates.byId(currentId).description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 긴 instruction은 고급 설정으로 접기
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
              dense: true,
              visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
              title: Text(
                tr('고급 설정 — 세부 정리 방식', 'Advanced — detailed formatting'),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    preview,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                      '* 회의 유형별로 요약에서 더 중요하게 볼 기준입니다. '
                      '커스텀 모드에서 직접 조정할 수 있습니다.',
                      '* These are the criteria each meeting type emphasizes in the summary. '
                      'You can adjust them directly in custom mode.'),
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // 커스텀 모드: 안내 + 에디터 기본 펼침 (커스텀1/2 별도 슬롯)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.engineering_outlined,
                  size: 14,
                  color: Colors.deepOrange.shade400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isCustom1
                        ? tr('커스텀1 — 요약에서 강조할 기준을 직접 편집합니다. 비워두면 일반 회의 지침이 사용됩니다.',
                            'Custom 1 — Edit the criteria to emphasize in the summary. If left empty, the general meeting guidance is used.')
                        : tr('커스텀2 — 요약에서 강조할 기준을 직접 편집합니다. 비워두면 일반 회의 지침이 사용됩니다.',
                            'Custom 2 — Edit the criteria to emphasize in the summary. If left empty, the general meeting guidance is used.'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _CustomPromptEditor(
            // 슬롯이 바뀌면 키도 바뀌어 에디터가 새 initial 로 다시 마운트되도록.
            key: ValueKey('custom_editor_$currentId'),
            initial: preview,
            onSaved: (v) async {
              if (isCustom1) {
                await settings.setCustomSummaryInstruction1(v);
              } else if (isCustom2) {
                await settings.setCustomSummaryInstruction2(v);
              }
              setState(() {});
            },
          ),
        ],
      ],
    );
  }

  // ── 2. 데이터 관리 ─────────────────────────────────────────────────
  Widget _buildDataSection() {
    final modelsMb = _modelsMb;
    final recMb = _recordingsMb;
    final totalMb = (modelsMb ?? 0) + (recMb ?? 0);

    String fmtSize(double? mb) {
      if (mb == null) return '-';
      if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
      return '${mb.toStringAsFixed(0)} MB';
    }

    return _SectionCard(
      title: tr('데이터 관리', 'Data management'),
      icon: Icons.storage,
      children: [
        // 저장 공간
        _SettingRow(
          title: tr('저장 공간 사용량', 'Storage usage'),
          subtitle: '',
          trailing: _loadingStorage
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: tr('새로고침', 'Refresh'),
                  onPressed: _loadStorageInfo,
                  visualDensity: VisualDensity.compact,
                ),
          child: _loadingStorage
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tr('계산 중...', 'Calculating...'),
                      style: const TextStyle(fontSize: 12)),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      _StorageBadge(
                        label: tr('모델', 'Models'),
                        value: fmtSize(modelsMb),
                        color: Colors.indigo,
                      ),
                      const SizedBox(width: 8),
                      _StorageBadge(
                        label: tr('녹음', 'Recordings'),
                        value: fmtSize(recMb),
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 8),
                      _StorageBadge(
                        label: tr('합계', 'Total'),
                        value: fmtSize(totalMb),
                        color: Colors.deepPurple,
                      ),
                    ],
                  ),
                ),
        ),

        const Divider(height: 20),

        // 자동 삭제
        _SettingRow(
          title: tr('오래된 녹음 파일 자동 삭제', 'Auto-delete old recordings'),
          subtitle: tr('오래된 WAV만 정리합니다. 회의록·전사·요약은 유지됩니다.',
              'Only old WAV files are cleaned up. Minutes, transcripts, and summaries are kept.'),
          trailing: DropdownButton<int>(
            value: AppSettings.instance.autoDeleteDays,
            underline: const SizedBox(),
            isDense: true,
            items: [
              DropdownMenuItem(value: 0, child: Text(tr('끄기', 'Off'))),
              DropdownMenuItem(value: 30, child: Text(tr('30일', '30 days'))),
              DropdownMenuItem(value: 60, child: Text(tr('60일', '60 days'))),
              DropdownMenuItem(value: 90, child: Text(tr('90일', '90 days'))),
              DropdownMenuItem(value: 180, child: Text(tr('180일', '180 days'))),
            ],
            onChanged: (v) async {
              if (v != null) {
                await AppSettings.instance.setAutoDeleteDays(v);
                setState(() => _deleteResult = null);
              }
            },
          ),
        ),

        // 즉시 삭제 버튼
        if (AppSettings.instance.autoDeleteDays > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () =>
                    _runAutoDelete(AppSettings.instance.autoDeleteDays),
                icon: Icon(
                  Icons.delete_sweep,
                  size: 16,
                  color: Colors.red.shade600,
                ),
                label: Text(
                  tr('오래된 녹음 삭제', 'Delete old recordings'),
                  style: TextStyle(fontSize: 12, color: Colors.red.shade600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (_deleteResult != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                _deleteResult!,
                style: TextStyle(fontSize: 11, color: Colors.green.shade700),
              ),
            ),
          ],
        ],
      ],
    );
  }

  // ── 3. 모델 관리 ──────────────────────────────────────────────────
  Widget _buildModelSection() {
    final downloadDisabled = _anyModelDownloading;

    return _SectionCard(
      title: tr('음성/요약 모델', 'Speech & summary models'),
      icon: Icons.memory,
      children: [
        _ModelGroupHeader(
          title: tr('필수', 'Required'),
          subtitle: tr('음성 인식 1개와 요약 모델 1개가 있으면 녹음과 요약을 시작할 수 있습니다.',
              'With one speech recognition model and one summary model, you can start recording and summarizing.'),
        ),
        _ModelRow(
          name: tr('빠른 음성 인식', 'Fast speech recognition'),
          size: '~900 MB',
          subtitle: tr('짧은 회의 초안 확인에 적합', 'Good for quick drafts of short meetings'),
          exists: _sttFastExists,
          dlState: _sttFastDl,
          onDownload: () => _downloadModel(target: _DlTarget.sttFast),
          downloadDisabled: downloadDisabled,
          onCancel: () {
            _sttFastDlService.cancel();
            setState(() => _sttFastDl = const _DlState());
          },
        ),
        const SizedBox(height: 8),
        _ModelRow(
          name: tr('기본 요약', 'Standard summary'),
          size: '~3 GB',
          subtitle: tr('빠르고 메모리 부담이 적음', 'Fast and light on memory'),
          exists: _llmGemmaExists,
          dlState: _llmGemmaDl,
          onDownload: () => _downloadModel(target: _DlTarget.llmGemma),
          downloadDisabled: downloadDisabled,
          onCancel: () {
            _llmGemmaDlService.cancel();
            setState(() => _llmGemmaDl = const _DlState());
          },
        ),
        const SizedBox(height: 18),
        _ModelGroupHeader(
          title: tr('선택', 'Optional'),
          subtitle: tr('정확도, 처리 속도, 구조화 품질이 더 필요할 때 추가합니다.',
              'Add these when you need more accuracy, processing speed, or structured quality.'),
        ),
        _ModelRow(
          name: tr('정확도 높은 음성 인식', 'High-accuracy speech recognition'),
          size: '~1.1 GB',
          subtitle: tr('긴 회의와 최종 회의록 품질에 유리',
              'Better for long meetings and final minutes quality'),
          exists: _sttAccurateExists,
          dlState: _sttAccurateDl,
          onDownload: () => _downloadModel(target: _DlTarget.sttAccurate),
          downloadDisabled: downloadDisabled,
          onCancel: () {
            _sttAccurateDlService.cancel();
            setState(() => _sttAccurateDl = const _DlState());
          },
        ),
        const SizedBox(height: 8),
        _ModelRow(
          name: tr('빠른 음성 인식 가속팩', 'Fast speech recognition accelerator pack'),
          size: '~1.2 GB',
          subtitle: tr('Apple Silicon에서 긴 녹음 전사를 더 빠르게 처리',
              'Transcribes long recordings faster on Apple Silicon'),
          exists: _sttFastCoreMlExists,
          dlState: _sttFastCoreMlDl,
          onDownload: () => _downloadModel(target: _DlTarget.sttFastCoreMl),
          downloadDisabled: downloadDisabled,
          onCancel: () {
            _sttFastCoreMlDlService.cancel();
            setState(() => _sttFastCoreMlDl = const _DlState());
          },
        ),
        const SizedBox(height: 8),
        _ModelRow(
          name: tr('고품질 요약', 'High-quality summary'),
          size: '~4.7 GB',
          subtitle: tr('논의·결정·액션아이템 구조화에 유리',
              'Better at structuring discussions, decisions, and action items'),
          exists: _llmQwenExists,
          dlState: _llmQwenDl,
          onDownload: () => _downloadModel(target: _DlTarget.llmQwen),
          downloadDisabled: downloadDisabled,
          onCancel: () {
            _llmQwenDlService.cancel();
            setState(() => _llmQwenDl = const _DlState());
          },
        ),
        const SizedBox(height: 16),
        _buildDefaultLlmPicker(),
        const SizedBox(height: 12),
        _buildAdvancedModelInfo(),
      ],
    );
  }

  // ── 기본 요약 모델 선택 ───────────────────────────────────────────
  Widget _buildDefaultLlmPicker() {
    final current = AppSettings.instance.selectedLlmModel;
    final installed = <String, bool>{
      'gemma4_e2b': _llmGemmaExists,
      'qwen25_7b': _llmQwenExists,
    };

    String labelOf(String id) {
      switch (id) {
        case 'qwen25_7b':
          return tr('고품질', 'High quality');
        default:
          return tr('기본', 'Standard');
      }
    }

    String tipOf(String id) {
      switch (id) {
        case 'qwen25_7b':
          return tr('회의 내용을 항목별로 정리하는 데 유리합니다.',
              'Better at organizing meeting content into structured items.');
        default:
          return tr('가볍고 빠르게 요약합니다.', 'Summarizes quickly with a light footprint.');
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                tr('기본 요약 모델', 'Default summary model'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr('기본 요약 방식을 고릅니다. 요약할 때마다 바꿀 수도 있습니다.',
                'Choose your default summary model. You can also change it for each summary.'),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppSettings.availableLlmModelIds.map((id) {
              final ok = installed[id] == true;
              final selected = current == id;
              return Tooltip(
                message: tipOf(id),
                child: FilterChip(
                  label: Text(
                    ok
                        ? labelOf(id)
                        : tr('${labelOf(id)} (미설치)', '${labelOf(id)} (not installed)'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: selected,
                  onSelected: !ok
                      ? null
                      : (_) async {
                          await AppSettings.instance.setSelectedLlmModel(id);
                          if (mounted) setState(() {});
                        },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedModelInfo() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, left: 8, right: 8),
        dense: true,
        iconColor: muted,
        collapsedIconColor: muted,
        title: Text(tr('고급 정보', 'Advanced info'),
            style: TextStyle(fontSize: 11, color: muted)),
        subtitle: Text(
          tr('모델 파일명과 상세 정보를 확인합니다.', 'View model file names and details.'),
          style: TextStyle(
            fontSize: 10.5,
            color: muted.withValues(alpha: 0.75),
          ),
        ),
        children: [
          _AdvancedInfoLine(tr('빠른 음성 인식', 'Fast speech recognition'),
              AppConstants.sttModelFileFast),
          _AdvancedInfoLine(tr('정확도 높은 음성 인식', 'High-accuracy speech recognition'),
              AppConstants.sttModelFileAccurate),
          _AdvancedInfoLine(
              tr('기본 요약', 'Standard summary'), AppConstants.llmModelFileGemma4E2B),
          _AdvancedInfoLine(
              tr('고품질 요약', 'High-quality summary'), AppConstants.llmModelFileQwen25_7B),
        ],
      ),
    );
  }

  Widget _buildLegalSection() {
    return _SectionCard(
      title: tr('라이선스와 개인정보', 'Licenses & privacy'),
      icon: Icons.verified_user_outlined,
      children: [
        _SettingRow(
          title: tr('사용 모델 및 라이선스', 'Models in use & licenses'),
          subtitle: tr('음성 인식과 요약은 사용자가 설치한 로컬 모델로 이 기기에서 실행됩니다.',
              'Speech recognition and summarization run on this device using the local models you installed.'),
          trailing: OutlinedButton.icon(
            icon: const Icon(Icons.article_outlined, size: 16),
            label: Text(tr('보기', 'View')),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _showLicenseNotices,
          ),
        ),
      ],
    );
  }

  void _showLicenseNotices() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final muted = Theme.of(ctx).colorScheme.onSurfaceVariant;
        return AlertDialog(
          title: Text(tr('사용 모델 및 라이선스', 'Models in use & licenses')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('회의 음성과 요약 내용은 설치된 로컬 모델로 처리됩니다.',
                        'Meeting audio and summaries are processed using the installed local models.'),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 12),
                  for (final item in LegalNotices.items) ...[
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      '${item.role} · ${item.license}\n${item.source}\n${item.note}',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr('닫기', 'Close')),
            ),
          ],
        );
      },
    );
  }

  // ── 3-1. 발화자 라벨 ─────────────────────────────────────────────
  Widget _buildDiarizationSection() {
    final settings = AppSettings.instance;
    final modelsReady = _diarSegExists && _diarEmbExists;
    final downloadDisabled = _anyModelDownloading;

    return _SectionCard(
      title: tr('발화자 라벨', 'Speaker labels'),
      icon: Icons.record_voice_over,
      children: [
        _SettingRow(
          title: tr('발화자 라벨 사용', 'Use speaker labels'),
          subtitle: modelsReady
              ? tr(
                  '사람 이름을 자동으로 알아내지는 않고, 각 문장에 A/B/C 라벨을 붙입니다. '
                  '회의 길이에 따라 수십 초~수 분 추가됩니다.',
                  'It does not detect real names automatically; it tags each sentence with A/B/C labels. '
                  'Adds tens of seconds to a few minutes depending on meeting length.')
              : tr('아래 두 모델을 먼저 다운로드하세요.',
                  'Download the two models below first.'),
          trailing: Switch.adaptive(
            value: settings.diarizationEnabled,
            onChanged: modelsReady
                ? (v) async {
                    await settings.setDiarizationEnabled(v);
                    setState(() {});
                  }
                : null,
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: tr('말할 사람 수', 'Number of speakers'),
          subtitle: tr('명시하면 A/B/C 라벨이 과하게 늘어나는 문제를 줄일 수 있습니다.',
              'Specifying this can reduce excessive A/B/C labels.'),
          trailing: DropdownButton<int>(
            value: settings.numSpeakersHint,
            underline: const SizedBox(),
            isDense: true,
            items: [
              DropdownMenuItem(value: 0, child: Text(tr('자동', 'Auto'))),
              DropdownMenuItem(value: 2, child: Text(tr('2명', '2 people'))),
              DropdownMenuItem(value: 3, child: Text(tr('3명', '3 people'))),
              DropdownMenuItem(value: 4, child: Text(tr('4명', '4 people'))),
              DropdownMenuItem(value: 5, child: Text(tr('5명', '5 people'))),
              DropdownMenuItem(value: 6, child: Text(tr('6명', '6 people'))),
            ],
            onChanged: (v) async {
              if (v != null) {
                await settings.setNumSpeakersHint(v);
                setState(() {});
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        _ModelGroupHeader(
          title: tr('필요한 모델', 'Required models'),
          subtitle: tr('두 모델을 모두 설치하면 발화자 라벨을 켤 수 있습니다.',
              'Once both models are installed, you can enable speaker labels.'),
        ),
        _ModelRow(
          name: tr('발화 구간 찾기 모델', 'Speech segmentation model'),
          size: '~6 MB',
          subtitle: tr('누가 언제 말했는지 나누기 위한 보조 모델',
              'Helper model for splitting who spoke when'),
          exists: _diarSegExists,
          dlState: _diarSegDl,
          onDownload: () => _downloadModel(target: _DlTarget.diarSeg),
          downloadDisabled: downloadDisabled,
          onCancel: () {
            _diarSegDlService.cancel();
            setState(() => _diarSegDl = const _DlState());
          },
        ),
        const SizedBox(height: 12),
        _ModelRow(
          name: tr('목소리 구분 모델', 'Voice distinction model'),
          size: '~26 MB',
          subtitle: tr('비슷한 목소리 구간을 같은 발화자로 묶는 모델',
              'Groups similar voice segments under the same speaker'),
          exists: _diarEmbExists,
          dlState: _diarEmbDl,
          onDownload: () => _downloadModel(target: _DlTarget.diarEmb),
          downloadDisabled: downloadDisabled,
          onCancel: () {
            _diarEmbDlService.cancel();
            setState(() => _diarEmbDl = const _DlState());
          },
        ),
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 4, left: 8, right: 8),
            dense: true,
            iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
            collapsedIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
            title: Text(
              tr('고급 정보', 'Advanced info'),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            subtitle: Text(
              tr('발화자 라벨 모델 파일명을 확인합니다.', 'View speaker label model file names.'),
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
            children: [
              _AdvancedInfoLine(
                  tr('발화 구간 찾기', 'Speech segmentation'), AppConstants.diarSegModelFile),
              _AdvancedInfoLine(
                  tr('목소리 구분', 'Voice distinction'), AppConstants.diarEmbModelFile),
            ],
          ),
        ),
      ],
    );
  }

  // ── 4. 화면 설정 ──────────────────────────────────────────────────
  Widget _buildDisplaySection() {
    final current = AppSettings.instance.themeMode;
    // '' = 시스템 따름, 'ko', 'en'
    final lang = AppSettings.instance.languageCode.isEmpty
        ? 'system'
        : AppSettings.instance.languageCode;

    return _SectionCard(
      title: tr('화면', 'Display'),
      icon: Icons.palette_outlined,
      children: [
        _SettingRow(
          title: tr('언어', 'Language'),
          subtitle: tr('앱 표시 언어를 선택합니다.', 'Choose the app display language.'),
          trailing: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'system',
                icon: const Icon(Icons.brightness_auto, size: 16),
                label: Text(tr('시스템', 'System')),
              ),
              const ButtonSegment(value: 'ko', label: Text('한국어')),
              const ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {lang},
            onSelectionChanged: (sel) async {
              final v = sel.first;
              await AppSettings.instance.setLanguageCode(
                v == 'system' ? '' : v,
              );
              // Riverpod 상태 즉시 업데이트 → 앱 전체 다시 렌더
              widget.ref.read(languageProvider.notifier).state =
                  AppSettings.instance.effectiveLanguageCode;
              setState(() {});
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
            ),
          ),
        ),
        _SettingRow(
          title: tr('테마', 'Theme'),
          subtitle: tr('앱 전체 색상 테마를 선택합니다.', 'Choose the overall color theme.'),
          trailing: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'system',
                icon: const Icon(Icons.brightness_auto, size: 16),
                label: Text(tr('시스템', 'System')),
              ),
              ButtonSegment(
                value: 'light',
                icon: const Icon(Icons.light_mode, size: 16),
                label: Text(tr('라이트', 'Light')),
              ),
              ButtonSegment(
                value: 'dark',
                icon: const Icon(Icons.dark_mode, size: 16),
                label: Text(tr('다크', 'Dark')),
              ),
            ],
            selected: {current},
            onSelectionChanged: (sel) async {
              final mode = sel.first;
              await AppSettings.instance.setThemeMode(mode);
              // Riverpod 상태 즉시 업데이트
              ThemeMode themeMode;
              switch (mode) {
                case 'light':
                  themeMode = ThemeMode.light;
                case 'dark':
                  themeMode = ThemeMode.dark;
                default:
                  themeMode = ThemeMode.system;
              }
              widget.ref.read(themeModeProvider.notifier).state = themeMode;
              setState(() {});
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }

  // ── 9. 디버그·진단 ─────────────────────────────────────────────────
  Widget _buildDebugSection() {
    final logStatus = _loadingCrashLogInfo
        ? tr('로그 상태 확인 중...', 'Checking log status...')
        : (_crashLogBytes == null || _crashLogBytes == 0)
        ? tr('최근 기록된 충돌·예외 로그가 없습니다.',
            'No recent crash or exception logs recorded.')
        : tr('최근 충돌·예외 로그 ${_formatBytes(_crashLogBytes!)}가 저장되어 있습니다.',
            '${_formatBytes(_crashLogBytes!)} of recent crash/exception logs are stored.');

    return _SectionCard(
      title: tr('문제 해결', 'Troubleshooting'),
      icon: Icons.bug_report_outlined,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.8),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(
                      '문제 진단 자료에는 원본 녹음, 전체 전사, 회의 요약 전문이 포함되지 않습니다. '
                      '앱 상태, 모델 설치 여부, 최근 처리 시간, 충돌 로그만 저장합니다.',
                      'Diagnostic data does not include original recordings, full transcripts, or complete meeting summaries. '
                      'It only stores app state, installed models, recent processing times, and crash logs.'),
                  style: const TextStyle(fontSize: 12.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SettingRow(
          title: tr('문제 진단 자료 내보내기', 'Export diagnostic data'),
          subtitle: tr('앱 상태, 모델 설치 여부, 처리 시간, 충돌 로그를 ZIP으로 저장합니다.',
              'Saves app state, installed models, processing times, and crash logs as a ZIP file.'),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilledButton.icon(
              icon: _exportingDiagnostics
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.archive_outlined, size: 16),
              label: Text(_exportingDiagnostics
                  ? tr('생성 중...', 'Generating...')
                  : tr('ZIP 저장', 'Save ZIP')),
              onPressed: _exportingDiagnostics ? null : _exportDiagnostics,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ),
        const Divider(height: 18),
        _SettingRow(
          title: tr('충돌·예외 로그', 'Crash & exception logs'),
          subtitle: tr('$logStatus 진단 자료와 함께 공유하면 원인 파악에 도움이 됩니다.',
              '$logStatus Sharing these with the diagnostic data helps identify the cause.'),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: Text(tr('보기', 'View')),
                  onPressed: () => _showCrashLogDialog(),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: Text(tr('파일 위치', 'File location')),
                  onPressed: () async {
                    final p = await CrashLogService.instance.exportPath();
                    if (!mounted) return;
                    await _openPathInFinder(p);
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(tr('지우기', 'Clear')),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(tr('로그를 지울까요?', 'Clear the logs?')),
                        content: Text(
                          tr(
                              '저장된 충돌·예외 기록이 모두 삭제됩니다. '
                              '되돌릴 수 없습니다.',
                              'All stored crash and exception records will be deleted. '
                              'This cannot be undone.'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(tr('취소', 'Cancel')),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(tr('지우기', 'Clear')),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await CrashLogService.instance.clearLog();
                      await _loadCrashLogInfo();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('로그가 비워졌습니다.', 'Logs cleared.'))),
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportDiagnostics() async {
    final confirmed = await _confirmDiagnosticExport();
    if (!mounted || !confirmed) return;

    setState(() => _exportingDiagnostics = true);
    try {
      final path = await DiagnosticExportService.exportWithSavePanel();
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
            content: Text(tr('진단 자료 내보내기를 취소했습니다.',
                'Diagnostic export was cancelled.'))));
      } else {
        await _loadCrashLogInfo();
        await Clipboard.setData(ClipboardData(text: path));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(tr('진단 자료를 저장했습니다. 파일 경로도 복사했습니다.',
                'Diagnostic data saved. The file path was also copied.')),
            action: SnackBarAction(
              label: tr('Finder 열기', 'Open in Finder'),
              onPressed: () => _openPathInFinder(path),
            ),
          ),
        );
      }
    } catch (e, st) {
      CrashLogService.instance.recordCaught(
        e,
        st,
        context: 'exportDiagnostics',
      );
      if (!mounted) return;
      final friendly = friendlyErrorText(
        e,
        fallbackTitle: tr('진단 자료를 만들지 못했습니다', 'Could not create diagnostic data'),
        fallbackMessage: tr('진단 ZIP 파일을 생성하거나 저장하는 중 문제가 발생했습니다.',
            'A problem occurred while creating or saving the diagnostic ZIP file.'),
        nextStep: tr('저장 위치 권한과 디스크 여유 공간을 확인한 뒤 다시 시도해주세요.',
            'Check the save location permissions and free disk space, then try again.'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendly),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 7),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingDiagnostics = false);
    }
  }

  Future<bool> _confirmDiagnosticExport() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.privacy_tip_outlined, size: 22),
            const SizedBox(width: 8),
            Text(tr('진단 자료 내보내기', 'Export diagnostic data')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('문제 원인 파악을 위한 ZIP 파일을 만듭니다.',
                'Creates a ZIP file to help diagnose the issue.')),
            const SizedBox(height: 12),
            Text(tr('포함되는 정보', 'Included information')),
            const SizedBox(height: 4),
            Text(tr('• 앱 버전, 기기/OS 정보, 설정 상태',
                '• App version, device/OS info, settings state')),
            Text(tr('• 모델 설치 여부와 저장 공간 정보',
                '• Installed models and storage usage info')),
            Text(tr('• 최근 회의의 처리 시간, 세그먼트 수 같은 메타데이터',
                '• Metadata such as processing time and segment count for recent meetings')),
            Text(tr('• 앱이 기록한 충돌·예외 로그',
                '• Crash and exception logs recorded by the app')),
            const SizedBox(height: 12),
            Text(tr('포함하지 않는 정보', 'Information not included')),
            const SizedBox(height: 4),
            Text(tr('• 원본 녹음 파일', '• Original recording files')),
            Text(tr('• 전체 전사 텍스트', '• Full transcript text')),
            Text(tr('• 회의 요약 전문', '• Complete meeting summaries')),
            Text(tr('• 회의 제목 원문', '• Original meeting titles')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('취소', 'Cancel')),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.archive_outlined, size: 16),
            onPressed: () => Navigator.pop(ctx, true),
            label: Text(tr('ZIP 저장', 'Save ZIP')),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _openPathInFinder(String path) async {
    try {
      final entityType = await FileSystemEntity.type(path);
      final folderPath = entityType == FileSystemEntityType.directory
          ? path
          : File(path).parent.path;
      final opened = await launchUrl(Uri.file(folderPath));
      if (!opened) {
        throw FileSystemException(
            tr('Finder에서 위치를 열 수 없습니다.', 'Could not open the location in Finder.'),
            folderPath);
      }
    } catch (e, st) {
      CrashLogService.instance.recordCaught(e, st, context: 'openPathInFinder');
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorText(
              e,
              fallbackTitle: tr('파일 위치를 열지 못했습니다', 'Could not open the file location'),
              fallbackMessage: tr('Finder에서 폴더를 열 수 없습니다. 대신 경로를 복사했습니다.',
                  'Could not open the folder in Finder. The path was copied instead.'),
              nextStep: path,
            ),
          ),
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 7),
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  Future<void> _showCrashLogDialog() async {
    final content = await CrashLogService.instance.readLog();
    final size = await CrashLogService.instance.sizeBytes();
    if (!mounted) return;
    final sizeStr = size < 1024
        ? '$size B'
        : size < 1024 * 1024
        ? '${(size / 1024).toStringAsFixed(1)} KB'
        : '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.terminal, size: 20),
            const SizedBox(width: 8),
            Text(tr('충돌·예외 로그', 'Crash & exception logs')),
            const Spacer(),
            Text(
              sizeStr,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 720,
          height: 480,
          child: content.trim().isEmpty
              ? Center(
                  child: Text(
                    tr('기록된 로그가 없습니다.', 'No logs recorded.'),
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(ctx).colorScheme.outlineVariant,
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      content,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
        ),
        actions: [
          if (content.trim().isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              label: Text(tr('전체 복사', 'Copy all')),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: content));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(tr('로그를 클립보드에 복사했습니다.',
                          'Logs copied to clipboard.'))),
                );
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('닫기', 'Close')),
          ),
        ],
      ),
    );
  }
}

// ── 커스텀 프롬프트 에디터 ────────────────────────────────────────────────
class _CustomPromptEditor extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onSaved;

  const _CustomPromptEditor({
    super.key,
    required this.initial,
    required this.onSaved,
  });

  @override
  State<_CustomPromptEditor> createState() => _CustomPromptEditorState();
}

class _CustomPromptEditorState extends State<_CustomPromptEditor> {
  late TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _controller.addListener(() {
      final isDirty = _controller.text != widget.initial;
      if (isDirty != _dirty) setState(() => _dirty = isDirty);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          maxLines: 6,
          minLines: 4,
          style: const TextStyle(fontSize: 12, height: 1.4),
          decoration: InputDecoration(
            hintText: tr(
                '요약 지침을 자유롭게 작성하세요. '
                '회의 제목, 주요 논의, 결정사항, 액션아이템, 미해결 이슈 형식은 앱이 자동으로 맞춥니다.',
                'Write your summary instructions freely. '
                'The app automatically formats the meeting title, key discussions, decisions, action items, and open issues.'),
            hintStyle: const TextStyle(fontSize: 11),
            isDense: true,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () {
                _controller.text = SummaryTemplates.defaultCustomInstruction;
              },
              icon: const Icon(Icons.restart_alt, size: 14),
              label: Text(tr('기본값 복원', 'Restore default'),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _dirty
                  ? () => widget.onSaved(_controller.text.trim())
                  : null,
              icon: const Icon(Icons.save, size: 14),
              label: Text(tr('저장', 'Save'), style: const TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── 섹션 카드 ─────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 섹션 헤더
        Row(
          children: [
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

// ── 설정 행 ───────────────────────────────────────────────────────────────
class _SettingRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? child;
  final bool subtitleIsPath;

  const _SettingRow({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.child,
    this.subtitleIsPath = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    fontFamily: subtitleIsPath ? 'monospace' : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
              // ignore: use_null_aware_elements
              if (child != null) child!,
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class _AdvancedInfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _AdvancedInfoLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: TextStyle(fontSize: 11, color: muted)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: muted.withValues(alpha: 0.86),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 저장 공간 뱃지 ────────────────────────────────────────────────────────
class _StorageBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StorageBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelGroupHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ModelGroupHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 모델 행 ───────────────────────────────────────────────────────────────
enum _DlTarget {
  sttFast,
  sttFastCoreMl,
  sttAccurate,
  llmGemma,
  llmQwen,
  diarSeg,
  diarEmb,
}

enum _DlStatus { idle, downloading, done, error }

class _DlState {
  final _DlStatus status;
  final double? progress; // 0~1, null이면 indeterminate
  final String label;

  const _DlState({
    this.status = _DlStatus.idle,
    this.progress,
    this.label = '',
  });
}

class _ModelRow extends StatelessWidget {
  final String name;
  final String size;
  final String? subtitle;
  final bool exists;
  final _DlState dlState;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final bool downloadDisabled;

  const _ModelRow({
    required this.name,
    required this.size,
    this.subtitle,
    required this.exists,
    required this.dlState,
    required this.onDownload,
    required this.onCancel,
    this.downloadDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDownloading = dlState.status == _DlStatus.downloading;
    final hasError = dlState.status == _DlStatus.error;
    final installed = dlState.status == _DlStatus.done || exists;
    final muted = scheme.onSurfaceVariant;
    final borderColor = installed
        ? Colors.green.shade300.withValues(alpha: 0.65)
        : hasError
        ? Colors.red.shade300.withValues(alpha: 0.65)
        : scheme.outlineVariant.withValues(alpha: 0.75);
    final backgroundColor = installed
        ? Colors.green.withValues(alpha: 0.04)
        : hasError
        ? Colors.red.withValues(alpha: 0.04)
        : scheme.surfaceContainerLowest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 상태 아이콘
              if (installed)
                const Icon(Icons.check_circle, size: 16, color: Colors.green)
              else if (hasError)
                Icon(Icons.error_outline, size: 16, color: Colors.red.shade600)
              else if (isDownloading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.radio_button_unchecked,
                  size: 16,
                  color: muted.withValues(alpha: 0.56),
                ),
              const SizedBox(width: 8),

              // 이름
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(size, style: TextStyle(fontSize: 11, color: muted)),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          color: muted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              // 버튼
              if (isDownloading)
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined, size: 14),
                  label: Text(tr('취소', 'Cancel'), style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: downloadDisabled ? null : onDownload,
                  icon: const Icon(Icons.download, size: 14),
                  label: Text(
                    exists ? tr('재다운로드', 'Re-download') : tr('다운로드', 'Download'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),

          // 다운로드 진행 상태
          if (isDownloading) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: dlState.progress,
                    backgroundColor: scheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                    minHeight: 4,
                  ),
                  if (dlState.label.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      dlState.label,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 오류 메시지
          if (dlState.status == _DlStatus.error &&
              dlState.label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                dlState.label,
                style: TextStyle(fontSize: 11, color: Colors.red.shade600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
