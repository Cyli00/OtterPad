import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 向左滑动超过 [threshold] 比例（或快速猛划）则删除；否则以弹簧动画回弹。
///
/// 使用 [SpringSimulation] 驱动回弹，产生真实的欠阻尼弹跳感。
/// [AnimationController.unbounded] 允许 value 超出 [0,1] 以支持弹跳过冲。
class SpringDismissible extends StatefulWidget {
  final Widget child;
  final Widget background;
  final VoidCallback onDismissed;

  /// 滑动比例阈值（相对于卡片宽度），超过则确认删除。
  final double threshold;

  /// 快速划动速度阈值（px/s），超过则无视位置直接删除。
  final double dismissVelocity;

  const SpringDismissible({
    super.key,
    required this.child,
    required this.background,
    required this.onDismissed,
    this.threshold = 0.55,
    this.dismissVelocity = 1200,
  });

  @override
  State<SpringDismissible> createState() => _SpringDismissibleState();
}

class _SpringDismissibleState extends State<SpringDismissible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double _offset = 0;
  double _width = 300;
  bool _dismissed = false;

  // ζ = damping / (2√(mass × stiffness)) ≈ 0.63 → 欠阻尼，有 1–2 次弹跳
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 28,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() => _offset = _controller.value);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_dismissed) return;
    _controller.stop();
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-_width, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dismissed) return;
    final velocity = d.primaryVelocity ?? 0;
    final fraction = -_offset / _width;

    if (fraction >= widget.threshold || velocity < -widget.dismissVelocity) {
      _dismissed = true;
      _controller.value = _offset;
      _controller
          .animateTo(
            -_width * 1.5,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeIn,
          )
          .then((_) {
        if (mounted) widget.onDismissed();
      });
    } else {
      _controller.value = _offset;
      _controller.animateWith(
        SpringSimulation(_spring, _offset, 0, velocity),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      _width = box.maxWidth;
      final reveal = Curves.easeIn.transform(
        (-_offset / _width).clamp(0.0, 1.0),
      );
      return GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(children: [
          Positioned.fill(
            child: Opacity(opacity: reveal, child: widget.background),
          ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ]),
      );
    });
  }
}
