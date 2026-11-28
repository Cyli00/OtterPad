import 'package:flutter/material.dart';

/// 浮起层级 → 阴影。禁止组件自写 blur / offset。
///
/// Folio：静止在纸面上的东西（卡片、分组）不投影，靠细线分隔；
/// 只有离开纸面的东西才有阴影，并且是「近处一道实影 + 远处一层环境影」，
/// 比柔光大阴影更像真实的纸叠在纸上。
///
/// Card(静止) < Card(悬停) < 浮层工具条 < BottomSheet < Dialog
abstract final class AppShadows {
  static final Color _key = Colors.black.withAlpha(20);
  static final Color _ambient = Colors.black.withAlpha(12);

  static List<BoxShadow> _layer(double y, double blur) => [
    BoxShadow(color: _key, blurRadius: 1, offset: const Offset(0, 1)),
    BoxShadow(color: _ambient, blurRadius: blur, offset: Offset(0, y)),
  ];

  /// 静止卡片：不投影。
  static const List<BoxShadow> card = [];

  /// 阅读器里的 PDF 页面：纸放在桌上，只要一道贴边的实影。
  static List<BoxShadow> get page => _layer(2, 8);

  /// 桌面 hover：纸张轻轻离开桌面。
  static List<BoxShadow> get cardHover => _layer(6, 14);

  static List<BoxShadow> get bar => _layer(8, 20);

  static List<BoxShadow> get sheet => _layer(-6, 24);

  static List<BoxShadow> get dialog => _layer(16, 40);
}
