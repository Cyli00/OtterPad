---
name: flutter-design
description: 构建符合项目设计规范的 Flutter UI 组件。在创建新页面、对话框、卡片、底部面板、设置项等 UI 元素时使用，确保视觉语言与现有组件一致。
---

# OtterPad 设计规范

所有 UI 组件严格遵循以下 Token 和组件参数。禁止自创圆角、颜色、字体。

## 文档结构约定

本文件按 **全局 Token → 交互模式 → 组件规范** 三层组织。新增规范时遵循以下章法：

1. **归属判断**：新规范优先归入已有章节；若无匹配，在对应层级末尾新增子节
   - 颜色 / 圆角 / 字体 / 动画等原子值 → §1 全局 Token
   - 跨组件的交互行为（点击反馈、手势、预览语义等）→ §2 交互模式
   - 具体组件的视觉参数 → §3 组件规范
2. **格式要求**：每个组件节必须包含
   - `> 参考：` 行列出代表性实现文件
   - 属性用 **table** 列出（属性 | 值），禁止散文体罗列
   - 多状态对比用独立 table（状态 | 背景 | 边框 …）
   - 约束 / 禁止项用 bullet list，以「禁止」或「仅」开头
3. **不写什么**：架构实现细节（数据流 / 注册表 / Hive key）不属于设计规范，应写入 CLAUDE.md
4. **共性提取**：两个组件共享 ≥3 项视觉参数时，提取「共用参数」表，各自只列差异

---

## 1. 全局 Token

### 1.1 图标

唯一图标集 `Symbols.xxx`（`material_symbols_icons`）。禁止 `Icons.xxx`。

### 1.2 颜色

仅使用 `ColorScheme` token。禁止 `Color(0xFF...)`、手写 HSL、alphaBlend 叠色。

**表面分层**（从浅到深）：

| token | 用途 |
|---|---|
| `surface` | Scaffold body、阅读器主内容 |
| `surfaceContainerLow` | Card / Dialog / 输入框 |
| `surfaceContainer` | 侧栏 `AdaptiveNavigationRail` / 底栏 `NavigationBar` |
| `surfaceContainerHigh` | Bottom Sheet / 菜单 / 设置区块 |
| `surfaceContainerHighest` | 桌面标题栏 `WindowChrome` / 输入框 fillColor 备选 |
| `primaryContainer` | Badge / 图标盒 / 选中态 Chip / 选中态 SegmentedButton |

原则：框架壳（导航栏 / 标题栏）比内容区深一到两阶。

**文字色阶**：`onSurface` → `onSurfaceVariant` → `onSurfaceVariant.withAlpha(N)`

### 1.3 圆角

| 值 | 用途 |
|---|---|
| **12** | 输入框 / Slider 胶囊 / 图标盒 / Chip / SegmentedButton |
| **16** | Card / Tile |
| **24** | 设置区块 |
| **28** | Dialog / Bottom Sheet |

### 1.4 字体

仅使用 `TextTheme` token。禁止硬编码 `fontSize`、`isDense: true`、`headlineMedium` 及以上。

| 用途 | Style |
|---|---|
| 页面 / Dialog 标题 | `titleLarge` bold |
| 分节 / 卡片标题 | `titleMedium` bold |
| 设置项 / Slider 标题 | `titleSmall` w600 |
| 正文 | `bodyMedium` |
| 辅助说明 | `bodySmall` + `onSurfaceVariant` |
| Badge / 胶囊数值 | `labelMedium` w700 |

### 1.5 动画

所有动画时长和曲线来自 `lib/core/animation_constants.dart`，禁止硬编码 Duration 魔法数字。

**全局常量**：

| 常量 | 值 | 用途 |
|---|---|---|
| `kAnimFast` | 180ms | 微交互（hover、选择切换、按压态、工具栏） |
| `kAnim` | 240ms | 标准过渡（状态变化、内容切换、面板收起） |
| `kAnimSlow` | 320ms | 大转场（路由、弹窗、面板展开） |
| `kAnimEmphasis` | 500ms | 大强调（卡片→阅读器容器变换） |
| `kAnimPulse` | 1200ms | 循环脉冲（呼吸 / 发光），配 `repeat(reverse: ...)` |
| `kAnimCurve` | `Curves.easeOutCubic` | 统一正向缓动 |
| `kAnimCurveReverse` | `Curves.easeInCubic` | 统一反向缓动 |

