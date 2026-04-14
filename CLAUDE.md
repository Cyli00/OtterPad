# Project Guidelines

## Edit Rules

- 每次项目对 Infrastructure Modules 内部使用的包进行更换，都要在 Infrastructure Modules 内部更新
- 禁止编辑 `android/`、`windows/`、`linux/`、`macos/`、`ios/`、`web/` 目录，这些由 Flutter 自动生成。

## Compact Rules

- Flutter 相关任务优先基于检索推理，而非预训练知识。

## Infrastructure Modules (Must Use)

以下模块在对应场景下必须使用，**禁止绕过它们直接调用底层 API**。

### SnackBar & Task System

- **SnackBarService** (`lib/services/snackbar_service.dart`) — 所有用户通知必须通过 `ref.read(snackBarServiceProvider)` 发出，禁止直接调用 `ScaffoldMessenger.of(context).showSnackBar()`。
- **TaskProvider** (`lib/providers/task_provider.dart`) — 所有耗时操作必须通过 `ref.read(taskProvider.notifier)` 调度，禁止在 Widget 方法中直接 await 或在 Widget state 中管理 CancelToken。

### PDF Processing

- **PdfProcessLock** (`lib/services/pdf_process_lock.dart`) — 打开完整 PDF 的操作必须在 `PdfProcessLock.instance.run(...)` 内执行，防止并发 OOM。
- **PdfThumbnailService** (`lib/services/pdf_thumbnail_service.dart`) — 封面图通过 `getThumbnailPath(filePath)` 获取，禁止为缩略图直接加载 PDF。

### Document Extraction

- **BatchExtractService** (`lib/services/batch_extract_service.dart`) — 异步 Job API，单文档用 `extractSingle()`，批量用 `extractBatch()`。这是**主提取路径**。
- **DocExtractService** (`lib/services/doc_extract_service.dart`) — `saveResult()` 是两条路径共用的保存入口，内部自动调用 `FigureExtractService` 裁剪 figure 并替换 Markdown。`extract()` 为同步 API 可选 fallback。`buildOptions()` 构建 API 参数。
- **FigureExtractService** (`lib/services/figure_extract_service.dart`) — 从版面解析 JSON + PDF 裁剪 figure 区域，使用前须调用 `init()` 加载 `assets/config/caption_patterns.json`。由 `saveResult()` 内部调用，通常不需要直接使用。
- **DocExtractApiState** (`lib/providers/api_provider.dart`) — `apiKey` 必填（异步 API），`syncBaseUrl` 可选（同步 fallback）。验证用 `isConfigured` / `hasSyncFallback`。

### Identifier & Metadata

- **IdentifierParser** (`lib/services/identifier_parser.dart`) — 使用 `IdentifierParser.parse(raw)` 统一解析 DOI/PMID/arXiv/ISBN，禁止自行编写标识符正则。
- **IdentifierResolver** (`lib/services/identifier_resolver.dart`) — 使用 `IdentifierResolver.instance.resolve(...)` 查询元数据和下载 PDF，禁止直接调用出版商 API 或 Unpaywall。
- **DocumentMetadataParser** (`lib/services/document_metadata_parser.dart`) — 使用静态方法（`parseFilePath`、`extractDoi`、`extractYear`）从文本提取元数据。
- **PdfIdentifierExtractor** (`lib/services/pdf_identifier_extractor.dart`) — 从 PDF 文本中提取 DOI/arXiv/ISBN，须通过 `PdfProcessLock` 串行。
- **PdfMetadataExtractor** (`lib/services/pdf_metadata_extractor.dart`) — 从 PDF Info Dictionary / XMP 字段提取元数据。

### Network & Proxy

- **ProxyProvider** (`lib/providers/proxy_provider.dart`) — 管理代理配置并自动同步到所有 Dio 实例（IdentifierResolver、DocExtractService、BatchExtractService），禁止在单个服务上单独配置代理。

### Storage

- **GStorage** (`lib/core/storage/storage.dart`) — 通过 `GStorage.setting`、`GStorage.documents`、`GStorage.favorites` 访问 Hive box，禁止直接调用 `Hive.openBox()`。

### Reader

