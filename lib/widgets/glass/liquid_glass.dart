import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/folio_look.dart';

/// 液态玻璃面板：背景模糊 + 饱和度提升 + 半透明着色 + 渐变高光描边 +
/// 顶部内高光 + 柔和投影。用于悬浮底栏、阅读器工具栏与问 AI 输入框。
///
/// [radius] 为 null 时是胶囊形（两端全圆）。
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius,
    this.blur = 22,
    this.tint,
    this.tintOpacity,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
  });

  final Widget child;
  final double? radius;
  final double blur;
  final Color? tint;
  final double? tintOpacity;
  final EdgeInsetsGeometry padding;
  final bool shadow;

  /// 饱和度提升矩阵（让模糊后的背景色更通透，而不是发灰）。
  static List<double> _saturation(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return [
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final OutlinedBorder shape = radius == null
        ? const StadiumBorder()
        : AppShape.of(radius!);
    final base = tint ?? cs.surfaceContainerLowest;
    final alpha = tintOpacity ?? (dark ? .52 : .58);

    final rim = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? [
              Colors.white.withValues(alpha: .22),
              Colors.white.withValues(alpha: .04),
              Colors.white.withValues(alpha: .12),
            ]
          : [
              Colors.white.withValues(alpha: .95),
              Colors.white.withValues(alpha: .25),
              Colors.white.withValues(alpha: .7),
            ],
      stops: const [0, .55, 1],
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .4 : .10),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .3 : .05),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ui.ImageFilter.compose(
            outer: ui.ColorFilter.matrix(_saturation(1.8)),
            inner: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.mirror,
            ),
          ),
          child: CustomPaint(
            foregroundPainter: _RimPainter(shape: shape, gradient: rim),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: dark ? .06 : .35),
                      base.withValues(alpha: alpha),
                    ),
                    base.withValues(alpha: alpha),
                    base.withValues(alpha: alpha * .92),
                  ],
                  stops: const [0, .45, 1],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({required this.shape, required this.gradient});
  final OutlinedBorder shape;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = gradient.createShader(rect);
    canvas.drawPath(shape.getOuterPath(rect.deflate(.6)), paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.shape != shape || old.gradient != gradient;
}

/// 悬浮玻璃开关打开时用 [LiquidGlass]，关闭时退回平铺的实色面板。
class BarSurface extends StatelessWidget {
  const BarSurface({
    super.key,
    required this.child,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.solidColor,
  });

  final Widget child;
  final double? radius;
  final EdgeInsetsGeometry padding;
  final Color? solidColor;

  @override
  Widget build(BuildContext context) {
    if (FolioLook.of(context).floatingBars) {
      return LiquidGlass(radius: radius, padding: padding, child: child);
    }
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: solidColor ?? cs.surfaceContainerHigh,
        shape: radius == null
            ? StadiumBorder(side: AppStroke.side(cs))
            : AppShape.of(radius!, side: AppStroke.side(cs)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
