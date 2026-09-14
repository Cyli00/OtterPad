---
name: flutter-design
description: 创建或调整 OtterPad Flutter 界面的视觉、交互和多端布局时使用；纯业务逻辑修改不适用。
---

# OtterPad UI 设计

沿用项目视觉语言，优先复用现有组件和主题。局部 UI 修改仅处理相关界面，不扩展为全项目样式重构。

## 核心设计约束

- 图标使用 `material_symbols_icons` 的 `Symbols`，不使用 `Icons`。
- 业务 UI 颜色使用 `ColorScheme`，不另写十六进制颜色、HSL 或叠色方案；透明背景、既有遮罩和明确的预览语义例外除外。
- 字体使用 `TextTheme`，不硬编码字号，不使用 `headlineMedium` 及以上；表单不使用 `isDense: true` 压缩密度。
- 默认圆角：输入框、图标盒、Chip、SegmentedButton 和数值胶囊为 12；Card/Tile 为 16；设置分组为 24；Dialog/Bottom Sheet 为 28。组件细节例外见参考。
- 动画复用 `lib/core/animation_constants.dart`，不硬编码时长或弹簧参数。
- 阴影复用 `lib/core/elevation.dart` 的 `AppShadows.card/bar/sheet/dialog/cardHover`，不在业务组件中自写阴影参数。

## 表面与文字层级

| 场景 | ColorScheme Token |
|---|---|
| 主内容 | surface |
| Card、Dialog、输入框 | surfaceContainerLow |
| 导航栏、移动端底栏 | surfaceContainer |
| Bottom Sheet、菜单、设置分组 | surfaceContainerHigh |
| 桌面标题栏、输入框背景备选 | surfaceContainerHighest |
| Badge、图标盒、选中态 | primaryContainer |

| 用途 | TextTheme 样式 |
|---|---|
| 页面、弹窗标题 | titleLarge bold |
| 分节、卡片标题 | titleMedium bold |
| 设置项、滑块标题 | titleSmall w600 |
| 正文 | bodyMedium |
| 辅助说明 | bodySmall + onSurfaceVariant |
| Badge、数值胶囊 | labelMedium w700 |

文字色阶使用 `onSurface`、`onSurfaceVariant` 及后者的透明度变体。

## 优先复用

以下源码路径均相对项目根目录；只查看本次需要调用或修改的组件。

- 弹窗：`showAppDialog`（`lib/widgets/app_dialog.dart`）；调用方不直接使用 `showDialog/showGeneralDialog`。
- 设置分组：`SettingGroup`（`lib/pages/setting/setting_group.dart`），不复制分组容器。
- 设置标题、帮助、重置与滑块：`lib/widgets/setting_controls.dart`。
- 分隔线：`AppDivider`（`lib/widgets/app_divider.dart`）；桌面卡片悬停：`HoverLift`（`lib/widgets/hover_lift.dart`）。
- 自定义可点击卡片、列表项：`TactilePress`（`lib/widgets/tactile_press.dart`），显式传入 `baseColor`；父容器已有背景的内嵌项使用透明底色。纯图标按钮保留 `IconButton`。
- 触觉：`Haptics`（`lib/services/haptics.dart`），不直接调用 `HapticFeedback` 或重复触发组件内置反馈。
- 滑动删除：`SpringDismissible`（`lib/widgets/spring_dismissible.dart`）；列表项调用处提供稳定的 `ValueKey(uniqueId)`，不用索引标识身份。
- 固定列表单选：`SettingPicker`（`lib/pages/setting/setting_picker.dart`）；少量且标签能完整显示的选项可用 `SegmentedButton`。多选使用 `FilterChip`。
- 桌面与移动端交互分型使用 `isDesktopOs`；尺寸依据当前窗口和可用空间。

## 按需参考

只阅读与本次修改相关的章节，不默认加载全部参考：

- 组件样式、设置行图标、弹窗按钮、选项控件：[组件规范](references/components.md)。
- 动效选择、手势、触觉或交互组件维护：[交互规范](references/interactions.md)。
- 桌面窗口、侧栏、阅读器工具栏或主题预览：[桌面与阅读器](references/desktop-reader.md)。

## 规范维护与验证

- 已封装组件的内部布局、默认值和动画参数由源码维护；文档保留使用条件、调用方约束和未封装的设计要求。
- 文档与实现不一致时，结合当前任务确认目标行为，不为匹配文档而修改无关组件。
- 业务状态和持久化规则放在对应模块文档；规范变更只更新受影响的条目。
- 检查改动涉及的主题、窗口尺寸和交互状态；仅运行相关验证，未运行的视觉验收如实说明。
