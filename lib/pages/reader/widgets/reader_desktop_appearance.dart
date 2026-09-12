import '../../../l10n/reader_labels.dart';
import '../../../services/translation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/elevation.dart';
import '../../../core/l10n.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../widgets/app_divider.dart';
import '../../setting/setting_group.dart';
import '../../setting/setting_picker.dart';

class ReaderDesktopAppearance extends ConsumerWidget {
  const ReaderDesktopAppearance({
    super.key,
    required this.pdfView,
    required this.onClose,
  });

  final bool pdfView;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final translation = ref.watch(translationConfigProvider);
    const defaults = ReaderSettingsState();
    final backgrounds = {
      ReaderTheme.themed: l10n.readerThemeWhite,
      ReaderTheme.sepia: l10n.readerThemeSepia,
      ReaderTheme.green: l10n.readerThemeGreen,
      ReaderTheme.night: l10n.readerThemeNight,
      ReaderTheme.dark: l10n.readerThemeDark,
    };
    final translationStyles = {
      for (final style in kTranslationStyles)
        style.id: translationStyleLabel(l10n, style.id),
    };

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : kAnim,
      curve: kAnimCurve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withAlpha(80)),
          boxShadow: AppShadows.sheet,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Icon(Symbols.tune_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.appearance,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    tooltip: l10n.close,
                    icon: const Icon(Symbols.close_rounded),
                  ),
                ],
              ),
            ),
            const AppDivider.full(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!pdfView)
                      SettingGroup(
                        title: l10n.readerTextAppearance,
                        child: Column(
                          children: [
                            _field(
                              context,
                              l10n.background,
                              SettingPicker<ReaderTheme>(
                                current: settings.theme,
                                options: backgrounds.keys.toList(),
                                labelFor: (v) => backgrounds[v]!,
                                sheetTitle: l10n.background,
                                onChanged: notifier.setTheme,
                              ),
                            ),
                            _field(
                              context,
                              l10n.fontFamily,
                              _choices(
                                context,
                                value: settings.font,
                                choices: {
                                  ReaderFont.serif: l10n.readerFontSerif,
                                  ReaderFont.sans: l10n.readerFontSans,
                                },
                                onChanged: notifier.setFont,
                              ),
                            ),
                            const AppDivider(),
                            _AppearanceSlider(
                              label: l10n.fontSize,
                              hint: l10n.readerFontSizeHint,
                              value: settings.fontSize,
                              fallback: defaults.fontSize,
                              min: 12,
                              max: 28,
                              divisions: 16,
                              onCommitted: notifier.setFontSize,
                            ),
                          ],
                        ),
                      ),
                    SettingGroup(
                      title: l10n.readerPageLayout,
                      child: Column(
                        children: [
                          _field(
                            context,
                            l10n.readerWidthFluid,
                            Text(
                              l10n.readerAutoLayoutHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const AppDivider(),
                          _AppearanceSlider(
                            label: l10n.readerHorizontalMargin,
                            hint: l10n.readerMarginHint,
                            value: settings.desktopHorizontalMargin,
                            fallback: defaults.desktopHorizontalMargin,
                            min: 0,
                            max: 120,
                            divisions: 30,
                            onCommitted: notifier.setDesktopHorizontalMargin,
                          ),
                          const AppDivider(),
                          _AppearanceSlider(
                            label: l10n.readerVerticalMargin,
                            hint: l10n.readerMarginHint,
                            value: settings.desktopVerticalMargin,
                            fallback: defaults.desktopVerticalMargin,
                            min: 0,
                            max: 80,
                            divisions: 20,
                            onCommitted: notifier.setDesktopVerticalMargin,
                          ),
                        ],
                      ),
                    ),
                    if (!pdfView)
                      SettingGroup(
                        title: l10n.readerReadingOptions,
                        child: Column(
                          children: [
                            _field(
                              context,
                              l10n.readerContinuousReading,
                              Text(
                                l10n.readerContinuousReadingHint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const AppDivider(),
                            _field(
                              context,
                              l10n.translationStyle,
                              SettingPicker<String>(
                                current:
                                    translationStyles.containsKey(
                                      translation.displayStyleId,
                                    )
                                    ? translation.displayStyleId
                                    : 'themed',
                                options: translationStyles.keys.toList(),
                                labelFor: (v) => translationStyles[v]!,
                                sheetTitle: l10n.translationStyle,
                                onChanged: ref
                                    .read(translationConfigProvider.notifier)
                                    .setDisplayStyleId,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, String title, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _choices<T>(
    BuildContext context, {
    required T value,
    required Map<T, String> choices,
    required ValueChanged<T> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        segments: [
          for (final entry in choices.entries)
            ButtonSegment(value: entry.key, label: Text(entry.value)),
        ],
        selected: {value},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          backgroundColor: cs.surface,
          selectedBackgroundColor: cs.primaryContainer,
          foregroundColor: cs.onSurfaceVariant,
          selectedForegroundColor: cs.onPrimaryContainer,
          side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        onSelectionChanged: (values) => onChanged(values.single),
      ),
    );
  }
}

class _AppearanceSlider extends StatefulWidget {
  const _AppearanceSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.fallback,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onCommitted,
  });

  final String label;
  final String hint;
  final double value;
  final double fallback;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onCommitted;

  @override
  State<_AppearanceSlider> createState() => _AppearanceSliderState();
}

class _AppearanceSliderState extends State<_AppearanceSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final value = _dragValue ?? widget.value;
    final isSet = value != widget.fallback;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: widget.hint,
                      child: Icon(
                        Symbols.help_outline_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSet
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest.withAlpha(160),
                  borderRadius: BorderRadius.circular(12),
                  border: isSet
                      ? null
                      : Border.all(color: cs.outlineVariant.withAlpha(80)),
                ),
                child: Text(
                  '${value.round()} px',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isSet ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  padding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _dragValue = v),
                  onChangeEnd: (v) {
                    widget.onCommitted(v);
                    setState(() => _dragValue = null);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Symbols.refresh_rounded, size: 20),
                tooltip: context.l10n.reset,
                onPressed: isSet
                    ? () {
                        widget.onCommitted(widget.fallback);
                        setState(() => _dragValue = null);
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
