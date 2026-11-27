import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/history_provider.dart';
import '../../../utils/desktop.dart';
import '../../../widgets/hover_lift.dart';
import '../../../widgets/spring_pop.dart';
import '../../../widgets/tactile_press.dart';
import '../../../utils/doc_paths.dart';
import 'doc_card_actions.dart';
import 'hover_actions.dart';
import 'pdf_cover.dart';
import 'progress_chip.dart';
import '../../../core/design_tokens.dart';
import '../../../core/elevation.dart';

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

    // Folio：一张纸条目——纸色底 + 1px 细线；选中时细线换成强调色、纸面微染。
    final paper = isSelected
        ? Color.alphaBlend(
            colorScheme.primary.withAlpha(18),
            colorScheme.surfaceContainerLowest,
          )
        : colorScheme.surfaceContainerLowest;
    Widget card = AnimatedContainer(
      duration: kAnimFast,
      decoration: BoxDecoration(
        borderRadius: AppRadius.mdAll,
        color: paper,
        border: Border.all(
          color: isSelected ? colorScheme.primary : AppStroke.rule(colorScheme),
          width: isSelected ? AppStroke.emphasis : AppStroke.hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: TactilePress(
        baseColor: paper,
        borderRadius: AppRadius.mdAll,
        pressedScale: 0.99,
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
                      Container(
                        width: _thumbWidth,
                        height: _thumbHeight,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: AppRadius.xsAll,
                          border: Border.all(
                            color: AppStroke.rule(colorScheme),
                          ),
                          boxShadow: AppShadows.page,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.xs - 1),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PdfCoverRender(
                                assetPath: DocPaths.pdf(doc.id),
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                              ),
                              if (isSelected)
                                ColoredBox(
                                  color: colorScheme.primary.withAlpha(46),
                                  child: Center(
                                    child: SpringPop(
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary,
                                          borderRadius: AppRadius.smAll,
                                        ),
                                        child: Icon(
                                          Symbols.check_rounded,
                                          color: colorScheme.onPrimary,
                                          size: 18,
                                          weight: 600,
                                        ),
                                      ),
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
                                fontFamily: AppType.displayFamily(
                                  theme.platform,
                                ),
                                fontFamilyFallback: AppType.displayFallbacks(
                                  theme.platform,
                                ),
                                fontWeight: FontWeight.w500,
                                fontSize: 17,
                                color: colorScheme.onSurface,
                                height: 1.28,
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
                                  color: colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
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
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            letterSpacing: 0.4,
                                            fontFeatures: AppType.tabular,
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
                      Container(
                        width: AppStroke.focus,
                        height: 44,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: AppSpace.x3),
                      Expanded(
                        child: Text(
                          comment!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: AppType.displayFamily(theme.platform),
                            fontFamilyFallback: AppType.displayFallbacks(
                              theme.platform,
                            ),
                            fontStyle: FontStyle.italic,
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
    return HoverLift(enabled: isDesktopOs && !isSelectionMode, child: card);
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
