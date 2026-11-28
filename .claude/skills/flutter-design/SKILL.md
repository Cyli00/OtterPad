---
name: flutter-design
description: 创建或调整 OtterPad Flutter 界面的视觉、交互和多端布局时使用；纯业务逻辑修改不适用。
---

# OtterPad UI 设计

这里是默认约定，不是像素级规范：目标是界面一致、层级清晰、信息密度合适。有更好的方案可以偏离，在总结里说明理由。

## 硬约定

- 图标用 `material_symbols_icons` 的 `Symbols`。
- 视觉语言是 Folio（纸与墨、细线分隔、衬线刊头、收紧圆角），规范见 `docs/design-system.md`。
- 颜色取 `ColorScheme`，字号取 `TextTheme`；透明背景、遮罩和主题预览例外。
- 圆角、间距、细线、眉题与刊头字体取 `lib/core/design_tokens.dart`（`AppRadius`、`AppSpace`、`AppStroke`、`AppType`），组件不写裸数字圆角；配色经 `FolioPalette.scheme` 生成。
- 动画时长与弹簧取 `lib/core/animation_constants.dart`，阴影取 `lib/core/elevation.dart` 的 `AppShadows`，触觉走 `Haptics`（`lib/services/haptics.dart`）。
- 桌面与移动端的交互分型用 `isDesktopOs`，尺寸按当前窗口的可用空间判断。

## 优先复用

只打开本次要调用或修改的组件。

- 弹窗 `showAppDialog`（`lib/widgets/app_dialog.dart`）；反馈条 `SnackBarService`（`lib/services/snackbar_service.dart`，失败传 `tone: SnackTone.error`）。
- 设置页：`SettingGroup`、`SettingListView`、`settingFieldDecoration`（`lib/pages/setting/setting_group.dart`），`SettingPicker`（`setting_picker.dart`），标题、帮助、重置与滑块（`lib/widgets/setting_controls.dart`）。
- 可点击卡片与列表项 `TactilePress`（`lib/widgets/tactile_press.dart`，显式传 `baseColor`，父容器有背景时用透明）；分隔线 `AppDivider`；桌面悬停 `HoverLift`。
- 一级导航 `appDestinations` / `AppNavigationRail`（`lib/widgets/layout/`）。
- 面板开合 `SpringReveal`，同区域互斥切换 `FadeThroughBranches`；浮层出现与收起都要有动画。
- 滑动删除 `SpringDismissible`，列表项用稳定的 `ValueKey(uniqueId)`。

## 按需参考

- 组件样式、设置行、弹窗按钮、选项控件、SnackBar 文案：[组件规范](references/components.md)。
- 动效选择、手势、触觉：[交互规范](references/interactions.md)。
- 桌面窗口、侧栏、阅读器工具栏、主题预览：[桌面与阅读器](references/desktop-reader.md)。

## 验证

用 `flutter-drive` skill 在运行中的应用里截图检查改动涉及的窗口尺寸、主题和交互状态；没跑到的视觉验收如实说明。
