import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_build_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/legal_notices.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/auto_delete_service.dart';
import '../../core/services/crash_log_service.dart';
import '../../core/services/diagnostic_export_service.dart';
import '../../core/services/model_download_service.dart';
import '../../core/services/summary_templates.dart';
import '../../core/services/user_error_message.dart';
import '../providers/settings_providers.dart';

/// 설정 다이얼로그 열기 헬퍼
void showSettingsDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (_) => _SettingsDialog(ref: ref),
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
  // 요약은 기본/고품질/한국어 특화 모델을 각각 다운로드
  final _sttFastDlService = ModelDownloadService();
  final _sttFastCoreMlDlService = ModelDownloadService();
  final _sttAccurateDlService = ModelDownloadService();
  final _llmGemmaDlService = ModelDownloadService();
  final _llmQwenDlService = ModelDownloadService();
  final _llmExaoneDlService = ModelDownloadService();
  final _diarSegDlService = ModelDownloadService();
  final _diarEmbDlService = ModelDownloadService();
  _DlState _sttFastDl = const _DlState();
  _DlState _sttFastCoreMlDl = const _DlState();
  _DlState _sttAccurateDl = const _DlState();
  _DlState _llmGemmaDl = const _DlState();
  _DlState _llmQwenDl = const _DlState();
  _DlState _llmExaoneDl = const _DlState();
  _DlState _diarSegDl = const _DlState();
  _DlState _diarEmbDl = const _DlState();
  bool _sttFastExists = false;
  bool _sttFastCoreMlExists = false;
  bool _sttAccurateExists = false;
  bool _llmGemmaExists = false;
  bool _llmQwenExists = false;
  bool _llmExaoneExists = false;
  bool _diarSegExists = false;
  bool _diarEmbExists = false;

  // ── 자동 삭제 결과 ───────────────────────────────────────────────
  String? _deleteResult;
  bool _exportingDiagnostics = false;
  int? _crashLogBytes;
  bool _loadingCrashLogInfo = true;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
    _checkModels();
    _loadCrashLogInfo();
  }

  @override
  void dispose() {
    _sttFastDlService.cancel();
    _sttFastCoreMlDlService.cancel();
    _sttAccurateDlService.cancel();
    _llmGemmaDlService.cancel();
    _llmQwenDlService.cancel();
    _llmExaoneDlService.cancel();
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

      // 커스텀 저장 경로가 있으면 해당 폴더도 계산
      final custom = _settings.recordingsSavePath;
      if (custom.isNotEmpty) {
        final customMb = await _dirSizeMb(custom);
        _recordingsMb = (_recordingsMb ?? 0) + customMb;
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
    _llmExaoneExists = await File(
      '$dir/${AppConstants.llmModelFileExaone35_7B}',
    ).exists();
    _diarSegExists = await File(
      '$dir/${AppConstants.diarSegModelFile}',
    ).exists();
    _diarEmbExists = await File(
      '$dir/${AppConstants.diarEmbModelFile}',
    ).exists();
    if (mounted) setState(() {});
  }

  // ── 모델 재다운로드 ───────────────────────────────────────────────
  Future<void> _downloadModel({required _DlTarget target}) async {
    if (target == _DlTarget.llmExaone &&
        !AppBuildConfig.allowRestrictedModels) {
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
      case _DlTarget.llmExaone:
        filename = AppConstants.llmModelFileExaone35_7B;
        url = AppConstants.llmDownloadUrlExaone35_7B;
        service = _llmExaoneDlService;
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
              fallbackTitle: '모델을 설치하지 못했습니다',
              fallbackMessage: '다운로드 또는 파일 저장 중 문제가 발생했습니다.',
              nextStep: '네트워크, 저장 공간, 모델 폴더 권한을 확인한 뒤 다시 시도해주세요.',
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
        case _DlTarget.llmExaone:
          _llmExaoneDl = state;
        case _DlTarget.diarSeg:
          _diarSegDl = state;
        case _DlTarget.diarEmb:
          _diarEmbDl = state;
      }
    });
  }

  // ── 폴더 선택 ─────────────────────────────────────────────────────
  Future<void> _pickRecordingsFolder() async {
    final path = await getDirectoryPath(confirmButtonText: '선택');
    if (path != null) {
      await _settings.setRecordingsSavePath(path);
      if (mounted) setState(() {});
      await _loadStorageInfo();
    }
  }

  // ── 오래된 녹음 WAV 파일만 삭제 (회의록·전사·요약은 유지) ──────────
  Future<void> _runAutoDelete(int days) async {
    final r = await AutoDeleteService.run(days);
    if (!mounted) return;
    setState(() {
      if (r.isEmpty) {
        _deleteResult = '삭제할 오래된 녹음 파일이 없습니다.';
      } else if (r.deleted > 0 && r.missing == 0) {
        _deleteResult = '녹음 파일 ${r.deleted}개가 삭제되었습니다. (회의록·요약은 유지됩니다)';
      } else if (r.deleted == 0 && r.missing > 0) {
        _deleteResult = '파일은 이미 없었지만 DB 참조 ${r.missing}개를 정리했습니다.';
      } else {
        _deleteResult = '녹음 파일 ${r.deleted}개 삭제 + DB 참조 ${r.missing}개 정리.';
      }
    });
    await _loadStorageInfo();
  }

  // ── BUILD ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 헤더 ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
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
                    '설정',
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
      ),
    );
  }

  // ── 1. 녹음 설정 ──────────────────────────────────────────────────
  Widget _buildRecordingSection() {
    final settings = AppSettings.instance;
    final customPath = settings.recordingsSavePath;

    return _SectionCard(
      title: '녹음',
      icon: Icons.mic,
      children: [
        // 언어 설정
        _SettingRow(
          title: '음성 인식 언어',
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

        const Divider(height: 20),

        // 음성 인식 속도/품질 모드
        _SettingRow(
          title: '음성 인식 방식',
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
                      '${AppSettings.sttProcessingModeLabel(next)} 방식으로 전환했습니다.',
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
          title: '녹음 파일 저장 위치',
          subtitle: customPath.isNotEmpty ? customPath : '저장 폴더가 선택되지 않았습니다.',
          subtitleIsPath: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _pickRecordingsFolder,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('변경'),
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
      title: '녹음 품질',
      icon: Icons.tune,
      children: [
        _SettingRow(
          title: '자동 음량 조절 (AGC)',
          subtitle:
              '조용한 화자의 볼륨을 자동 보정합니다. '
              '조용한 환경에서 유리하지만 배경 소음도 함께 증폭될 수 있습니다.',
          trailing: Switch(
            value: settings.recordAutoGain,
            onChanged: (v) async {
              await settings.setRecordAutoGain(v);
              setState(() {});
            },
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: '에코 제거',
          subtitle:
              '스피커폰 통화 환경에 유리합니다. '
              '다중 화자가 마주 앉은 회의에서는 반대편 화자 음량이 감쇄돼 '
              '오히려 품질이 떨어질 수 있습니다. (기본: 꺼짐)',
          trailing: Switch(
            value: settings.recordEchoCancel,
            onChanged: (v) async {
              await settings.setRecordEchoCancel(v);
              setState(() {});
            },
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: '녹음 정규화 (피크 -1dB)',
          subtitle:
              '저장 시 전체 음량을 최대치 근처까지 자동으로 끌어올립니다. '
              '음성 인식 품질 향상에 유리하며 클리핑은 발생하지 않습니다. '
              '(권장: 켜짐)',
          trailing: Switch(
            value: settings.recordNormalize,
            onChanged: (v) async {
              await settings.setRecordNormalize(v);
              setState(() {});
            },
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: '마이크 가이드 다시 보기',
          subtitle: settings.micGuideShown
              ? '다음 녹음 시작 시 마이크 위치/거리 가이드를 한 번 더 표시합니다.'
              : '아직 표시되지 않았습니다. 첫 녹음 시작 시 자동으로 안내됩니다.',
          trailing: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('리셋'),
            onPressed: settings.micGuideShown
                ? () async {
                    await settings.setMicGuideShown(false);
                    setState(() {});
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('가이드가 초기화되었습니다. 다음 녹음 시작 시 다시 표시됩니다.'),
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
            title: '녹음 종료 후 macOS 캘린더에 자동 등록',
            subtitle:
                '회의 제목과 시작/종료 시각으로 Calendar.app에 새 이벤트가 추가됩니다. '
                '첫 활성화 시 macOS가 자동화 권한을 요청합니다.',
            trailing: Switch(
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
      title: '회의 유형',
      icon: Icons.auto_awesome,
      children: [
        _SettingRow(
          title: '요약 방식',
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
          title: '기본 회의 유형',
          subtitle: '회의 성격에 맞춰 요약에서 강조할 항목이 달라집니다.',
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
                  label: const Text('커스텀1', style: TextStyle(fontSize: 12)),
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
                  label: const Text('커스텀2', style: TextStyle(fontSize: 12)),
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
                      color: Colors.grey.shade700,
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
                '고급 설정 — 세부 정리 방식',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
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
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '* 회의 유형별로 요약에서 더 중요하게 볼 기준입니다. '
                  '커스텀 모드에서 직접 조정할 수 있습니다.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
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
                        ? '커스텀1 — 요약에서 강조할 기준을 직접 편집합니다. 비워두면 일반 회의 지침이 사용됩니다.'
                        : '커스텀2 — 요약에서 강조할 기준을 직접 편집합니다. 비워두면 일반 회의 지침이 사용됩니다.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
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
      title: '데이터 관리',
      icon: Icons.storage,
      children: [
        // 저장 공간
        _SettingRow(
          title: '저장 공간 사용량',
          subtitle: '',
          trailing: _loadingStorage
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '새로고침',
                  onPressed: _loadStorageInfo,
                  visualDensity: VisualDensity.compact,
                ),
          child: _loadingStorage
              ? const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('계산 중...', style: TextStyle(fontSize: 12)),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      _StorageBadge(
                        label: '모델',
                        value: fmtSize(modelsMb),
                        color: Colors.indigo,
                      ),
                      const SizedBox(width: 8),
                      _StorageBadge(
                        label: '녹음',
                        value: fmtSize(recMb),
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 8),
                      _StorageBadge(
                        label: '합계',
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
          title: '오래된 녹음 파일 자동 삭제',
          subtitle: '설정한 일수보다 오래된 WAV 파일만 삭제합니다. 회의록·전사·요약은 그대로 유지됩니다.',
          trailing: DropdownButton<int>(
            value: AppSettings.instance.autoDeleteDays,
            underline: const SizedBox(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 0, child: Text('끄기')),
              DropdownMenuItem(value: 30, child: Text('30일')),
              DropdownMenuItem(value: 60, child: Text('60일')),
              DropdownMenuItem(value: 90, child: Text('90일')),
              DropdownMenuItem(value: 180, child: Text('180일')),
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
                  '지금 삭제 (${AppSettings.instance.autoDeleteDays}일 이상 지난 녹음 파일만)',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade200),
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
                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
              ),
            ),
          ],
        ],
      ],
    );
  }

  // ── 3. 모델 관리 ──────────────────────────────────────────────────
  Widget _buildModelSection() {
    return _SectionCard(
      title: '음성/요약 모델',
      icon: Icons.memory,
      children: [
        _ModelRow(
          name: '빠른 음성 인식 모델',
          size: '~900 MB',
          subtitle: '짧은 회의 초안 확인에 적합합니다.',
          exists: _sttFastExists,
          dlState: _sttFastDl,
          onDownload: () => _downloadModel(target: _DlTarget.sttFast),
          onCancel: () {
            _sttFastDlService.cancel();
            setState(() => _sttFastDl = const _DlState());
          },
        ),
        const SizedBox(height: 12),
        _ModelRow(
          name: '빠른 음성 인식 가속팩',
          size: '~1.2 GB',
          subtitle: 'Apple Silicon에서 Core ML로 긴 녹음 전사를 더 빠르게 처리합니다.',
          exists: _sttFastCoreMlExists,
          dlState: _sttFastCoreMlDl,
          onDownload: () => _downloadModel(target: _DlTarget.sttFastCoreMl),
          onCancel: () {
            _sttFastCoreMlDlService.cancel();
            setState(() => _sttFastCoreMlDl = const _DlState());
          },
        ),
        const SizedBox(height: 12),
        _ModelRow(
          name: '정확도 높은 음성 인식 모델',
          size: '~1.1 GB',
          subtitle: '긴 회의와 최종 회의록 품질에 유리합니다.',
          exists: _sttAccurateExists,
          dlState: _sttAccurateDl,
          onDownload: () => _downloadModel(target: _DlTarget.sttAccurate),
          onCancel: () {
            _sttAccurateDlService.cancel();
            setState(() => _sttAccurateDl = const _DlState());
          },
        ),
        const SizedBox(height: 12),
        _ModelRow(
          name: '기본 요약 모델',
          size: '~3 GB',
          subtitle: '빠르게 요약하고 메모리 부담이 적습니다.',
          exists: _llmGemmaExists,
          dlState: _llmGemmaDl,
          onDownload: () => _downloadModel(target: _DlTarget.llmGemma),
          onCancel: () {
            _llmGemmaDlService.cancel();
            setState(() => _llmGemmaDl = const _DlState());
          },
        ),
        const SizedBox(height: 12),
        _ModelRow(
          name: '고품질 요약 모델',
          size: '~4.7 GB',
          subtitle: '논의·결정·액션아이템을 구조화하는 데 유리합니다.',
          exists: _llmQwenExists,
          dlState: _llmQwenDl,
          onDownload: () => _downloadModel(target: _DlTarget.llmQwen),
          onCancel: () {
            _llmQwenDlService.cancel();
            setState(() => _llmQwenDl = const _DlState());
          },
        ),
        const SizedBox(height: 12),
        if (AppBuildConfig.allowRestrictedModels) ...[
          _ModelRow(
            name: '내부 테스트 요약 모델',
            size: '~4.8 GB',
            subtitle: '앱스토어 빌드에서는 라이선스 리스크로 숨겨집니다.',
            exists: _llmExaoneExists,
            dlState: _llmExaoneDl,
            onDownload: () => _downloadModel(target: _DlTarget.llmExaone),
            onCancel: () {
              _llmExaoneDlService.cancel();
              setState(() => _llmExaoneDl = const _DlState());
            },
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
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
      if (AppBuildConfig.allowRestrictedModels) 'exaone35_7b': _llmExaoneExists,
    };

    String labelOf(String id) {
      switch (id) {
        case 'qwen25_7b':
          return '고품질';
        case 'exaone35_7b':
          return '내부 테스트';
        default:
          return '기본';
      }
    }

    String tipOf(String id) {
      switch (id) {
        case 'qwen25_7b':
          return '회의 내용을 항목별로 정리하는 데 유리합니다.';
        case 'exaone35_7b':
          return '앱스토어 빌드에서는 숨겨지는 내부 테스트 모델입니다.';
        default:
          return '가볍고 빠르게 요약합니다.';
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
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
              const Text(
                '기본 요약 모델',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '회의록 요약에 기본으로 사용할 방식을 고릅니다. 요약할 때마다 바꿀 수도 있습니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                    ok ? labelOf(id) : '${labelOf(id)} (미설치)',
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
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, left: 8, right: 8),
        dense: true,
        title: const Text(
          '고급 정보',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          '모델 파일명과 상세 정보를 확인합니다.',
          style: TextStyle(fontSize: 11),
        ),
        children: [
          _AdvancedInfoLine('빠른 음성 인식', AppConstants.sttModelFileFast),
          _AdvancedInfoLine('정확도 높은 음성 인식', AppConstants.sttModelFileAccurate),
          _AdvancedInfoLine('기본 요약', AppConstants.llmModelFileGemma4E2B),
          _AdvancedInfoLine('고품질 요약', AppConstants.llmModelFileQwen25_7B),
          if (AppBuildConfig.allowRestrictedModels)
            _AdvancedInfoLine(
              '내부 테스트 요약',
              AppConstants.llmModelFileExaone35_7B,
            ),
        ],
      ),
    );
  }

  Widget _buildLegalSection() {
    return _SectionCard(
      title: '라이선스와 개인정보',
      icon: Icons.verified_user_outlined,
      children: [
        _SettingRow(
          title: '사용 모델 및 라이선스',
          subtitle:
              '음성 인식과 요약은 로컬 Mac에서 실행됩니다. 앱스토어 빌드에서는 상업 배포 리스크가 큰 모델을 숨깁니다.',
          trailing: OutlinedButton.icon(
            icon: const Icon(Icons.article_outlined, size: 16),
            label: const Text('보기'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _showLicenseNotices,
          ),
        ),
        const Divider(height: 20),
        _SettingRow(
          title: '앱스토어 안전 모드',
          subtitle: AppBuildConfig.appStoreComplianceMode
              ? '켜짐 · EXAONE, 캘린더 자동화, AppleEvent 기능을 기본 화면에서 숨깁니다.'
              : '꺼짐 · 내부 테스트용 빌드 플래그가 적용되어 있습니다.',
          trailing: Icon(
            AppBuildConfig.appStoreComplianceMode
                ? Icons.lock_outline
                : Icons.science_outlined,
            size: 18,
          ),
        ),
      ],
    );
  }

  void _showLicenseNotices() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사용 모델 및 라이선스'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '이 앱은 회의 음성과 요약 내용을 외부 서버로 보내지 않고, 사용자가 설치한 로컬 모델로 처리합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: SelectableText(
                    LegalNotices.restrictedModelNote,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Colors.brown.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  // ── 3-1. 발화자 라벨 ─────────────────────────────────────────────
  Widget _buildDiarizationSection() {
    final settings = AppSettings.instance;
    final modelsReady = _diarSegExists && _diarEmbExists;

    return _SectionCard(
      title: '발화자 라벨',
      icon: Icons.record_voice_over,
      children: [
        _SettingRow(
          title: '발화자 라벨 사용',
          subtitle: modelsReady
              ? '사람 이름을 자동으로 알아내지는 않고, 각 문장에 A/B/C 라벨을 붙입니다. '
                    '회의 길이에 따라 수십 초~수 분 추가됩니다.'
              : '아래 두 모델을 먼저 다운로드하세요.',
          trailing: Switch(
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
          title: '말할 사람 수',
          subtitle: '명시하면 A/B/C 라벨이 과하게 늘어나는 문제를 줄일 수 있습니다.',
          trailing: DropdownButton<int>(
            value: settings.numSpeakersHint,
            underline: const SizedBox(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 0, child: Text('자동')),
              DropdownMenuItem(value: 2, child: Text('2명')),
              DropdownMenuItem(value: 3, child: Text('3명')),
              DropdownMenuItem(value: 4, child: Text('4명')),
              DropdownMenuItem(value: 5, child: Text('5명')),
              DropdownMenuItem(value: 6, child: Text('6명')),
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
        _ModelRow(
          name: '발화 구간 찾기 모델',
          size: '~6 MB',
          subtitle: '누가 언제 말했는지 나누기 위한 보조 모델입니다.',
          exists: _diarSegExists,
          dlState: _diarSegDl,
          onDownload: () => _downloadModel(target: _DlTarget.diarSeg),
          onCancel: () {
            _diarSegDlService.cancel();
            setState(() => _diarSegDl = const _DlState());
          },
        ),
        const SizedBox(height: 12),
        _ModelRow(
          name: '목소리 구분 모델',
          size: '~26 MB',
          subtitle: '비슷한 목소리 구간을 같은 발화자로 묶는 데 사용합니다.',
          exists: _diarEmbExists,
          dlState: _diarEmbDl,
          onDownload: () => _downloadModel(target: _DlTarget.diarEmb),
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
            title: const Text(
              '고급 정보',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '발화자 라벨 모델 파일명을 확인합니다.',
              style: TextStyle(fontSize: 11),
            ),
            children: [
              _AdvancedInfoLine('발화 구간 찾기', AppConstants.diarSegModelFile),
              _AdvancedInfoLine('목소리 구분', AppConstants.diarEmbModelFile),
            ],
          ),
        ),
      ],
    );
  }

  // ── 4. 화면 설정 ──────────────────────────────────────────────────
  Widget _buildDisplaySection() {
    final current = AppSettings.instance.themeMode;

    return _SectionCard(
      title: '화면',
      icon: Icons.palette_outlined,
      children: [
        _SettingRow(
          title: '테마',
          subtitle: '앱 전체 색상 테마를 선택합니다.',
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'system',
                icon: Icon(Icons.brightness_auto, size: 16),
                label: Text('시스템'),
              ),
              ButtonSegment(
                value: 'light',
                icon: Icon(Icons.light_mode, size: 16),
                label: Text('라이트'),
              ),
              ButtonSegment(
                value: 'dark',
                icon: Icon(Icons.dark_mode, size: 16),
                label: Text('다크'),
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
        ? '로그 상태 확인 중...'
        : (_crashLogBytes == null || _crashLogBytes == 0)
        ? '최근 기록된 충돌·예외 로그가 없습니다.'
        : '최근 충돌·예외 로그 ${_formatBytes(_crashLogBytes!)}가 저장되어 있습니다.';

    return _SectionCard(
      title: '문제 해결',
      icon: Icons.bug_report_outlined,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '문제 진단 자료에는 원본 녹음, 전체 전사, 회의 요약 전문이 포함되지 않습니다. '
                  '앱 상태, 모델 설치 여부, 최근 처리 시간, 충돌 로그만 저장합니다.',
                  style: TextStyle(fontSize: 12.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SettingRow(
          title: '문제 진단 자료 내보내기',
          subtitle:
              '앱 상태, 모델 설치 여부, 최근 처리 시간, 충돌 로그를 ZIP 파일로 저장합니다. '
              '고객 문의나 오류 분석에 사용할 수 있습니다.',
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
              label: Text(_exportingDiagnostics ? '생성 중...' : 'ZIP 저장'),
              onPressed: _exportingDiagnostics ? null : _exportDiagnostics,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ),
        const Divider(height: 18),
        _SettingRow(
          title: '충돌·예외 로그',
          subtitle: '$logStatus 문제가 발생했을 때 진단 자료와 함께 공유하면 원인 파악에 도움이 됩니다.',
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('보기'),
                  onPressed: () => _showCrashLogDialog(),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: const Text('파일 위치'),
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
                  label: const Text('지우기'),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('로그를 지울까요?'),
                        content: const Text(
                          '저장된 충돌·예외 기록이 모두 삭제됩니다. '
                          '되돌릴 수 없습니다.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('취소'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('지우기'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await CrashLogService.instance.clearLog();
                      await _loadCrashLogInfo();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('로그가 비워졌습니다.')),
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
        ).showSnackBar(const SnackBar(content: Text('진단 자료 내보내기를 취소했습니다.')));
      } else {
        await _loadCrashLogInfo();
        await Clipboard.setData(ClipboardData(text: path));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: const Text('진단 자료를 저장했습니다. 파일 경로도 복사했습니다.'),
            action: SnackBarAction(
              label: 'Finder 열기',
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
        fallbackTitle: '진단 자료를 만들지 못했습니다',
        fallbackMessage: '진단 ZIP 파일을 생성하거나 저장하는 중 문제가 발생했습니다.',
        nextStep: '저장 위치 권한과 디스크 여유 공간을 확인한 뒤 다시 시도해주세요.',
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
        title: const Row(
          children: [
            Icon(Icons.privacy_tip_outlined, size: 22),
            SizedBox(width: 8),
            Text('진단 자료 내보내기'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('문제 원인 파악을 위한 ZIP 파일을 만듭니다.'),
            SizedBox(height: 12),
            Text('포함되는 정보'),
            SizedBox(height: 4),
            Text('• 앱 버전, 기기/OS 정보, 설정 상태'),
            Text('• 모델 설치 여부와 저장 공간 정보'),
            Text('• 최근 회의의 처리 시간, 세그먼트 수 같은 메타데이터'),
            Text('• 앱이 기록한 충돌·예외 로그'),
            SizedBox(height: 12),
            Text('포함하지 않는 정보'),
            SizedBox(height: 4),
            Text('• 원본 녹음 파일'),
            Text('• 전체 전사 텍스트'),
            Text('• 회의 요약 전문'),
            Text('• 회의 제목 원문'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.archive_outlined, size: 16),
            onPressed: () => Navigator.pop(ctx, true),
            label: const Text('ZIP 저장'),
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
        throw FileSystemException('Finder에서 위치를 열 수 없습니다.', folderPath);
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
              fallbackTitle: '파일 위치를 열지 못했습니다',
              fallbackMessage: 'Finder에서 폴더를 열 수 없습니다. 대신 경로를 복사했습니다.',
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
            const Text('충돌·예외 로그'),
            const Spacer(),
            Text(
              sizeStr,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        content: SizedBox(
          width: 720,
          height: 480,
          child: content.trim().isEmpty
              ? Center(
                  child: Text(
                    '기록된 로그가 없습니다.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
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
              label: const Text('전체 복사'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: content));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('로그를 클립보드에 복사했습니다.')),
                );
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
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
            hintText:
                '요약 지침을 자유롭게 작성하세요. '
                '회의 제목, 주요 논의, 결정사항, 액션아이템, 미해결 이슈 형식은 앱이 자동으로 맞춥니다.',
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
              label: const Text('기본값 복원', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _dirty
                  ? () => widget.onSaved(_controller.text.trim())
                  : null,
              icon: const Icon(Icons.save, size: 14),
              label: const Text('저장', style: TextStyle(fontSize: 12)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 섹션 헤더
        Row(
          children: [
            Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.all(16),
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
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.grey.shade600,
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

// ── 모델 행 ───────────────────────────────────────────────────────────────
enum _DlTarget {
  sttFast,
  sttFastCoreMl,
  sttAccurate,
  llmGemma,
  llmQwen,
  llmExaone,
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

  const _ModelRow({
    required this.name,
    required this.size,
    this.subtitle,
    required this.exists,
    required this.dlState,
    required this.onDownload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDownloading = dlState.status == _DlStatus.downloading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 상태 아이콘
            if (dlState.status == _DlStatus.done || exists)
              const Icon(Icons.check_circle, size: 16, color: Colors.green)
            else if (dlState.status == _DlStatus.error)
              Icon(Icons.error_outline, size: 16, color: Colors.red.shade600)
            else
              Icon(
                Icons.radio_button_unchecked,
                size: 16,
                color: Colors.grey.shade400,
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
                  Text(
                    size,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),

            // 버튼
            if (isDownloading)
              TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 14),
                label: const Text('취소', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  visualDensity: VisualDensity.compact,
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download, size: 14),
                label: Text(
                  exists ? '재다운로드' : '다운로드',
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
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: dlState.progress,
                  backgroundColor: Colors.grey.shade200,
                  minHeight: 4,
                ),
                if (dlState.label.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    dlState.label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        ],

        // 오류 메시지
        if (dlState.status == _DlStatus.error && dlState.label.isNotEmpty) ...[
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
    );
  }
}
