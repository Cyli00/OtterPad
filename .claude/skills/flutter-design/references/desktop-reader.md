# 桌面与阅读器

仅在修改桌面适配、阅读器布局或预览语义时使用。源码路径均相对项目根目录。

## 桌面窗口与侧栏

桌面交互以 `isDesktopOs` 分型，移动端保持纯色侧栏及常规间距。

| 场景 | 约定 |
|---|---|
| 窗口失焦 | WindowChrome 标题与按钮整体淡出至 0.55，使用 kAnimFast |
| 半透明侧栏 | 桌面 AdaptiveScaffold 使用 surfaceContainer.withAlpha(180)，与主内容分栏避让，不叠层遮挡内容 |
| 紧凑布局 | 使用 Responsive.compactDensity(context)，仅缩小行距，不改列距和字号 |
| 窗口尺寸 | 最小与初始尺寸由 DisplayMetrics 推导 |
| 阅读器右侧栏 | 桌面默认保持窗口左边缘，向右扩宽窗口；当前显示器工作区放不下、最大化或全屏时在窗口内展开。收起撤回自动增加的宽度，用户手动调宽后保留其尺寸 |
| 修饰键 | Windows/Linux 使用 Ctrl 点选；Shift 仅在已多选时划选，不把 Win/Super 当作多选键 |

参考 `lib/widgets/window_chrome.dart`、`lib/widgets/layout/adaptive_navigation.dart`、`lib/utils/responsive.dart`、`lib/services/display_metrics.dart`。
紧凑布局的断点与间距数值由现有实现维护；修饰键规则用于避免 IME 丢失 key-up 后误入多选。

## 菜单与浮层

复用 `lib/widgets/app_context_menu.dart` 的 `showAppContextMenu`；桌面右键用 `onSecondaryTapDown`，移动端使用长按。

`SettingPicker` 的桌面分支位于 `lib/pages/setting/setting_picker.dart`：

- 固定列表单选使用锚定菜单，移动端使用 bottom sheet；不随选项数量改变桌面模态。
- 沿用现有 MenuAnchor、MenuItemButton 和键盘导航，不自行实现 ↑↓、Enter、Esc。
- 面板使用 `surfaceContainerHigh`、圆角 16、elevation 3，与项目上下文菜单一致。
- 浮层高度依据当前窗口和可用空间，不依据物理屏幕分辨率；超出时滚动。
- 修改菜单宽度时保留每个 `MenuItemButton.minimumSize` 的下限设置。现有实现记录：仅设置面板 `MenuStyle.minimumSize` 会被 IntrinsicWidth 布局忽略。
- 具体宽高上下限、定位偏移、展开图标动画均由组件维护，不在调用方复制。

## 阅读器底栏与工具栏

参考 `lib/pages/reader/widgets/reader_bottom_bar.dart` 和 `lib/pages/reader/widgets/reader_top_toolbar.dart`。

| 属性 | 移动端 | 桌面端 |
|---|---|---|
| 形态 | 通栏吸底 | 居中浮动药丸 |
| 背景 | surfaceContainer | surfaceContainerHigh |
| 边框 / 阴影 | 顶边 outlineVariant.withAlpha(80) | 同色描边 + AppShadows.bar |
| 按钮 | 均匀分布 | 紧凑排布 |
| 安全区域 | 保留底部安全区域 | 保留底部安全区域与浮动留白 |

具体高度、按钮尺寸、圆角和内外边距复用现有组件。
顶部右侧操作区与桌面底栏要适应窄窗和侧栏展开：沿用水平滚动，右侧操作区靠右，不硬编码固定宽度导致溢出。
滑出工具栏时保留外层 `ClipRect`，避免 `AnimatedSlide` 的绘制位移透出透明状态栏。

## 阅读器动效与预览

- 阅读器入场沿用卡片矩形到全屏的容器变换；没有起点时回落为缩放、淡入和轻微上移，分别使用 `kAnimEmphasis/kAnimSlow`。
- dock 开合沿用 `SingleMotionBuilder` 与 `kSpringPanel`；原文定位返回引导条使用 `AnimatedPositioned` 与 `kAnim`。
- 主题预览展示“选中后的效果”，不直接套用当前运行时配色。跟随型选项按预览语义固定色调，例如白天预览固定浅色，避免当前深色主题改变选项含义。
- 阅读器实时预览面板不加背景模糊，保持底层效果可见。
