import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/animation_constants.dart';
import '../../widgets/tactile_press.dart';

/// 小圆角标签：用于标注"默认 / 快速"等模型角色。
class RoleBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const RoleBadge({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// 场景角色切换条目——用于"添加模型"对话框内
///
/// 整行 TactilePress 可点；关闭态为浅色 surface，开启态容器色上升一档；
/// 替换提示以 AnimatedSize 展开，避免常态占高。
class RoleToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color containerColor;
  final Color onContainerColor;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? replacingText;

  const RoleToggleTile({
    super.key,
    required this.icon,
    required this.label,
    required this.containerColor,
    required this.onContainerColor,
    required this.value,
    required this.onChanged,
    this.replacingText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onChanged != null;
    final showWarn = replacingText != null && (value || !enabled);

    return AnimatedContainer(
      duration: kAnim,
      curve: kAnimCurve,
      decoration: BoxDecoration(
        color: !enabled
            ? cs.surfaceContainerHighest.withAlpha(60)
            : value
                ? containerColor.withAlpha(90)
                : cs.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value ? containerColor : cs.outlineVariant.withAlpha(70),
          width: value ? 1.2 : 1,
        ),
      ),
      child: TactilePress(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onChanged!(!value) : null,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: kAnim,
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: value ? containerColor : cs.surface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 20,
                    color: value ? onContainerColor : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
            AnimatedSize(
              duration: kAnim,
              curve: kAnimCurve,
              child: showWarn
                  ? Padding(
                      padding: const EdgeInsets.only(
                          left: 52, top: 6, right: 4),
                      child: Row(
                        children: [
                          Icon(
                            Symbols.swap_horiz_rounded,
                            size: 14,
                            color: cs.tertiary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              replacingText!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.tertiary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