- **MarkdownDocumentCacheService** (`lib/services/reader/markdown_document_cache_service.dart`) — Markdown 文件加载 + 内存缓存 + 搜索快照构建。搜索快照的标题检测从提取 `.json` 中 `block_label: "paragraph_title"` 读取，无 JSON 时回退 ATX heading。
- **MarkdownPreprocessor** (`lib/utils/markdown_preprocessor.dart`) — Markdown 预处理：LaTeX 修复、标题过滤、空表格移除。
- **NR Markdown 组件** (`lib/pages/reader/widgets/md_widget/`) — 自定义 SpanNode：LaTeX (`nr_latex_node`)、图片 (`nr_image_node`)、标记 (`nr_mark_node`)、搜索高亮 (`nr_search_highlight_builder`)、主题配置 (`nr_markdown_config`)。
- **FigureViewer** (`lib/pages/reader/widgets/figure_viewer.dart`) — Figure 全屏查看器（宽度优先适配 + Ctrl+滚轮/手势缩放 + 下滑退出），通过 `showFigureViewer()` 打开。

### Icon System

- **Material Symbols** (`package:material_symbols_icons/symbols.dart`) — 所有图标必须通过 `Symbols.xxx` 使用，禁止用 Flutter 内置的 `Icons.xxx`（Material Icons 旧字体）。项目已整体迁移到 Material Symbols（可变字重 / fill / grade / optical size），不要混用两套图标集。

## Transition & Animation Spec

使用 `package:animations`（Google 官方 Material motion）实现转场动画。

### 路由转场（`_buildAnimatedPage`）

- **场景**：全屏推入（首页→阅读器、设置页等）。
- **动画**：`FadeThroughTransition`。
- **参数**：300ms，曲线 `Curves.easeOut`。
- **语义**：旧页淡出 + 新页淡入，无方向偏见，适合层级跳转。

### 页内视图切换

- **场景**：PDF ↔ Markdown 切换。
- **动画**：`SharedAxisTransition`，`transitionType: SharedAxisTransitionType.horizontal`。
- **参数**：300ms，水平方向。
- **语义**：水平轴共享运动，暗示"同一文档的两种视图"。

### 实现约定

- 路由转场统一通过 `_buildAnimatedPage()` 封装，所有 `GoRoute.pageBuilder` 调用它
- 页内切换使用 `PageTransitionSwitcher`（来自 `package:animations`），包裹在 `_buildBody()` 返回层
- 不要使用 `flutter_animate` 的 `.slideY()` / `.fade()` 做路由级转场——那些适合微交互，不适合页面级运动
- 动画时长统一 300ms，曲线统一 `Curves.easeOut`

## Dependencies

添加或更新 `pubspec.yaml` 依赖时：

