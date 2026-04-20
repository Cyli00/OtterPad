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

### 颜色层级

`surface`（Scaffold）→ `surfaceContainerLow`（Card / 输入框）→ `surfaceContainerHigh`（Sheet / 菜单 / 设置区块）→ `primaryContainer`（Badge / 图标盒）

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
SheetItem：44×44 图标盒（圆角 12 · `primaryContainer` · 22px `primary`）· `bodyLarge` w600 · `bodySmall` `onSurfaceVariant` · chevron `.withAlpha(120)`

## Card

> `DocumentCard` · `DocListCard` · `FavoriteCard`

圆角 **16** · 背景 `surfaceContainerLow` · 标题 `titleMedium` bold
阴影 `BoxShadow(black.withAlpha(13), blur: 10, offset: (0, 4))`
选中边框 `primary.withAlpha(160)` width 2 · `AnimatedContainer` 150ms + 勾选缩放 200ms `easeOutBack`

## 动画

| 场景 | 方案 | 时长 |
|---|---|---|
| 路由转场 | `FadeThroughTransition` (`package:animations`) | 300ms easeOut |
| 视图切换 | `SharedAxisTransition` 水平 | 300ms |
| 选中态 | `AnimatedContainer` + 缩放 `easeOutBack` | 150+200ms |
| 工具栏 | `AnimatedSlide` | 220ms easeOut |

路由级禁止 `flutter_animate` 的 `slideY()` / `fade()`
