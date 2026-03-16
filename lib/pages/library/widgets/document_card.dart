import 'package:flutter/material.dart';
import 'pdf_cover.dart';

enum _CardAction { delete, batchDelete }

/// 文献网格卡片
///
/// 长按弹出上下文菜单：删除 / 批量删除。
class DocumentCard extends StatelessWidget {
  final String docId;
  final String coverAsset;
  final String name;
  final String authors;
  final String journalName;
  final String year;
  final VoidCallback onTap;
  final bool isBookmarked;
  final VoidCallback onBookmarkToggle;
  final VoidCallback onMoreTap;
  final VoidCallback? onDelete;
  final VoidCallback? onBatchDelete;

  const DocumentCard({
    super.key,
    required this.docId,
    required this.coverAsset,
    required this.name,
    this.authors = '',
    required this.journalName,
    required this.year,
    required this.onTap,
    this.isBookmarked = false,
    required this.onBookmarkToggle,
    required this.onMoreTap,
    this.onDelete,
    this.onBatchDelete,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文献'),
        content: Text('确定要从文库中移除「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete?.call();
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<_CardAction>(
      context: context,
      position: position,
      items: [
        if (onDelete != null)
          const PopupMenuItem(
            value: _CardAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline_rounded),
              title: Text('删除'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
        if (onBatchDelete != null)
          const PopupMenuItem(
            value: _CardAction.batchDelete,
            child: ListTile(
              leading: Icon(Icons.checklist_rounded),
              title: Text('批量删除'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );

    if (!context.mounted || action == null) return;
    switch (action) {
      case _CardAction.delete:
        _confirmDelete(context);
      case _CardAction.batchDelete:
        onBatchDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasMenu = onDelete != null || onBatchDelete != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withAlpha(100),
          width: 1,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: hasMenu
            ? (details) => _showContextMenu(context, details.globalPosition)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面缩略图
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: coverAsset.isNotEmpty
                    ? PdfCoverRender(assetPath: coverAsset)
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            Icons.article_outlined,
                            color:
                                colorScheme.onSurfaceVariant.withAlpha(80),
                            size: 48,
                          ),
                        ),
                      ),
              ),
            ),
            // 底部信息区域
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (authors.isNotEmpty)
                    Text(
                      authors,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (journalName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      journalName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (year.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        year,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              colorScheme.onSurfaceVariant.withAlpha(180),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
