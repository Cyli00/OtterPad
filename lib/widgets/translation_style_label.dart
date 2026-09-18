import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

class TranslationStyleLabel extends StatelessWidget {
  final String styleId;
  final String label;
  const TranslationStyleLabel({
    super.key,
    required this.styleId,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
          imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
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
