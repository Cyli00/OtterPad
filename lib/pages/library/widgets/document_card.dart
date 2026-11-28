import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/design_tokens.dart';
import '../../../core/elevation.dart';
import '../../../utils/desktop.dart';
import '../../../widgets/spring_pop.dart';
import '../../../widgets/tactile_press.dart';
import 'doc_card_actions.dart';
import 'hover_actions.dart';
import 'pdf_cover.dart';
import 'progress_chip.dart';

/// 文献网格卡片
///
/// 支持两种模式：
/// - 正常模式：点击打开阅读器，长按进入多选模式
/// - 多选模式：点击切换选中/取消，缩略图显示蒙版 + 勾选图标
///
/// 视觉规范（Folio）：
/// - 封面就是卡片：A4 比例（W/H = 0.707）的一张纸，细线 + 贴边实影；
///   没有外层卡片底色和柔光阴影
/// - 阅读进度是封面底边的 2px 强调色线
/// - 封面下方：衬线标题 2 行 / 期刊 · 年份 1 行 + 等宽百分比
/// - 桌面悬停时只有封面离开纸面（上浮 2px、阴影变深）
class DocumentCard extends StatefulWidget {
  final String docId;
  final String coverAsset;
  final String name;
  final String authors;
  final String journalName;
  final String year;

  /// 0.0–1.0；==0 时进度 chip 不渲染（避免新导入文献一片 0%）
  final double progress;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionTap;
  final VoidCallback? onModifierToggle;
  final VoidCallback? onSelectRange;
  final void Function(Offset globalPosition)? onContextMenu;
  final VoidCallback? onFavorite;

  const DocumentCard({
    super.key,
    required this.docId,
    required this.coverAsset,
    required this.name,
    this.authors = '',
    required this.journalName,
    required this.year,
    this.progress = 0.0,
    required this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionTap,
    this.onModifierToggle,
    this.onSelectRange,
    this.onContextMenu,
    this.onFavorite,
  });

  @override
  State<DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<DocumentCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final lift = isDesktopOs && !w.isSelectionMode && _hover;
    final showHover =
        isDesktopOs &&
        !w.isSelectionMode &&
        (w.onFavorite != null || w.onContextMenu != null);

    final meta = [
      if (w.journalName.isNotEmpty) w.journalName,
      if (w.year.isNotEmpty) w.year,
    ].join(' · ');

    // 封面：一张纸。选中时细线换成 2px 强调色，纸面压一层浅色。
    Widget cover = AnimatedContainer(
      duration: kAnimFast,
      curve: kAnimCurve,
      transform: Matrix4.translationValues(0, lift ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: AppRadius.xsAll,
        border: Border.all(
          color: w.isSelected ? cs.primary : AppStroke.rule(cs),
          width: w.isSelected ? AppStroke.focus : AppStroke.hairline,
        ),
        boxShadow: lift ? AppShadows.cardHover : AppShadows.page,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // cover + topCenter：非 A4 PDF 从顶部裁，保留标题/作者区
            if (w.coverAsset.isNotEmpty)
              PdfCoverRender(
                assetPath: w.coverAsset,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              )
            else
              _TypesetCover(title: w.name),
            if (w.progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ProgressLine(progress: w.progress),
              ),
            if (w.isSelected)
              ColoredBox(
                color: cs.primary.withAlpha(46),
                child: Align(
                  alignment: AlignmentDirectional.topEnd,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.x2),
                    child: SpringPop(
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: AppRadius.smAll,
                        ),
                        child: Icon(
                          Symbols.check_rounded,
                          color: cs.onPrimary,
                          size: 18,
                          weight: 600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (showHover) {
      cover = HoverActions(
        bar: DocHoverButtons(onFavorite: w.onFavorite, onMore: w.onContextMenu),
        child: cover,
      );
    }

    Widget card = TactilePress(
      // 不铺按压底色：反馈只有回弹缩放，纸面保持干净
      highlightSize: Size.zero,
      pressedScale: 0.98,
      onTap: () => DocCardActions.handleTap(
        isSelectionMode: w.isSelectionMode,
        onOpen: w.onTap,
        onToggle: w.onSelectionTap,
        onModifierToggle: w.onModifierToggle,
        onSelectRange: w.onSelectRange,
      ),
      onLongPress: w.isSelectionMode ? null : w.onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 0.707, child: cover),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: AppType.displayFamily(theme.platform),
                      fontFamilyFallback: AppType.displayFallbacks(
                        theme.platform,
                      ),
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      height: 1.28,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpace.x1),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (w.progress > 0)
                        ProgressChip(progress: w.progress, trackWidth: 0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isDesktopOs && w.onContextMenu != null) {
      card = GestureDetector(
        onSecondaryTapDown: (d) => w.onContextMenu!(d.globalPosition),
        child: card,
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: card,
    );
  }
}

/// 没有 PDF 文件时的封面：像一页排好版的扉页，而不是灰底图标。
class _TypesetCover extends StatelessWidget {
  const _TypesetCover({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 20, height: AppStroke.focus, color: cs.onSurface),
            const SizedBox(height: AppSpace.x3),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.onSurface,
                  height: 1.22,
                ),
                overflow: TextOverflow.fade,
              ),
            ),
            Icon(Symbols.article_rounded, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