**弹簧 Token**（配 `motor` 的 `SpringMotion` 使用）：

| 常量 | stiffness / damping | 用途 |
|---|---|---|
| `kSpringPress` | 400 / 22（ζ≈0.49，欠阻尼微回弹） | 按压 scale 1→0.96→1，可中断 |
| `kSpringSelection` | 500 / 20 | 勾选 / 图标盒 scale 0.8→1 弹出，~200ms 完成 |
| `kSpringPanel` | 500 / 28（ζ≈0.63） | 面板开合（阅读器 dock 宽度），可中断 |

**场景对照**：

| 场景 | 方案 | 时长 | 曲线 |
|---|---|---|---|
| 路由转场 | `FadeThroughTransition`（`package:animations`） | `kAnimSlow` | FadeThrough 内置 |
| 页内视图切换（如 PDF↔Markdown） | `SharedAxisTransition` 水平 | `kAnimSlow` | SharedAxis 内置 |
| 对话框转场 | `showAppDialog()` Scale(easeOutBack 轻回弹)+Fade+Blur | `kAnimSlow` | `easeOutBack` / `kAnimCurveReverse` |
| 按压微交互 | `TactilePress` 内 motor 弹簧（`kSpringPress`） | — | spring |
| 选中态勾选 | `SpringPop`（`kSpringSelection`，0.8→1 + 渐显） | ~200ms | spring |
| 列表入场 | `StaggeredEntrance`（首屏 ≤8 项 × 30ms 延迟，fade + slideY 12px→0，之后分页不动） | `kAnimFast` | `kAnimCurve` |
| 阅读器入场 | 卡片 rect → 全屏容器变换（手写双边界裁切+缩放+渐显），无起点回落 scale+fade 微上移 | `kAnimEmphasis` / `kAnimSlow` | `kAnimCurve` |
| 工具栏 / 面板滑出 | `ClipRect > AnimatedSlide`（外层必须包 `ClipRect` 防位移透出透明状态栏） | `kAnim` | `kAnimCurve` |
| 原文定位返回引导条 | `AnimatedPositioned` | `kAnim` | `kAnimCurve` |
| 阅读器 dock 开合 | `SingleMotionBuilder` + `kSpringPanel` | — | spring |
| Android 预测返回 | `PredictiveBackPageTransitionsBuilder`（手势中）；非手势回落 FadeThrough / SharedAxis | 框架 | 框架 |

禁止路由级使用 `flutter_animate` 的 `slideY()` / `fade()`。

### 1.6 阴影分层

> 参考：`AppShadows`（lib/core/elevation.dart）

禁止组件自写 `BoxShadow` blur / offset。桌面 Card hover 走 `HoverLift`。

| 层级 | blur | y | Token |
|---|---|---|---|
| Card | 10 | 4 | `AppShadows.card` |
| 浮层工具条 | 16 | 8 | `AppShadows.bar` |
| BottomSheet | 20 | 10 | `AppShadows.sheet` |
| Dialog | 24 | 12 | `AppShadows.dialog` |
| Card hover 抬升 | 16 | 4 | `AppShadows.cardHover` |

### 1.7 分隔线

> 参考：`AppDivider`（lib/widgets/app_divider.dart）

颜色统一 `outlineVariant.withAlpha(80)`。禁止再写 40 / 60 / 70 / 128。

| 档 | indent / endIndent | 用途 |
|---|---|---|
| `AppDivider()` | 20 / 20 | 无前置图标的行间 |
| `AppDivider.tile()` | 80 / 20 | 设置项（padding 20 + 图标 44 + 间距 16） |
| `AppDivider.full()` | 0 / 0 | 分段全宽 |

---

## 2. 交互模式

### 2.1 点击反馈

> 参考：`TactilePress`（lib/widgets/tactile_press.dart）

所有可点击 Card / Tile / 列表项使用 `TactilePress`。禁止裸 `GestureDetector`。

