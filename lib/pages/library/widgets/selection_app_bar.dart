import 'package:flutter/material.dart';

/// 多选模式顶部操作栏（普通 AppBar 版）
///
/// 用于 FavoriteDetailPage、NoFileEntriesPage 等使用 Scaffold.appBar 的页面。
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onClose;
  final int selectedCount;
  final VoidCallback onSelectAll;
  final bool allSelected;
  final VoidCallback? onExtract;
  final VoidCallback? onRemoveFromFavorite;
  final VoidCallback onDelete;

  const SelectionAppBar({
    super.key,
    required this.onClose,
    required this.selectedCount,
    required this.onSelectAll,
    required this.allSelected,
    this.onExtract,
    this.onRemoveFromFavorite,
    required this.onDelete,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppBar(
      backgroundColor: colorScheme.surface,
      leading: IconButton(
        onPressed: onClose,
        icon: const Icon(Icons.close_rounded),
        tooltip: '退出多选',
      ),
      title: Text(
        '已选 $selectedCount',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          onPressed: onSelectAll,
          icon: Icon(
            allSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
          ),
          tooltip: allSelected ? '取消全选' : '全选',
        ),
        if (onRemoveFromFavorite != null)
          IconButton(
            onPressed: selectedCount > 0 ? onRemoveFromFavorite : null,
            icon: const Icon(Icons.bookmark_remove_outlined),
            tooltip: '移出收藏夹',
          ),
        if (onExtract != null)
          IconButton(
            onPressed: selectedCount > 0 ? onExtract : null,
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: '文本提取',
          ),
        IconButton(
          onPressed: selectedCount > 0 ? onDelete : null,
          icon: Icon(
            Icons.delete_outline_rounded,
            color: selectedCount > 0 ? colorScheme.error : null,
          ),
          tooltip: '删除',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// 多选模式顶部操作栏（Sliver 版）
///
/// 用于 LibraryPage 的 NestedScrollView，替换 HomeHeader + TabBar。
class SliverSelectionBar extends StatelessWidget {
  final VoidCallback onClose;
  final int selectedCount;
  final VoidCallback onSelectAll;
  final bool allSelected;
  final VoidCallback? onExtract;
  final VoidCallback onDelete;

  const SliverSelectionBar({
    super.key,
    required this.onClose,
    required this.selectedCount,
    required this.onSelectAll,
    required this.allSelected,
    this.onExtract,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SliverToBoxAdapter(
      child: Container(
        color: colorScheme.surface,
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
        ),
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                tooltip: '退出多选',
              ),
              const SizedBox(width: 8),
              Text(
                '已选 $selectedCount',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onSelectAll,
                icon: Icon(
                  allSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                ),
                tooltip: allSelected ? '取消全选' : '全选',
              ),
              if (onExtract != null)
                IconButton(
                  onPressed: selectedCount > 0 ? onExtract : null,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  tooltip: '文本提取',
                ),
              IconButton(
                onPressed: selectedCount > 0 ? onDelete : null,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: selectedCount > 0 ? colorScheme.error : null,
                ),
                tooltip: '删除',
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
