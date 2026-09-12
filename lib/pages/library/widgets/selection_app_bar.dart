import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../utils/responsive.dart';
import '../../../providers/selection_provider.dart';
import 'document_export_action.dart';

/// 多选模式操作栏
///
/// 兼用于 Scaffold.appBar（shelf 页面）和 Column 内嵌（LibraryPage）。
/// [useSafeArea] 仅在作为 appBar 时为 true；Library 已包 SafeArea，必须关掉。
class SelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback onClose;
  final Set<String> allIds;
  final VoidCallback onSelectAll;
  final VoidCallback? onExtract;
  final VoidCallback? onDownload;
  final VoidCallback? onAddToFavorite;
  final VoidCallback? onRemoveFromFavorite;
  final VoidCallback onDelete;
  final bool useSafeArea;

  const SelectionAppBar({
    super.key,
    required this.onClose,
    required this.allIds,
    required this.onSelectAll,
    this.onExtract,
    this.onDownload,
    this.onAddToFavorite,
    this.onRemoveFromFavorite,
    required this.onDelete,
    this.useSafeArea = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final selectedCount = selection.selectedIds.length;
    final allSelected =
        allIds.isNotEmpty && selection.selectedIds.containsAll(allIds);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final wide = Responsive.showNavigationRail(context);
    final sz = wide ? 40.0 : 36.0;
    final iconSz = sz * 0.5;
    final enabled = selectedCount > 0;

    final row = SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: sz,
              height: sz,
              child: IconButton(
                onPressed: () {
                  Haptics.soft();
                  onClose();
                },
                icon: Icon(Symbols.close_rounded, size: iconSz, fill: 1),
                padding: EdgeInsets.zero,
                tooltip: context.l10n.exitMultiSelect,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.selectedCount(selectedCount),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              flex: 3,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _button(
                      icon: allSelected
                          ? Symbols.deselect_rounded
                          : Symbols.select_all_rounded,
                      sz: sz,
                      iconSz: iconSz,
                      onPressed: onSelectAll,
                      tooltip: allSelected
                          ? context.l10n.deselectAll
                          : context.l10n.selectAll,
                      bg: cs.primaryContainer,
                      fg: cs.primary,
                    ),
                    if (onExtract != null) ...[
                      const SizedBox(width: 8),
                      _button(
                        icon: Symbols.auto_awesome_rounded,
                        sz: sz,
                        iconSz: iconSz,
                        onPressed: enabled ? onExtract : null,
                        tooltip: context.l10n.textExtraction,
                        bg: cs.primaryContainer,
                        fg: cs.primary,
                      ),
                    ],
                    if (onDownload != null) ...[
                      const SizedBox(width: 8),
                      _button(
                        icon: Symbols.download_rounded,
                        sz: sz,
                        iconSz: iconSz,
                        onPressed: enabled ? onDownload : null,
                        tooltip: context.l10n.downloadPdf,
                        bg: cs.primaryContainer,
                        fg: cs.primary,
                      ),
                    ],
                    if (onAddToFavorite != null) ...[
                      const SizedBox(width: 8),
                      _button(
                        icon: Symbols.bookmark_add_rounded,
                        sz: sz,
                        iconSz: iconSz,
                        onPressed: enabled ? onAddToFavorite : null,
                        tooltip: context.l10n.addToFavorite,
                        bg: cs.tertiaryContainer,
                        fg: cs.tertiary,
                      ),
                    ],
                    if (onRemoveFromFavorite != null) ...[
                      const SizedBox(width: 8),
                      _button(
                        icon: Symbols.bookmark_remove_rounded,
                        sz: sz,
                        iconSz: iconSz,
                        onPressed: enabled ? onRemoveFromFavorite : null,
                        tooltip: context.l10n.removeFromFavorite,
                        bg: cs.tertiaryContainer,
                        fg: cs.tertiary,
                      ),
                    ],
                    const SizedBox(width: 8),
                    _button(
                      icon: Symbols.ios_share_rounded,
                      sz: sz,
                      iconSz: iconSz,
                      onPressed: enabled
                          ? () => showDocumentExport(
                              context,
                              ref,
                              ref.read(selectionProvider).selectedIds,
                            )
                          : null,
                      tooltip: context.l10n.exportDocuments,
                      bg: cs.primaryContainer,
                      fg: cs.primary,
                    ),
                    const SizedBox(width: 8),
                    _button(
                      icon: Symbols.delete_rounded,
                      sz: sz,
                      iconSz: iconSz,
                      onPressed: enabled ? onDelete : null,
                      tooltip: context.l10n.delete,
                      bg: cs.errorContainer,
                      fg: cs.error,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return ColoredBox(
      color: cs.surface,
      child: useSafeArea ? SafeArea(bottom: false, child: row) : row,
    );
  }

  static Widget _button({
    required IconData icon,
    required double sz,
    required double iconSz,
    required VoidCallback? onPressed,
    required String tooltip,
    required Color bg,
    required Color fg,
  }) {
    return SizedBox(
      width: sz,
      height: sz,
      child: IconButton.filled(
        onPressed: onPressed == null
            ? null
            : () {
                Haptics.soft();
                onPressed();
              },
        icon: Icon(icon, size: iconSz, fill: 1),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
