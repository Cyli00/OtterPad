import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../utils/responsive.dart';
import '../../../providers/selection_provider.dart';
import '../../../core/design_tokens.dart';
import '../../../widgets/rule_icon_button.dart';

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
    final sz = wide ? 34.0 : 36.0;
    final iconSz = sz * 0.5;
    final enabled = selectedCount > 0;

    final row = SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 12),
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
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFeatures: AppType.tabular,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              flex: 3,
              fit: FlexFit.tight,
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _button(
                        icon: allSelected
                            ? Symbols.deselect_rounded
                            : Symbols.select_all_rounded,
                        sz: sz,
                        onPressed: onSelectAll,
                        tooltip: allSelected
                            ? context.l10n.deselectAll
                            : context.l10n.selectAll,
                      ),
                      if (onExtract != null) ...[
                        const SizedBox(width: 8),
                        _button(
                          icon: Symbols.auto_awesome_rounded,
                          sz: sz,
                          onPressed: enabled ? onExtract : null,
                          tooltip: context.l10n.textExtraction,
                        ),
                      ],
                      if (onDownload != null) ...[
                        const SizedBox(width: 8),
                        _button(
                          icon: Symbols.download_rounded,
                          sz: sz,
                          onPressed: enabled ? onDownload : null,
                          tooltip: context.l10n.downloadPdf,
                        ),
                      ],
                      if (onAddToFavorite != null) ...[
                        const SizedBox(width: 8),
                        _button(
                          icon: Symbols.bookmark_add_rounded,
                          sz: sz,
                          onPressed: enabled ? onAddToFavorite : null,
                          tooltip: context.l10n.addToFavorite,
                        ),
                      ],
                      if (onRemoveFromFavorite != null) ...[
                        const SizedBox(width: 8),
                        _button(
                          icon: Symbols.bookmark_remove_rounded,
                          sz: sz,
                          onPressed: enabled ? onRemoveFromFavorite : null,
                          tooltip: context.l10n.removeFromFavorite,
                        ),
                      ],
                      const SizedBox(width: 8),
                      _button(
                        icon: Symbols.delete_rounded,
                        sz: sz,
                        onPressed: enabled ? onDelete : null,
                        tooltip: context.l10n.delete,
                        danger: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: AppStroke.side(cs)),
      ),
      child: useSafeArea ? SafeArea(bottom: false, child: row) : row,
    );
  }

  static Widget _button({
    required IconData icon,
    required double sz,
    required VoidCallback? onPressed,
    required String tooltip,
    bool danger = false,
  }) {
    return RuleIconButton(
      icon: icon,
      size: sz,
      tooltip: tooltip,
      danger: danger,
      onPressed: onPressed == null
          ? null
          : () {
              Haptics.soft();
              onPressed();
            },
    );
  }
}
