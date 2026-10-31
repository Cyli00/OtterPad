# 组件规范

用于创建或调整组件外观与设置项。共享 Token 和组件入口见 [SKILL.md](../SKILL.md)；以下源码路径相对项目根目录。

## Dialog

参考 `lib/widgets/app_dialog.dart`、`lib/pages/setting/backup_settings_page.dart`、`lib/pages/shelf/widgets/create_favorite_dialog.dart`。
由 `showAppDialog` 负责转场、模糊和遮罩，调用方不重复实现。

- 内容背景 `surfaceContainerLow`，圆角 28，padding 为 `fromLTRB(24, 24, 24, 20)`。
- 配置型最大宽度 540；创建型沿用 `(w * 0.85).clamp(320, 480)`。小窗口仍需服从可用空间约束。
- 标题为 `titleLarge` bold。
- 底部统一 `TextButton`，取消和确认沿用默认主题，危险操作使用 `cs.error` 文字。
- 按钮靠右排列、间距 8，不使用填充按钮、描边按钮或等宽拉伸，不自定义按钮 padding 和圆角。
- 点击选项即确认的选择型弹窗仅保留清除与取消操作。

## Bottom Sheet

参考 `lib/pages/library/widgets/toolbar_bottom_sheet.dart`。

| 属性 | 值 |
|---|---|
| 工具面板外层 | 透明背景 + BackdropFilter，blur 4 |
| 容器 | surfaceContainerHigh，顶部圆角 28 |
| Grabber | 32×4，onSurfaceVariant.withAlpha(80)，圆角 2 |
| 底部留白 | 安全区域 padding.bottom + 16 |
| SheetItem 图标盒 | 44×44，圆角 12，primaryContainer 背景，22px primary 图标 |
| SheetItem 文字 | bodyLarge w600；说明 bodySmall + onSurfaceVariant |
| 展开图标 | onSurfaceVariant.withAlpha(120) |

阅读器实时预览面板和 `SettingPicker` 不加背景模糊；不要从工具面板机械复制 blur。
自定义 SheetItem 使用透明底色的 `TactilePress`。

## SnackBar

参考 `lib/services/snackbar_service.dart`。所有反馈条经 `SnackBarService`：一次性结果用 `showResult`，后台任务用 `showListenableProgress` 或 `TaskRunner.runTask` 登记进 Task Activity；不直接调用 `ScaffoldMessenger.showSnackBar`。

**结构**：全局只有一个槽位。条只在「空 ↔ 有内容」时进出场；进度推进、进度转结果、任务数变化都在条内交叉淡化并平滑伸缩高度，不整条退场重进。结果优先于进度，按 `duration` 自动收起（带按钮也一样），之后回落到仍在跑的任务；≥2 个任务聚合为「N 个任务进行中」。

| 属性 | 值 |
|---|---|
| 形态 | floating；桌面宽 400，移动端左右 16、底部 12 外边距；圆角 12 |
| 尺寸 | padding `symmetric(h: 16, v: 8)`，内容行最小高 32，单行条高 48 |
| 底色 | 默认 `inverseSurface`，不改色、不按语义换底色 |
| 文字 | `bodyMedium` + `onInverseSurface`；进度单行省略，结果最多 3 行 |
| 计数 | `labelMedium` + `onInverseSurface` 70%，等宽数字，格式 `3 / 10` |
| 前导位 | 20×20，与文字间距 12；无图标时不留空位 |
| 强调色 | 仅 `inversePrimary`：进度指示与操作按钮。图标、文字一律 `onInverseSurface` |
| 进度 | 有总数为确定进度（轨道 `onInverseSurface` 20%），否则 spinner；完成态换对勾 |
| 操作按钮 | 紧凑 `TextButton`，最多一个；按下后禁用，进度条的「取消」不收起整条 |

**语义（`SnackTone`）只换图标，不换颜色**：

| Tone | 图标 | 用于 |
|---|---|---|
| `info`（默认） | 无 | 轻量确认（已复制、已保存）、中性提示、取消 |
| `success` | `check_circle_rounded` | 耗时操作或后台任务完成 |
| `error` | `error_rounded` | 失败、文件缺失、权限不足 |

`TaskFinish` 不填 tone 时按出口推断（成功 → success，失败 → error，取消 → info）；成功出口里的非成功结果（已存在、未找到 PDF 源）显式写 tone。

**文案**（ARB 三语同步，代码内中文兜底文案同样遵守）：

| 场景 | 中文格式 | 示例 |
|---|---|---|
| 进行中 | `正在{动作}`，有对象时 `正在{动作} · {对象}` | 正在下载 PDF · {title} |
| 排队 | `等待{动作} · {对象}` | 等待提取 · {title} |
| 成功 | `已{动作}`，有标题时 `已{动作}「{title}」` | 已添加「{title}」 |
| 汇总 | `{任务}完成，{摘要}` | Zotero 同步完成，新增 3 篇 |
| 失败 | `{动作}失败：{原因}` | 下载失败：{error} |
| 取消 | `已取消{动作}` | 已取消提取 |
| 忙碌 | `正在{动作}，请稍候` / `已有任务在进行，请稍候` | 正在重构文库，请稍候 |

- 进度文案先写阶段、后写对象，长标题被省略时阶段仍可见；状态推进时按阶段更新（如解析 → 下载 PDF），不留空字符串（为空时回退任务名）。
- 不加省略号、不以句号结尾；中文用全角「：」「，」「」；英文用 sentence case、半角冒号、标题加英文双引号。
- 一条只说一件事，需要下一步时用逗号接短句（「…，请重试」），不写多句说明。

## Card

参考 `lib/pages/library/widgets/document_card.dart`、`lib/pages/library/widgets/doc_list_card.dart`、`lib/pages/shelf/widgets/favorite_card.dart`。

