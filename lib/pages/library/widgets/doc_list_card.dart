import 'package:flutter/material.dart';
import '../../../data/models/book/document.dart';
import 'pdf_cover.dart';

/// 文献列表卡片（文献库列表视图 + 收藏夹详情页共用）
///
/// 长按显示右上角删除按钮 → 点击后二次确认。
class DocListCard extends StatefulWidget {
  final Document doc;
  final String? comment;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const DocListCard({
    super.key,
    required this.doc,
    this.comment,
    this.onTap,
    this.onDelete,
  });

  @override
  State<DocListCard> createState() => _DocListCardState();
}

class _DocListCardState extends State<DocListCard> {
  bool _showDelete = false;

  Future<void> _confirmDelete() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文献'),
        content: Text('确定要从文库中移除「${widget.doc.title}」吗？'),
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
      widget.onDelete?.call();
    }
    if (mounted) {
      setState(() => _showDelete = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final doc = widget.doc;

    return Stack(
      children: [
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _showDelete
                ? () => setState(() => _showDelete = false)
                : widget.onTap,
            onLongPress: widget.onDelete != null
                ? () => setState(() => _showDelete = !_showDelete)
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
                            width: 100,
                            height: 140,
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
                  if (widget.comment != null &&
                      widget.comment!.isNotEmpty) ...[
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
                            widget.comment!,
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
        ),

        // 删除按钮
        Positioned(
          top: 4,
          right: 4,
          child: IgnorePointer(
            ignoring: !_showDelete,
            child: AnimatedScale(
              scale: _showDelete ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Material(
                type: MaterialType.circle,
                color: colorScheme.errorContainer,
                elevation: 1,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _confirmDelete,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.remove_rounded,
                      size: 20,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
