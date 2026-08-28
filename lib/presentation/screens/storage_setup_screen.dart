import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../core/l10n/app_tr.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/isar_service.dart';
import '../../core/services/security_scoped_bookmark_service.dart';
import 'home_screen.dart';
import 'setup_screen.dart';
import '../widgets/theme_tint.dart';

PageRouteBuilder<void> _instantRoute(Widget child) => PageRouteBuilder<void>(
  pageBuilder: (_, _, _) => child,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);

class StorageSetupScreen extends StatefulWidget {
  final ValueChanged<String> onComplete;

  /// 첫 단계(step 0)에서 '이전'을 눌렀을 때 호출. null이면 첫 단계에 뒤로가기를
  /// 표시하지 않는다. (보통 언어 선택 화면으로 되돌아가는 데 사용.)
  final VoidCallback? onBack;

  /// 이 화면에서 곧바로 모델 준비 화면(SetupScreen)으로 넘어가는 경우,
  /// 모델 준비가 끝났을 때 루트 상태(_showHome)·트레이 동기화를 수행하기 위한 콜백.
  /// 비워두면 모델 준비 완료 후 트레이 빠른 녹음 상태가 갱신되지 않는다.
  final VoidCallback? onModelsComplete;

  /// 비어 있지 않으면 '재연결 모드'. 이전에 쓰던 저장 폴더 경로를 표시하고,
  /// 기존 회의록을 잃지 않으려면 같은 폴더를 다시 선택하라고 안내한다(I1).
  final String reconnectPath;

  const StorageSetupScreen({
    super.key,
    required this.onComplete,
    this.onBack,
    this.onModelsComplete,
    this.reconnectPath = '',
  });

  @override
  State<StorageSetupScreen> createState() => _StorageSetupScreenState();
}

class _StorageSetupScreenState extends State<StorageSetupScreen> {
  int _step = 0;
  bool _picking = false;
  String _pickingMessage = '선택 중...';
  String? _error;

  void _nextStep() {
    if (_step >= 2) return;
    setState(() => _step += 1);
  }

  void _previousStep() {
    if (_step <= 0) return;
    setState(() => _step -= 1);
  }

