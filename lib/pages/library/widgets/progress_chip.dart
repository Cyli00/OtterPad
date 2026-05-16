import 'package:flutter/material.dart';

/// 阅读进度胶囊：primary container 圆角小标签 + 10sp 百分比文字。
///
/// 调用方应在 progress == 0 时不渲染此组件（避免新导入文献一片 0%）。
/// 网格卡 / 列表卡 / 历史卡 / 搜索结果卡共用，统一视觉。
class ProgressChip extends StatelessWidget {
  final double progress;
  const ProgressChip({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (progress * 100).round().clamp(1, 100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}
