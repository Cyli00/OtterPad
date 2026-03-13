import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/reader_settings_provider.dart';
import '../../providers/theme_provider.dart';

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeState = ref.watch(themeProvider);
    final settings = ref.watch(readerSettingsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          '外观设置',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ).copyWith(bottom: 40),
        children: [
          // ── 主题模式 ──
          _buildGroup(
            context,
            title: '主题模式',
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('自动'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.wb_sunny_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {themeState.mode},
                  onSelectionChanged: (set) {
                    final mode = set.first;
                    ref.read(themeProvider.notifier).setThemeMode(mode);
                    _syncReaderTheme(ref, context, mode);
                  },
                  style: SegmentedButton.styleFrom(
                    backgroundColor: cs.surface,
                    selectedBackgroundColor: cs.primaryContainer,
                    side: BorderSide(
                      color: cs.outlineVariant.withAlpha(100),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── 主题色彩 ──
          _buildGroup(
            context,
            title: '主题色彩',
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildColorGrid(context, ref, themeState),
            ),
          ),

          // ── 阅读设置 ──
          _buildGroup(
            context,
            title: '阅读设置',
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '默认阅读模式',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<DefaultReadingMode>(
                      segments: DefaultReadingMode.values
                          .map(
                            (m) => ButtonSegment(
                              value: m,
                              label: Text(m.label),
                            ),
                          )
                          .toList(),
                      selected: {settings.defaultReadingMode},
                      onSelectionChanged: (set) => ref
                          .read(readerSettingsProvider.notifier)
                          .setDefaultReadingMode(set.first),
                      style: SegmentedButton.styleFrom(
                        backgroundColor: cs.surface,
                        selectedBackgroundColor: cs.primaryContainer,
                        side: BorderSide(
                          color: cs.outlineVariant.withAlpha(100),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '选择 Markdown 时，若文档无提取结果将自动回退到 PDF 视图',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 切换应用主题模式时，同步更新阅读器内部主题
  void _syncReaderTheme(WidgetRef ref, BuildContext context, ThemeMode mode) {
    final ReaderTheme readerTheme;
    if (mode == ThemeMode.dark) {
      readerTheme = ReaderTheme.dark;
    } else if (mode == ThemeMode.light) {
      readerTheme = ReaderTheme.light;
    } else {
      // 跟随系统：取当前平台亮度
      final brightness = MediaQuery.platformBrightnessOf(context);
      readerTheme =
          brightness == Brightness.dark ? ReaderTheme.dark : ReaderTheme.light;
    }
    ref.read(readerSettingsProvider.notifier).setTheme(readerTheme);
  }

  Widget _buildColorGrid(
    BuildContext context,
    WidgetRef ref,
    ThemeState themeState,
  ) {
    final isDynamic = themeState.useDynamicColor;

    final allItems = <Widget>[
      _ColorCircle(
        isDynamic: true,
        isSelected: isDynamic,
        onTap: () => ref.read(themeProvider.notifier).setUseDynamicColor(true),
      ),
      for (final color in ThemeNotifier.presetColors)
        _ColorCircle(
          color: color,
          isSelected:
              !isDynamic && color.toARGB32() == themeState.seedColor.toARGB32(),
          onTap: () => ref.read(themeProvider.notifier).setSeedColor(color),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const itemSize = 48.0;
        const minSpacing = 12.0;
        final crossAxisCount =
            ((constraints.maxWidth + minSpacing) / (itemSize + minSpacing))
                .floor();
        final spacing = (constraints.maxWidth - crossAxisCount * itemSize) /
            (crossAxisCount - 1);

        return Wrap(
          spacing: spacing,
          runSpacing: 12,
          children: allItems,
        );
      },
    );
  }

  Widget _buildGroup(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12, top: 24),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}

// ── 色彩选择圆形按钮 ──

class _ColorCircle extends StatelessWidget {
  final Color? color;
  final bool isDynamic;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorCircle({
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
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? cs.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isDynamic ? cs.primary : color!)
                        .withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
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
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 20,
                ),
              )
            : _ThemeColorPreview(seedColor: color!),
      ),
    );
  }
}

// ── 色彩预览饼图 ──

class _ThemeColorPreview extends StatelessWidget {
  final Color seedColor;
  const _ThemeColorPreview({required this.seedColor});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: seedColor);
    return ClipOval(
      child: CustomPaint(
        size: const Size(44, 44),
        painter: _PieChartPainter(scheme),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final ColorScheme scheme;
  _PieChartPainter(this.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()..style = PaintingStyle.fill;

    // 左半圆：primary
    paint.color = scheme.primary;
    canvas.drawArc(rect, 0.5 * pi, pi, true, paint);

    // 右上 1/4：primaryContainer
    paint.color = scheme.primaryContainer;
    canvas.drawArc(rect, 1.5 * pi, 0.5 * pi, true, paint);

    // 右下 1/4：tertiary
    paint.color = scheme.tertiary;
    canvas.drawArc(rect, 0, 0.5 * pi, true, paint);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter old) =>
      old.scheme != scheme;
}
