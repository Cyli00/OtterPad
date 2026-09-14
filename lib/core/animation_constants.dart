import 'package:flutter/animation.dart';

const Duration kAnimFast = Duration(milliseconds: 180);
const Duration kAnim = Duration(milliseconds: 240);
const Duration kAnimSlow = Duration(milliseconds: 320);

/// 循环脉冲：呼吸 / 发光等循环往复动画（repeat/reverse）。
const Duration kAnimPulse = Duration(milliseconds: 1200);

/// 大强调：容器展开（卡片→页面）等大尺度强调动画。
const Duration kAnimEmphasis = Duration(milliseconds: 500);

const Curve kAnimCurve = Curves.easeOutCubic;
const Curve kAnimCurveReverse = Curves.easeInCubic;

/// 按压弹簧：scale 1→pressed 欠阻尼微回弹（ζ≈0.49），可中断。
/// 与 motor 的 `SpringMotion` 配合使用。
const SpringDescription kSpringPress = SpringDescription(
  mass: 1,
  stiffness: 400,
  damping: 22,
);

/// 选中态弹簧：勾选 / 图标盒 0.8→1 弹出，~200ms 内完成。
const SpringDescription kSpringSelection = SpringDescription(
  mass: 1,
  stiffness: 500,
  damping: 20,
);

/// 面板开合：近临界阻尼，可中断，避免宽度越界后裁切造成停顿与回跳。
const SpringDescription kSpringPanel = SpringDescription(
  mass: 1,
  stiffness: 500,
  damping: 45,
);
