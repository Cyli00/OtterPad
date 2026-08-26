import 'package:flutter/material.dart';

/// 全局分隔线：`outlineVariant.withAlpha(80)` + 固定缩进档。
///
/// - [AppDivider] 内容缩进 20（无前置图标的行间）
/// - [AppDivider.tile] 对齐设置项标题（padding 20 + 图标 44 + 间距 16 = 80）
/// - [AppDivider.full] 分段全宽
class AppDivider extends StatelessWidget {
  const AppDivider({
    super.key,
    this.indent = kContent,
    this.endIndent = kContent,
    this.height = 1,
  });

  const AppDivider.tile({super.key, this.endIndent = kContent, this.height = 1})
    : indent = kTile;

  const AppDivider.full({super.key, this.height = 1})
    : indent = 0,
      endIndent = 0;

  static const double kContent = 20;
  static const double kTile = 80;
  static const int kAlpha = 80;

  final double indent;
  final double endIndent;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: height,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(kAlpha),
    );
  }
}
