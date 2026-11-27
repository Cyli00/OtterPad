# Folio 设计规范

0.2.0 起 OtterPad 的界面语言叫 **Folio**：把应用当成一张纸、一本刊物来设计，而不是一套 Material 模板。
代码入口是 `lib/core/design_tokens.dart`（Token）和 `lib/core/app_theme.dart`（组件主题）；组件不再各自写圆角、底色和阴影。

## 为什么改

旧界面完全是 Material 3 默认范式：种子色生成的整套色调、16–28 的大圆角、每个块都铺一层 `surfaceContainer*` 底色再加柔光阴影、`primaryContainer` 色块图标按钮、primary 色的加粗分组标题。
它没有错，但一眼就是「模板脸」，所有块的分量都差不多，看不出重点。

参考的思路（《UI Libraries for Claude Code (Ban the AI Look)》）有三条落到了 Flutter 上：

1. **基础组件交给成熟实现，只改品牌参数**。按钮、输入框、弹窗、菜单、Tabs 都继续用 Material 组件（等同于 shadcn/Radix 的角色：焦点、键盘、无障碍都由框架负责），但在 `app_theme.dart` 里一次性换掉配色、字体和圆角。
2. **收紧圆角 + 衬线标题**，把「普通 SaaS 模板」变成「编辑出版级产品」。这条是 Folio 的核心。
3. **每页只留一个视觉亮点**。刊头（页面大标题）就是这个亮点，其余元素都退成细线和中性色。

另外两条专精组件的思路已经由项目自带实现覆盖：反馈条的堆叠与进出场（Sonner 的角色）是 `SnackBarService` 的单槽模型；数字滚动（NumberFlow 的角色）新增了 `RollingNumber`。

## 原则

| 原则 | 做法 |
|---|---|
| 纸，不是塑料 | 中性色固定为暖纸色系（浅色 `#F6F3EC` 纸面、深色 `#141311` 墨底），不随种子色变；层级靠 1px 细线，不靠色块和柔光阴影 |
| 一个强调色 | 用户选的主题色（或系统动态色）只用于选中、焦点、主操作、进度；图标盒、计数、标题都回到中性色 |
| 字体分工 | 衬线管内容与标题（刊头、文献标题、弹窗标题），无衬线管界面（按钮、标签、正文控件） |
| 收紧的几何 | 圆角只有 2 / 4 / 6 / 10 / 14 五档；不再出现 16、24、28 |
| 每页一个重心 | 页面刊头是唯一的大字；栏目标题降为小号加宽字距的眉题 |
| 浮起才有影 | 静止的卡片、分组不投影；菜单、浮层、弹窗用「近处实影 + 远处环境影」双层阴影 |
| 动效照旧 | 弹簧 token（`animation_constants.dart`）不变；新增数字滚动 |

## Token

### 颜色（`FolioPalette`）

`FolioPalette.scheme(seed, brightness)` 先用 `DynamicSchemeVariant.fidelity` 从种子色生成强调色（保留种子色本来的饱和度），再把所有中性角色换成固定的纸 / 墨色。

`*Container` 角色（`primaryContainer` 等）不再是饱和色块，而是**淡彩**：强调色以 12%（浅色）/ 20%（深色）叠在纸色上，`on*Container` 用强调色本身。散落各处的标签、选中底因此自动降到 Folio 的分量。

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

### 圆角（`AppRadius`）

| Token | 值 | 用于 |
|---|---|---|
| `hairline` | 2 | 细进度条、拖拽条 |
| `xs` | 4 | Tooltip、复选框、小徽标 |
| `sm` | 6 | 按钮、输入框、Chip、图标盒、菜单项、分段按钮 |
| `md` | 10 | 卡片、设置分组、菜单、反馈条 |
| `lg` | 14 | 弹窗、底部面板 |

### 间距（`AppSpace`）

4 的倍数：4 / 8 / 12 / 16 / 20 / 24 / 32 / 48。页面左右边距 `AppSpace.pageGutter`：窄屏 20、宽屏 32。

