# 组件规范

用于创建或调整组件外观与设置项。共享 Token 和组件入口见 [SKILL.md](../SKILL.md)；以下源码路径相对项目根目录。

## Dialog

参考 `lib/widgets/app_dialog.dart`、`lib/pages/setting/backup_settings_page.dart`、`lib/pages/shelf/widgets/create_favorite_dialog.dart`。
由 `showAppDialog` 负责转场、模糊和遮罩，调用方不重复实现。

- 形状与底色取主题：纸色 `surfaceContainerLowest` + 1px 细线 + `AppRadius.lg`（28，连续曲率），阴影 `AppShadows.dialog`；不在 `AlertDialog` 上写 `backgroundColor` / `shape`。自定义 `Material` 用 `AppShape.lg(AppStroke.side(cs))`（`RoundedSuperellipseBorder`），不要再写 `RoundedRectangleBorder`。padding 为 `fromLTRB(24, 24, 24, 20)`。
- 配置型最大宽度 540；创建型沿用 `(w * 0.85).clamp(320, 480)`。小窗口仍需服从可用空间约束。
- 标题为 `titleLarge`（衬线、w500），不加粗。关闭按钮用 `RuleIconButton`，不用圆形填充按钮。表单分区标签用 `AppType.eyebrow` + `eyebrowText`。
- 底部统一 `TextButton`，取消和确认沿用默认主题，危险操作使用 `cs.error` 文字。
- 按钮靠右排列、间距 8，不使用填充按钮、描边按钮或等宽拉伸，不自定义按钮 padding 和圆角。
- 点击选项即确认的选择型弹窗仅保留清除与取消操作。

## Bottom Sheet

参考 `lib/pages/library/widgets/toolbar_bottom_sheet.dart`。

| 属性 | 值 |
|---|---|
| 工具面板外层 | 透明背景 + BackdropFilter，blur 4 |
| 容器 | `surfaceContainerLowest` 纸色，`AppRadius.sheetTop`（28），顶边 `Border(top: AppStroke.side(cs))`，阴影 `AppShadows.sheet` |
| Grabber | 32×3，`outline`，圆角 `AppRadius.hairline` |
| 底部留白 | 安全区域 padding.bottom + 16 |
| 面板标题 | 眉题 `AppType.eyebrow` + `eyebrowText` |
| SheetItem 图标盒 | 40×40，`AppRadius.sm`，透明底 + 细线，20px `onSurface` 图标 |
| SheetItem 文字 | bodyLarge w600；说明 bodySmall + onSurfaceVariant |
| 展开图标 | `arrow_forward`，`onSurfaceVariant` |

阅读器实时预览面板和 `SettingPicker` 不加背景模糊；不要从工具面板机械复制 blur。
自定义 SheetItem 使用透明底色的 `TactilePress`。

## SnackBar

参考 `lib/services/snackbar_service.dart`。所有反馈条经 `SnackBarService`：一次性结果用 `showResult`，后台任务用 `showListenableProgress` 或 `TaskRunner.runTask` 登记进 Task Activity；不直接调用 `ScaffoldMessenger.showSnackBar`。

**结构**：全局只有一个槽位。条只在「空 ↔ 有内容」时进出场；进度推进、进度转结果、任务数变化都在条内交叉淡化并平滑伸缩高度，不整条退场重进。结果优先于进度，按 `duration` 自动收起（带按钮也一样），之后回落到仍在跑的任务；≥2 个任务聚合为「N 个任务进行中」。

| 属性 | 值 |
|---|---|
| 形态 | floating；桌面宽 400，移动端左右 16、底部 12 外边距；`AppRadius.md`（20） |
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

Folio 里「卡片」分三种，都不铺 `surfaceContainer*` 底色：

| 种类 | 做法 |
|---|---|
| 网格文献卡 | 封面本身就是卡片：纸色 + 细线 + `AppRadius.xs` + `AppShadows.page`；悬停换 `AppShadows.cardHover` 并上移 2px。进度是封面底边的 `ProgressLine`。封面下方衬线标题 15px、`期刊 · 年份` 与百分比一行 |
| 列表文献条目 | 纸页条目：纸色 + 细线 + `AppRadius.md`；缩略图细线 + 页影；衬线 17px 标题、斜体期刊、等宽年份；批注为左侧细线 + 衬线斜体 |
| 收藏 / 分组卡 | 纸色 + 细线 + `AppRadius.md`，`titleLarge` 衬线标题；底部链接行上方一条细线 |

