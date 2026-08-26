import 'package:flutter/material.dart';
import '../../core/elevation.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../widgets/tactile_press.dart';

/// 设置页单选 picker：折叠态一行 + bottom sheet 列出全部选项。
///
/// 决策见 `flutter-design` skill §3.6 / §3.8：
/// 选项 ≥ 4 或 (选项 ≥ 3 且任一标签 ≥ 5 字符) 时替代 SegmentedButton——
/// SegmentedButton 等分宽度在此场景会触发 ellipsis 截断或竖向折断。
class SettingPicker<T> extends StatelessWidget {
  final T current;
  final List<T> options;
  final String Function(T) labelFor;
  final String Function(T)? subtitleFor;
  final String sheetTitle;
  final ValueChanged<T> onChanged;

  const SettingPicker({
    super.key,
    required this.current,
    required this.options,
    required this.labelFor,
    this.subtitleFor,
    required this.sheetTitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return TactilePress(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showSheet(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withAlpha(100)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                labelFor(current),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Symbols.expand_more_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // 桌面端窗口宽时 sheet 居中不撑满全宽，避免 1080p 屏上字横跨整屏。
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final maxH = MediaQuery.sizeOf(ctx).height * 0.7;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: AppShadows.sheet,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    sheetTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).padding.bottom + 16,
                  ),
                  children: options.map((opt) {
                    final isSelected = opt == current;
                    final subtitle = subtitleFor?.call(opt);
                    return TactilePress(
                      baseColor: Colors.transparent,
                      onTap: () => Navigator.pop(ctx, opt),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  labelFor(opt),
                                  style:
                                      theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurface,
                                  ),
                                ),
                                if (subtitle != null && subtitle.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      subtitle,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Symbols.check_rounded,
                              size: 20,
                              color: cs.primary,
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected != null && selected != current) {
      onChanged(selected);
    }
  }
}
