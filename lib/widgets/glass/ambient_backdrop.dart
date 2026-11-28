import 'package:flutter/material.dart';

import '../../core/folio_look.dart';

/// 一级页面背后的氛围光：底色之上铺三团来自主题色的大面积径向柔光。
///
/// 关闭氛围光时只铺底色。页面自身的 Scaffold 需要透明背景才能透出它，
/// 用 [AmbientBackdrop.pageColor] 取页面背景色。
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, required this.child});

  final Widget child;

  /// 一级页面的 Scaffold 背景：氛围光打开时透明。
  static Color pageColor(BuildContext context) => FolioLook.of(context).ambient
      ? Colors.transparent
      : Theme.of(context).colorScheme.surface;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final look = FolioLook.of(context);
    if (!look.ambient) {
      return ColoredBox(color: cs.surface, child: child);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = dark ? .75 : 1.0;

    Widget glow(Alignment at, Color c, double a, double r) => Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: at,
            radius: r,
            colors: [
              c.withValues(alpha: a * k),
              c.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );

    return ColoredBox(
      color: cs.surface,
      child: Stack(
        children: [
          glow(const Alignment(-1.1, -1.2), cs.primary, .24, 1.15),
          glow(const Alignment(1.2, -.5), cs.tertiary, .18, .95),
          glow(const Alignment(.3, 1.4), cs.secondary, .12, 1.0),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
