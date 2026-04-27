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

| 场景 | 方案 | 时长 |
|---|---|---|
| 路由转场 | `FadeThroughTransition`（`package:animations`） | 300ms easeOut |
| 页内视图切换 | `SharedAxisTransition` 水平 | 300ms |
| 选中态 | `AnimatedContainer` + 缩放 `easeOutBack` | 150 + 200ms |
| 工具栏滑出 | `AnimatedSlide` | 220ms easeOut |

禁止路由级使用 `flutter_animate` 的 `slideY()` / `fade()`。

---

## 2. 交互模式

### 2.1 点击反馈

所有可点击 Card / Tile 必须使用 `Material(type: transparency) + InkWell`。禁止裸 `GestureDetector`。

容器结构：
```
Container(clipBehavior: antiAlias, decoration) → Material → InkWell → Padding → child
```

- `Padding` 放在 InkWell 内部：确保 ripple 覆盖整卡
- `clipBehavior` 放在外层 Container：裁剪 ripple 到圆角范围

需要 `onLongPressStart(details)` 位置信息时：外层 `GestureDetector` 只注册 longPress，内层 InkWell 管 hover/tap（手势类型不同，不抢 gesture arena）。

### 2.2 滑动删除（Swipe to Dismiss）

> 参考：`_SpringDismissible`（agent_model_list_tile.dart）

禁止使用 Flutter 内置 `Dismissible` 或第三方 `flutter_slidable`。统一使用项目内 `_SpringDismissible`，提供弹簧回弹和防误删阈值。

| 属性 | 值 |
|---|---|
| 方向 | `endToStart`（右→左） |
| 确认阈值 | 滑动距离 ≥ 55% 卡片宽度，**或**速度 ≥ 1200 px/s |
| 回弹弹簧 | `SpringDescription(mass:1, stiffness:500, damping:28)`，ζ ≈ 0.63（欠阻尼，1–2 次弹跳） |
| 确认动画 | 220ms `Curves.easeIn` 飞出屏幕，完成后触发 `onDismissed` |
| 背景配色 | `errorContainer` 背景 · `onErrorContainer` 图标 + 标签 · 右侧 padding 20 |
| 背景渐显 | `Curves.easeIn.transform(reveal)`，随拖拽深度加深 |

**必须配 `ValueKey`**：列表中凡包含 `_SpringDismissible` 的 tile，调用处必须加 `key: ValueKey(uniqueId)`，防止删除后 Flutter 按位置复用 State 导致残留动画污染相邻 tile。

### 2.3 预览卡语义

预览卡展示「选中后的效果」而非「当前运行时色」。跟随型选项（如 `ReaderTheme.themed`）锁定语义对应的固定色调（白天锁浅色），避免 dark 模式下被染黑失去选项语义。

---

## 3. 组件规范

### 3.1 Dialog

> 参考：`_RemoteDialogScaffold`（backup_settings_page）· `showCreateFavoriteDialog`（create_favorite_dialog）

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
| 阴影 | `BoxShadow(black.withAlpha(13), blur: 10, offset: (0, 4))` |
| 选中边框 | `primary.withAlpha(160)` width 2 |
| 选中动画 | `AnimatedContainer` 150ms + 勾选缩放 200ms `easeOutBack` |

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
