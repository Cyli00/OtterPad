import 'package:flutter/animation.dart';
import 'package:motor/motor.dart';

const Duration kAnimFast = Duration(milliseconds: 180);
const Duration kAnim = Duration(milliseconds: 240);
const Duration kAnimSlow = Duration(milliseconds: 320);

/// 循环脉冲：呼吸 / 发光等循环往复动画（repeat/reverse）。
const Duration kAnimPulse = Duration(milliseconds: 1200);

/// 大强调：容器展开（卡片→页面）等大尺度强调动画。
const Duration kAnimEmphasis = Duration(milliseconds: 500);

const Curve kAnimCurve = Curves.easeOutCubic;
const Curve kAnimCurveReverse = Curves.easeInCubic;

// ── 弹簧 token ──
//
// Material 3 Expressive 的弹簧参数，由 motor 提供，配合 `SingleMotionBuilder`
// / `MotionBuilder` 使用。弹簧可中断：目标中途改变时带着当前速度继续。
// 位置、尺寸、缩放用 spatial；透明度、颜色等用 effects。

/// 小幅的空间变化：按压回弹、选中弹出。带轻微过冲。
const Motion kMotionSpatialFast = MaterialSpringMotion.expressiveSpatialFast();

/// 会被裁切的尺寸变化：面板开合、内容展开。标准档，过冲小到不可见，
/// 避免越界后裁切造成停顿与回跳。
const Motion kMotionSpatialSteady =
    MaterialSpringMotion.standardSpatialDefault();

/// 颜色、透明度、图标填充等效果变化，不过冲。
const Motion kMotionEffects = MaterialSpringMotion.expressiveEffectsDefault();
