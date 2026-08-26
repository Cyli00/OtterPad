import 'package:flutter/material.dart';

/// 浮起层级 → 阴影。禁止组件自写 blur / offset。
///
/// Card < 浮层工具条 < BottomSheet < Dialog
/// blur  10        16         20          24
/// y      4         8         10          12
abstract final class AppShadows {
  static final Color _color = Colors.black.withAlpha(13);

  static List<BoxShadow> get card => [
    BoxShadow(color: _color, blurRadius: 10, offset: const Offset(0, 4)),
  ];

  /// 桌面 hover 抬升：Card blur 10→16。
  static List<BoxShadow> get cardHover => [
    BoxShadow(color: _color, blurRadius: 16, offset: const Offset(0, 4)),
  ];

  static List<BoxShadow> get bar => [
    BoxShadow(color: _color, blurRadius: 16, offset: const Offset(0, 8)),
  ];

  static List<BoxShadow> get sheet => [
    BoxShadow(color: _color, blurRadius: 20, offset: const Offset(0, 10)),
  ];

  static List<BoxShadow> get dialog => [
    BoxShadow(color: _color, blurRadius: 24, offset: const Offset(0, 12)),
  ];
}
