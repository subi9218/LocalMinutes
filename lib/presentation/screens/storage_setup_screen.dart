import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../core/services/app_settings.dart';

class StorageSetupScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const StorageSetupScreen({super.key, required this.onComplete});

  @override
  State<StorageSetupScreen> createState() => _StorageSetupScreenState();
}

class _StorageSetupScreenState extends State<StorageSetupScreen> {
  int _step = 0;
  bool _picking = false;
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
      _error = null;
    });

    try {
      final path = await getDirectoryPath(confirmButtonText: '저장 폴더 선택');
      if (!mounted) return;
      if (path == null || path.trim().isEmpty) {
        setState(() => _picking = false);
        return;
      }

      final dir = Directory(path);
      if (!await dir.exists()) {
        throw Exception('선택한 폴더를 찾을 수 없습니다.');
      }

      await AppSettings.instance.setRecordingsSavePath(path);
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = '저장 폴더를 설정하지 못했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final steps = [
      _OnboardingStep(
        icon: Icons.lock_outline_rounded,
        title: '회의 내용은 내 Mac 밖으로 나가지 않습니다',
        description:
            '녹음, 음성 인식, 발화자 라벨, 요약은 모두 이 Mac 안에서 실행됩니다. 회의 음성이나 전사본을 외부 서버로 전송하지 않습니다.',
        points: const [
          _OnboardingPoint(
            icon: Icons.cloud_off_outlined,
            text: '회의 파일을 클라우드로 업로드하지 않습니다.',
          ),
          _OnboardingPoint(
            icon: Icons.computer_rounded,
            text: 'AI 처리는 로컬 모델로 이 Mac에서 실행됩니다.',
          ),
          _OnboardingPoint(
            icon: Icons.security_rounded,
            text: '네트워크가 불안정해도 회의록 작업을 계속할 수 있습니다.',
          ),
        ],
      ),
      _OnboardingStep(
        icon: Icons.memory_rounded,
        title: '음성 인식과 요약 모델을 한 번만 준비합니다',
        description:
            '처음에는 모델 다운로드가 필요합니다. 용량은 크지만, 설치 후에는 회의마다 외부 서비스 없이 사용할 수 있습니다.',
        points: const [
          _OnboardingPoint(
            icon: Icons.graphic_eq_rounded,
            text: '음성 인식 모델은 녹음 내용을 텍스트로 바꿉니다.',
          ),
          _OnboardingPoint(
            icon: Icons.auto_awesome_rounded,
            text: '요약 모델은 결정사항과 액션아이템을 정리합니다.',
          ),
          _OnboardingPoint(
            icon: Icons.label_outline_rounded,
            text: '발화자 라벨은 사람 이름이 아니라 A/B/C 흐름 보조입니다.',
          ),
        ],
      ),
      _OnboardingStep(
        icon: Icons.folder_open_rounded,
        title: '녹음 파일을 저장할 폴더를 선택하세요',
        description:
            '회의 녹음과 전사 데이터는 사용자가 선택한 폴더를 기준으로 관리됩니다. 나중에 설정에서 변경할 수 있습니다.',
        points: const [
          _OnboardingPoint(
            icon: Icons.folder_rounded,
            text: '회사 프로젝트 폴더나 개인 문서 폴더를 선택할 수 있습니다.',
          ),
          _OnboardingPoint(
            icon: Icons.edit_location_alt_outlined,
            text: '저장 위치는 설정 화면에서 언제든 변경할 수 있습니다.',
          ),
          _OnboardingPoint(
            icon: Icons.task_alt_rounded,
            text: '폴더 선택이 끝나면 앱 준비 화면으로 이동합니다.',
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
                                  label: const Text('이전'),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              flex: _step > 0 ? 2 : 1,
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
                                      ? '선택 중...'
                                      : isLastStep
                                      ? '저장 폴더 선택'
                                      : '다음',
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