  Future<void> _pickFolder() async {
    setState(() {
      _picking = true;
      _pickingMessage = tr('폴더 선택 중...', 'Choosing folder...');
      _error = null;
    });

    try {
      final path = await getDirectoryPath(
        confirmButtonText: tr('저장 폴더 선택', 'Choose folder'),
      );
      if (!mounted) return;
      if (path == null || path.trim().isEmpty) {
        setState(() {
          _picking = false;
          _pickingMessage = tr('선택 중...', 'Selecting...');
        });
        return;
      }

      final selectedPath = path.trim();
      setState(() => _pickingMessage = tr('저장 위치 적용 중...', 'Applying location...'));
      await SecurityScopedBookmarkService.saveRecordingsFolderSelection(
        selectedPath,
      );
      // 새 사용자 폴더에 Isar DB 열기 (구버전 컨테이너 잔재가 있으면 이전)
      if (IsarService.instance.isOpen) {
        await IsarService.instance.relocateToUserSelectedDirectory();
      } else {
        await IsarService.instance.init();
      }

      if (!mounted) return;
      setState(() => _pickingMessage = tr('다음 화면으로 이동 중...', 'Moving on...'));
      if (!mounted) return;
      _openNextScreen();
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => widget.onComplete(selectedPath),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _pickingMessage = tr('선택 중...', 'Selecting...');
        _error =
            '${tr('저장 폴더를 설정하지 못했습니다', 'Could not set the storage folder')}: $e';
      });
    }
  }

  void _openNextScreen() {
    final next = AppSettings.instance.modelsSetupComplete
        ? const HomeScreen()
        : SetupScreen(onComplete: widget.onModelsComplete ?? () {});
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushReplacement(_instantRoute(next));
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final steps = [
      _OnboardingStep(
        icon: Icons.lock_outline_rounded,
        title: tr(
          '회의 내용은 기기 밖으로 나가지 않습니다',
          'Your meetings never leave this device',
        ),
        description: tr(
          '녹음, 음성 인식, 발화자 라벨, 요약은 모두 이 기기에서 실행됩니다. 회의 음성이나 전사본을 외부 서버로 전송하지 않습니다.',
          'Recording, speech recognition, speaker labels, and summaries all run on this device. Meeting audio and transcripts are never sent to an external server.',
        ),
        points: [
          _OnboardingPoint(
            icon: Icons.cloud_off_outlined,
            text: tr(
              '회의 파일을 클라우드로 업로드하지 않습니다.',
              'Meeting files are never uploaded to the cloud.',
            ),
          ),
          _OnboardingPoint(
            icon: Icons.computer_rounded,
            text: tr(
              'AI 처리는 로컬 모델로 이 기기에서 실행됩니다.',
              'AI runs locally on this device.',
            ),
          ),
          _OnboardingPoint(
            icon: Icons.security_rounded,
            text: tr(
              '네트워크가 불안정해도 회의록 작업을 계속할 수 있습니다.',
              'Works even with an unstable network connection.',
            ),
          ),
        ],
      ),
      _OnboardingStep(
        icon: Icons.memory_rounded,
        title: tr(
          '음성 인식과 요약 모델을 한 번만 준비합니다',
          'Set up the speech and summary models once',
        ),
        description: tr(
          '처음에는 모델 다운로드가 필요합니다. 용량은 크지만, 설치 후에는 회의마다 외부 서비스 없이 사용할 수 있습니다.',
          'A one-time model download is required. The files are large, but afterward every meeting works without any external service.',
        ),
        points: [
          _OnboardingPoint(
            icon: Icons.graphic_eq_rounded,
            text: tr(
              '음성 인식 모델은 녹음 내용을 텍스트로 바꿉니다.',
              'The speech model turns recordings into text.',
            ),
          ),
          _OnboardingPoint(
            icon: Icons.auto_awesome_rounded,
            text: tr(
              '요약 모델은 결정사항과 액션아이템을 정리합니다.',
              'The summary model organizes decisions and action items.',
            ),
          ),
          _OnboardingPoint(
            icon: Icons.label_outline_rounded,
            text: tr(
              '발화자 라벨은 사람 이름이 아니라 A/B/C 흐름 보조입니다.',
              'Speaker labels are A/B/C flow hints, not real names.',
            ),
          ),
        ],
      ),
      _OnboardingStep(
        icon: Icons.folder_open_rounded,
        title: tr(
          '녹음 파일을 저장할 폴더를 선택하세요',
          'Choose a folder to store recordings',
        ),
        description: tr(
          '회의 녹음과 전사 데이터는 사용자가 선택한 폴더를 기준으로 관리됩니다. 나중에 설정에서 변경할 수 있습니다.',
          'Meeting recordings and transcript data are kept in the folder you choose. You can change it later in Settings.',
        ),
        points: [
          _OnboardingPoint(
            icon: Icons.folder_rounded,
            text: tr(
              '회사 프로젝트 폴더나 개인 문서 폴더를 선택할 수 있습니다.',
              'Pick a work project folder or your documents folder.',
            ),
          ),
          _OnboardingPoint(
            icon: Icons.edit_location_alt_outlined,
            text: tr(
              '저장 위치는 설정 화면에서 언제든 변경할 수 있습니다.',
              'You can change the location anytime in Settings.',
            ),
          ),
          _OnboardingPoint(
            icon: Icons.task_alt_rounded,
            text: tr(
              '폴더 선택이 끝나면 앱 준비 화면으로 이동합니다.',
              'After choosing, you move on to model setup.',
            ),
          ),
        ],
      ),
    ];
    final current = steps[_step];
    final isLastStep = _step == steps.length - 1;

    return MacosWindow(
      disableWallpaperTinting: true,
      child: MacosScaffold(
        children: [
          ContentArea(
            builder: (context, scrollController) => Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.reconnectPath.isNotEmpty) ...[
                          _ReconnectBanner(
                            path: widget.reconnectPath,
                            color: color,
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(steps.length, (index) {
                            final active = index == _step;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: active ? 28 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: active
                                    ? color.primary
                                    : color.outlineVariant.withValues(
                                        alpha: 0.8,
                                      ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 24),
                        Icon(current.icon, size: 52, color: color.primary),
                        const SizedBox(height: 20),
                        Text(
                          current.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          current.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: color.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: color.primaryContainer.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: color.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Column(
                            children: current.points
                                .map(
                                  (point) => Padding(
                                    padding: EdgeInsets.only(
                                      bottom: point == current.points.last
                                          ? 0
                                          : 10,
                                    ),
                                    child: _PrivacyPoint(
                                      icon: point.icon,
                                      text: point.text,
                                      color: color,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: color.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(color: color.onErrorContainer),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            if (_step > 0) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _picking ? null : _previousStep,
                                  icon: const Icon(Icons.chevron_left_rounded),
                                  label: Text(tr('이전', 'Back')),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ] else if (widget.onBack != null) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _picking ? null : widget.onBack,
                                  icon: const Icon(Icons.chevron_left_rounded),
                                  label: Text(tr('이전', 'Back')),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              flex: (_step > 0 || widget.onBack != null) ? 2 : 1,
                              child: FilledButton.icon(
                                onPressed: _picking
                                    ? null
                                    : isLastStep
                                    ? _pickFolder
                                    : _nextStep,
                                icon: _picking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        isLastStep
                                            ? Icons.folder_rounded
                                            : Icons.chevron_right_rounded,
                                      ),
                                label: Text(
                                  _picking
                                      ? _pickingMessage
                                      : isLastStep
                                      ? tr('저장 폴더 선택', 'Choose folder')
                                      : tr('다음', 'Next'),
                                ),
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
}

class _OnboardingStep {
  final IconData icon;
  final String title;
  final String description;
  final List<_OnboardingPoint> points;

  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.points,
  });
}

class _OnboardingPoint {
  final IconData icon;
  final String text;

  const _OnboardingPoint({required this.icon, required this.text});
}

class _PrivacyPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme color;

  const _PrivacyPoint({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: color.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// 재연결 안내 배너 (I1): 이전 저장 폴더에 접근할 수 없을 때, 같은 폴더를
/// 다시 선택하면 기존 회의록을 복구할 수 있음을 안내한다.
class _ReconnectBanner extends StatelessWidget {
  final String path;
  final ColorScheme color;

  const _ReconnectBanner({required this.path, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: tintFg(context, Colors.amber)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    '이전 저장 폴더에 접근할 수 없습니다',
                    'Your previous storage folder is not accessible',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tintFg(context, Colors.amber),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              '기존 회의록을 복구하려면 아래 폴더를 다시 선택하세요. 다른 폴더를 선택하면 빈 상태로 시작되며 기존 데이터는 연결되지 않습니다.',
              'To recover your existing meetings, re-select the same folder below. Choosing a different folder starts empty and will not link your existing data.',
            ),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: tintFg(context, Colors.amber),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.outlineVariant),
            ),
            child: Text(
              path,
              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
