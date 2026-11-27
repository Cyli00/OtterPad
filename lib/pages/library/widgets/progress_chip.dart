import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';

/// 阅读进度：一段 2px 的进度线 + 等宽百分比，不再是彩色胶囊。
///
/// 调用方应在 progress == 0 时不渲染此组件（避免新导入文献一片 0%）。
/// 网格卡 / 列表卡 / 历史卡 / 搜索结果卡共用，统一视觉。
class ProgressChip extends StatelessWidget {
  final double progress;

  /// 进度线长度；为 0 时只显示百分比（网格卡的进度线已画在封面底边）。
  final double trackWidth;

  const ProgressChip({super.key, required this.progress, this.trackWidth = 28});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = (progress * 100).round().clamp(1, 100);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trackWidth > 0) ...[
          ProgressLine(progress: progress, width: trackWidth),
          const SizedBox(width: AppSpace.x2),
        ],
        Text(
          '$pct%',
          style: theme.textTheme.labelSmall?.copyWith(
            color: pct >= 100 ? cs.primary : cs.onSurfaceVariant,
            letterSpacing: 0.2,
            fontFeatures: AppType.tabular,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

/// 2px 细进度线：墨色细轨 + 强调色填充。
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.progress, this.width});

  final double progress;

  /// 为 null 时撑满父级宽度。
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: AppStroke.focus,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.onSurface.withAlpha(28),
          borderRadius: BorderRadius.circular(AppRadius.hairline),
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(AppRadius.hairline),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