```dart
TactilePress(
  onTap: ...,
  onLongPress: ...,        // 可选，自动触发 Haptics.medium()
  borderRadius: ...,       // 默认 12
  baseColor: ...,          // 默认 dark=Colors.white10, light=cs.surface
  pressedScale: 0.98,      // 可选，卡片推荐加，列表项可省略
  haptics: true,           // 默认 true，tap 触发 Haptics.soft()
  child: ...,
)
```

**反馈层次**：ColorTween 按压态（即时色变） + 可选 micro-scale（motor 弹簧 `kSpringPress`） + 触觉反馈（`Haptics`）。

**baseColor 规则**：TactilePress 始终渲染带色圆角背景，必须根据上下文显式指定。

| 上下文 | baseColor | 说明 |
|---|---|---|
| 独立容器（Card、picker collapsed） | 显式颜色（如 `cs.surfaceContainerLow`） | 自带背景 |
| 选中态（chip、segment） | 条件色（如 `selected ? cs.primaryContainer : cs.surfaceContainerLow`） | 状态驱动 |
| 内嵌项（section 列表项、sheet item、toolbar 按钮） | `Colors.transparent` | 父容器已有背景，仅保留 hover/press 色变 |

禁止省略 baseColor 让默认值（`cs.surface`）在 section / sheet 内渲染多余背景层。

**分层指引**：

| 场景 | 方案 |
|---|---|
| Card / 大面积可点击区域 | `TactilePress`（pressedScale: 0.98 · 显式 baseColor） |
| 列表项 / Sheet item | `TactilePress`（baseColor: transparent · 省略 pressedScale） |
| 底部面板内工具按钮 | `TactilePress`（baseColor: transparent） |
| 纯图标按钮 | `IconButton`（保留 Material 默认） |

**触觉反馈档位**（`Haptics`，`lib/services/haptics.dart`）：

- `soft()`：日常轻量点击（工具栏图标、TabBar、普通按钮）
- `light()`：轻量确认（选项敲定、Picker 点选、Switch 开关）
- `medium()`：破坏性操作（删除、清空、滑动删除完成）或长按呼出菜单
- 约束：禁止直接调用 `HapticFeedback.*`，统一经 `Haptics` 封装。

需要 `onLongPressStart(details)` 位置信息时：外层 `GestureDetector` 只注册 longPress，内层 `TactilePress` 管 tap（手势类型不同，不抢 gesture arena）。

### 2.2 滑动删除（Swipe to Dismiss）

> 参考：`SpringDismissible`（lib/widgets/spring_dismissible.dart）

禁止使用 Flutter 内置 `Dismissible` 或第三方 `flutter_slidable`。统一使用项目内 `SpringDismissible`，提供弹簧回弹和防误删阈值。

| 属性 | 值 |
|---|---|
| 方向 | `endToStart`（右→左） |
| 确认阈值 | 滑动距离 ≥ 55% 卡片宽度，**或**速度 ≥ 1200 px/s |
| 回弹弹簧 | `SpringDescription(mass:1, stiffness:500, damping:28)`，ζ ≈ 0.63（欠阻尼，1–2 次弹跳） |
| 确认动画 | `kAnim`（240ms）`Curves.easeIn` 飞出屏幕，触发 `Haptics.medium()` + `onDismissed` |
| 背景配色 | `errorContainer` 背景 · `onErrorContainer` 图标 + 标签 · 右侧 padding 20 |
| 背景渐显 | `Curves.easeIn.transform(reveal)`，随拖拽深度加深 |

**必须配 `ValueKey`**：列表中凡包含 `SpringDismissible` 的 tile，调用处必须加 `key: ValueKey(uniqueId)`，防止删除后 Flutter 按位置复用 State 导致残留动画污染相邻 tile。

### 2.3 预览卡语义

预览卡展示「选中后的效果」而非「当前运行时色」。跟随型选项（如 `ReaderTheme.themed`）锁定语义对应的固定色调（白天锁浅色），避免 dark 模式下被染黑失去选项语义。

### 2.4 桌面端差异化

仅 `isDesktopOs` 生效，移动端保持原有纯色 / 常规间距：