- 背景 `surfaceContainerLow`，圆角 16，标题 `titleMedium` bold。
- 阴影 `AppShadows.card`；桌面 hover 使用 `HoverLift`。
- 点击使用 `TactilePress`，卡片推荐 `pressedScale: 0.98`。
- 选中边框 `primary.withAlpha(160)`、宽 2，以 `kAnimFast` 过渡；勾选使用 `SpringPop`。

## TextField

参考 `lib/pages/setting/backup_settings_page.dart`、`lib/pages/setting/ocr_settings_page.dart`。

| 属性 | 值 |
|---|---|
| 背景 | filled，surfaceContainerLow |
| 圆角 | 12 |
| 边框 | enabled 为 outline；focused 为 primary、宽 2 |
| contentPadding | 水平 16、垂直 14 |
| prefixIcon（需要时） | 20px，onSurfaceVariant |

上级没有独立标题，或同级均为 TextField 时用 `labelText`；
上方已有标题且同级混有其他控件时用 `hintText`。前置图标还需服从下方设置行规则。

## 设置滑块与基础控件

复用 `lib/widgets/setting_controls.dart` 中的 `SettingSlider`、`SettingTitle`、`SettingHelpIcon`、`SettingResetButton`。
滑块主题由 `lib/core/app_theme.dart` 维护，不复制旧页面的私有 `_sliderRow`。

- `value == null` 表示使用 `fallback`；`formatter` 始终显示实际数值，不用“默认”替代数值。
- 重置按钮始终占位，默认状态禁用；复用组件内置的标题、数值胶囊和状态配色。
- 分组已提供边距时可传零 padding，避免重复留白。
- 桌面阅读器可保留本地拖动状态、松手提交及原保存频率，复用主题不代表改变交互语义。

## SegmentedButton 与 SettingPicker

四个及以上选项默认用 `SettingPicker`。少量选项只有在目标窗口宽度、各语言标签和文字缩放下均能完整显示时才用 `SegmentedButton`；长标签优先用 Picker，不以固定字符数代替布局判断。

SegmentedButton 的项目样式：

| 属性 | 值 |
|---|---|
| 背景 / 选中背景 | surface / primaryContainer |
| 边框 | outlineVariant.withAlpha(100) |
| 圆角 | 12 |
| 布局 | 撑满可用宽度；showSelectedIcon: false |
| 可选文字样式 | bodyMedium w600，未选中 onSurfaceVariant，选中 onPrimaryContainer |

`SettingPicker<T>` 位于 `lib/pages/setting/setting_picker.dart`，仅用于固定列表单选。
通过 `current/options/labelFor/subtitleFor/sheetTitle/onChanged` 配置内容，不复制内部组件树。

- 移动端使用无模糊的 bottom sheet，桌面使用锚定下拉菜单；不按选项数量改变桌面交互模态。
- 点选后关闭；选择不同值时通知调用方，不额外增加确认按钮。
- 桌面菜单修改注意事项见[桌面与阅读器](desktop-reader.md#菜单与浮层)。

## Chip 选择器

参考 `lib/pages/setting/ocr_settings_page.dart` 与 `lib/pages/setting/translation_settings_section.dart`。

- 布局 `Wrap(spacing: 8, runSpacing: 8)`，圆角 12。
- 选中背景 `primaryContainer`、透明边框；未选中边框 `outlineVariant.withAlpha(100)`。
- 标题使用 `SettingTitle`，不重复实现帮助图标。
- 多选标签使用 `FilterChip`，`showCheckmark: false`，未选中背景 `surface`。
- 自描述样式 Chip 使用 `TactilePress`，未选中背景 `surfaceContainerLow`；名称以对应效果渲染，如“加粗”使用粗体、“主题色”使用 primary。
- 样式预览以 `bodyMedium` 为基础；模糊文字预览 sigma 3，保持可读性。实际阅读模式中的样式生效范围由业务模块维护。

## 设置分组、行图标与分隔线

分组使用 `lib/pages/setting/setting_group.dart` 的 `SettingGroup`。
通用与 AI 设置共用相同标题、容器和间距，不另写分组容器或另一套同级样式。

| 设置内容行 | 前置图标 |
|---|---|
| 右侧为 Switch | 不使用，即使涉及存储、日志或数据库 |
| 存储、日志、数据库操作入口 | 可使用，如导出日志、备份、数据库维护 |
| 模型、翻译、外观等普通参数 | 不使用 |

这些限制不影响页面导航标识，以及帮助、重置、显隐、展开等功能图标。
输入框内的装饰图标也不得绕过普通参数行的限制。

分隔线复用 `AppDivider`：无前置图标用默认构造；带图标且需要对齐正文用 `.tile()`；全宽分段用 `.full()`。颜色和缩进由组件维护。

## 用量卡片

参考 `lib/pages/setting/ocr_settings_page.dart`。提供商选择沿用上方单选控件规则。

| 属性 | 值 |
|---|---|
| 容器 | surfaceContainerHigh，圆角 24，padding 16，撑满可用宽度 |
| 标题 | titleSmall w600 + 帮助图标，紧凑 Wrap |
| 数值胶囊 | padding 水平 10、垂直 4，圆角 12，labelMedium w700 |
| 正常配色 | primaryContainer / onPrimaryContainer |
| 超额配色 | errorContainer / onErrorContainer |
| 进度条 | 圆角 4，高度 4，背景 outlineVariant.withAlpha(80) |

进度展示使用 `ratio.clamp(0.0, 1.0)`，保持超额数值可见。
本地估算需标明性质，并以 Tooltip 解释硬上限或降优先级等含义；数据来源与提供商配置规则见 [设置与 API 模块](../../../../docs/settings-and-api-modules.md)。
