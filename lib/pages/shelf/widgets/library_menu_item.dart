import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/design_tokens.dart';
import '../../../widgets/tactile_press.dart';

/// 目录式条目：无色块图标 + 标题 + 等宽计数 + 箭头，条目之间是细线。
///
/// 像一本书的目录页，而不是一列彩色图标按钮。
class LibraryMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  /// 右侧计数；为 0 或 null 时不显示。
  final int? count;

  /// 计数需要引起注意（如无文件条目）：用错误色。
  final bool alert;

  /// 是否在条目下方画细线（最后一项传 false）。
  final bool divider;

  const LibraryMenuItem({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
    this.count,
    this.alert = false,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(bottom: AppStroke.side(cs)) : null,
      ),
      child: TactilePress(
        onTap: onTap,
        baseColor: Colors.transparent,
        borderRadius: AppRadius.smAll,
        pressedScale: 0.99,
        padding: const EdgeInsets.symmetric(vertical: AppSpace.x4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: AppSpace.x4),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (count != null && count! > 0) ...[
              Text(
                '$count',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFeatures: AppType.tabular,
                  color: alert ? cs.error : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpace.x3),
            ],
            Icon(Symbols.arrow_forward_rounded, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}