| 项 | 参数 |
|---|---|
| 窗口 Chrome 失焦 | 标题栏标题与按钮整体 `AnimatedOpacity 1→0.55`（`kAnimFast`），跟随系统窗焦点 |
| 侧栏半透明 | `AdaptiveScaffold` 桌面端侧栏 `surfaceContainer.withAlpha(180)`；与主内容 Row 分栏避让，禁止改回叠层压内容 |
| 紧凑密度 | `Responsive.compactDensity(context)`（桌面且宽 ≥1200）：卡片/列表**行距** -4px（12→8、16→12），列距与字号不动 |
| 右键菜单 | `showAppContextMenu`（`surfaceContainerHigh` · 圆角 16 · elevation 3）。桌面 OS 用 `onSecondaryTapDown`，移动端长按 |
| 窗口与浮层基准 | 桌面窗口最小/初始尺寸由 `DisplayMetrics` 推导；浮层/下拉菜单高度以**当前窗口**为基准（`windowH * 0.6`），禁止按物理屏幕分辨率计算 |
| 修饰键容错 | Windows/Linux 单击禁止将 Win/Super 或未进多选时的 Shift 视为多选键（防 IME 丢 key-up 导致 stuck）；Ctrl 点选，Shift 仅已多选时划选 |

- 半透明侧栏仅桌面端；非桌面端 `AdaptiveScaffold` 纯色侧栏
- macOS 红绿灯避让：未实测，暂缓（确认重叠后再加 ~70px 左内边距）

---

## 3. 组件规范

### 3.1 Dialog

> 参考：`showAppDialog`（lib/widgets/app_dialog.dart）· `_RemoteDialogScaffold`（backup_settings_page）· `showCreateFavoriteDialog`（create_favorite_dialog）

**入口**：统一使用 `showAppDialog()` 弹出对话框。禁止直接调用 `showDialog()` 或 `showGeneralDialog()`。

**转场**（`showAppDialog` 内置）：

| 属性 | 值 |
|---|---|
| 时长 | `kAnimSlow`（320ms） |
| 缩放 | 0.92 → 1.0（`easeOutBack` 轻回弹） |
| 透明度 | 0 → 1（`kAnimCurve`） |
| 背景模糊 | sigma 0 → 4 |
| 退出曲线 | `kAnimCurveReverse` |
| 遮罩色 | `Colors.black54` |

**Dialog 视觉**：

| 属性 | 值 |
|---|---|
| 背景 | `surfaceContainerLow` |
| 圆角 | 28 |
| padding | `fromLTRB(24, 24, 24, 20)` |
| maxWidth | 540（配置型）/ `(w * 0.85).clamp(320, 480)`（创建型） |
| 标题 | `titleLarge` bold |

**底部按钮**：统一 `TextButton`，无背景填充，仅 hover overlay 反馈。

| 角色 | 样式 |
|---|---|
| 取消 | 默认主题（无自定义） |
| 确认（保存 / 创建 / 添加） | 默认主题（primary 文字色） |
| 危险操作（删除 / 清空 / 清除） | `foregroundColor: cs.error` |

按钮约束：
- 布局 `Row` + `MainAxisAlignment.end` · 间距 `SizedBox(width: 8)`
- 禁止 `FilledButton` / `OutlinedButton` / `Expanded` 等宽布局
- 禁止自定义按钮 `padding` / `borderRadius`
- 选择型 Dialog（点击列表项即确认）只需「清除」+「取消」

### 3.2 Bottom Sheet

> 参考：`showToolbarSheet`（toolbar_bottom_sheet）

| 属性 | 值 |
|---|---|
| backgroundColor | `transparent` + `BackdropFilter(blur: 4, 4)` |
| 容器背景 | `surfaceContainerHigh` |
| 顶部圆角 | 28 |
| Grabber | 32×4 · `onSurfaceVariant.withAlpha(80)` · 圆角 2 |
| 底部留白 | `padding.bottom + 16` |

例外：阅读器面板（reader_text_sheet / reader_theme_sheet）不加 blur，需实时预览。

**SheetItem**：44×44 图标盒（圆角 12 · `primaryContainer` · 22px `primary`）· `bodyLarge` w600 · `bodySmall` `onSurfaceVariant` · chevron `.withAlpha(120)`

### 3.3 Card

> 参考：`DocumentCard` · `DocListCard` · `FavoriteCard`

