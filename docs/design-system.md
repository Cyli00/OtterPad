# Folio 设计规范

0.2.0 起 OtterPad 的界面语言叫 **Folio**：把应用当成一本刊物来设计，而不是一套 Material 模板。
刊物可以换纸：纸墨只是六种主题风格之一，圆角、刊头、细线、动效这些骨架在每种风格下都一样。
代码入口是 `lib/core/design_tokens.dart`（Token）和 `lib/core/app_theme.dart`（组件主题）；组件不再各自写圆角、底色和阴影。

## 为什么改

旧界面完全是 Material 3 默认范式：种子色生成的整套色调、16–28 的大圆角、每个块都铺一层 `surfaceContainer*` 底色再加柔光阴影、`primaryContainer` 色块图标按钮、primary 色的加粗分组标题。
它没有错，但一眼就是「模板脸」，所有块的分量都差不多，看不出重点。

参考的思路（《UI Libraries for Claude Code (Ban the AI Look)》）有三条落到了 Flutter 上：

1. **基础组件交给成熟实现，只改品牌参数**。按钮、输入框、弹窗、菜单、Tabs 都继续用 Material 组件（等同于 shadcn/Radix 的角色：焦点、键盘、无障碍都由框架负责），但在 `app_theme.dart` 里一次性换掉配色、字体和圆角。
2. **衬线标题 + 有性格的几何**，把「普通 SaaS 模板」变成「编辑出版级产品」。第一版收紧了圆角；第二版改成更饱满的连续曲率圆角，让刊物感和亲和力并存。
3. **每页只留一个视觉亮点**。刊头（页面大标题）就是这个亮点，其余元素都退成细线和中性色。

另外两条专精组件的思路已经由项目自带实现覆盖：反馈条的堆叠与进出场（Sonner 的角色）是 `SnackBarService` 的单槽模型；数字滚动（NumberFlow 的角色）新增了 `RollingNumber`。

## 原则

| 原则 | 做法 |
|---|---|
| 换纸不换骨 | 中性色由主题风格决定（纸墨、随色、雾凇、苔原、暮色、石墨），强调色由主题色决定；层级仍靠 1px 细线，不靠色块堆叠 |
| 一个强调色 | 用户选的主题色（或系统动态色）只用于选中、焦点、主操作、进度；图标盒、计数、标题都回到中性色 |
| 字体分工 | 衬线管内容与标题（刊头、文献标题、弹窗标题），无衬线管界面（按钮、标签、正文控件） |
| 饱满的连续曲率 | 圆角 8 / 14 / 20 / 28 + 胶囊，全部用 `RoundedSuperellipseBorder`（连续曲率，像 iOS 图标那样没有折角） |
| 每页一个重心 | 页面刊头是唯一的大字；栏目标题降为小号加宽字距的眉题 |
| 浮起才有影 | 静止的卡片、分组不投影；菜单、浮层、弹窗用「近处实影 + 远处环境影」双层阴影 |
| 有生命的 AI | 问 AI 有自己的形象（会转、会呼吸的光球）和专属动效，其余界面动效照旧走弹簧 token |
| 可选的悬浮玻璃 | 底部各栏可在「通用设置 › 界面」切换成悬浮的液态玻璃样式 |

## Token

### 颜色（`FolioPalette` + `ThemeStyle`）

`FolioPalette.scheme(seed, brightness, style)` 先用 `DynamicSchemeVariant.fidelity` 从种子色生成强调色（保留种子色本来的饱和度），再按主题风格换掉中性色。设置入口是「外观 › 主题风格」，每张卡片用真实配色渲染一页缩略界面。

| 风格 | 中性色 | `*Container` |
|---|---|---|
| 纸墨 `paper` | 固定暖纸 / 墨色（浅 `#F6F3EC`，深 `#141311`），不随主题色变 | 淡彩：强调色 12% / 20% 叠在纸色上 |
| 随色 `vivid` | 跟着主题色走的 Material 色调 | 保留饱和色块 |
| 雾凇 `mist` | 带主题色倾向的冷调蓝灰 | 淡彩 |
| 苔原 `moss` | 低饱和灰绿 | 淡彩 |
| 暮色 `dusk` | 带玫瑰紫调的灰 | 淡彩 |
| 石墨 `graphite` | 几乎无彩的灰，深色下 `surface` 为纯黑 | 淡彩 |

纸墨的中性色表：

