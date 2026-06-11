import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/haptics.dart';
import 'reader_background.dart';

/// 阅读器「主题色 + 背景」底部面板 body。
///
/// 由 [ReaderSheetHost] 弹出，不再自带 [showModalBottomSheet] 包装。
/// 颜色复用 [themeProvider] 的 seed color（与设置页的色板对齐）；
/// 背景 5 选项落到 [ReaderTheme] 枚举，仅影响阅读器局部主题。
class ReaderThemeSheetBody extends ConsumerWidget {
  const ReaderThemeSheetBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeState = ref.watch(themeProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      // 包一层 ScrollView：窗口高度被 showModalBottomSheet 的 9/16 上限
      // 压到小于内容自然高度时，允许内部滚动而不是报 RenderFlex overflow。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(cs),
            const SizedBox(height: 4),

            // ── 颜色（主题色） ──
            _sectionLabel(theme, cs, Symbols.palette_rounded, context.l10n.color),
            const SizedBox(height: 12),
            _SeedColorRow(
              selected: themeState.useDynamicColor
                  ? null
                  : themeState.seedColor,
              isDynamic: themeState.useDynamicColor,
              onDynamic: () =>
                  ref.read(themeProvider.notifier).setUseDynamicColor(true),
              onSelect: (c) => ref.read(themeProvider.notifier).setSeedColor(c),
            ),

            const SizedBox(height: 20),

            // ── 背景 ──
            _sectionLabel(theme, cs, Symbols.wallpaper_rounded, context.l10n.background),
            const SizedBox(height: 12),
            _BackgroundRow(
              current: readerSettings.theme,
              onChanged: (t) {
                ref.read(readerSettingsProvider.notifier).setTheme(t);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _grabber(ColorScheme cs) {
    return Center(
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant.withAlpha(80),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _sectionLabel(
    ThemeData theme,
    ColorScheme cs,
    IconData icon,
    String title,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ── 颜色选择行：动态色 + 预设 seed colors，与设置页的 _buildColorGrid 视觉对齐 ──

class _SeedColorRow extends StatelessWidget {
  final Color? selected;
  final bool isDynamic;
  final VoidCallback onDynamic;
  final ValueChanged<Color> onSelect;

  const _SeedColorRow({
    required this.selected,
    required this.isDynamic,
    required this.onDynamic,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _ColorDot(isDynamic: true, isSelected: isDynamic, onTap: onDynamic),
      for (final color in ThemeNotifier.presetColors)
        _ColorDot(
          color: color,
          isSelected: !isDynamic && color.toARGB32() == selected?.toARGB32(),
          onTap: () => onSelect(color),
        ),
    ];

    return LayoutBuilder(
      builder: (_, constraints) {
        const size = 40.0;
        const minSpacing = 8.0;
        final count =
            ((constraints.maxWidth + minSpacing) / (size + minSpacing))
                .floor()
                .clamp(1, items.length);
        final spacing = count > 1
            ? (constraints.maxWidth - count * size) / (count - 1)
            : 0.0;
        return Wrap(spacing: spacing, runSpacing: 10, children: items);
      },
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color? color;
  final bool isDynamic;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorDot({
    this.color,
    this.isDynamic = false,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        Haptics.soft();
        onTap();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: isDynamic
            ? Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Colors.blue,
                      Colors.purple,
                      Colors.green,
                      Colors.orange,
                      Colors.blue,
                    ],
                  ),
                ),
                child: const Icon(
                  Symbols.auto_awesome_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ColorScheme.fromSeed(seedColor: color!).primary,
                ),
              ),
      ),
    );
  }
}

// ── 背景选择行：5 个圆形色块对应 ReaderTheme ──

class _BackgroundRow extends StatelessWidget {
  final ReaderTheme current;
  final ValueChanged<ReaderTheme> onChanged;

  const _BackgroundRow({required this.current, required this.onChanged});

  /// 视觉展示顺序：浅色先、深色后；独立于 `ReaderTheme.values` 的声明顺序
  /// （后者被 Hive 的 `.index` 锁定，不能随意调整）。
  static const _displayOrder = <ReaderTheme>[
    ReaderTheme.themed,
    ReaderTheme.sepia,
    ReaderTheme.green,
    ReaderTheme.night,
    ReaderTheme.dark,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < _displayOrder.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: i == _displayOrder.length - 1 ? 0 : 10,
              ),
              child: _BackgroundCard(
                theme: _displayOrder[i],
                selected: _displayOrder[i] == current,
                cs: cs,
                onTap: () => onChanged(_displayOrder[i]),
              ),
            ),
          ),
      ],
    );
  }
}

/// 单个背景选择卡片：大色块 + 横条指示 + 短标签。
///
/// 抽成独立 widget 后，card 的 build 只依赖 4 个参数（theme/selected/cs/onTap），
/// 外层 sheet rebuild 时若参数未变 Flutter 能复用 Element 树。
class _BackgroundCard extends StatelessWidget {
  final ReaderTheme theme;
  final bool selected;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _BackgroundCard({
    required this.theme,
    required this.selected,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final previewCs = ColorScheme.fromSeed(
      seedColor: cs.primary,
      brightness: theme.brightness,
    );
    final palette = resolveReaderPalette(theme, previewCs);
    final previewBg = palette.background;
    final previewLine = palette.text.withAlpha(120);
    return GestureDetector(
      onTap: () {
        Haptics.soft();
        onTap();
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: kAnimFast,
            curve: kAnimCurve,
            height: 56,
            decoration: BoxDecoration(
              color: previewBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: previewLine,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            theme.shortLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? cs.primary : cs.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
