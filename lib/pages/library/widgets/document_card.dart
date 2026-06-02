import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'pdf_cover.dart';
import 'progress_chip.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 文献网格卡片
///
/// 支持两种模式：
/// - 正常模式：点击打开阅读器，长按进入多选模式
/// - 多选模式：点击切换选中/取消，缩略图显示蒙版 + 勾选图标
///
/// 视觉规范：
/// - 缩略图区域锁定 A4 比例（W/H = 0.707），`BoxFit.contain` 不裁切
/// - 文字层：标题（titleSmall + w600，2 行）/ 期刊 1 行 / 底行年-进度
/// - 移动端窄卡（~156px）下作者行被隐藏，避免拥挤
class DocumentCard extends StatelessWidget {
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
                // 封面缩略图：A4 槽位 + BoxFit.cover + 顶部对齐。
                //
                // 设计取舍：
                // - 槽位锁 0.707（A4 W/H）保证网格视觉对齐
                // - 非 A4 PDF（PPT 导出、海报等）会被裁，但**从顶部裁**——
                //   PDF 首页顶部一般是标题/作者，最有识别价值的信息留下
                // - 之前 BoxFit.contain 在非 A4 PDF 上下产生 letterbox，
                //   配卡片圆角难看；cover + topCenter 彻底消除 letterbox
                AspectRatio(
                  aspectRatio: 0.707,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: colorScheme.surfaceContainerLow,
                        child: coverAsset.isNotEmpty
                            ? PdfCoverRender(
                                assetPath: coverAsset,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                              )
                            : Center(
                                child: Icon(
                                  Symbols.article,
                                  color: colorScheme.onSurfaceVariant
                                      .withAlpha(80),
                                  size: 48,
                                ),
                              ),
                      ),
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
                // 文字层
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (journalName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            journalName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                year,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withAlpha(180),
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
                    ),
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