| 角色 | 浅色 · 纸 | 深色 · 墨 | 用途 |
|---|---|---|---|
| `surface` | `#F6F3EC` | `#141311` | 页面底色 |
| `surfaceContainerLowest` | `#FDFCF9` | `#0E0D0C` | 「一张纸」：卡片、弹窗、面板、输入框底色 |
| `surfaceContainerLow` | `#F1EDE5` | `#1A1916` | 次级填充 |
| `surfaceContainer` | `#ECE7DE` | `#1F1D1A` | 侧栏 |
| `surfaceContainerHigh` | `#E6E1D6` | `#272522` | 按下态、占位 |
| `surfaceContainerHighest` | `#DFD9CD` | `#302D29` | 封面缺省底 |
| `onSurface` | `#1C1A17` | `#EDE7DC` | 墨色正文 |
| `onSurfaceVariant` | `#5F594F` | `#ADA597` | 次要文字、图标 |
| `outlineVariant` | `#DCD5C8` | `#37332E` | **细线**（Folio 的主要分隔手段） |
| `outline` | `#8D867A` | `#7E776C` | 强调细线、未选中控件 |
| `inverseSurface` | `#22201C` | `#EDE7DC` | 反馈条、Tooltip、选中的分段按钮 |

**氛围光**（`AmbientBackdrop`，外观设置里可关）：一级页面（文库、书架、设置）的底色上铺三团大面积径向柔光，分别取 `primary`（24%）、`tertiary`（18%）、`secondary`（12%），深色下乘 0.75。页面 Scaffold 用 `AmbientBackdrop.pageColor(context)` 取背景，开着时透明。

**界面外观**统一挂在 `FolioLook`（`ThemeExtension`）上：`style`、`ambient`、`floatingBars`，组件用 `FolioLook.of(context)` 读取。

### 字体（`AppType`）

| 角色 | 字体 | 字号 / 字重 / 字距 |
|---|---|---|
| `displaySmall` | 衬线 | 34 / w500 / -0.6，宽屏刊头 |
| `headlineLarge` | 衬线 | 30 / w500 / -0.5，窄屏刊头 |
| `headlineSmall` | 衬线 | 22 / w500 / -0.2，弹窗标题 |
| `titleLarge` | 衬线 | 20 / w500 / -0.1，二级页标题、AppBar |
| `titleMedium` / `titleSmall` | 界面字体 | w600 |
| `body*` | 界面字体 | 行高 1.4–1.5 |
| `labelSmall` | 界面字体 | w600 / +1.1，**眉题**（`AppType.eyebrow`） |

衬线字体：Windows / macOS / iOS 用 Georgia，Linux 用 Noto Serif，Android 用系统 serif；中文回退 Noto Serif CJK → 思源宋体 → 宋体。
计数、百分比一律加 `AppType.tabular`（等宽数位）。

### 圆角（`AppRadius` + `AppShape`）

| Token | 值 | 用于 |
|---|---|---|
| `hairline` | 3 | 细进度条、拖拽条 |
| `xs` | 8 | 封面、Tooltip、徽标、复选框 |
| `sm` | 14 | 按钮、输入框、Chip、图标盒、菜单项 |
| `md` | 20 | 卡片、设置分组、菜单、反馈条、选区工具栏 |
| `lg` | 28 | 弹窗、底部面板、问 AI 输入框、对话气泡 |
| `pill` | 999 | 悬浮底栏、Tabs 指示器、导航指示器、发送按钮、意图条 |

形状一律用 `AppShape.of(r)` / `AppShape.sm()` / `md()` / `lg()`，它们返回 `RoundedSuperellipseBorder`；裁切用 `ClipRSuperellipse`，自绘用 `canvas.drawRSuperellipse`。不要再直接写 `RoundedRectangleBorder`。

### 间距（`AppSpace`）

4 的倍数：4 / 8 / 12 / 16 / 20 / 24 / 32 / 48。页面左右边距 `AppSpace.pageGutter`：窄屏 20、宽屏 32。

### 线与阴影

- 细线 `AppStroke.side(cs)`：1px `outlineVariant`。卡片、分组、输入框、菜单、弹窗都有。
- 焦点 1.5px primary；Tabs 指示器是 `primaryContainer` 胶囊，没有底部分隔线。
- 阴影 `AppShadows`：`card` 为空；`page`（阅读器 PDF 页）、`cardHover`、`bar`、`sheet`、`dialog` 均为「1px 实影 + 环境影」两层。

## 组件范式

