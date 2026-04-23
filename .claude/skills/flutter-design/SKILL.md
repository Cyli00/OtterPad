---
name: flutter-design
description: 构建符合项目设计规范的 Flutter UI 组件。在创建新页面、对话框、卡片、底部面板、设置项等 UI 元素时使用，确保视觉语言与现有组件一致。
---

# NightReader 设计范式

所有 UI 组件严格遵循以下参数。禁止自创圆角/颜色/字体。

## 全局约束

- 图标：`Symbols.xxx` only（`material_symbols_icons`），禁止 `Icons.xxx`
- 颜色：`ColorScheme` only，禁止 `Color(0xFF...)`
- 字体：`TextTheme` only，禁止硬编码 `fontSize`
- 禁止 `isDense: true`、`headlineMedium` 及以上

### 表面分层（MD3 surface tones）

三个维度，从浅到深：

| 维度 | token | 用途 |
|---|---|---|
| **内容区** | `surface` | Scaffold body、阅读器主内容 |
| **组件表面** | `surfaceContainerLow` | Card / 输入框 |
|  | `surfaceContainerHigh` | Sheet / 菜单 / Dialog / 设置区块 |
|  | `surfaceContainerHighest` | 输入框 fillColor 备选、棋盘格底 |
| **框架壳（app-level chrome）** | `surfaceContainer` | 侧栏 `AdaptiveNavigationRail` / 底栏 `NavigationBar` |
|  | `surfaceContainerHighest` | 桌面窗口标题栏 `WindowChrome` |
| **高亮组件** | `primaryContainer` | Badge / 图标盒 / 选中态 Rail item 走 `secondaryContainer` |

原则：**框架壳比内容区深一到两阶**，利用 MD3 seed-染色阶梯自然呈现层次；禁止手写 HSL/alphaBlend 叠色仿阶梯。

文字：`onSurface` → `onSurfaceVariant` → `onSurfaceVariant.withAlpha(N)`

### 圆角

12（胶囊 / 输入框 / 图标盒）→ 16（卡片 / Tile）→ 24（设置区块）→ 28（Dialog / Sheet）

### 字体

| 用途 | Style |
|---|---|
| 页面 / Dialog 标题 | `titleLarge` bold |
| 分节 / 卡片标题 | `titleMedium` bold |
| 设置项 / Slider 标题 | `titleSmall` w600 |
| 正文 | `bodyMedium` |
| 辅助 | `bodySmall` + `onSurfaceVariant` |
| Badge 数值 | `labelMedium` w700 |

## Slider

> `_sliderRow`（agent_model_params_sheet.dart）

- 签名：`double? value` + `double fallback` + `String Function(double) formatter`
- 外层 `Padding(h:20, v:12)` · 标题 `titleSmall` w600 + `_helpIcon`
- 胶囊 `padding(h:10, v:4)` 圆角 12 `labelMedium` w700
  - set 态：`primaryContainer` / `onPrimaryContainer`
  - default 态：`surfaceContainerHighest.withAlpha(160)` + `outlineVariant.withAlpha(80)` border
  - 始终显示格式化数值，禁止显示"默认"文字
- SliderTheme：thumb 8 · overlay 16 · track 3
- 重置按钮 `Symbols.refresh_rounded` 20px，始终渲染，null 态 `onPressed: null`

## TextField

> `_ConfigField`（backup_settings_page.dart）· `fieldDeco`（ocr_settings_page.dart）

- **labelText**：上级无独立标题，或同级全是 TextField
- **hintText**：上方有标题且同级有非 TextField 元素

两种模式共用：`filled:true` · `fillColor: surfaceContainerLow` · 圆角 12 · enabled `outline` · focused `primary` width 2 · `contentPadding(h:16, v:14)` · prefixIcon 20px `onSurfaceVariant`

## Dialog

> `_RemoteDialogScaffold`（backup_settings_page.dart）· `showCreateFavoriteDialog`（create_favorite_dialog.dart）

背景 `surfaceContainerLow` · 圆角 **28** · `padding: fromLTRB(24, 24, 24, 20)`
maxWidth：540（配置型）/ `(w * 0.85).clamp(320, 480)`（创建型）
标题 `titleLarge` bold · 内部 TextField `bodyMedium` prefixIcon 20 padding 16×14

## Bottom Sheet

> `showToolbarSheet`（toolbar_bottom_sheet.dart）

`backgroundColor: transparent` + `BackdropFilter(blur: 4, 4)`
容器 `surfaceContainerHigh` · 顶部圆角 **28**
Grabber **32×4** `onSurfaceVariant.withAlpha(80)` 圆角 2 · 底部 `padding.bottom + 16`
例外：阅读器面板（reader_text_sheet / reader_theme_sheet）不加 blur，需实时预览
SheetItem：44×44 图标盒（圆角 12 · `primaryContainer` · 22px `primary`）· `bodyLarge` w600 · `bodySmall` `onSurfaceVariant` · chevron `.withAlpha(120)`