### 线与阴影

- 细线 `AppStroke.side(cs)`：1px `outlineVariant`。卡片、分组、输入框、菜单、弹窗都有。
- 焦点 1.5px primary；Tabs 指示器 2px 墨色下划线。
- 阴影 `AppShadows`：`card` 为空；`page`（阅读器 PDF 页）、`cardHover`、`bar`、`sheet`、`dialog` 均为「1px 实影 + 环境影」两层。

## 组件范式

| 组件 | 旧范式 | Folio |
|---|---|---|
| 页面标题 | `headlineLarge` bold 无衬线 | 衬线刊头 + 眉题，数字滚动的计数 |
| 分组标题 | primary 色 `titleMedium` bold | `AppType.eyebrow`：小号、加宽字距、中性色 |
| 设置分组 | `surfaceContainerHigh` 底 + 24 圆角 | 纸色底 + 细线 + 10 圆角 |
| 文献卡（网格） | 卡片底色 + 柔光阴影 + 百分比胶囊 | 封面就是卡片：纸页 + 细线 + 贴边实影；下方衬线标题；进度是封面底边的 2px 墨线 |
| 文献卡（列表） | 圆角卡片堆叠 | 纸页条目：纸色 + 细线、细线缩略图、衬线标题、斜体期刊、批注为细线 + 衬线斜体 |
| 文库首页 | Material AppBar + 搜索 | `Masthead` 刊头（日期眉题 + 衬线「我的文库」+ 滚动计数）+ 细线搜索框；Tabs 左对齐 |
| 书架 | 色块菜单卡 | 目录页：细线分隔的条目 + 等宽计数 + 箭头；收藏区用眉题 |
| 设置首页 | 色块图标 + 圆角卡 | 细线图标盒、选中为淡彩底 + 主题色图标 |
| 进度 | `primaryContainer` 胶囊 | 2px 进度线 + 等宽百分比 |
| 图标按钮 | `primaryContainer` 圆形填充 | `RuleIconButton`：透明底 + 细线方框（6 圆角），悬停加深，选中墨色反白 |
| 导航 | 药丸指示器 | 侧栏：左缘 2px 墨线 + 加粗图标；底栏：无指示器，选中项墨色，顶边细线 |
| Tabs | 居中、primary 色、3px 指示器 | 左对齐、墨色、2px 下划线，带全宽细线 |
| 弹窗 | `surfaceContainerLow` + 28 圆角 | 纸色 + 细线 + 14 圆角，衬线标题，双层阴影 |
| 底部面板 | 28 圆角 + `surfaceContainerHigh` | 14 圆角 + 纸色 + 细线顶边 |
| 反馈条 | 12 圆角 | 10 圆角，墨色底（保持单槽逻辑） |
| 标签 / 图标盒 | `primaryContainer` 饱和色块 | 强调色淡彩或细线方框 |
| 分段按钮 | `primaryContainer` 选中 | 墨色反白选中 |

## 新增组件

| 组件 | 作用 |
|---|---|
| `Masthead`（`lib/widgets/masthead.dart`） | 一级页面的刊头：衬线标题 + 眉题 + 滚动计数 + 右侧操作 |
| `RuleIconButton`（`lib/widgets/rule_icon_button.dart`） | 细线方框图标按钮，替代填充圆形按钮 |
| `ProgressLine`（`lib/widgets/progress_chip.dart`） | 2px 进度线；`ProgressChip` 是进度线 + 等宽百分比 |
| `RollingNumber`（`lib/widgets/rolling_number.dart`） | 逐位滚动的数字 |

## 不做的事

- 不加外部 UI 依赖：Material 组件 + 主题即可覆盖，参考思路里的 Web 组件库在 Flutter 上没有等价物，硬套只会多一层适配。
- 不在同一页堆多个亮点：刊头之外不加渐变、发光、背景动画。
- 阅读器正文排版（`reader2/`、`md_widget/`）由阅读主题控制，不受 Folio 字体分工影响。
