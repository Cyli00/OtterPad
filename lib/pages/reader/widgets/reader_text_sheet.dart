import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../providers/reader_settings_provider.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../services/translation_style.dart';
import 'reader_background.dart';

/// 阅读器「字体/字号 + 翻页方式 + 译文样式」底部面板。
///
/// 控件：字号 slider、字体族按钮组、翻页方式按钮组、译文样式按钮组。
/// 边距 / 行距见 CLAUDE.md Todolist，后续阶段再加。
Future<void> showReaderTextSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (_) => const ReaderLocalTheme(child: _ReaderTextSheet()),
  );
}

class _ReaderTextSheet extends ConsumerStatefulWidget {
  const _ReaderTextSheet();

  @override
  ConsumerState<_ReaderTextSheet> createState() => _ReaderTextSheetState();
}

class _ReaderTextSheetState extends ConsumerState<_ReaderTextSheet> {
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
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final translationCfg = ref.watch(translationConfigProvider);
    final currentStyle = resolveTranslationStyle(translationCfg.displayStyleId);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      // 加入译文样式后高度可能超出 9/16 屏幕上限——包一层 ScrollView，
      // 与 reader_theme_sheet 同款防 overflow。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(cs),
            const SizedBox(height: 4),

            // ── 字号 ──
            _sectionLabel(
              theme,
              cs,
              Symbols.format_size_rounded,
              '字号',
              '${_localFontSize.round()}px',
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
              '字体',
              settings.font.label,
            ),
            const SizedBox(height: 12),
            _FontFamilyRow(current: settings.font, onChanged: notifier.setFont),

            const SizedBox(height: 16),

            // ── 翻页方式 ──
            _sectionLabel(
              theme,
              cs,
              Symbols.menu_book_rounded,
              '翻页方式',
              settings.paginationMode.label,
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
              '译文样式',
              currentStyle.label,
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
    String title,
    String? trailing,
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
            child: Material(
              color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
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
            child: Material(
              color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
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
            return Material(
              color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => ref
                    .read(translationConfigProvider.notifier)
                    .setDisplayStyleId(s.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
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
    final base = theme.textTheme.bodyMedium!;
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
