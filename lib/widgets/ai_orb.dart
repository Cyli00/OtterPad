import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 问 AI 的形象：一颗由主题色、第三色、第二色旋转扫出的光球。
///
/// 静止时缓慢自转；[thinking] 时转速加快并「呼吸」（缩放 + 外发光起伏），
/// 用作头像、思考中状态、阅读器底栏入口与空状态主视觉。
class AiOrb extends StatefulWidget {
  const AiOrb({
    super.key,
    this.size = 24,
    this.thinking = false,
    this.icon,
    this.glow = true,
  });

  final double size;
  final bool thinking;

  /// 球心图标（如 sparkle）；null 时只有光球。
  final IconData? icon;
  final bool glow;

  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AiOrb old) {
    super.didUpdateWidget(old);
    if (old.thinking != widget.thinking) _sync();
  }

  void _sync() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
      return;
    }
    _spin.duration = Duration(milliseconds: widget.thinking ? 1600 : 6000);
    if (!_spin.isAnimating) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  /// 光球用的颜色：把主题色推到足够饱和、明度适中，深浅色下都像一团光。
  static Color _vivid(Color c, bool dark) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation(math.max(hsl.saturation, .62))
        .withLightness(dark ? .6 : .54)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = _vivid(cs.primary, dark);
    final t = _vivid(cs.tertiary, dark);
    final q = _vivid(cs.secondary, dark);
    final s = widget.size;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) {
          final a = _spin.value * 2 * math.pi;
          // 思考时呼吸：一个周期内两次起伏
          final breathe = widget.thinking ? (math.sin(a * 2) + 1) / 2 : 0.0;
          return Transform.scale(
            scale: 1 + .06 * breathe,
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  transform: GradientRotation(a),
                  colors: [p, t, q, Color.lerp(p, t, .5)!, p],
                ),
                boxShadow: widget.glow
                    ? [
                        BoxShadow(
                          color: p.withValues(alpha: .3 + .25 * breathe),
                          blurRadius: s * (.35 + .25 * breathe),
                          spreadRadius: s * .02,
                        ),
                      ]
                    : null,
              ),
              child: DecoratedBox(
                // 球面高光：左上角一团白
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-.4, -.5),
                    radius: .9,
                    colors: [
                      Colors.white.withValues(alpha: dark ? .3 : .5),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: widget.icon == null
                    ? null
                    : Icon(
                        widget.icon,
                        size: s * .5,
                        color: Colors.white,
                        fill: 1,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 一行会流光的文字（「正在思考」）：高光带从左往右扫过。
class ShimmerText extends StatefulWidget {
  const ShimmerText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.onSurfaceVariant.withValues(alpha: .55);
    final text = Text(widget.text, style: widget.style);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value * 2.4 - .7;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [base, cs.primary, cs.tertiary, base],
            stops: [
              (t - .25).clamp(0.0, 1.0),
              (t - .05).clamp(0.0, 1.0),
              (t + .05).clamp(0.0, 1.0),
              (t + .25).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: text,
    );
  }
}

/// 发送中绕输入框流动的极光描边：一道主题色扫光沿圆角矩形旋转。
class AuroraRing extends StatefulWidget {
  const AuroraRing({
    super.key,
    required this.active,
    required this.radius,
    required this.child,
    this.width = 2,
  });

  final bool active;
  final double radius;
  final double width;
  final Widget child;

  @override
  State<AuroraRing> createState() => _AuroraRingState();
}

class _AuroraRingState extends State<AuroraRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AuroraRing old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.active ? 1 : 0),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, on, child) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          foregroundPainter: on <= 0.001
              ? null
              : _AuroraPainter(
                  turn: _c.value,
                  opacity: on,
                  radius: widget.radius,
                  width: widget.width,
                  colors: [cs.primary, cs.tertiary, cs.secondary],
                ),
          child: child,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.turn,
    required this.opacity,
    required this.radius,
    required this.width,
    required this.colors,
  });

  final double turn;
  final double opacity;
  final double radius;
  final double width;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final rrect = RSuperellipse.fromRectAndRadius(
      rect,
      Radius.circular(radius),
    );
    final c = colors;
    Color o(Color x, double a) => x.withValues(alpha: a * opacity);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(
        transform: GradientRotation(turn * 2 * math.pi),
        colors: [
          o(c[0], 0),
          o(c[0], 1),
          o(c[1], 1),
          o(c[2], .6),
          o(c[0], 0),
          o(c[0], 0),
        ],
        stops: const [0, .14, .3, .42, .55, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRSuperellipse(rrect, paint);
    // 一层更宽更淡的外晕
    canvas.drawRSuperellipse(
      rrect,
      paint
        ..strokeWidth = width * 4
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 2)
        ..color = const Color(0x73000000),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.turn != turn || old.opacity != opacity || old.colors != colors;
}
