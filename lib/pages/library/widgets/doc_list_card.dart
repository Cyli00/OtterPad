import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../data/models/book/document.dart';
import 'pdf_cover.dart';

/// 文献列表卡片（文献库列表视图 + 收藏夹详情页共用）
///
/// 支持两种模式：
/// - 正常模式：点击打开阅读器，长按进入多选模式
/// - 多选模式：点击切换选中/取消，缩略图显示蒙版 + 勾选图标
class DocListCard extends StatelessWidget {
  final Document doc;
  final String? comment;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionTap;

  const DocListCard({
    super.key,
    required this.doc,
    this.comment,
    this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: 150.ms,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isSelected
            ? colorScheme.primaryContainer.withAlpha(80)
            : colorScheme.surfaceContainerLow,
        border: Border.all(
          color: isSelected
              ? colorScheme.primary.withAlpha(160)
              : Colors.transparent,
          width: isSelected ? 2 : 0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isSelectionMode ? onSelectionTap : onTap,
          onLongPress: isSelectionMode
              ? null
              : onLongPress != null
                  ? () {
                      HapticFeedback.mediumImpact();
                      onLongPress!();
                    }
                  : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 缩略图 + 选中蒙版
                    if (doc.filePath.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 120,
                          height: 168,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PdfCoverRender(
                                assetPath: doc.filePath,
                                fit: BoxFit.cover,
                              ),
                              if (isSelected)
                                Container(
                                  color: colorScheme.primary.withAlpha(80),
                                  child: Center(
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.check_rounded,
                                        color: colorScheme.onPrimary,
                                        size: 22,
                                      ),
                                    )
                                        .animate()
                                        .scaleXY(
                                          begin: 0.6,
                                          end: 1,
                                          duration: 200.ms,
                                          curve: Curves.easeOutBack,
                                        ),
                                  ),
                                ),
                            ],
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
      ),
    );
  }
}
