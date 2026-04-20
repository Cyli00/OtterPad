import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../providers/reader_settings_provider.dart';
import '../../../providers/theme_provider.dart';
import 'reader_background.dart';

/// 阅读器「主题色 + 背景」底部面板。
///
/// 结构：
/// - **颜色**：复用 [themeProvider] 的 seed color（与设置页的色板对齐）；
/// - **背景**：4 个固定选项 — 主题色 / 白 / 羊皮纸 / 黑，落到 [ReaderTheme] 枚举上。
Future<void> showReaderThemeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (_) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: const _ReaderThemeSheet(),
    ),
  );
}

class _ReaderThemeSheet extends ConsumerWidget {
  const _ReaderThemeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeState = ref.watch(themeProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grabber(cs),
          const SizedBox(height: 4),

          // ── 颜色（主题色） ──
          _sectionLabel(theme, cs, Symbols.palette_rounded, '颜色'),
          const SizedBox(height: 12),
          _SeedColorRow(
            selected: themeState.useDynamicColor ? null : themeState.seedColor,
            isDynamic: themeState.useDynamicColor,
            onDynamic: () =>
                ref.read(themeProvider.notifier).setUseDynamicColor(true),
            onSelect: (c) =>
                ref.read(themeProvider.notifier).setSeedColor(c),
          ),

          const SizedBox(height: 20),

          // ── 背景 ──
          _sectionLabel(theme, cs, Symbols.wallpaper_rounded, '背景'),
          const SizedBox(height: 12),
          _BackgroundRow(
            current: readerSettings.theme,
            onChanged: (t) =>
                ref.read(readerSettingsProvider.notifier).setTheme(t),
          ),

          const SizedBox(height: 20),

          // ── 工具栏透明度 ──
          _sectionLabel(theme, cs, Symbols.blur_on_rounded, '工具栏透明度'),
          const SizedBox(height: 12),
          _OpacityRow(
            current: readerSettings.toolbarOpacity,
            onChanged: (o) =>
                ref.read(readerSettingsProvider.notifier).setToolbarOpacity(o),
          ),
        ],
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
      ThemeData theme, ColorScheme cs, IconData icon, String title) {
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
      _ColorDot(
        isDynamic: true,
        isSelected: isDynamic,
        onTap: onDynamic,
      ),
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
        final count = ((constraints.maxWidth + minSpacing) / (size + minSpacing))
            .floor()
            .clamp(1, items.length);
        final spacing = count > 1
            ? (constraints.maxWidth - count * size) / (count - 1)
            : 0.0;
        return Wrap(
          spacing: spacing,
          runSpacing: 10,
          children: items,
        );
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
      onTap: onTap,
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
                  Symbols.auto_awesome,
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

// ── 工具栏透明度选择行：4 档预设，视觉对齐背景选择行 ──

class _OpacityRow extends StatelessWidget {
  final ToolbarOpacity current;
  final ValueChanged<ToolbarOpacity> onChanged;

  const _OpacityRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: ToolbarOpacity.values.map((o) {
        final selected = o == current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: o != ToolbarOpacity.values.last ? 10 : 0,
            ),
            child: GestureDetector(
              onTap: () => onChanged(o),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? cs.primary : cs.outlineVariant,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13.5),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(painter: _CheckerPainter(cs: cs)),
                          ColoredBox(
                            color: cs.surface.withValues(alpha: o.value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    o.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 棋盘格底纹，用来直观展示透明度差异
class _CheckerPainter extends CustomPainter {
  final ColorScheme cs;
  _CheckerPainter({required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    const step = 8.0;
    final light = Paint()..color = cs.surfaceContainerHighest;
    final dark = Paint()..color = cs.outlineVariant.withAlpha(60);
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        final isEven = ((x ~/ step) + (y ~/ step)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, step, step),
          isEven ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) => cs != old.cs;
}

// ── 背景选择行：4 个圆形色块对应 ReaderTheme ──

class _BackgroundRow extends StatelessWidget {
  final ReaderTheme current;
  final ValueChanged<ReaderTheme> onChanged;

  const _BackgroundRow({required this.current, required this.onChanged});

  static const _labels = {
    ReaderTheme.themed: '主题',
    ReaderTheme.sepia: '羊皮',
    ReaderTheme.night: '夜间',
    ReaderTheme.dark: '纯黑',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: ReaderTheme.values.map((t) {
        final bg = resolveReaderBackground(t, cs);
        final selected = t == current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: t != ReaderTheme.values.last ? 10 : 0,
            ),
            child: GestureDetector(
              onTap: () => onChanged(t),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    height: 56,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? cs.primary : cs.outlineVariant,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: t == ReaderTheme.themed
                        ? Icon(
                            Symbols.auto_awesome,
                            size: 18,
                            color: cs.onPrimaryContainer,
                          )
                        : Container(
                            width: 28,
                            height: 3,
                            decoration: BoxDecoration(
                              color: resolveReaderTextColor(t, cs)
                                  .withAlpha(120),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _labels[t] ?? t.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: selected ? cs.primary : cs.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

