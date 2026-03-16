import 'package:flutter/material.dart';
import '../../../data/models/book/document.dart';
import 'pdf_cover.dart';

enum _CardAction { delete, batchDelete }

/// 文献列表卡片（文献库列表视图 + 收藏夹详情页共用）
///
/// 长按弹出上下文菜单：删除 / 批量删除。
class DocListCard extends StatelessWidget {
  final Document doc;
  final String? comment;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onBatchDelete;

  const DocListCard({
    super.key,
    required this.doc,
    this.comment,
    this.onTap,
    this.onDelete,
    this.onBatchDelete,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文献'),
        content: Text('确定要从文库中移除「${doc.title}」吗？'),
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
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: hasMenu
            ? (details) => _showContextMenu(context, details.globalPosition)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (doc.filePath.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 120,  // ← 列表缩略图宽度（可调）
                        height: 168, // ← 列表缩略图高度（可调）
                        child: PdfCoverRender(
                          assetPath: doc.filePath,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  if (doc.filePath.isNotEmpty) const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          doc.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (doc.authors.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            doc.authors.join(', '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (doc.journal != null &&
                            doc.journal!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            doc.journal!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withAlpha(180),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (doc.year != null &&
                            doc.year!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            doc.year!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withAlpha(140),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // 评语区域
              if (comment != null && comment!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.format_quote_rounded,
                      size: 24,
                      color: colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        comment!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
