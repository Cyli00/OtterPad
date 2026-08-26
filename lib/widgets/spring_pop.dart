import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import '../core/animation_constants.dart';

/// 选中态弹出（勾选 / 图标盒）：弹簧 scale 0.8→1 + 不透明度渐显，
/// ~200ms 内完成，挂载时播放一次。替代各处 `easeOutBack` 手写实现。
class SpringPop extends StatelessWidget {
  const SpringPop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: const SpringMotion(kSpringSelection),
      from: 0,
      value: 1,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
      ),
      child: child,
    );
  }
}
