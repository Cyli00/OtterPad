import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/elevation.dart';
import '../../../core/l10n.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../services/haptics.dart';
import '../../../services/translation_style.dart';
import '../../../widgets/tactile_press.dart';
import 'reader_background.dart';

/// 阅读器「外观」底部面板 body：
/// 主题色 / 背景 / 字号 / 字体 / 翻页方式 / 译文样式。
///
/// 由 [ReaderSheetHost] 弹出，不再自带 [showModalBottomSheet] 包装。
/// 颜色复用 [themeProvider] 的 seed color（与设置页的色板对齐）；
/// 背景 5 选项落到 [ReaderTheme] 枚举，仅影响阅读器局部主题。
class ReaderThemeSheetBody extends ConsumerStatefulWidget {
  const ReaderThemeSheetBody({super.key});

  @override
  ConsumerState<ReaderThemeSheetBody> createState() =>
      _ReaderThemeSheetBodyState();
}

class _ReaderThemeSheetBodyState extends ConsumerState<ReaderThemeSheetBody> {
  late double _localFontSize;

  @override
  void initState() {
    super.initState();
    _localFontSize = ref.read(readerSettingsProvider).fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeState = ref.watch(themeProvider);
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final l10n = context.l10n;
    final translationCfg = ref.watch(translationConfigProvider);
    final currentStyle = resolveTranslationStyle(translationCfg.displayStyleId);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: AppShadows.sheet,
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      // 六个 section 高度必然超出 9/16 屏幕上限——包一层 ScrollView，
      // 允许内部滚动而不是报 RenderFlex overflow。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(cs),
            const SizedBox(height: 4),

            // ── 颜色（主题色） ──
            _sectionLabel(theme, cs, Symbols.palette_rounded, l10n.color),
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
            _sectionLabel(
              theme,
              cs,
              Symbols.wallpaper_rounded,
              l10n.background,
            ),
            const SizedBox(height: 12),
            _BackgroundRow(
              current: settings.theme,
              onChanged: (t) {
                ref.read(readerSettingsProvider.notifier).setTheme(t);
              },
            ),

            const SizedBox(height: 20),

            // ── 字号 ──
            _sectionLabel(
              theme,
              cs,
              Symbols.format_size_rounded,
              l10n.fontSize,
              trailing: '${_localFontSize.round()}px',
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: _localFontSize,
                min: ReaderSettingsState.minFontSize,
                max: ReaderSettingsState.maxFontSize,
                onChanged: (v) => setState(() => _localFontSize = v),
                onChangeEnd: notifier.setFontSize,
              ),
            ),

            const SizedBox(height: 16),

            // ── 字体族 ──
            _sectionLabel(
              theme,
              cs,
              Symbols.text_fields_rounded,
              l10n.fontFamily,
              trailing: settings.font.label,
            ),
            const SizedBox(height: 12),
            _FontFamilyRow(current: settings.font, onChanged: notifier.setFont),

            const SizedBox(height: 16),

            // ── 翻页方式 ──
            _sectionLabel(
              theme,
              cs,
              Symbols.menu_book_rounded,
              l10n.paginationMode,
              trailing: settings.paginationMode.label,
            ),
            const SizedBox(height: 12),
            _PaginationModeRow(
              current: settings.paginationMode,
              onChanged: notifier.setPaginationMode,
            ),

            const SizedBox(height: 20),

