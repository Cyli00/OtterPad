import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/l10n.dart';

class ReaderTopToolbar extends StatelessWidget {
  final bool showPreview;
  final bool hasResult;
  final bool hasMarkdownContent;
  final bool fileExists;
  final bool inFavorite;
  final bool extracting;
  final bool canRetranslate;
  final bool hasSummaryImage;
  final Widget extractButton;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onGenerateSummaryImage;
  final VoidCallback onAddFavorite;
  final VoidCallback onRemoveFavorite;
  final VoidCallback onExtract;
  final VoidCallback onShowInfo;
  final VoidCallback onReprocess;
  final VoidCallback onRetranslate;
  final VoidCallback onOpenSummaryImage;

  const ReaderTopToolbar({
    super.key,
    required this.showPreview,
    required this.hasResult,
    required this.hasMarkdownContent,
    required this.fileExists,
    required this.inFavorite,
    required this.extracting,
    required this.canRetranslate,
    required this.hasSummaryImage,
    required this.extractButton,
    required this.onBack,
    required this.onSearch,
    required this.onGenerateSummaryImage,
    required this.onAddFavorite,
    required this.onRemoveFavorite,
    required this.onExtract,
    required this.onShowInfo,
    required this.onReprocess,
    required this.onRetranslate,
    required this.onOpenSummaryImage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Symbols.chevron_left_rounded,
                size: 28,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: l10n.back,
              onPressed: onBack,
            ),
            const Spacer(),
            if ((showPreview && hasResult) || (!showPreview && fileExists))
              IconButton(
                icon: Icon(
                  Symbols.search_rounded,
                  size: 22,
                  fill: 1,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: l10n.search,
                onPressed: onSearch,
              ),
            extractButton,
            if (showPreview && hasResult && hasMarkdownContent)
              IconButton(
                icon: Icon(
                  Symbols.mindfulness,
                  size: 22,
                  fill: 1,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: l10n.generateSummary,
                onPressed: onGenerateSummaryImage,
              ),
            if (!showPreview && fileExists)
              IconButton(
                icon: Icon(
                  inFavorite
                      ? Symbols.bookmark_remove_rounded
                      : Symbols.bookmark_add_rounded,
                  size: 22,
                  fill: 1,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: inFavorite ? l10n.removeFromFavorite : l10n.moveToFavorite,
                onPressed: inFavorite ? onRemoveFavorite : onAddFavorite,
              ),
            if (hasResult && !extracting)
              IconButton(
                icon: Icon(
                  Symbols.sync_rounded,
                  size: 22,
                  fill: 1,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: l10n.reExtract,
                onPressed: onExtract,
              ),
            if (!showPreview)
              IconButton(
                icon: Icon(
                  Symbols.info_rounded,
                  size: 22,
                  fill: 1,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: l10n.documentInfo,
                onPressed: onShowInfo,
              )
            else
              PopupMenuButton<String>(
                icon: Icon(
                  Symbols.more_vert_rounded,
                  size: 22,
                  fill: 1,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: l10n.more,
                color: cs.surfaceContainerHigh,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                position: PopupMenuPosition.under,
                onSelected: (value) {
                  switch (value) {
                    case 'info':
                      onShowInfo();
                    case 'favorite_add':
                      onAddFavorite();
                    case 'favorite_remove':
                      onRemoveFavorite();
                    case 'reprocess':
                      onReprocess();
                    case 'retranslate':
                      onRetranslate();
                    case 'view_summary_image':
                      onOpenSummaryImage();
                  }
                },
                itemBuilder: (_) => [
                  if (hasSummaryImage)
                    _popupItem(
                      'view_summary_image',
                      Symbols.image_rounded,
                      l10n.viewSummary,
                      cs,
                    ),
                  _popupItem('info', Symbols.info_rounded, l10n.documentInfo, cs),
                  if (inFavorite)
                    _popupItem(
                      'favorite_remove',
                      Symbols.bookmark_remove_rounded,
                      l10n.removeFromFavorite,
                      cs,
                    )
                  else
                    _popupItem(
                      'favorite_add',
                      Symbols.bookmark_add_rounded,
                      l10n.moveToFavorite,
                      cs,
                    ),
                  if (hasResult)
                    _popupItem(
                      'reprocess',
                      Symbols.refresh_rounded,
                      l10n.reformat,
                      cs,
                    ),
                  if (canRetranslate)
                    _popupItem(
                      'retranslate',
                      Symbols.translate_rounded,
                      l10n.reTranslate,
                      cs,
                    ),
                ],
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  static PopupMenuItem<String> _popupItem(
    String value,
    IconData icon,
    String title,
    ColorScheme cs,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 20, fill: 1, color: cs.onSurfaceVariant),
          const SizedBox(width: 14),
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