- 静止时无阴影（`AppShadows.card` 为空），只有封面类「一张纸」用 `page` 阴影。
- 点击使用 `TactilePress`，`highlightSize: Size.zero`，卡片推荐 `pressedScale: 0.98`。
- 选中：2px `primary` 边框 + 淡彩底（`primaryContainer` 即强调色淡彩）+ 方形勾选，以 `kAnimFast` 过渡。

## 刊头、细线图标按钮与进度线

| 组件 | 文件 | 用法 |
|---|---|---|
| `Masthead` | `lib/widgets/masthead.dart` | 每个一级页面唯一的大字：衬线标题（`AppType.masthead`）+ 可选眉题 + `RollingNumber` 计数；右侧放搜索框或操作。不要再加第二个大标题 |
| `RuleIconButton` | `lib/widgets/rule_icon_button.dart` | 页面级图标按钮：透明底 + 1px 细线方框（`AppRadius.sm`）；悬停加深细线，`selected` 墨色反白，`danger` 用 error 色图标。替代 `primaryContainer` 圆形填充按钮 |
| `ProgressLine` / `ProgressChip` | `lib/widgets/progress_chip.dart` | 阅读进度：2px 墨线 + 等宽百分比，不用胶囊 |
| `RollingNumber` | `lib/widgets/rolling_number.dart` | 会变化的计数：逐位滚动，减少动态效果时直接切换 |

## TextField

参考 `lib/pages/setting/backup_settings_page.dart`、`lib/pages/setting/ocr_settings_page.dart`。

| 属性 | 值 |
|---|---|
| 背景 | 取主题：filled，纸色 `surfaceContainerLowest` |
| 圆角 | `AppRadius.sm`（14） |
| 边框 | enabled 为细线 `outlineVariant`；focused 为 primary、宽 1.5 |
| contentPadding | 主题默认：水平 14、垂直 12 |

设置页内用 `settingFieldDecoration`；其他地方只写 `hintText` / `labelText` 等内容字段，不覆盖填充色和边框。
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
| 背景 / 选中背景 | 透明 / `inverseSurface`（墨色反白） |
| 边框 | 细线 `outlineVariant` |
| 圆角 | `AppRadius.sm`（14） |
| 布局 | 撑满可用宽度；showSelectedIcon: false |
| 文字 | 取主题；未选中 `onSurfaceVariant`，选中 `onInverseSurface` |

样式全部在 `app_theme.dart` 的 `segmentedButtonTheme`，调用处不写 `styleFrom`。

`SettingPicker<T>` 位于 `lib/pages/setting/setting_picker.dart`，仅用于固定列表单选。
通过 `current/options/labelFor/subtitleFor/sheetTitle/onChanged` 配置内容，不复制内部组件树。

