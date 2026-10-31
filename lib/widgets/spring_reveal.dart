import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import '../core/animation_constants.dart';

/// 侧栏横向开合：外层裁切宽度由 [kMotionSpatialSteady] 弹簧补间（可中断），
/// 子树始终按自身完整宽度布局，开合过程中不重排。
///
/// [alignment] 决定内容贴哪一侧：左侧栏用 [Alignment.centerRight]（内容随右缘
/// 滑入滑出），右侧栏用 [Alignment.centerLeft]。收起期间忽略指针、焦点与语义。
class SpringReveal extends StatefulWidget {
  const SpringReveal({
    super.key,
    required this.open,
    required this.child,
    this.alignment = Alignment.centerLeft,
    this.animate = true,
    this.animateOnMount = false,
    this.onSettled,
  });

  final bool open;
  final Widget child;
  final Alignment alignment;

  /// false 时直接跳到终态（系统「减少动态效果」同样生效）。
  final bool animate;

  /// 首次挂载即为 open 时是否从收起态展开；常驻侧栏保持 false，避免进页就播放。
  final bool animateOnMount;

  /// 弹簧停稳后的下一帧回调；期间 [open] 又变化则不回调。
  final VoidCallback? onSettled;

  @override
  State<SpringReveal> createState() => _SpringRevealState();
}

class _SpringRevealState extends State<SpringReveal> {
  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    final target = open ? 1.0 : 0.0;
    final animate = widget.animate && !MediaQuery.disableAnimationsOf(context);
    return SingleMotionBuilder(
      motion: kMotionSpatialSteady,
      from: animate && widget.animateOnMount ? 0.0 : target,
      value: target,
      active: animate,
      onAnimationStatusChanged: (status) {
        if (status != AnimationStatus.completed &&
            status != AnimationStatus.dismissed) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.open == open) widget.onSettled?.call();
        });
      },
      builder: (context, t, child) {
        // 弹簧在容差内停下，吸附残余尾差，避免收起后留细缝或展开后差半像素。
        final factor = (t - target).abs() < 0.002 ? target : t.clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: !open || factor == 0,
          child: ExcludeFocus(
            excluding: !open,
            child: ExcludeSemantics(
              excluding: !open,
              child: ClipRect(
                child: Align(
                  alignment: widget.alignment,
                  widthFactor: factor,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: RepaintBoundary(child: widget.child),
    );
  }
}
