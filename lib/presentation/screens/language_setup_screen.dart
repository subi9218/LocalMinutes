import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../core/services/app_settings.dart';
import '../widgets/theme_tint.dart';

PageRouteBuilder<void> _instantRoute(Widget child) => PageRouteBuilder<void>(
  pageBuilder: (_, _, _) => child,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);

/// 첫 실행 시 표시 언어를 선택하는 화면.
///
/// 시스템 로케일을 기본 선택으로 미리 잡아두므로, 영어권 사용자(앱 심사자 포함)는
/// 그대로 '계속'만 누르면 영어로 진행할 수 있다.
class LanguageSetupScreen extends StatefulWidget {
  /// 선택된 언어 코드('ko'/'en')를 전달한다(루트 상태 동기화용).
  final ValueChanged<String> onSelected;

  /// '계속' 후 전환할 다음 화면. (이 앱은 home: 스왑이 아니라
  /// Navigator.pushReplacement로 화면을 전환한다.)
  final Widget nextScreen;

  const LanguageSetupScreen({
    super.key,
    required this.onSelected,
    required this.nextScreen,
  });

  @override
  State<LanguageSetupScreen> createState() => _LanguageSetupScreenState();
}

class _LanguageSetupScreenState extends State<LanguageSetupScreen> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    // 시스템 로케일 기반 기본 선택 (ko 계열 → ko, 그 외 → en)
    _selected = AppSettings.instance.effectiveLanguageCode;
  }

  Future<void> _continue() async {
    await AppSettings.instance.setLanguageCode(_selected);
    if (!mounted) return;
    widget.onSelected(_selected);
    // 명시적 화면 전환 (storage_setup_screen과 동일한 패턴)
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushReplacement(_instantRoute(widget.nextScreen));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MacosWindow(
      disableWallpaperTinting: true,
      child: MacosScaffold(
        children: [
          ContentArea(
            builder: (context, scrollController) => Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.translate_rounded,
                          size: 48,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Local Minutes',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '언어를 선택하세요  ·  Choose your language',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _LanguageOption(
                          label: '한국어',
                          sublabel: 'Korean',
                          selected: _selected == 'ko',
                          onTap: () => setState(() => _selected = 'ko'),
                          scheme: scheme,
                        ),
                        const SizedBox(height: 10),
                        _LanguageOption(
                          label: 'English',
                          sublabel: '영어',
                          selected: _selected == 'en',
                          onTap: () => setState(() => _selected = 'en'),
                          scheme: scheme,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _continue,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _selected == 'en' ? 'Continue' : '계속',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _selected == 'en'
                              ? 'You can change this later in Settings.'
                              : '나중에 설정에서 변경할 수 있습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade500,
                          ),
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

class _LanguageOption extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _LanguageOption({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.08)
              : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.6)
                : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? scheme.primary : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}