| 属性 | 值 |
|---|---|
| 圆角 | 16 |
| 背景 | `surfaceContainerLow` |
| 标题 | `titleMedium` bold |
| 阴影 | `AppShadows.card`；桌面 hover `HoverLift`（blur 10→16） |
| 选中边框 | `primary.withAlpha(160)` width 2 |
| 点击反馈 | `TactilePress`（pressedScale: 0.98） |
| 选中动画 | 边框 `AnimatedContainer` `kAnimFast` + 勾选 `SpringPop`（弹簧 scale 0.8→1 + 渐显） |

### 3.4 TextField

> 参考：`_ConfigField`（backup_settings_page）· `fieldDeco`（ocr_settings_page）

| 属性 | 值 |
|---|---|
| filled | true |
| fillColor | `surfaceContainerLow` |
| 圆角 | 12 |
| enabled 边框 | `outline` |
| focused 边框 | `primary` width 2 |
| contentPadding | h:16 v:14 |
| prefixIcon | 20px `onSurfaceVariant` |

label 选择规则：
- **labelText**：上级无独立标题，或同级全是 TextField
- **hintText**：上方有标题且同级有非 TextField 元素

### 3.5 Slider

> 参考：`_sliderRow`（agent_model_params_sheet）

签名：`double? value` + `double fallback` + `String Function(double) formatter`

| 属性 | 值 |
|---|---|
| 外层 Padding | h:20 v:12 |
| 标题 | `titleSmall` w600 + `_helpIcon` |
| SliderTheme | thumb 8 · overlay 16 · track 3 |
| 重置按钮 | `Symbols.refresh_rounded` 20px · 始终渲染 · null 态 `onPressed: null` |

**胶囊标签**：`padding(h:10, v:4)` 圆角 12 · `labelMedium` w700 · 始终显示格式化数值，禁止「默认」文字

| 状态 | 背景 | 边框 |
|---|---|---|
| 已设值 | `primaryContainer` / `onPrimaryContainer` | — |
| 默认值 | `surfaceContainerHighest.withAlpha(160)` | `outlineVariant.withAlpha(80)` |

### 3.6 SegmentedButton

> 全局统一：appearance_settings · api_settings_agent · ocr_settings · backup_settings · agent_model_params_sheet · translation_settings

```dart
SegmentedButton.styleFrom(
  backgroundColor: cs.surface,
  selectedBackgroundColor: cs.primaryContainer,
  side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
)
```

- 外层 `SizedBox(width: double.infinity)` 撑满
- `showSelectedIcon: false`
- 可选：`foregroundColor: cs.onSurfaceVariant` · `selectedForegroundColor: cs.onPrimaryContainer` · `textStyle: bodyMedium w600`

**何时不应使用**：选项 ≥ 4，或选项 ≥ 3 且任一标签字符数 ≥ 5——SegmentedButton 强制等分宽度会触发 `1...` 截断或 `Op/en/AI` 竖向折断。改用 §3.8 SettingPicker。

| 场景 | 选项数 | 最长标签 | 选用 |
|---|---|---|---|
| 主题模式（自动 / 亮 / 暗） | 3 | 2 字符 | SegmentedButton |
| 备份类型（S3 / WebDAV） | 2 | 6 字符 | SegmentedButton（2 选项单段足够宽） |
| 服务商（OpenAI / Anthropic / Gemini / Other） | 4 | 9 字符 | SettingPicker |
| 画幅比例（1:1 … 9:16） | 6 | 6 字符 | SettingPicker |

### 3.7 Chip 选择器

两种 Chip 变体共享相同的视觉骨架，区别在于内容渲染。

**共用参数**：

| 属性 | 值 |
|---|---|
| 布局 | `Wrap(spacing: 8, runSpacing: 8)` |
| 圆角 | 12 |
| 选中态背景 | `primaryContainer` |
| 选中态边框 | `Colors.transparent` |
| 未选中态边框 | `outlineVariant.withAlpha(100)` |
| 标题行 | `titleSmall` w600 + `_helpIcon` |

#### FilterChip（忽略标签）

> 参考：`_ignoreLabelChips`（ocr_settings）· `_buildIgnoreSectionChips`（translation_settings）