            // ── 译文样式 ──
            _sectionLabel(
              theme,
              cs,
              Symbols.translate_rounded,
              l10n.translationStyle,
              trailing: currentStyle.label,
            ),
            const SizedBox(height: 12),
            _TranslationStyleRow(currentId: translationCfg.displayStyleId),
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
    String title, {
    String? trailing,
  }) {
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
        const Spacer(),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              trailing,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
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

class _FontFamilyRow extends StatelessWidget {
  final ReaderFont current;
  final ValueChanged<ReaderFont> onChanged;

  const _FontFamilyRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: ReaderFont.values.map((f) {
        final selected = f == current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: f != ReaderFont.values.last ? 8 : 0,
            ),
            child: TactilePress(
              baseColor: selected
                  ? cs.primaryContainer
                  : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(f),
              child: AnimatedContainer(
                duration: kAnim,
                curve: kAnimCurve,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? cs.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontFamily: f.fontFamily,
                    fontFamilyFallback: f.fontFamilyFallback,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 翻页方式双选行——与 [_FontFamilyRow] 视觉骨架完全对齐
/// （高 56、圆角 12、`primaryContainer` 选中态、200ms easeOut）。
class _PaginationModeRow extends StatelessWidget {
  final ReaderPaginationMode current;
  final ValueChanged<ReaderPaginationMode> onChanged;

  const _PaginationModeRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: ReaderPaginationMode.values.map((m) {
        final selected = m == current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: m != ReaderPaginationMode.values.last ? 8 : 0,
            ),
            child: TactilePress(
              baseColor: selected
                  ? cs.primaryContainer
                  : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(m),
              child: AnimatedContainer(
                duration: kAnim,
                curve: kAnimCurve,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? cs.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      m == ReaderPaginationMode.vertical
                          ? Symbols.swap_vert_rounded
                          : Symbols.swap_horiz_rounded,
                      size: 18,
                      color: selected
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 译文样式选择行（横向滚动 + 边缘 fade 蒙版）。
///
/// 与 [_FontFamilyRow] 高度对齐（56），每张卡片宽度按内容自适应。
/// 8 个样式不像 3 个字体那样能等分一行，所以走横向 ListView——
/// 用 [ShaderMask] 在视口左右边缘做 6% 渐变蒙版，作为"可滑动"的
/// 视觉信号；监听 [ScrollController] 位置：滚到最左/最右时对应方向的
/// fade 自动隐藏，避免给出无意义的"还有内容"暗示。
/// 选中态用 `primaryContainer` 底 + `primary` 边框，跟字体行同款；
/// 标签本身按各自样式渲染（粗体/斜体/虚线/模糊…）作为自描述预览。
class _TranslationStyleRow extends ConsumerStatefulWidget {
  final String currentId;
  const _TranslationStyleRow({required this.currentId});

  @override
  ConsumerState<_TranslationStyleRow> createState() =>
      _TranslationStyleRowState();
}

class _TranslationStyleRowState extends ConsumerState<_TranslationStyleRow> {
  final ScrollController _ctrl = ScrollController();
  // 默认假设右侧有溢出（首次构建时大概率 8 个 chip 排不下），
  // 首帧测量后再 _updateFade 校准。
  bool _fadeLeft = false;
  bool _fadeRight = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_updateFade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_updateFade);
    _ctrl.dispose();
    super.dispose();
  }

  void _updateFade() {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    // 4px 容差：避免在边缘附近因 fractional pixel 反复抖动。
    final left = pos.pixels > 4;
    final right = pos.pixels < pos.maxScrollExtent - 4;
    if (left != _fadeLeft || right != _fadeRight) {
      setState(() {
        _fadeLeft = left;
        _fadeRight = right;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final list = SizedBox(
      height: 56,
      child: NotificationListener<ScrollMetricsNotification>(
        // ListView 内容数量/容器宽度变化时也重新测一次 maxScrollExtent。
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
          return false;
        },
        child: ListView.separated(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: kTranslationStyles.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final s = kTranslationStyles[i];
            final selected = s.id == widget.currentId;
            return TactilePress(
              baseColor: selected
                  ? cs.primaryContainer
                  : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              onTap: () => ref
                  .read(translationConfigProvider.notifier)
                  .setDisplayStyleId(s.id),
              child: AnimatedContainer(
                duration: kAnim,
                curve: kAnimCurve,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? cs.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: _styledLabel(s.id, s.label, cs, theme),
              ),
            );
          },
        ),
      ),
    );

    // ShaderMask + dstIn：渐变 alpha 作为蒙版乘到 child 上，
    // 透明区域 = 隐藏，白色区域 = 完全显示。
    // 双向 fade 各占视口 6%，已滚到边缘的方向用纯白（不 fade）。
    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          _fadeLeft ? Colors.transparent : Colors.white,
          Colors.white,
          Colors.white,
          _fadeRight ? Colors.transparent : Colors.white,
        ],
        stops: const [0.0, 0.06, 0.94, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: list,
    );
  }

  /// 把样式 id 映射为"自描述 chip"的预览内容——文本本身就反映该样式特征。
  /// 与 translation_settings_section 的 _buildStyledLabel 视觉一致。
  Widget _styledLabel(
    String styleId,
    String label,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final base = theme.textTheme.bodyMedium!.copyWith(color: cs.onSurface);
    return switch (styleId) {
      'themed' => Text(label, style: base.copyWith(color: cs.primary)),
      'bold' => Text(label, style: base.copyWith(fontWeight: FontWeight.bold)),
      'italic' => Text(
        label,
        style: base.copyWith(fontStyle: FontStyle.italic),
      ),
      'weakened' => Text(
        label,
        style: base.copyWith(color: cs.onSurface.withAlpha(120)),
      ),
      'dashed' => Text(
        label,
        style: base.copyWith(
          color: cs.primary,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dashed,
          decorationColor: cs.primary.withAlpha(140),
        ),
      ),
      'highlight' => Text(
        label,
        style: base.copyWith(backgroundColor: cs.primaryContainer),
      ),
      'blur' => ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Text(label, style: base),
        ),
      ),
      'quote' => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: base.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
      _ => Text(label, style: base),
    };
  }
}
