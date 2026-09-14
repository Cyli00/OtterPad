# 交互规范

用于新增动效、手势、触觉反馈或修改相关组件。源码路径均相对项目根目录。

## 动画选择

时长、曲线和弹簧参数统一取自 `lib/core/animation_constants.dart`，具体数值由源码维护。

| Token | 用途 |
|---|---|
| kAnimFast | hover、按压、选择切换、工具栏微交互 |
| kAnim | 状态与内容变化、面板收起 |
| kAnimSlow | 路由、弹窗、面板展开 |
| kAnimEmphasis | 卡片进入阅读器的容器变换 |
| kAnimPulse | 循环呼吸或发光 |
| kAnimCurve / kAnimCurveReverse | 正向 / 反向缓动 |
| kSpringPress / kSpringSelection / kSpringPanel | 按压 / 选中弹出 / 面板开合 |

| 场景 | 项目方案 |
|---|---|
| 路由转场 | package:animations 的 FadeThroughTransition，kAnimSlow |
| 页内视图切换 | 水平 SharedAxisTransition，kAnimSlow |
| Dialog | showAppDialog 内置转场 |
| 按压 | TactilePress |
| 选中态勾选 | SpringPop |
| 列表入场 | StaggeredEntrance，仅首屏，后续分页不重复播放 |
| 工具栏、面板滑出 | ClipRect 包裹 AnimatedSlide，kAnim |
| Android 预测返回 | PredictiveBackPageTransitionsBuilder；非手势沿用项目转场 |

路由级不使用 `flutter_animate` 的 `slideY/fade` 替代项目转场。
`StaggeredEntrance` 的数量上限和交错参数由 `lib/widgets/staggered_entrance.dart` 维护。
阅读器容器变换与 dock 见[桌面与阅读器](desktop-reader.md#阅读器动效与预览)。

## 点击与手势

复用 `lib/widgets/tactile_press.dart`，不以裸 `GestureDetector` 替代其点击反馈。

| 场景 | 配置 |
|---|---|
| 独立卡片 | 显式容器 baseColor，推荐 pressedScale: 0.98 |
| 选中态容器 | baseColor 随选中状态变化 |
| section、sheet 内嵌项和面板工具按钮 | baseColor: Colors.transparent，通常省略 pressedScale |
| 纯图标按钮 | IconButton，保留 Material 默认反馈 |

`TactilePress` 会绘制背景；省略 baseColor 会在父容器上增加不需要的色块。
需要 `onLongPressStart(details)` 位置信息时，可由外层 `GestureDetector` 只接收 longPress、内层 `TactilePress` 接收 tap；避免重复注册同一长按动作或反馈。

## 触觉反馈

调用 `lib/services/haptics.dart` 的 `Haptics`，不直接调用平台 `HapticFeedback`。

- `soft()`：工具栏、TabBar、普通按钮等日常点击。
- `light()`：Picker 点选、Switch 切换等轻量确认。
- `medium()`：删除、清空、滑动删除完成或长按菜单。
- 使用封装组件时沿用其内置触觉，不再在调用方重复触发。

## 滑动删除

复用 `lib/widgets/spring_dismissible.dart` 的 `SpringDismissible`，不替换为 Flutter `Dismissible` 或 `flutter_slidable`。

列表项调用处必须以业务唯一 ID 提供稳定 `ValueKey`，防止删除后按位置复用 State，导致相邻项继承残留动画。
方向、距离与速度阈值、回弹参数、背景渐显和完成反馈由组件内部维护；仅在任务要求改变删除手感时修改这些实现。
