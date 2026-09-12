import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/l10n.dart';
import '../services/haptics.dart';

class SettingHelpIcon extends StatelessWidget {
  const SettingHelpIcon(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 5),
      preferBelow: true,
      verticalOffset: 16,
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: theme.textTheme.bodySmall?.copyWith(
        color: cs.onInverseSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Symbols.help_rounded, size: 16, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class SettingTitle extends StatelessWidget {
  const SettingTitle(this.title, this.tooltip, {super.key});

  final String title;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 4),
      SettingHelpIcon(tooltip),
    ],
  );
}

class SettingResetButton extends StatelessWidget {
  const SettingResetButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed == null
        ? null
        : () {
            Haptics.soft();
            onPressed!();
          },
    icon: const Icon(Symbols.refresh_rounded, size: 20),
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    tooltip: context.l10n.restoreDefaults,
  );
}

class SettingSlider extends StatelessWidget {
  const SettingSlider({
    super.key,
    required this.title,
    required this.tooltip,
    required this.value,
    required this.fallback,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatter,
    required this.onChanged,
    this.onReset,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  final String title;
  final String tooltip;
  final double? value;
  final double fallback;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) formatter;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayValue = value ?? fallback;
    final isSet = value != null;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SettingTitle(title, tooltip)),
              const SizedBox(width: 12),
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
                  formatter(displayValue),
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
                  value: displayValue.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  padding: EdgeInsets.zero,
                  onChanged: (v) {
                    Haptics.soft();
                    onChanged(v);
                  },
                ),
              ),
              if (onReset != null)
                SettingResetButton(onPressed: isSet ? onReset : null),
            ],
          ),
        ],
      ),
    );
  }
}
