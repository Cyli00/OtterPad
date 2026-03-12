import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import 'pdf_cover.dart';

/// 文献网格卡片
///
/// 长按显示右上角删除按钮 → 点击后二次确认。
/// 通过 [activeDeleteIdProvider] 实现卡片间删除按钮互斥。
class DocumentCard extends ConsumerWidget {
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
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
    ref.read(activeDeleteIdProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeDeleteId = ref.watch(activeDeleteIdProvider);
    final showDelete = activeDeleteId == docId;

    return Stack(
      children: [
        Card(
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
          child: InkWell(
            onTap: activeDeleteId != null
                ? () => ref.read(activeDeleteIdProvider.notifier).state = null
                : onTap,
            onLongPress: onDelete != null
                ? () => ref.read(activeDeleteIdProvider.notifier).state =
                    showDelete ? null : docId
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
                                color: colorScheme.onSurfaceVariant
                                    .withAlpha(80),
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
                        Text(
                          year,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                colorScheme.onSurfaceVariant.withAlpha(180),
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
        ),

        // 删除按钮
        Positioned(
          top: 4,
          right: 4,
          child: IgnorePointer(
            ignoring: !showDelete,
            child: Material(
              type: MaterialType.circle,
              color: colorScheme.errorContainer,
              elevation: 1,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _confirmDelete(context, ref),
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
            )
                .animate(target: showDelete ? 1 : 0)
                .scaleXY(begin: 0, end: 1, curve: Curves.easeOutBack, duration: 250.ms)
                .fade(begin: 0, end: 1, duration: 200.ms),
          ),
        ),
      ],
    );
  }
}
