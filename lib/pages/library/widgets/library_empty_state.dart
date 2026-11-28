import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../utils/desktop.dart';
import '../../../core/design_tokens.dart';

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
            // Folio：空白页像一张还没写字的纸——细线方框里一个墨色图标，
            // 衬线标题，不用彩色色块。
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppStroke.rule(cs)),
              ),
              alignment: Alignment.center,
              child: Icon(
                Symbols.auto_stories_rounded,
                size: 26,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: AppSpace.x6),
            Text(
              context.l10n.emptyLibraryTitle,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.x2),
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
              FilledButton.icon(
                onPressed: () {
                  Haptics.soft();
                  onStartSetup!();
                },
                icon: const Icon(Symbols.tune_rounded, size: 18),
                label: Text(context.l10n.emptyLibraryAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