- 移动端使用无模糊的 bottom sheet，桌面使用锚定下拉菜单；不按选项数量改变桌面交互模态。
- 点选后关闭；选择不同值时通知调用方，不额外增加确认按钮。
- 桌面菜单修改注意事项见[桌面与阅读器](desktop-reader.md#菜单与浮层)。

## Chip 选择器

参考 `lib/pages/setting/ocr_settings_page.dart` 与 `lib/pages/setting/translation_settings_section.dart`。

- 布局 `Wrap(spacing: 8, runSpacing: 8)`，圆角 `AppRadius.sm`。
- 选中背景 `primaryContainer`（强调色淡彩）、透明边框；未选中边框细线 `outlineVariant`。
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
| 容器 | 纸色 + 细线，`AppRadius.md`，padding 16，撑满可用宽度 |
| 标题 | titleSmall w600 + 帮助图标，紧凑 Wrap |
| 数值胶囊 | padding 水平 10、垂直 4，`AppRadius.sm`，labelMedium 等宽数字 |
| 正常配色 | primaryContainer / onPrimaryContainer |
| 超额配色 | errorContainer / onErrorContainer |
| 进度条 | `AppRadius.hairline`，高度 4，背景 `outlineVariant` |

进度展示使用 `ratio.clamp(0.0, 1.0)`，保持超额数值可见。
本地估算需标明性质，并以 Tooltip 解释硬上限或降优先级等含义；数据来源与提供商配置规则见 [设置与 API 模块](../../../../docs/settings-and-api-modules.md)。

## 主题风格与氛围光

- 风格由 `ThemeStyle` 决定（纸墨、随色、雾凇、苔原、暮色、石墨），组件只读 `ColorScheme` 角色，不判断风格、不写死纸色。
- 需要知道外观开关时读 `FolioLook.of(context)`：`style`、`ambient`、`floatingBars`。
- 一级页面（文库、书架、设置及其嵌入的子页）的 Scaffold 背景用 `AmbientBackdrop.pageColor(context)`（嵌入子页直接透明），让 `AdaptiveScaffold` 铺的氛围光透出来；二级页面照常用 `cs.surface`。

## 悬浮玻璃底栏

| 项 | 规范 |
|---|---|
| 开关 | 「通用设置 › 界面 › 悬浮底栏」，`ThemeNotifier.setFloatingBars`；默认关 |
| 面板 | `LiquidGlass`：模糊 22 + 饱和度 1.8 + 半透明着色（浅 58% / 深 52%）+ 左上亮、右下暗的渐变描边 + 双层投影；`radius` 为空时是胶囊 |
| 切换 | 需要两种样式的栏用 `BarSurface`，关时退回 `surfaceContainerHigh` 实色 + 细线 |
| 底部导航 | 开时 `AdaptiveScaffold` 设 `extendBody`，`AdaptiveBottomNavigation` 换成 `FloatingGlassNav`：每项 112 宽、64 高；透镜左右两条边各走一套弹簧，前缘 `kMotionSpatialFast`、后缘 `kMotionSpatialSteady`，移动时被拉长并略压扁 |
| 内容避让 | 悬浮时内容延伸到栏下：列表底部要加 `MediaQuery.paddingOf(context).bottom`，`SafeArea(bottom: false)` |
| 阅读器 | 悬浮时底栏叠在内容上，随工具栏显隐滑出 96px 并淡出，隐藏时 `IgnorePointer` |

## 问 AI

| 项 | 规范 |
|---|---|
| 形象 | `AiOrb`：主题三色 `SweepGradient` 自转的光球（颜色先推到饱和度 ≥ .62），左上白色高光；`thinking` 时转速从 6s 加快到 1.6s 并缩放呼吸、外发光起伏 |
| 入口 · 阅读器底栏 | `_AskAiOrbButton`：52×48，内含 30 的光球 + sparkle 图标，对话打开时光球进入 thinking 并加 primary 外环 |
| 入口 · 选区菜单 | 操作栏下方的 `_AiIntentStrip`：深色胶囊 + 主题三色渐变描边；光球和「随便问」固定在两端，中间四个意图（解释 / 简化 / 举例 / 挑刺）横向滚动、右缘渐隐；意图依次从左滑入。点意图 = 带引用打开对话并立即发送对应提示词；点「随便问」= 只带引用打开对话 |
| 自动发送 | `DocumentChatPageArgs.initialPrompt`；页面在首帧后填入并发送，停靠栏通过 `onQuoteConsumed` 清掉 |
| 空状态 | 64 光球 + 衬线大标题 + 文档名 + 四张起手卡（`_StarterCard`，宽 ≥ 520 时两列，错峰入场）；有待发引用时换成意图卡，标签就是完整提示词 |
| 气泡 | 用户：`primaryContainer → tertiaryContainer` 渐变，28 圆角、右下角收成 6，文字 `onSurface`，最大宽 86%；助手：无底色，顶部一枚 20 的光球 |
| 新消息 | `_MessageEntrance` 弹簧（stiffness 420、damping 28）上滑 + 放大，用户消息从右侧进；正在流式输出的那条不做入场 |
| 思考中 | 22 的光球（thinking）+ `ShimmerText` 流光「正在思考」 |
| 输入框 | 28 圆角浮起胶囊：悬浮玻璃开时为 `LiquidGlass`，关时为纸色 + `AppShadows.bar`；输入框自身无边框。发送中外圈 `AuroraRing`：沿连续曲率圆角旋转的三色扫光 + 外晕；发送键是主题色→第三色渐变圆，发送中换成 errorContainer 停止键 |
| 宽屏 | 对话与输入框最大宽 760，居中 |
| 减少动效 | 光球、流光、极光在 `MediaQuery.disableAnimations` 时都停住 |
