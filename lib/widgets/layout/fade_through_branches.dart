import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../core/animation_constants.dart';

/// StatefulShellRoute 的分支容器：切换 tab 时旧页淡出、新页淡入并轻微放大
/// （Material fade through）。
///
/// 与 IndexedStack 一样所有分支常驻、保留各自状态；非当前分支 Offstage 并停掉
/// ticker。每个分支始终包同一套 widget，只换动画参数，避免切换时分支子树重建。
/// 系统开启「减少动态效果」时直接切换。
class FadeThroughBranches extends StatefulWidget {
  const FadeThroughBranches({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<FadeThroughBranches> createState() => _FadeThroughBranchesState();
}

class _FadeThroughBranchesState extends State<FadeThroughBranches>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: kAnimSlow, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _previous != null) {
            setState(() => _previous = null);
          }
        });

  /// 正在淡出的分支；转场结束后置空
  int? _previous;

  @override
  void didUpdateWidget(FadeThroughBranches oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _previous = null;
      _ctrl.value = 1;
      return;
    }
    _previous = oldWidget.currentIndex;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++) _buildBranch(i),
      ],
    );
  }

  Widget _buildBranch(int index) {
    final isCurrent = index == widget.currentIndex;
    final isOutgoing = index == _previous;
    return Offstage(
      offstage: !isCurrent && !isOutgoing,
      child: TickerMode(
        enabled: isCurrent || isOutgoing,
        child: IgnorePointer(
          ignoring: !isCurrent,
          child: FadeThroughTransition(
            animation: isCurrent ? _ctrl : kAlwaysCompleteAnimation,
            secondaryAnimation: isOutgoing ? _ctrl : kAlwaysDismissedAnimation,
            fillColor: Colors.transparent,
            child: widget.children[index],
          ),
        ),
      ),
    );
  }
}
