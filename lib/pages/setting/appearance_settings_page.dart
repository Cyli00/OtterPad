import 'dart:math';

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../providers/locale_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/haptics.dart';
import '../../widgets/tactile_press.dart';
import 'package:material_symbols_icons/symbols.dart';

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final themeState = ref.watch(themeProvider);
    final settings = ref.watch(readerSettingsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: embedded ? null : AppBar(
        title: Text(
          l10n.appearanceSettings,
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
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12, top: 24),
            child: Text(
              l10n.themeMode,
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l10n.autoMode),
                    icon: const Icon(Symbols.brightness_auto_rounded),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l10n.lightMode),
                    icon: const Icon(Symbols.wb_sunny_rounded),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(l10n.darkMode),
                    icon: const Icon(Symbols.dark_mode_rounded),
                  ),
                ],
                selected: {themeState.mode},
                onSelectionChanged: (set) {
                  Haptics.soft();
                  final mode = set.first;
                  ref.read(themeProvider.notifier).setThemeMode(mode);
                },
                style: SegmentedButton.styleFrom(
                  backgroundColor: cs.surface,
                  selectedBackgroundColor: cs.primaryContainer,
                  side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),

          // ── 主题色彩 ──
          _buildGroup(
            context,
            title: l10n.themeColor,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildColorGrid(context, ref, themeState),
            ),
          ),

          // ── 阅读设置 ──
          _buildGroup(
            context,
            title: l10n.readingSettings,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.defaultReadingMode,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<DefaultReadingMode>(
                      segments:
                          const [
                                DefaultReadingMode.markdown,
                                DefaultReadingMode.pdf,
                              ]
                              .map(
                                (m) => ButtonSegment(
                                  value: m,
                                  label: Text(m.label),
                                ),
                              )
                              .toList(),
                      selected: {settings.defaultReadingMode},
                      onSelectionChanged: (set) {
                        Haptics.soft();
                        ref
                            .read(readerSettingsProvider.notifier)
                            .setDefaultReadingMode(set.first);
                      },
                      style: SegmentedButton.styleFrom(
                        backgroundColor: cs.surface,
                        selectedBackgroundColor: cs.primaryContainer,
                        side: BorderSide(
                          color: cs.outlineVariant.withAlpha(100),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.defaultReadingModeHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.systemTextScale,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _scaleLabel(
                            l10n,
                            _closestPreset(themeState.textScale),
                          ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _closestPreset(themeState.textScale),
                      min: 1.0,
                      max: 1.3,
                      divisions: 2,
                      onChanged: (v) {
                        Haptics.soft();
                        ref.read(themeProvider.notifier).setTextScale(v);
                      },
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.textSizeStandard,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          l10n.textSizeLarge,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          l10n.textSizeExtraLarge,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _AppLanguagePicker(ref: ref),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _scaleLabel(AppLocalizations l10n, double scale) {
    if (scale <= 1.0) return l10n.textSizeStandard;
    if (scale >= 1.3) return l10n.textSizeExtraLarge;
    return l10n.textSizeLarge;
  }

  double _closestPreset(double current) {
    final presets = ThemeNotifier.textScalePresets;
    double best = presets.first;
    double minDiff = (current - best).abs();
    for (final p in presets.skip(1)) {
      final diff = (current - p).abs();
      if (diff < minDiff) {
        minDiff = diff;
        best = p;
      }
    }
    return best;
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
        final spacing =
            (constraints.maxWidth - crossAxisCount * itemSize) /
            (crossAxisCount - 1);

        return Wrap(spacing: spacing, runSpacing: 12, children: allItems);
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
      onTap: () {
        Haptics.soft();
        onTap();
      },
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
                    color: (isDynamic ? cs.primary : color!).withValues(
                      alpha: 0.4,
                    ),
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
                  Symbols.auto_awesome_rounded,
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
  bool shouldRepaint(covariant _PieChartPainter old) => old.scheme != scheme;
}

// ── 应用语言选择器（视觉参照翻译设置目标语言 picker）──

class _AppLanguagePicker extends ConsumerWidget {
  final WidgetRef ref;
  const _AppLanguagePicker({required this.ref});

  static final _options = <(Locale?, String Function(AppLocalizations))>[
    (null, _systemLabel),
    (const Locale('zh'), _zhLabel),
    (const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), _zhHantLabel),
    (const Locale('en'), _enLabel),
  ];

  static String _systemLabel(AppLocalizations l10n) => l10n.languageSystem;
  static String _zhLabel(AppLocalizations l10n) => l10n.languageChinese;
  static String _zhHantLabel(AppLocalizations l10n) => l10n.languageTraditionalChinese;
  static String _enLabel(AppLocalizations l10n) => l10n.languageEnglish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final current = ref.watch(localeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                l10n.appLanguage,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: l10n.appLanguageDesc,
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 5),
              preferBelow: true,
              verticalOffset: 16,
              decoration: BoxDecoration(
                color: cs.inverseSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Symbols.help_rounded,
                    size: 16, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TactilePress(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showSheet(context, ref, current),
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
                    _displayName(l10n, current),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Symbols.expand_more_rounded,
                    size: 20, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _displayName(AppLocalizations l10n, Locale? locale) {
    if (locale == null) return l10n.languageSystem;
    if (locale.languageCode == 'zh' && locale.scriptCode == 'Hant') {
      return l10n.languageTraditionalChinese;
    }
    return switch (locale.languageCode) {
      'zh' => l10n.languageChinese,
      'en' => l10n.languageEnglish,
      _ => locale.languageCode,
    };
  }

  void _showSheet(BuildContext context, WidgetRef ref, Locale? current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final l10n = ctx.l10n;
        final maxH = MediaQuery.sizeOf(ctx).height * 0.5;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
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
                      l10n.appLanguage,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                ..._options.map((opt) {
                  final (locale, labelFn) = opt;
                  final isSelected = current == locale;
                  return TactilePress(
                    baseColor: Colors.transparent,
                    onTap: () {
                      ref.read(localeProvider.notifier).setLocale(locale);
                      Navigator.pop(ctx);
                    },
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            labelFn(l10n),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color:
                                  isSelected ? cs.primary : cs.onSurface,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Symbols.check_rounded,
                              color: cs.primary, size: 22),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
