import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../utils/desktop.dart';

class LibraryEmptyState extends StatelessWidget {
  final VoidCallback? onStartSetup;

  const LibraryEmptyState({super.key, this.onStartSetup});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Icon(
                Symbols.auto_stories_rounded,
                size: 36,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.emptyLibraryTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.emptyLibraryBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (isDesktopOs) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.emptyLibraryDropHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withAlpha(180),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onStartSetup != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () {
                  Haptics.soft();
                  onStartSetup!();
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.tune_rounded,
                      size: 18,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(context.l10n.emptyLibraryAction),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