| 组件 | 旧范式 | Folio |
|---|---|---|
| 页面标题 | `headlineLarge` bold 无衬线 | 衬线刊头 + 眉题，数字滚动的计数 |
| 分组标题 | primary 色 `titleMedium` bold | `AppType.eyebrow`：小号、加宽字距、中性色 |
| 设置分组 | `surfaceContainerHigh` 底 + 24 圆角 | 纸色底 + 细线 + 20 连续曲率圆角 |
| 文献卡（网格） | 卡片底色 + 柔光阴影 + 百分比胶囊 | 封面就是卡片：纸页 + 细线 + 贴边实影；下方衬线标题；进度是封面底边的 2px 墨线 |
| 文献卡（列表） | 圆角卡片堆叠 | 纸页条目：纸色 + 细线、细线缩略图、衬线标题、斜体期刊、批注为细线 + 衬线斜体 |
| 文库首页 | Material AppBar + 搜索 | `Masthead` 刊头（日期眉题 + 衬线「我的文库」+ 滚动计数）+ 细线搜索框；Tabs 左对齐 |
| 书架 | 色块菜单卡 | 目录页：细线分隔的条目 + 等宽计数 + 箭头；收藏区用眉题 |
| 设置首页 | 色块图标 + 圆角卡 | 细线图标盒、选中为淡彩底 + 主题色图标 |
| 进度 | `primaryContainer` 胶囊 | 2px 进度线 + 等宽百分比 |
| 图标按钮 | `primaryContainer` 圆形填充 | `RuleIconButton`：透明底 + 细线方框（14 圆角），悬停加深，选中墨色反白 |
| 导航 | 药丸指示器 | 侧栏：会沿水平方向弹开的 `primaryContainer` 胶囊；底栏：胶囊指示器。打开悬浮玻璃后底栏变成 `FloatingGlassNav`：浮起的玻璃胶囊，选中处有一枚会被拉长再回弹的液态透镜 |
| Tabs | 居中、primary 色、3px 指示器 | 左对齐、`primaryContainer` 胶囊指示器、无分隔线 |
| 弹窗 | `surfaceContainerLow` + 28 圆角 | 纸色 + 细线 + 28 连续曲率圆角，衬线标题，双层阴影 |
| 底部面板 | 28 圆角 + `surfaceContainerHigh` | 28 连续曲率圆角 + 纸色 + 细线顶边 |
| 反馈条 | 12 圆角 | 20 圆角，墨色底（保持单槽逻辑） |
| 阅读器底栏 | 平铺工具栏 + 「问 AI」图标 | 中间是会转的 AI 光球按钮；悬浮玻璃打开时整条栏浮起成玻璃胶囊，随工具栏显隐滑入滑出 |
| 选区菜单 | 操作栏里一个「问 AI」图标 | 操作栏下方多一条意图条：解释、简化、举例、挑刺，右端固定「随便问」；点一下直接打开对话并发送 |
| 问 AI 对话 | 普通 AppBar + 气泡 + 输入框 | 标题旁的光球随发送转快；空状态是大光球 + 四张起手卡（带引用时换成意图卡）；用户气泡是 `primaryContainer→tertiaryContainer` 渐变；新消息弹簧入场；思考中是光球 + 流光文字；输入框是 28 圆角的浮起胶囊（悬浮玻璃时为玻璃），发送中外圈有一道流动的极光描边；宽屏上对话与输入框收在 760 宽内 |
| 标签 / 图标盒 | `primaryContainer` 饱和色块 | 强调色淡彩或细线方框 |
| 分段按钮 | `primaryContainer` 选中 | 墨色反白选中 |

## 新增组件

| 组件 | 作用 |
|---|---|
| `Masthead`（`lib/widgets/masthead.dart`） | 一级页面的刊头：衬线标题 + 眉题 + 滚动计数 + 右侧操作 |
| `RuleIconButton`（`lib/widgets/rule_icon_button.dart`） | 细线方框图标按钮，替代填充圆形按钮 |
| `ProgressLine`（`lib/widgets/progress_chip.dart`） | 2px 进度线；`ProgressChip` 是进度线 + 等宽百分比 |
| `RollingNumber`（`lib/widgets/rolling_number.dart`） | 逐位滚动的数字 |
| `ThemeStylePicker`（`lib/pages/setting/theme_style_picker.dart`） | 主题风格卡片：每张卡用真实配色画一页缩略界面 |
| `AmbientBackdrop`（`lib/widgets/glass/ambient_backdrop.dart`） | 一级页面背后的氛围光 |
| `LiquidGlass` / `BarSurface`（`lib/widgets/glass/liquid_glass.dart`） | 液态玻璃面板：背景模糊 + 饱和度提升 + 半透明着色 + 渐变高光描边；`BarSurface` 按开关在玻璃与实色之间切换 |
| `FloatingGlassNav`（`lib/widgets/adaptive/adaptive_navigation.dart`） | 悬浮玻璃底部导航，透镜两条边各走一套弹簧，前缘快、后缘慢，移动时被拉长 |
| `AiOrb` / `ShimmerText` / `AuroraRing`（`lib/widgets/ai_orb.dart`） | 问 AI 的光球形象、流光文字、发送中的极光描边；都尊重系统「减少动效」 |

## 不做的事

- 不加外部 UI 依赖：Material 组件 + 主题即可覆盖，参考思路里的 Web 组件库在 Flutter 上没有等价物，硬套只会多一层适配。
- 不在同一页堆多个亮点：渐变和发光只给两处，一级页面的氛围光和问 AI；其他组件不加。
- 阅读器正文排版（`reader2/`、`md_widget/`）由阅读主题控制，不受 Folio 字体分工影响。
