# 组件规则

可运行实现都在[示例](../examples/ai_settings/lib/)里：`paper_widgets.dart`、`paper_surfaces.dart`、`paper_favorite_card.dart`、`default_widgets_demo.dart`。改组件时先看对应实现，再把规则更新到这里或[tokens.md](tokens.md)。

## 标题、说明与右侧动作

- 一个字段只显示一次标题。使用外置 `PaperLabel` 后，输入／下拉框不再设置同名 `labelText`；通过 Semantics 保留读屏名称。
- 解释性 subtitle 统一收进标题旁问号。当前值、固定／跟随状态、错误和加载结果保持可见，不藏进帮助。
- 标题行右侧的获取、刷新、恢复默认、更多操作，统一为普通 `IconButton`：与“恢复默认提示词”相同，无常驻底色、边框、胶囊或装饰容器；有 Tooltip、读屏名称、键盘焦点和禁用状态。
- 标题可换行，动作保持右侧同一标题行，不因窄屏单独新增一行装饰按钮。加载在原命中区内替换为 20 的进度环，线宽 1.5，不改变标题宽度。
- 这条只管标题工具动作。保存／取消／删除确认、导入导出等正文主操作保留文字，避免把所有业务操作变成难识别的图标。

## 量化规则

| 组件 | 规则与实际入口 |
|---|---|
| 分组卡片 | 圆角 16、边框 1、内边距 16；标题底线 2；无常驻阴影。[PaperSection](../examples/ai_settings/lib/paper_widgets.dart) |
| 子分组 | 用 1 的分隔线与 12 的上间距，不再套一层卡片。[PaperSubsection](../examples/ai_settings/lib/paper_widgets.dart) |
| 输入／普通选择器 | 圆角 12；正常边框 1、焦点 2；只显示当前值与必要状态。[PaperSelect](../examples/ai_settings/lib/paper_widgets.dart) |
| 分段单选 | 等宽通栏、连续外框、圆角 12、分隔线 1；中性选中底色＋勾选。文字中心与每段几何中心重合；左侧 20 图标＋6 间距，右侧对称预留 26，切换不移动文字。[PaperOptions](../examples/ai_settings/lib/paper_surfaces.dart) |
| 分段换行 | 按实际字体、缩放和字宽决定横排／纵向连体，不用设备名称决定。不可取消最后一个选中项。放在弹窗里时由宿主给出可用宽度，避开 IntrinsicSize 与 LayoutBuilder 冲突。 |
| 真正多选 | 独立勾选 Chip，选中语义与分段单选区分；8 的项间距、12 圆角。译文样式保留真实字形预览。[PaperChoice](../examples/ai_settings/lib/paper_widgets.dart) |
| Slider | 轨道 1、拇指半径 9、刻度半径 1.2；数值保持等宽数字，重置用普通图标。范围、步长、保存频率不随样式改变。 |
| 菜单／问号帮助 | 菜单圆角 12、边框 1、elevation 3；帮助正文内边距 16、最大内容宽度约 320，窄屏留边。 |
| 对话框 | 圆角 20、边框 1、elevation 6；内容宽度最多 480，外侧左右至少 16、上下至少 24；内容内边距水平 24、垂直 16，子项间距 16；长内容可滚动。[PaperDialog](../examples/ai_settings/lib/paper_surfaces.dart) |
| 遮罩 | scrim 42%，使用既有弹窗／Sheet 宿主，不额外叠加多层蒙版。 |
| Snackbar | 圆角 12；宽屏宽 420，窄屏左右 16；逆色背景与文字；图标 20，图文间距 10。结果、错误／重试、进度沿用同一反馈宿主。 |
| Alert | 圆角 12、内边距 16、边框 1；图标 22、图文间距 12、标题到说明 4；错误用语义边框和图标，不整卡铺红。 |
| 收藏夹卡片 | 外框圆角 16、边框 1、内边距 16；封面区基准高 180、上下间距 16；菜单用普通图标，计数和打开入口保留文字。[PaperFavoriteCard](../examples/ai_settings/lib/paper_favorite_card.dart) |
| 收藏夹编辑器 | emoji 选择、名称输入、效果预览自上而下；字段标题行右侧放字数计数；名称为空时禁用保存，交互后再就地校验。[FavoriteEditorDemo](../examples/ai_settings/lib/default_widgets_demo.dart) |

## 收藏夹：身份与封面

身份是生产已有的 `Favorite.emoji` 字符串，顺序与该列表一致：不改用图标字体，不为示例或迁移新增 Symbols 引用。

选择器的形态：一个圆角 16、边框 1、内边距 12 的面，emoji 直接平铺，不分分类；长列表交给对话框自身滚动。每项命中区按平台 40／48／44、圆角 12；未选中不加底色，选中用 selected 底色＋2 的 primary 边框；emoji 按图标处理，字号 20、行高 1，不随系统字号放大；名称、选中状态与按钮落在同一语义节点。

卡片头部（标题行＋emoji 与篇数行）由 [PaperFavoriteHeader](../examples/ai_settings/lib/paper_favorite_card.dart) 提供，卡片与编辑器预览共用它，预览不另画一份。

封面按内容排版：0 空态、1 居中、2 并排、3 一大两小、4 网格、5+ 一大四小；以稳定身份维护每张卡片，编辑／删除／撤销只影响目标。图片有原色时不染成石墨。
