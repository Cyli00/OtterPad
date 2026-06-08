import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';

/// 多选模式操作栏
///
/// 兼用于 Scaffold.appBar（shelf 页面）和 Column 内嵌（LibraryPage）。
/// 内部处理 SafeArea，外部无需额外包裹。
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onClose;
  final int selectedCount;
  final VoidCallback onSelectAll;
  final bool allSelected;
  final VoidCallback? onExtract;
  final VoidCallback? onDownload;
  final VoidCallback? onAddToFavorite;
  final VoidCallback? onRemoveFromFavorite;
  final VoidCallback onDelete;

  const SelectionAppBar({
    super.key,
    required this.onClose,
    required this.selectedCount,
    required this.onSelectAll,
    required this.allSelected,
    this.onExtract,
    this.onDownload,
    this.onAddToFavorite,
    this.onRemoveFromFavorite,
    required this.onDelete,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final sz = isMobile ? 36.0 : 40.0;
    final iconSz = sz * 0.5;
    final enabled = selectedCount > 0;

    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: sz,
                  height: sz,
                  child: IconButton(
                    onPressed: onClose,
                    icon: Icon(Symbols.close_rounded, size: iconSz),
                    padding: EdgeInsets.zero,
                    tooltip: context.l10n.exitMultiSelect,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  context.l10n.selectedCount(selectedCount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _button(
                  icon: allSelected
                      ? Symbols.deselect_rounded
                      : Symbols.select_all_rounded,
                  sz: sz,
                  iconSz: iconSz,
                  onPressed: onSelectAll,
                  tooltip: allSelected ? context.l10n.deselectAll : context.l10n.selectAll,
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
      ),
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
        onPressed: onPressed,
        icon: Icon(icon, size: iconSz),
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
