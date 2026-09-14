# 新 UI · Dart／Flutter 双端示例

这个示例用真实 Flutter Widget 实现新规范，以当前 OtterPad AI 设置、数据管理与通用组件的业务结构为基础。仅展示内容页，不重画导航、设置分类或窗口外壳。没有调用产品 provider 或数据库，更改只保留在当前页面内存中。

## 运行

在 OtterPad 根目录，用 Git Bash 执行：

```bash
bash .claude/skills/flutter-newui-design/scripts/build_demo.sh
bash .claude/skills/flutter-newui-design/scripts/serve_demo.sh
```

三个页面同时展示可操作的桌面与移动端，支持独立打开原尺寸：

- [AI 设置](http://127.0.0.1:8123/demo.html)
- [数据管理](http://127.0.0.1:8123/demo-backup_setting.html)
- [基础组件](http://127.0.0.1:8123/demo-default_widget.html)

桌面 iframe 固定逻辑视口 1100×960，移动端为 390×844；外层按可用宽度缩放，窄窗口改为上下排列。平台交互分别模拟 Windows 和 Android，Zotero 本机入口、Picker 弹出方式按平台区分。产物位于 `build/flutter-newui-design/site/demo.html`，要与同目录脚本、图标资源和 CanvasKit 一起使用。页面内容均为同一份 Flutter Web 编译产物；HTML 只负责双视口展示，导航栏属于预览工具。

WebAssembly 与字体通过本地 HTTP 加载。直接打开 demo.html 会跳转到上述本地地址；重新启动电脑后先运行 serve_demo.sh。构建脚本可传一个独立输出目录，服务脚本可传对应 site 目录。

首次构建需要 Flutter SDK、Git Bash、uv 与网络下载依赖；构建完成后运行时不需要 CDN。正文使用系统自带 serif，不提供字体资产。脚本只在 build 输出目录生成 Flutter Web 工程，不改产品平台目录与依赖。

## 组件文件

| 文件 | 职责 |
|---|---|
| lib/paper_theme.dart | 内容局部主题、字体层级、边界与状态颜色 |
| lib/paper_widgets.dart | 分组、子分组、响应式字段行、选择器、Chip、滑块、帮助 |
| lib/ai_settings_demo.dart | AI 设置页面与内存交互状态 |
| lib/main.dart | 按 page／device 选择内容与平台、主题、语言、缩放 |
| lib/backup_settings_demo.dart | 数据管理四分组、配置、备份与恢复、平台入口 |
| lib/default_widgets_demo.dart | 弹窗、收藏夹、Snackbar、Alert、用量和基础操作 |
| lib/paper_surfaces.dart | Dialog、动作行、Notice、Snackbar、选择组 |
| lib/paper_favorite_card.dart | 按封面数量排版的收藏夹卡片及菜单 |
| preview.html | 两个独立 Flutter iframe 的展示外壳 |
| lib/l10n/app_*.arb | 界面文案；Prompt 模板留在 Dart |
| test/demo_test.dart、surfaces_test.dart | 尺寸、缩放、选择、弹窗、草稿、独立卡片操作与反馈；selection_test.dart 验证分段布局与禁用 |

顶部开关用于预览“减少动态效果”；三个图标依次切换主题、语言、文字大小（100%／130%／200%）。它们属于演示工具，不是生产设置导航。

## 行为边界

可以操作标题问号帮助、获取演示模型、服务商、凭据显隐、模型与角色选择、搜索提供商、语言、译文样式、忽略项、温度、提示词、图像比例、质量及参考图片数。服务商和搜索提供商切换时分别保留演示草稿，主题／语言切换保留当前输入。

译文样式单选，忽略项多选；温度步长 0.05，参考图片 1–10。无效用户模板会就地显示错误。提示词文案是演示用模板，不覆盖产品默认 Prompt。展示的模型名和能力为示例数据，不是对真实服务可用性的声明。

获取模型采用本地目录模拟，显示加载和结果；无效 API 地址可触发错误／重试，切换服务商或修改连接信息会废弃旧请求。专家、快速、图像分别使用思考、闪电、画笔线性图标；模型 ID 直接显示，说明统一放在标题旁问号。

模型增删、网络测试、真实能力发现、账单估算和持久化没有接入；这些操作仍是生产迁移时需要保留的业务。演示没有虚构“连接成功”或“已保存”的反馈。

数据管理按项目 `lib/pages/setting/backup_settings_page.dart` 还原当前前端结构与入口；外部文件选择、联网、扫描、数据库与子页深层流程采用明确的本地样例。收藏夹编辑仅提交目标卡片；删除可撤销。通用反馈包括结果提示、错误重试、单任务、聚合进度、取消与结果占槽后的进度恢复。

组件视觉以 [paper_theme.dart](lib/paper_theme.dart) 和 [paper_surfaces.dart](lib/paper_surfaces.dart) 为准。生产没有改动，原有 emoji、业务 provider、持久化与导航仍由项目负责。

## 字体

默认全部使用系统自带 serif，正文与说明也继承同一局部字体体系；不恢复 `fonts:`、字体目录、子集构建或字体下载。图标继续使用现有 Material Symbols。

Flutter Web CanvasKit 不能直接使用 CSS／系统字体家族，所以必须通过 `serve_demo.sh` 启动本机预览：`serve_demo.py` 在 localhost 将 Windows 已安装的 Times New Roman（西文）与宋体（中文回退）只读提供给引擎，运行时生成字体清单，不复制字体到仓库或构建产物。引擎默认家族 Roboto 映射至同一宋体，不另下载 Roboto。不要改用通用 `http.server`，也不能把此本机桥接直接部署到公网。两个预览窗口都使用当前 Windows 的字形；移动视口模拟的是布局与交互，不代表已验证 Android 字体。

## 分段选择

基础组件首屏展示「备份方式」两段带图标和「最低记录级别」三段无图标，与数据管理、AI 生图质量共享 `PaperOptions`。横向通栏等分、连续外框、细分隔；选中底色＋预留勾选位，不发生文字位移。放不下时转为纵向连体排列。真正多选仍为独立勾选 Chip，译文样式继续保留单选字形预览。

## 浏览器验收

本地服务启动后执行：

```bash
uv run --no-project --with playwright python -X utf8 .claude/skills/flutter-newui-design/scripts/verify_demo.py
uv run --no-project --with playwright python -X utf8 .claude/skills/flutter-newui-design/scripts/verify_surfaces.py
```

默认使用本机 Chrome；可通过 `--chrome` 指定其他 Chromium 可执行文件。脚本用真实鼠标和键盘操作编译产物，保存浅深色、中英文、四种宽度与两倍文字的截图和 verification.json。只访问 localhost，外部运行时请求会被拦截并导致验证失败。

技能入口可用 skill-creator 的 quick_validate.py 校验；Windows 下加 `python -X utf8`，避免中文规范被系统默认编码误读。

## 本次验证结果（2026-09-14）

Flutter 3.44.6 / Dart 3.12.2：静态分析通过，25 项 Widget 回归通过，release Web 构建通过。Chromium 验证 390／700／1440／1720 宽度、浅深色、中英文、100%／130%／200% 文字；帮助键盘打开／Esc 关闭、获取模型加载／结果／重试／过期请求、角色标识、真实鼠标选择、单选／多选、键盘滑块 0.05 步长及重置通过。新增数据管理与基础组件通过 1100dp 桌面／390dp 移动端浏览器验收，三个双端展示页、平台入口、配置保存、自动备份、信息弹窗、收藏夹取消、动态封面与 Snackbar 均通过。分段选择已验证两段／三段互斥、重复点击保留选择、键盘切换和窄屏纵向排列；系统字体响应与本机 Times New Roman／宋体字节一致。浏览器无页面异常、无外部运行时请求。

检查产物位于 `build/flutter-newui-design/checks/`。这些结果验证独立 demo；生产 provider、原生桌面宿主和导航隔离仍需在实际迁移时按项目环境验证。
