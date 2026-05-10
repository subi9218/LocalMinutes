import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionCredit extends StatelessWidget {
  const AppVersionCredit({
    super.key,
    this.compact = false,
    this.badgeBackgroundColor,
    this.badgeBorderColor,
    this.versionColor,
    this.creditColor,
  });

  final bool compact;
  final Color? badgeBackgroundColor;
  final Color? badgeBorderColor;
  final Color? versionColor;
  final Color? creditColor;

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final effectiveBadgeBackground =
        badgeBackgroundColor ??
        (compact ? primary.withValues(alpha: 0.08) : Colors.grey.shade100);
    final effectiveVersionColor =
        versionColor ??
        (compact ? primary.withValues(alpha: 0.7) : Colors.grey.shade500);
    final effectiveCreditColor = creditColor ?? Colors.grey.shade400;

    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final package = snapshot.data;
        final versionLabel = package == null ? 'v...' : 'v${package.version}';
        final buildNumber = package?.buildNumber ?? '';
        final tooltip = buildNumber.isEmpty
            ? versionLabel
            : '$versionLabel (build $buildNumber)';

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Tooltip(
              message: tooltip,
              child: Container(
                padding: compact
                    ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                    : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: effectiveBadgeBackground,
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                  border: badgeBorderColor == null
                      ? null
                      : Border.all(color: badgeBorderColor!),
                ),
                child: Text(
                  versionLabel,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
                    color: effectiveVersionColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            SizedBox(width: compact ? 6 : 8),
            if (!compact) ...[
              Text(
                '·',
                style: TextStyle(fontSize: 11, color: effectiveCreditColor),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              'by 수비짱',
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                color: effectiveCreditColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      },
    );
  }
}
