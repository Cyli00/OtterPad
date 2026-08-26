import 'package:flutter/widgets.dart';

import '../core/animation_constants.dart';

/// 列表交错入场：首屏前 [maxAnimatedCount] 项按 `index * 30ms` 延迟依次
/// fade + slideY(12px→0) 入场；之后的项与分页追加不重复动。
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  /// 列表下标；≥ [maxAnimatedCount] 时静置渲染、不参与动画。
  final int index;
  final Widget child;

  static const int maxAnimatedCount = 8;
  static const Duration stepDelay = Duration(milliseconds: 30);

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: kAnimFast);
    if (widget.index < StaggeredEntrance.maxAnimatedCount) {
      // 一次性播放，结束后保持终态；不参与后续 rebuild
      Future.delayed(StaggeredEntrance.stepDelay * widget.index, () {
        if (mounted) _ctrl.forward();
      });
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = kAnimCurve.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
