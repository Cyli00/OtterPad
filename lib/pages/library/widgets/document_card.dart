import 'package:flutter/material.dart';
import 'pdf_cover.dart';

class DocumentCard extends StatelessWidget {
  final String coverAsset;
  final String name;
  final String journalName;
  final String year;
  final VoidCallback onTap;
  final bool isBookmarked;
  final VoidCallback onBookmarkToggle;
  final VoidCallback onMoreTap;

  const DocumentCard({
    super.key,
    required this.coverAsset,
    required this.name,
    required this.journalName,
    required this.year,
    required this.onTap,
    this.isBookmarked = false,
    required this.onBookmarkToggle,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面缩略图
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: PdfCoverRender(assetPath: coverAsset),
              ),
            ),
            // 底部信息区域
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 文献名
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
                  // 期刊名
                  if (journalName.isNotEmpty)
                    Text(
                      journalName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // 发表年份
                  if (year.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      year,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withAlpha(180),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 操作栏
                  Row(
                    children: [
                      InkWell(
                        onTap: onBookmarkToggle,
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isBookmarked
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              size: 16,
                              color: isBookmarked
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '收藏',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isBookmarked
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: onMoreTap,
                        borderRadius: BorderRadius.circular(12),
                        child: Icon(
                          Icons.more_vert,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
