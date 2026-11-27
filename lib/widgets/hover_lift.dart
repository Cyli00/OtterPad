import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import '../core/design_tokens.dart';
import '../core/elevation.dart';

/// 桌面 hover：卡片上浮 2px 并出现近实远虚的双层阴影，像纸从桌面抬起。
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
        transform: Matrix4.translationValues(
          0,
          _hovered && widget.enabled ? -2 : 0,
          0,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadius.mdAll,
          boxShadow: _hovered && widget.enabled
              ? AppShadows.cardHover
              : AppShadows.card,
        ),
        child: widget.child,
      ),
    );
  }
}
