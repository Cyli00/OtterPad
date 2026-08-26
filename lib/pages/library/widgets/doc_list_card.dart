import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/history_provider.dart';
import '../../../utils/desktop.dart';
import '../../../widgets/tactile_press.dart';
import '../../../utils/doc_paths.dart';
import 'doc_card_actions.dart';
import 'hover_actions.dart';
import 'pdf_cover.dart';
import 'progress_chip.dart';

/// 文献列表卡片（文献库列表 / 搜索 / 阅读历史 / 收藏夹 / 无文件条目共用）
///
/// 支持两种模式：
/// - 正常模式：点击打开阅读器，长按进入多选模式
/// - 多选模式：点击切换选中/取消，缩略图显示蒙版 + 勾选图标
///
/// 阅读进度由卡片自己经 [docProgressProvider] 按 docId 细粒度订阅——
/// 阅读器每 500ms 的 setProgress 只重建对应卡片，调用方无需再 watch
/// historyProvider 拼 map 下发。
class DocListCard extends ConsumerWidget {
  final Document doc;
  final String? comment;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionTap;
  final VoidCallback? onModifierToggle;
  final VoidCallback? onSelectRange;
  final void Function(Offset globalPosition)? onContextMenu;
  final VoidCallback? onFavorite;

  const DocListCard({
    super.key,
    required this.doc,
    this.comment,
    this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionTap,
    this.onModifierToggle,
    this.onSelectRange,
    this.onContextMenu,
    this.onFavorite,
  });

  // 缩略图尺寸——锁 A4 比例（W/H 0.707），cover + topCenter 不裁切页面。
  // 右列文字高度跟它对齐，年份行顶到缩略图底边。
  static const double _thumbWidth = 100;
  static const double _thumbHeight = 142;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = ref.watch(docProgressProvider(doc.id));
    final showHover =
        isDesktopOs &&
        !isSelectionMode &&
        (onFavorite != null || onContextMenu != null);

    Widget card = AnimatedContainer(
      duration: kAnimFast,
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
      child: TactilePress(
        baseColor: isSelected
            ? colorScheme.primaryContainer.withAlpha(80)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        pressedScale: 0.98,
        onTap:
            (onTap == null &&
                !isSelectionMode &&
                onModifierToggle == null &&
                onSelectRange == null)
            ? null
            : () => DocCardActions.handleTap(
                isSelectionMode: isSelectionMode,
                onOpen: onTap ?? () {},
                onToggle: onSelectionTap,
                onModifierToggle: onModifierToggle,
                onSelectRange: onSelectRange,
              ),
        onLongPress: isSelectionMode ? null : onLongPress,
        child: _wrapHover(
          showHover: showHover,
          bar: DocHoverButtons(onFavorite: onFavorite, onMore: onContextMenu),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                          width: _thumbWidth,
                          height: _thumbHeight,
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
                                          duration: kAnim,
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
                        height: doc.contentHash != null ? _thumbHeight : null,
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
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (doc.authors.isNotEmpty) ...[
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
                                  color: colorScheme.onSurfaceVariant.withAlpha(
                                    180,
                                  ),
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

    if (isDesktopOs && onContextMenu != null) {
      card = GestureDetector(
        onSecondaryTapDown: (d) => onContextMenu!(d.globalPosition),
        child: card,
      );
    }
    return card;
  }

  Widget _wrapHover({
    required bool showHover,
    required Widget bar,
    required Widget child,
  }) {
    if (!showHover) return child;
    return HoverActions(
      padding: const EdgeInsets.all(8),
      bar: bar,
      child: child,
    );
  }
}
