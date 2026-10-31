import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import 'reader_icon_button.dart';

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
  final bool showNavigationToggle;
  final bool navigationVisible;
  final VoidCallback? onToggleNavigation;

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
    this.showNavigationToggle = false,
    this.navigationVisible = true,
    this.onToggleNavigation,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            ReaderIconButton(
              icon: Symbols.chevron_left_rounded,
              iconSize: 28,
              tooltip: l10n.back,
              onPressed: onBack,
            ),
            if (showNavigationToggle && onToggleNavigation != null)
              ReaderIconButton(
                icon: navigationVisible
                    ? Symbols.left_panel_close_rounded
                    : Symbols.left_panel_open_rounded,
                tooltip: navigationVisible
                    ? l10n.readerHideNavigation
                    : l10n.readerShowNavigation,
                onPressed: onToggleNavigation!,
              ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((showPreview && hasResult) ||
                          (!showPreview && fileExists))
                        ReaderIconButton(
                          icon: Symbols.search_rounded,
                          tooltip: l10n.search,
                          onPressed: onSearch,
                        ),
                      extractButton,
                      if (showPreview && hasResult && hasMarkdownContent)
                        ReaderIconButton(
                          icon: Symbols.mindfulness_rounded,
                          tooltip: l10n.generateSummary,
                          onPressed: onGenerateSummaryImage,
                        ),
                      if (!showPreview && fileExists)
                        ReaderIconButton(
                          icon: inFavorite
                              ? Symbols.bookmark_remove_rounded
                              : Symbols.bookmark_add_rounded,
                          tooltip: inFavorite
                              ? l10n.removeFromFavorite
                              : l10n.moveToFavorite,
                          onPressed: inFavorite
                              ? onRemoveFavorite
                              : onAddFavorite,
                        ),
                      if (!showPreview && hasResult && !extracting)
                        ReaderIconButton(
                          icon: Symbols.sync_rounded,
                          tooltip: l10n.reExtract,
                          onPressed: onExtract,
                        ),
                      if (!showPreview)
                        ReaderIconButton(
                          icon: Symbols.info_rounded,
                          tooltip: l10n.documentInfo,
                          onPressed: onShowInfo,
                        )
                      else
                        Builder(
                          builder: (anchor) => ReaderIconButton(
                            icon: Symbols.more_vert_rounded,
                            tooltip: l10n.more,
                            onPressed: () => _showMoreMenu(anchor),
                          ),
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 更多菜单：锚在按钮正下方，与原 PopupMenuButton(position: under) 一致。
  Future<void> _showMoreMenu(BuildContext anchor) async {
    final cs = Theme.of(anchor).colorScheme;
    final l10n = anchor.l10n;
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final value = await showMenu<String>(
      context: anchor,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(rect.left, rect.bottom, rect.width, 0),
        Offset.zero & overlay.size,
      ),
      color: cs.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
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
        if (hasResult && !extracting)
          _popupItem('re_extract', Symbols.sync_rounded, l10n.reExtract, cs),
        if (hasResult && !extracting)
          _popupItem('reprocess', Symbols.refresh_rounded, l10n.reformat, cs),
        if (canRetranslate)
          _popupItem(
            'retranslate',
            Symbols.translate_rounded,
            l10n.reTranslate,
            cs,
          ),
      ],
    );
    if (value == null) return;
    Haptics.soft();
    switch (value) {
      case 'info':
        onShowInfo();
      case 'favorite_add':
        onAddFavorite();
      case 'favorite_remove':
        onRemoveFavorite();
      case 're_extract':
        onExtract();
      case 'reprocess':
        onReprocess();
      case 'retranslate':
        onRetranslate();
      case 'view_summary_image':
        onOpenSummaryImage();
    }
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
