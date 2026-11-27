import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import '../core/design_tokens.dart';

/// 数字滚动：数值变化时逐位上下滚动，而不是整块刷新。
///
/// 只有变化的那几位会动；增大向上滚，减小向下滚。数位等宽，宽度不跳。
/// 减少动态效果时直接切换。
class RollingNumber extends StatefulWidget {
  const RollingNumber(this.value, {super.key, this.style, this.suffix = ''});

  final int value;
  final TextStyle? style;

  /// 跟在数字后面、不参与滚动的文字，如 `%`。
  final String suffix;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber> {
  bool _up = true;

  @override
  void didUpdateWidget(RollingNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _up = widget.value > old.value;
  }

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: AppType.tabular,
    );
    final digits = '${widget.value}';
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '$digits${widget.suffix}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (var i = 0; i < digits.length; i++)
            ClipRect(
              child: AnimatedSwitcher(
                duration: animate ? kAnim : Duration.zero,
                switchInCurve: kAnimCurve,
                switchOutCurve: kAnimCurve,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.center,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, animation) {
                  // 出场的位倒放动画（1→0），所以出场与进场的起点方向相反：
                  // 增大时新数从下方进、旧数向上方出。
                  final incoming = child.key == ValueKey(_digitKey(digits, i));
                  return SlideTransition(
                    position: Tween(
                      begin: Offset(0, _up == incoming ? 1 : -1),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Text(
                  digits[i],
                  key: ValueKey(_digitKey(digits, i)),
                  style: style,
                ),
              ),
            ),
          if (widget.suffix.isNotEmpty) Text(widget.suffix, style: style),
        ],
      ),
    );
  }

  /// 按「从右数第几位 + 数字」做 key：位数变化时个位仍对齐个位。
  static String _digitKey(String digits, int i) =>
      '${digits.length - i}:${digits[i]}';
}