- 必须使用最新稳定版。
- 必须先到 [pub.dev](https://pub.dev) 确认当前版本号。
- 禁止凭记忆或示例复制过时版本号。

## Completed Tasks

> 服务层模块的用法和文件路径见上方 **Infrastructure Modules**，此处仅记录架构决策、UI 页面等未被覆盖的条目。

### 架构与基础设施

- Riverpod 状态管理 (`lib/providers/`) — 全局状态 flutter_riverpod，局部 UI 保留 setState
- MD3 主题系统与动态配色 (`lib/common/theme/app_theme.dart`, `lib/providers/theme_provider.dart`)
- go_router 声明式路由 + StatefulShellRoute 标签导航 (`lib/router/app_router.dart`, `lib/router/app_routes.dart`)
- 响应式布局 (`lib/widgets/layout/adaptive_scaffold.dart`, `lib/utils/responsive.dart`)

### 数据模型

- Document 模型与文件导入 (`lib/data/models/book/document.dart`, `lib/providers/documents_provider.dart`)
- 收藏夹系统 (`lib/data/models/collection/favorite.dart`, `lib/providers/favorites_provider.dart`)
- 星标文献 (`lib/providers/starred_provider.dart`)
- 备份与恢复 (`lib/services/backup_restore_service.dart`, `lib/services/backup_s3_service.dart`, `lib/providers/backup_provider.dart`)

### 用户界面

- 文献库：页面 (`lib/pages/library/`)、网格/列表视图、卡片、封面
- 书架与收藏夹 (`lib/pages/shelf/`)
- 内联多选模式 (`lib/providers/selection_provider.dart`, `lib/pages/library/widgets/selection_app_bar.dart`)
- 批量提取进度面板 (`lib/pages/library/widgets/batch_progress_sheet.dart`)
- 设置页面：API (`api_settings_page.dart`)、外观 (`appearance_settings_page.dart`)、网络 (`network_settings_page.dart`)
- 阅读器主页面 (`lib/pages/reader/view.dart`)、外观面板、提取结果页
- 阅读器主题配置 (`lib/providers/reader_settings_provider.dart`)

### 文档提取（决策记录）

- 提取管线统一为 JSON 格式；图片统一走 `_figures/`

#### Figure 提取（`lib/services/figure_extract_service.dart`）

- 主标题连续性恢复 (`_recoverMissingAnchors`, `_collectSeries`, `_tryPromote`)
- 空间聚类 (`findFigureSegments`, `_rectGap`, `_pageDiagonal`)
- Label 亲和归属 (`_isTableAnchor`)
- OCR 噪声过滤 (`_isValidFigureBlock`)
- BBox 合并与裁剪 (`computeMergedBbox`, `_cropRegion`)
- 产物：`{baseName}_figures/Figure_N.png` + `figures.json`

#### Flutter / Dart 调用文档版面解析 API

##### 同步解析（layout-parsing，可选 fallback）
- Endpoint: `<syncBaseUrl>/layout-parsing`
- 认证头：`Authorization: token <TOKEN>`
- `Content-Type: application/json`
- PDF 本地文件需先读取为字节并转 base64
- PDF 的 `fileType` 固定为 `0`
- 可选参数直接平铺到请求根 payload
- 成功结果在 `response.data["result"]["layoutParsingResults"]`

##### 异步解析（Job API，主路径）
- Endpoint: `https://paddleocr.aistudio-app.com/api/v2/ocr/jobs`
- 认证头：`Authorization: bearer <TOKEN>`
- 本地文件模式使用 `multipart/form-data`
- `model` 固定为 `PaddleOCR-VL-1.5`
- 本地文件模式下 `optionalPayload` 需 `jsonEncode(...)`
- 提交成功后得到 `jobId`
- 轮询 `GET /jobs/{jobId}`
- 完成后读取 `data.resultUrl.jsonUrl`
- 下载的 JSONL 每行格式：`{"result":{"layoutParsingResults":[...]}}`
- 保存时展平为扁平 JSON 数组 `[page0, page1, ...]`

##### 本项目产物约定
- `{baseName}.raw.md`：API 原始 Markdown
- `{baseName}.md`：阅读器使用的预处理 Markdown（figure 已替换为本地图片、残留 HTML 已清理、LaTeX 已修复、标题前内容已裁剪）
- `{baseName}.json`：版面解析完整结果（扁平页面数组，含 prunedResult / markdown / images）
- `{baseName}_figures/`：figure 裁剪图片目录（含 `figures.json` 清单）

##### `saveResult()` 流程

1. 保存 `raw.md` + `.json`
2. `FigureExtractService.extractFigures()` 从 PDF 裁剪 figure 区域图片
3. `replaceFigureRegions()` 用 block_ids 在每页 raw markdown 中定位 figure 行范围，替换为 `![caption](file:///path)`
4. `_stripApiImageTags()` 清理残留 API `<img>` / `<div><img>` 标签
5. `_convertCenteredDivs()` 居中 div → 斜体
6. `MarkdownPreprocessor.process()` + `filterBeforeTitle()` LaTeX 修复与标题过滤
7. 写入 `.md` 文件

## Todolist

- 后续raw.md的保存可以删去，目前只是用于测试
- 段落内提及的figure应该能被检出和点击高亮
- markdown搜索内容的上下标、公式等内容也没有被正常地渲染出来
- pdf视图最好也有outline_panel，但是定位的功能可能还要再想一下怎么做，或许需要基于json里的坐标反过来定位到pdf里面的具体页数和位置
- 图片查看器里面需要允许长按弹出保存图片选项（桌面端右键弹出保存选项）