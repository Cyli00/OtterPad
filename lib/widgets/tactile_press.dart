import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import '../services/haptics.dart';

class TactilePress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final Color? baseColor;
  final double? pressedScale;
  final EdgeInsetsGeometry? padding;
  final bool haptics;

  const TactilePress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.border,
    this.baseColor,
    this.pressedScale,
    this.padding,
    this.haptics = true,
  });

  @override
  State<TactilePress> createState() => _TactilePressState();
}

class _TactilePressState extends State<TactilePress> {
  bool _pressed = false;
  bool _hovered = false;

  bool get _interactive =>
      widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    final Color base =
        widget.baseColor ?? (isDark ? Colors.white10 : cs.surface);
    const double k = 0.12;
    final Color pressTarget =
        Color.lerp(base, isDark ? Colors.white : Colors.black, k) ?? base;
    final Color hoverTarget =
        Color.lerp(base, isDark ? Colors.white : Colors.black, k * 0.6) ??
            base;
    final Color target =
        _pressed ? pressTarget : (_hovered ? hoverTarget : base);
    final double scale =
        _pressed ? (widget.pressedScale ?? 1.0) : 1.0;
    final radius = widget.borderRadius ?? BorderRadius.circular(12);

    final content = widget.padding == null
        ? widget.child
        : Padding(padding: widget.padding!, child: widget.child);

    return MouseRegion(
      cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (r) {
              r
                ..onTapDown = _interactive
                    ? (_) => setState(() => _pressed = true)
                    : null
                ..onTapUp = _interactive
                    ? (_) => setState(() => _pressed = false)
                    : null
                ..onTapCancel = _interactive
                    ? () => setState(() => _pressed = false)
                    : null
                ..onTap = widget.onTap == null
                    ? null
                    : () {
                        if (widget.haptics) Haptics.soft();
                        widget.onTap!();
                      };
            },
          ),
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            LongPressGestureRecognizer.new,
            (r) {
              r
                ..onLongPress = widget.onLongPress == null
                    ? null
                    : () {
                        if (widget.haptics) Haptics.medium();
                        widget.onLongPress!();
                      }
                ..onLongPressEnd = widget.onLongPress != null
                    ? (_) => setState(() => _pressed = false)
                    : null;
            },
          ),
        },
        child: AnimatedScale(
          scale: scale,
          duration: kAnimFast,
          curve: kAnimCurve,
          child: AnimatedContainer(
            duration: kAnimFast,
            curve: kAnimCurve,
            decoration: BoxDecoration(
              color: target,
              borderRadius: radius,
              border: widget.border,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
