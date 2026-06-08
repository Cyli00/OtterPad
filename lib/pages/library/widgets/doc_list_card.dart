import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../data/models/book/document.dart';
import '../../../utils/doc_paths.dart';
import 'pdf_cover.dart';
import 'progress_chip.dart';
import 'package:material_symbols_icons/symbols.dart';

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
  final bool compact;

  /// 阅读进度 0.0–1.0；==0 时不渲染 chip。
  /// 由调用方从 historyProvider 派生后传入（统一在父级 watch，避免每张卡都
  /// 单独订阅 historyProvider）。
  final double progress;

  const DocListCard({
    super.key,
    required this.doc,
    this.comment,
    this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionTap,
    this.compact = false,
    this.progress = 0.0,
  });

  // 缩略图尺寸——锁 A4 比例（W/H 0.707），cover + topCenter 不裁切页面。
  // 右列文字高度跟它对齐，年份行顶到缩略图底边。
  static const double _thumbWidthCompact = 88;
  static const double _thumbHeightCompact = 124;
  static const double _thumbWidthFull = 100;
  static const double _thumbHeightFull = 142;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thumbWidth = compact ? _thumbWidthCompact : _thumbWidthFull;
    final thumbHeight = compact ? _thumbHeightCompact : _thumbHeightFull;

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 缩略图 + 选中蒙版
                    if (doc.contentHash != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: thumbWidth,
                          height: thumbHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PdfCoverRender(
                                assetPath: DocPaths.pdf(doc.id),
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                              ),
                              if (isSelected)
                                Container(
                                  color: colorScheme.primary.withAlpha(80),
                                  child: Center(
                                    child:
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Symbols.check_rounded,
                                            color: colorScheme.onPrimary,
                                            size: 22,
                                          ),
                                        ).animate().scaleXY(
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
                    if (doc.contentHash != null) const SizedBox(width: 16),
                    // 右列文字锁到缩略图高度：有 thumb 时用 Spacer 把年份行顶到
                    // 缩略图底边对齐；没 thumb（无文件条目页）走自然高度，用固定留白
                    // ——Spacer 在 unbounded Column 里会断言失败。
                    Expanded(
                      child: SizedBox(
                        height: doc.contentHash != null ? thumbHeight : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                                height: 1.3,
                              ),
                              maxLines: compact ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // compact 模式下隐藏作者：作者信息密度最低（同期作者经常
                            // 重复），窄卡优先牺牲。Full 模式保留。
                            if (!compact && doc.authors.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                doc.authors.join(', '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (doc.journal != null &&
                                doc.journal!.isNotEmpty) ...[
                              const SizedBox(height: 2),
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
                            if ((doc.year != null && doc.year!.isNotEmpty) ||
                                progress > 0) ...[
                              if (doc.contentHash != null)
                                const Spacer()
                              else
                                const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      doc.year ?? '',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant
                                                .withAlpha(140),
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (progress > 0)
                                    ProgressChip(progress: progress),
                                ],
                              ),
                            ],
                          ],
                        ),
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
                        Symbols.format_quote_rounded,
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
