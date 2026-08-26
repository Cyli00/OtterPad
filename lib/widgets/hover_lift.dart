import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import '../core/elevation.dart';

/// 桌面 hover 时把 Card 阴影从 blur 10 抬到 16。
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: kAnimFast,
        curve: kAnimCurve,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: _hovered && widget.enabled
              ? AppShadows.cardHover
              : AppShadows.card,
        ),
        child: widget.child,
      ),
    );
  }
}