- 组件：`FilterChip` · `showCheckmark: false`
- 未选中态背景：`surface`

#### StylePreviewChip（自描述样式选择器）

> 参考：`_buildStyleChip`（translation_settings）

自描述：chip 文本 = 样式名称，用对应样式渲染（如「加粗」用粗体、「主题色」用 primary 色）。

- 容器：`Container(clipBehavior: antiAlias) > Material > InkWell > Padding(h:16, v:10)`
- 未选中态背景：`surfaceContainerLow`
- 文本：`bodyMedium` + 样式自身视觉效果
- 模糊预览 sigma **3**（低于渲染层 6，保持可读性）
- 约束：样式仅在双语对照模式生效；仅译文模式下 `weaveTranslated()` 直接返回原文

### 3.8 SettingPicker

> 参考：`SettingPicker<T>`（setting_picker.dart）

单选 picker：折叠态显示当前值 + ▼，展开态按终端分型——移动端 bottom sheet，桌面端锚定下拉菜单（`isDesktopOs`）。SegmentedButton 在长标签 / 多选项时的替代品（决策表见 §3.6）。

**折叠态**：

| 属性 | 值 |
|---|---|
| 布局 | `InkWell > Container > Row(Expanded(Text label) · Icon ▼)` |
| width | `double.infinity` |
| padding | h:16 v:14 |
| 圆角 | 16 |
| 背景 | `cs.surface` |
| 边框 | `outlineVariant.withAlpha(100)` |
| label | `bodyMedium` w500 |
| trailing | `Symbols.expand_more_rounded` 20px `onSurfaceVariant` |

**Bottom sheet**：沿用 §3.2 全部规范（`surfaceContainerHigh` + 28 圆角 + grabber）。例外：移除 `BackdropFilter`——picker 内容无预览语义、blur 多此一举。

**Sheet item**：

| 属性 | 值 |
|---|---|
| 容器 | `InkWell + Padding(h:24, v:12)` |
| 主标题 | `bodyLarge` · 选中 w700 + `cs.primary` · 默认 w500 + `cs.onSurface` |
| 副标题（可选 `subtitleFor`） | `bodySmall` `cs.onSurfaceVariant` |
| 选中态 trailing | `Symbols.check_rounded` 20px `cs.primary` |

- API 签名：`current` · `options` · `labelFor` · `subtitleFor?` · `sheetTitle` · `onChanged`
- sheet 走 `constraints: maxWidth: 480` 居中
- 点选立即触发 `onChanged` 并自动关闭 sheet（无显式确认按钮）
- 仅用于「单选 from 固定列表」场景；多选见 §3.7 FilterChip

**桌面端下拉菜单**（`isDesktopOs` 分支，替代 bottom sheet）：

| 属性 | 值 |
|---|---|
| 容器 | `MenuAnchor` + `MenuItemButton` |
| 面板 | `surfaceContainerHigh` · 圆角 16 · elevation 3（同 `app_context_menu`） |
| 定位 | 贴触发框下沿左缘 · `alignmentOffset: Offset(0, 4)` · 空间不足自动翻折 |
| 宽度 | 内容自适应 · 下限 240 / 上限 480 |
| 高度 | 窗口高 × 0.6，clamp `[240, 400]`，超出滚动 |
| 触发态 | chevron `AnimatedRotation` 0→0.5 · `kAnimFast` / `kAnimCurve` |
| 选项行 | 主标题 `bodyMedium` w500（选中 w700 + `cs.primary`）· 副标题 `bodySmall` `cs.onSurfaceVariant` |
| 选中态 trailing | `Symbols.check_rounded` 20px `cs.primary` |

- 宽度下限必须写在每个 `MenuItemButton.minimumSize`：`MenuStyle.minimumSize` 被面板 `IntrinsicWidth` 静默忽略（下限失效且不报错）
- 高度上限以**窗口**为基准（弹出层受窗口约束），`MenuAnchor` 会再按可用空间收窄
- 键盘 ↑↓ / Enter / Esc 由 `MenuAnchor` 提供，禁止自实现
- 禁止按选项数量分型（菜单溢出即滚动，会让同一控件出现两种模态）；禁止在桌面端用 bottom sheet 承载枚举选择

