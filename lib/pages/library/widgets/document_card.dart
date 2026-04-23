import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'pdf_cover.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 文献网格卡片
///
/// 支持两种模式：
/// - 正常模式：点击打开阅读器，长按进入多选模式
/// - 多选模式：点击切换选中/取消，缩略图显示蒙版 + 勾选图标
class DocumentCard extends StatelessWidget {
  final String docId;
  final String coverAsset;
  final String name;
  final String authors;
  final String journalName;
  final String year;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionTap;

  const DocumentCard({
    super.key,
    required this.docId,
    required this.coverAsset,
    required this.name,
    this.authors = '',
    required this.journalName,
    required this.year,
    required this.onTap,
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
        border: Border.all(
          color: isSelected
              ? colorScheme.primary.withAlpha(160)
              : colorScheme.outlineVariant.withAlpha(100),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: isSelectionMode ? onSelectionTap : onTap,
            onLongPress: isSelectionMode
                ? null
                : onLongPress != null
                    ? () {
                        HapticFeedback.mediumImpact();
                        onLongPress!();
                      }
                    : null,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面缩略图 + 选中蒙版
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    coverAsset.isNotEmpty
                        ? PdfCoverRender(assetPath: coverAsset)
                        : Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(
                                Symbols.article,
                                color: colorScheme.onSurfaceVariant
                                    .withAlpha(80),
                                size: 48,
                              ),
                            ),
                          ),
                    // 选中蒙版 + 勾选标记
                    if (isSelected)
                      Container(
                        color: colorScheme.primary.withAlpha(80),
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Symbols.check_rounded,
                              color: colorScheme.onPrimary,
                              size: 28,
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
              // 底部信息区域
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
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
        ),
      ),
    );
  }
}
