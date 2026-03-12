import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/reader_settings_provider.dart';

/// 阅读器外观设置浮层
///
/// 从工具栏 "A" 按钮下方弹出，包含主题 / 字体 / 字号三组设置。
/// 字号 Slider 仅在松手时写入 Provider（方案 A），拖动过程零重建。
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
      borderRadius: BorderRadius.circular(16),
      color: cs.surfaceContainerHigh,
      surfaceTintColor: cs.surfaceTint,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 主题 ──
              Text(
                'Theme:',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _ThemeSelector(
                current: settings.theme,
                onChanged: notifier.setTheme,
              ),

              const SizedBox(height: 16),

              // ── 字体 ──
              Text(
                'Font:',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _FontSelector(
                current: settings.font,
                onChanged: notifier.setFont,
              ),

              const SizedBox(height: 16),

              // ── 字号 ──
              Text(
                'Font size:',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 220,
                child: SliderTheme(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主题选择行：Light / Sepia / Dark
class _ThemeSelector extends StatelessWidget {
  final ReaderTheme current;
  final ValueChanged<ReaderTheme> onChanged;

  const _ThemeSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ReaderTheme.values.map((t) {
        final selected = t == current;
        return Padding(
          padding: EdgeInsets.only(
            right: t != ReaderTheme.values.last ? 8 : 0,
          ),
          child: _OptionChip(
            label: t.label,
            selected: selected,
            onTap: () => onChanged(t),
          ),
        );
      }).toList(),
    );
  }
}

/// 字体选择行：Serif / Sans / Mono
class _FontSelector extends StatelessWidget {
  final ReaderFont current;
  final ValueChanged<ReaderFont> onChanged;

  const _FontSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ReaderFont.values.map((f) {
        final selected = f == current;
        return Padding(
          padding: EdgeInsets.only(
            right: f != ReaderFont.values.last ? 8 : 0,
          ),
          child: _OptionChip(
            label: f.label,
            selected: selected,
            onTap: () => onChanged(f),
          ),
        );
      }).toList(),
    );
  }
}

/// 统一的可选芯片按钮
class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.secondaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 60, minHeight: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
          ),
        ),
      ),
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

      // 面板宽度约 260，右对齐于按钮
      const panelWidth = 260.0;
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