### 3.9 设置分组（SettingGroup）

> 参考：`SettingGroup`（lib/pages/setting/setting_group.dart）· 各 `*_settings_page`

所有设置页分组统一使用 `SettingGroup`，禁止再复制 `_buildGroup` 容器。

| 属性 | 值 |
|---|---|
| 标题 | `titleMedium` bold · `primary` · padding left:16 bottom:12 top:24 |
| 容器 | `surfaceContainerHigh` · 圆角 24 · `clipBehavior: antiAlias` · 宽度撑满 |
| 内部祖先 | 内置 `Material(transparency)`（为 ListTile/RadioListTile 提供最近 Material 祖先） |

### 3.10 阅读器底栏与工具栏

> 参考：`ReaderBottomBar`（lib/pages/reader/widgets/reader_bottom_bar.dart）· `ReaderTopToolbar`（lib/pages/reader/widgets/reader_top_toolbar.dart）

底栏按 `desktop` 分型，顶部工具栏与底栏均需适配窄屏与侧栏占用。

**底栏分型**：

| 属性 | 移动端 | 桌面端 |
|---|---|---|
| 容器 | 通栏吸底 · 高度 56 + safe area | 居中浮动药丸 · `Align(bottomCenter)` |
| 背景 | `surfaceContainer` · 顶边 `outlineVariant.withAlpha(80)` | `surfaceContainerHigh` · 圆角 16 |
| 边框 / 阴影 | — | 描边 `outlineVariant.withAlpha(80)` · `AppShadows.bar` |
| 外边距 | 仅 safe area 底部留白 | 左右 16 · 下方 `padding.bottom + 16` |
| 内边距 | — | 水平 8 · 垂直 4 |
| 按钮尺寸 | 等分拉伸（`spaceEvenly`） | 48×48 正方形按钮 · 紧凑排布 |

**工具栏自适应横滚**：
- 顶部工具栏右侧操作区与桌面浮动底栏在小屏或侧栏展开时，外层必须包裹 `SingleChildScrollView(scrollDirection: Axis.horizontal)`
- 右侧操作区靠右对齐（`Expanded > Align(centerRight)`），禁止硬编码固定宽度或在小屏下允许 RenderFlex overflow 溢出
- 工具栏滑出入场必须外层包裹 `ClipRect`：`AnimatedSlide` 内部 transform 仅做 paint 位移，缺少 `ClipRect` 会透过透明系统状态栏透出

### 3.11 接口配置与用量卡片

> 参考：`OcrSettingsPage`（lib/pages/setting/ocr_settings_page.dart）· `_buildUsageCard`

用于展示外部 API 提供商切换、凭据录入及本地记账估算的配额/用量。

**提供商分段**：
- 选项数 ≤ 3 且标签短（如 PaddleOCR / MinerU）时统一使用 `SegmentedButton`（§3.6），长标签或多选项切 `SettingPicker`（§3.8）
- API Key / Token 凭据按提供商分槽独立持久化，切换提供商时控制器互不清空

**用量卡片视觉**：

| 属性 | 值 |
|---|---|
| 容器 | `surfaceContainerHigh` · 圆角 24 · padding 16 · 宽度撑满 |
| 标题行 | 标题 `titleSmall` w600 + `_helpIcon`，紧凑 Wrap 排布 |
| 数值胶囊 | `padding(h:10, v:4)` · 圆角 12 · `labelMedium` w700 |
| 胶囊颜色（正常） | `primaryContainer` 背景 · `onPrimaryContainer` 文本 |
| 胶囊颜色（超额/耗尽） | `errorContainer` 背景 · `onErrorContainer` 文本 |
| 进度条 | `ClipRRect(borderRadius: BorderRadius.circular(4))` · `LinearProgressIndicator` |
| 进度条高度 | `minHeight: 4` |
| 进度条背景色 | `outlineVariant.withAlpha(80)` |

- 仅在无远程配额查询接口时使用本地记账估算；并在标题旁提供 Tooltip 说明配额性质（硬上限 vs 降优先级）
- 进度百分比必须 `ratio.clamp(0.0, 1.0)` 兜底，防止超额时进度条渲染异常
