import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 外观偏好里不属于 ColorScheme 的部分：主题风格、氛围光、悬浮玻璃栏。
///
/// 通过 `ThemeData.extensions` 下发，组件用 [FolioLook.of] 读取。
@immutable
class FolioLook extends ThemeExtension<FolioLook> {
  const FolioLook({
    this.style = ThemeStyle.paper,
    this.ambient = true,
    this.floatingBars = true,
  });

  final ThemeStyle style;

  /// 一级页面背后来自主题色的柔光。
  final bool ambient;

  /// 底部各种栏悬浮在内容上方，呈液态玻璃质感。
  final bool floatingBars;

  static FolioLook of(BuildContext context) =>
      Theme.of(context).extension<FolioLook>() ?? const FolioLook();

  @override
  FolioLook copyWith({ThemeStyle? style, bool? ambient, bool? floatingBars}) =>
      FolioLook(
        style: style ?? this.style,
        ambient: ambient ?? this.ambient,
        floatingBars: floatingBars ?? this.floatingBars,
      );

  @override
  FolioLook lerp(FolioLook? other, double t) => t < .5 ? this : (other ?? this);
}
