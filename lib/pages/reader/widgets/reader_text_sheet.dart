import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../providers/reader_settings_provider.dart';

/// 阅读器「字体/字号」底部面板。
///
/// 只包含两个控件：字号 slider + 字体族按钮组。
/// 边距 / 行距 / 阅读模式（上下/左右）见 CLAUDE.md Todolist，后续阶段再加。
Future<void> showReaderTextSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (_) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: const _ReaderTextSheet(),
    ),
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

          // ── 字号 ──
          _sectionLabel(theme, cs, '字号', '${_localFontSize.round()}px'),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 16),
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
          _sectionLabel(theme, cs, '字体', settings.font.label),
          const SizedBox(height: 12),
          _FontFamilyRow(
            current: settings.font,
            onChanged: notifier.setFont,
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
      ThemeData theme, ColorScheme cs, String title, String? trailing) {
    return Row(
      children: [
        Icon(
          title == '字号' ? Symbols.format_size_rounded : Symbols.text_fields_rounded,
          size: 18,
          color: cs.primary,
        ),
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