## Card

> `DocumentCard` · `DocListCard` · `FavoriteCard`

圆角 **16** · 背景 `surfaceContainerLow` · 标题 `titleMedium` bold
阴影 `BoxShadow(black.withAlpha(13), blur: 10, offset: (0, 4))`
选中边框 `primary.withAlpha(160)` width 2 · `AnimatedContainer` 150ms + 勾选缩放 200ms `easeOutBack`

### 交互反馈（强制）

所有可点击卡片 / Tile 必须用 `Material(type: transparency) + InkWell`，禁止裸 `GestureDetector`。InkWell 同时提供桌面 hover overlay 和移动 ripple，单路径覆盖两端。

InkWell 的 hover/splash 画在 Material 的 ink 层、位于 child 之下——图片区域被缩略图盖住无反馈是正常的，文字/padding 空隙可见即符合预期（见 `DocListCard`）。

**需要 `onLongPressStart(details)` 位置信息时**（如 `FavoriteCard` 用 `globalPosition` 定位弹出菜单）：外层 `GestureDetector` 只注册 longPress、内层 InkWell 管 hover/tap。两者手势类型不同，不会抢 gesture arena。

容器结构：`Container(clipBehavior: antiAlias, decoration: ...) > Material > InkWell > Padding > child`。padding 放在 InkWell 内部（确保 ripple 覆盖整卡），`clipBehavior` 放在外层 Container（裁剪 ripple 到圆角范围内）。

### 选择器预览：预览色 vs 实际色解耦

预览卡（如 `ReaderTheme` 的 `_BackgroundCard`）应展示**选中后的效果**，而不是"当前主题下的运行时色"。当某个主题定义为"跟随应用 brightness"（如 `ReaderTheme.themed`）时，其预览卡必须锁定到该主题语义对应的固定色调（"白天"锁浅色），否则在 dark 模式下预览卡会被染黑、失去选项语义。

实现：在 card build 里单独为"跟随型"arm 返回固定 palette，其他 arm 继续走 `resolvePalette(theme, cs)`。

## SegmentedButton

> 全局统一风格：`appearance_settings_page` · `api_settings_agent` · `ocr_settings_page` · `backup_settings_page` · `agent_model_params_sheet` · `translation_settings_section`

```dart
SegmentedButton.styleFrom(
  backgroundColor: cs.surface,
  selectedBackgroundColor: cs.primaryContainer,
  side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
)
```

- 圆角 **12**（与输入框 / 胶囊 / 图标盒统一）
- 外层 `SizedBox(width: double.infinity)` 撑满
- `showSelectedIcon: false`（无勾选图标）
- 可选：`foregroundColor` `cs.onSurfaceVariant` · `selectedForegroundColor` `cs.onPrimaryContainer`
- 可选：`textStyle` `bodyMedium` w600

## FilterChip 忽略标签

> `_ignoreLabelChips`（ocr_settings_page.dart）· `_buildIgnoreSectionChips`（translation_settings_section.dart）

选中 = 忽略/启用该标签。视觉参数：

- 布局：`Wrap(spacing: 8, runSpacing: 8)`
- 组件：`FilterChip` · `showCheckmark: false`
- 选中态：`primaryContainer` 背景 · `Colors.transparent` 边框
- 未选中态：`surface` 背景 · `outlineVariant.withAlpha(100)` 边框
- 圆角 **12** · `RoundedRectangleBorder`
- 标题行复用 `_buildTitleRow(title, tooltip)` 或 `titleSmall` w600 + `_helpIcon`

### 翻译忽略模块（translation_skip_sections.dart）

可跳过区域的模块化注册表。新增区域两步完成：

1. 在 `kAllTranslationSkipSections` 追加 `TranslationSkipSectionDef(id, label)`
2. 在 `detectSkipSections()` 添加对应的标题正则检测分支

- 配置存储：`TranslationConfig.ignoreSections: List<String>`（Hive key `translation_config_ignore_sections`）
- 提取器接口：`MarkdownParagraphExtractor.extract(md, ignoreSections: [...])`
  - 列表内 ID → 整段跳过
  - 不在列表的已知区域 → 合并为单个 `TranslatableParagraph` 送入 LLM
- UI 自动拾取 `kAllTranslationSkipSections` 生成 FilterChip，无需改设置页

## 动画

| 场景 | 方案 | 时长 |
|---|---|---|
| 路由转场 | `FadeThroughTransition` (`package:animations`) | 300ms easeOut |
| 视图切换 | `SharedAxisTransition` 水平 | 300ms |
| 选中态 | `AnimatedContainer` + 缩放 `easeOutBack` | 150+200ms |
| 工具栏 | `AnimatedSlide` | 220ms easeOut |

路由级禁止 `flutter_animate` 的 `slideY()` / `fade()`
