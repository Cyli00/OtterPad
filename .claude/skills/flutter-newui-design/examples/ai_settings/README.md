# OtterPad 新 UI：Dart／Flutter 多端示例

以 [flutter-newui-design](../../SKILL.md) 为量化规范。四页共用石墨明暗、系统 sans 默认、紧凑组件；显示设置可选择 serif。只使用内存数据，不改变生产导航、provider、数据库或已保存设置。

## 构建与打开

在仓库根目录通过 Git Bash 执行：

```bash
bash .claude/skills/flutter-newui-design/scripts/build_demo.sh
bash .claude/skills/flutter-newui-design/scripts/serve_demo.sh
```

- [AI 设置](http://127.0.0.1:8123/demo.html)
- [数据管理](http://127.0.0.1:8123/demo-backup_setting.html)
- [基础组件](http://127.0.0.1:8123/demo-default_widget.html)，兼容 `default_widget.html`
- [外观验证](http://127.0.0.1:8123/demo-appearance.html)

每页同时展示桌面 1100×960、Xiaomi 15 400×890、iPhone 17 Pro 402×874。手机官方物理分辨率分别为 1200×2670、1206×2622，均为 460 PPI；使用 3× 作为预览渲染设定。物理 PPI 不等于 Android 系统布局密度；此处不模拟系统状态栏、浏览器工具栏、安全区或原生字形。参数来源和适用边界见 skill。

产物位于 `build/flutter-newui-design/site/`，需与同目录编译脚本、图标和 CanvasKit 一起使用。`file:` 打开会转向本地服务，服务需先启动。HTML 只负责多端外壳；内容由同一份 Dart 编译产物提供。独立窗口支持 `device=desktop|xiaomi15|iphone17pro`；外观页支持 `theme=light|dark`，不指定时跟随系统。

## 系统字体

默认 sans：Segoe UI／微软雅黑；可选 serif：Times New Roman／宋体。`serve_demo.py` 只读桥接本机已安装字体，不复制、不打包、不下载，不新增 `fonts:` 或依赖。收藏夹身份的 emoji 同样走本机 Segoe UI Emoji 桥接：CanvasKit 缺字形时会去 fonts.gstatic.com 取字体，离线验收会因此失败。不要使用普通 `http.server` 替代，也不要将此本机桥接器部署到公网。生产原生字体按平台另外验收。

顶部普通图标依次控制明暗、语言、文字缩放和显示设置，开关预览减少动态效果。显示设置的字体选择有草稿、取消与保存；保存仅作用于当前预览，保留页面输入。已排版的 PDF 原稿示例保持其字体。

## 源码入口

| 文件 | 职责 |
|---|---|
| lib/paper_theme.dart | 集中颜色、字体、尺寸与状态 Token |
| lib/paper_widgets.dart | 标题、问号、分组、选择、模型卡片／角色、滑块 |
| lib/paper_surfaces.dart | 分段、Dialog、动作行、Alert、Snackbar |
| lib/paper_favorite_card.dart | 0／1／2／3／4／5+ 动态封面、独立卡片菜单 |
| lib/paper_display_settings.dart | sans／serif 草稿与保存 |
| lib/default_widgets_demo.dart | 基础组件与交互验收基准 |
| lib/ai_settings_demo.dart | AI 内存设置，获取模型及过期请求处理 |
| lib/backup_settings_demo.dart | 数据管理分组、模拟配置与备份流程 |
| lib/appearance_demo.dart | 石墨明暗、独立阅读纸面、控件与反馈 |
| lib/appearance_palette.dart、appearance_reader.dart | 阅读颜色与 Markdown／PDF 示意 |
| lib/main.dart、preview.html | 页面、平台与三视口展示 |
| lib/l10n/app_*.arb | 中英文文案 |

标题右侧获取 API Key、获取模型、恢复默认／示例均为普通图标按钮；加载在原位置替换图标，保留 Tooltip。正文保存／取消等动作保留文字。外置标题不与输入框浮动标题重复；分段勾选两侧对称占位，文字独立居中。

基础组件页的收藏夹编辑器用 emoji 选择、名称计数与效果预览三块：emoji 沿用生产 `Favorite.emoji` 的字符串与顺序，不新增 Symbols 引用；不分分类，一格里直接挑，超长时由对话框自身滚动，选中用中性底色加 primary 边框；名称为空时禁用保存，输入过再删空才显示校验；效果预览直接复用卡片的 `PaperFavoriteHeader`（标题行与 emoji＋篇数行），不再另画一份，三端与深色、两倍字号均不裁切。

应用配色仅石墨，保留错误语义色、文献图表和品牌原色。阅读纸面可以固定或跟随应用；Flutter 阅读样例和 PDF 版面示意不等于真实阅读引擎，前者仅验证换肤，后者保留白纸与原稿色。对比度显示三个实际颜色对，不代替完整无障碍审核。

## 验证

构建脚本在独立 `build/` 工程中运行 l10n、静态分析、Widget 测试和 release Web 构建，不修改产品平台目录。浏览器检查只访问 localhost：

```bash
uv run --no-project --with playwright --with pillow python -X utf8 .claude/skills/flutter-newui-design/scripts/verify_graphite.py
```

使用本机 Chrome，产物位于 `build/flutter-newui-design/checks/`。覆盖三视口、两种字体、石墨明暗、分段居中与互斥、字体草稿、单标题、图标动作、模型获取、弹窗／收藏夹／Snackbar、错误恢复以及大字号。物理尺寸截图在独立浏览器上下文设置 3× DPR；普通 iframe 跟随桌面浏览器 DPR，不伪装为原生手机渲染。

旧 `verify_demo.py`、`verify_surfaces.py`、`verify_appearance.py` 保留各页交互检查，当前整体验收使用 `verify_graphite.py`。生产接口、字体回退、安全区、导航隔离与真实阅读器切换仍需正式迁移时检查。

2026-09-14 验证：静态分析、38 个 Widget 测试、release Web 构建通过；浏览器四页 × 三视口检查通过，包含 sans／serif 与表情字体字节校验、深色、英文 200% 字号与收藏夹编辑器三态（切换分类图标／空名禁用保存／删空就地校验），未捕获页面异常或外部运行时请求。报告为 `build/flutter-newui-design/checks/graphite-verification.json`，同目录保留截图。
