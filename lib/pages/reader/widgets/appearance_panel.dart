import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/reader_settings_provider.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 阅读器外观设置浮层
///
/// 从工具栏 "A" 按钮下方弹出，包含字体族 / 字号 / 主题预设三组设置。
/// 字号 Slider 仅在松手时写入 Provider，拖动过程零重建。
class AppearancePanel extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  const AppearancePanel({super.key, required this.onDismiss});

  @override
  ConsumerState<AppearancePanel> createState() => _AppearancePanelState();
}

class _AppearancePanelState extends ConsumerState<AppearancePanel> {
  late double _localFontSize;

  @override
  void initState() {
    super.initState();
    _localFontSize = ref.read(readerSettingsProvider).fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      color: cs.surfaceContainerHigh,
      surfaceTintColor: cs.surfaceTint,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 字体族 ──
            _SectionTitle(
              icon: Symbols.text_fields,
              title: '字体',
            ),
            const SizedBox(height: 12),
            _FontFamilySelector(
              current: settings.font,
              onChanged: notifier.setFont,
            ),

            const SizedBox(height: 24),

            // ── 字号 ──
            Row(
              children: [
                _SectionTitle(
                  icon: Symbols.format_size,
                  title: '字号',
                ),
                const Spacer(),
                Text(
                  '${_localFontSize.round()}px',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 8,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 16,
                ),
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.surfaceContainerHighest,
                thumbColor: cs.primary,
              ),
              child: Slider(
                value: _localFontSize,
                min: ReaderSettingsState.minFontSize,
                max: ReaderSettingsState.maxFontSize,
                onChanged: (v) => setState(() => _localFontSize = v),
                onChangeEnd: notifier.setFontSize,
              ),
            ),

            const SizedBox(height: 24),

            // ── 主题预设 ──
            _SectionTitle(
              icon: Symbols.palette,
              title: '主题预设',
            ),
            const SizedBox(height: 12),
            _ThemePresetSelector(
              current: settings.theme,
              onChanged: notifier.setTheme,
            ),
          ],
        ),
      ),
    );
  }
}

/// 分区标题：图标 + 文字
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: tt.titleSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 字体族选择：大圆角卡片，用对应字体渲染名称作为预览
class _FontFamilySelector extends StatelessWidget {
  final ReaderFont current;
  final ValueChanged<ReaderFont> onChanged;

  const _FontFamilySelector({
    required this.current,
    required this.onChanged,
  });

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
              color: selected
                  ? cs.primaryContainer
                  : cs.surfaceContainerLow,
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
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
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

/// 主题预设选择：可视化预览卡片
class _ThemePresetSelector extends StatelessWidget {
  final ReaderTheme current;
  final ValueChanged<ReaderTheme> onChanged;

  const _ThemePresetSelector({
    required this.current,
    required this.onChanged,
  });

  /// 每个主题的预览配色
  static const _previewColors = {
    ReaderTheme.light: (bg: Color(0xFFFFFFFF), line: Color(0xFF444444)),
    ReaderTheme.sepia: (bg: Color(0xFFF5EDDC), line: Color(0xFF6B5D4A)),
    ReaderTheme.dark: (bg: Color(0xFF1C1B1F), line: Color(0xFFB0B0B0)),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: ReaderTheme.values.map((t) {
        final selected = t == current;
        final colors = _previewColors[t]!;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: t != ReaderTheme.values.last ? 10 : 0,
            ),
            child: GestureDetector(
              onTap: () => onChanged(t),
              child: Column(
                children: [
                  // 预览卡片
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? cs.primary : cs.outlineVariant,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: colors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 标签
                  Text(
                    t.label,
                    style: tt.labelMedium?.copyWith(
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

/// 在指定 [anchorKey] 按钮下方展示外观设置浮层。
/// [onDismiss] 在面板因点击外部而关闭时调用，用于清除调用方的引用。
OverlayEntry showAppearancePanel({
  required BuildContext context,
  required GlobalKey anchorKey,
  required WidgetRef ref,
  VoidCallback? onDismiss,
}) {
  late OverlayEntry entry;

  void dismiss() {
    entry.remove();
    onDismiss?.call();
  }

  entry = OverlayEntry(
    builder: (overlayContext) {
      final renderBox =
          anchorKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) {
        return const SizedBox.shrink();
      }
      final offset = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final screenWidth = MediaQuery.sizeOf(context).width;

      const panelWidth = 320.0;
      final right = screenWidth - offset.dx - size.width;
      final top = offset.dy + size.height + 4;

      return Stack(
        children: [
          // 透明遮罩，点击关闭
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            top: top,
            right: right.clamp(8, screenWidth - panelWidth - 8),
            child: SizedBox(
              width: panelWidth,
              child: UncontrolledProviderScope(
                container: ProviderScope.containerOf(context),
                child: AppearancePanel(onDismiss: dismiss),
              ),
            ),
          ),
        ],
      );
    },
  );

  Overlay.of(context).insert(entry);
  return entry;
}
