# Project Guidelines

## Edit Rules

- 每次项目对 Infrastructure Modules 内部使用的包进行更换，都要在 Infrastructure Modules 内部更新
- 禁止编辑 `android/`、`windows/`、`linux/`、`macos/`、`ios/`、`web/` 目录，这些由 Flutter 自动生成。

## Compact Rules

- Flutter 相关任务优先基于检索推理，而非预训练知识。

## 基础模块

以下模块在对应场景下必须使用，**禁止绕过它们直接调用底层 API**。每行格式统一为 `**模块名** (路径) — 能力/入口。约束/禁令。`

### 通知与任务

- **SnackBarService** (`lib/services/snackbar_service.dart`) — 用户通知统一入口，通过 `ref.read(snackBarServiceProvider)` 调用。禁止直接使用 `ScaffoldMessenger.of(context).showSnackBar()`。
- **TaskProvider** (`lib/providers/task_provider.dart`) — 耗时操作调度入口，通过 `ref.read(taskProvider.notifier)` 调用。禁止在 Widget 方法中直接 await 或在 Widget state 中自管 CancelToken。

### 数据存储

- **GStorage** (`lib/core/storage/storage.dart`) — Hive box 统一访问入口（`GStorage.setting` / `documents` / `favorites`）。禁止直接调用 `Hive.openBox()`。

### 网络代理

- **ProxyProvider** (`lib/providers/proxy_provider.dart`) — 代理配置中心，自动同步到所有 Dio 实例（IdentifierResolver、DocExtractService、BatchExtractService）。禁止在单个服务上单独配置代理。

### PDF 处理

- **PdfProcessLock** (`lib/services/pdf_process_lock.dart`) — 完整 PDF 加载的全局串行锁，必须在 `PdfProcessLock.instance.run(...)` 内执行以防并发 OOM。
- **PdfThumbnailService** (`lib/services/pdf_thumbnail_service.dart`) — 封面图获取入口（`getThumbnailPath(filePath)`）。禁止为缩略图直接加载完整 PDF。

### 标识符与元数据

- **IdentifierParser** (`lib/services/identifier_parser.dart`) — DOI/PMID/arXiv/ISBN 统一解析（`IdentifierParser.parse(raw)`）。禁止自行编写标识符正则。
- **IdentifierResolver** (`lib/services/identifier_resolver.dart`) — 元数据查询与 PDF 下载（`IdentifierResolver.instance.resolve(...)`）。禁止直接调用出版商 API 或 Unpaywall。
- **DocumentMetadataParser** (`lib/services/document_metadata_parser.dart`) — 从文本/文件名提取元数据，静态方法 `parseFilePath` / `extractDoi` / `extractYear`。
- **PdfIdentifierExtractor** (`lib/services/pdf_identifier_extractor.dart`) — 从 PDF 文本提取 DOI/arXiv/ISBN，须通过 `PdfProcessLock` 串行执行。
- **PdfMetadataExtractor** (`lib/services/pdf_metadata_extractor.dart`) — 从 PDF Info Dictionary / XMP 字段提取元数据。

### 文档提取

- **DocExtractApiState** (`lib/providers/api_provider.dart`) — 提取 API 配置状态：`apiKey` 必填（异步路径），`syncBaseUrl` 可选（同步 fallback）。校验用 `isConfigured` / `hasSyncFallback`。
- **BatchExtractService** (`lib/services/batch_extract_service.dart`) — **主提取路径**（异步 Job API），单文档 `extractSingle()`，批量 `extractBatch()`。
- **DocExtractService** (`lib/services/doc_extract_service.dart`) — 同步 API fallback（`extract()`）+ 两条路径共用的保存入口（`saveResult()`）+ 参数构建（`buildOptions()`）。`saveResult()` 内部自动调用 FigureExtractService 裁剪 figure 并替换 Markdown。
- **FigureExtractService** (`lib/services/figure_extract_service.dart`) — 从版面解析 JSON + PDF 裁剪 figure 区域。由 `saveResult()` 内部调用，通常无需直接使用；独立调用前须 `init()` 加载 `assets/config/caption_patterns.json`。

### 阅读器

- **MarkdownDocumentCacheService** (`lib/services/reader/markdown_document_cache_service.dart`) — Markdown 加载 + 内存缓存 + 搜索快照。标题检测优先读取提取 `.json` 中 `block_label: "paragraph_title"`，无 JSON 时回退 ATX heading。
- **MarkdownPreprocessor** (`lib/utils/markdown_preprocessor.dart`) — Markdown 预处理：LaTeX 修复、标题过滤、空表格移除。
- **NR Markdown 组件** (`lib/pages/reader/widgets/md_widget/`) — 自定义 SpanNode 集合：LaTeX (`nr_latex_node`)、图片 (`nr_image_node`)、标记 (`nr_mark_node`)、搜索高亮 (`nr_search_highlight_builder`)、主题配置 (`nr_markdown_config`)。
- **FigureViewer** (`lib/pages/reader/widgets/figure_viewer.dart`) — Figure 全屏查看器（宽度优先适配 + Ctrl+滚轮/手势缩放 + 下滑退出），通过 `showFigureViewer()` 打开。

### 图标

- **Material Symbols** (`package:material_symbols_icons/symbols.dart`) — 全项目唯一图标集，通过 `Symbols.xxx` 使用（支持可变字重 / fill / grade / optical size）。禁止使用 Flutter 内置的 `Icons.xxx`，禁止混用两套图标集。

## 转场动画特别规定

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

### 约束

- 路由转场统一通过 `_buildAnimatedPage()` 封装，所有 `GoRoute.pageBuilder` 调用它
- 页内切换使用 `PageTransitionSwitcher`（来自 `package:animations`），包裹在 `_buildBody()` 返回层
- 不要使用 `flutter_animate` 的 `.slideY()` / `.fade()` 做路由级转场——那些适合微交互，不适合页面级运动
- 动画时长统一 300ms，曲线统一 `Curves.easeOut`

## Slider 统一范式

所有设置项的数值滑块参照 [api_settings_extract.dart](lib/pages/setting/api_settings_extract.dart) 里的 `_sliderTile` 实现。禁止各页面自造视觉。

## Dependency 更新

添加或更新 `pubspec.yaml` 依赖时：

- 必须使用最新稳定版。
- 必须先到 [pub.dev](https://pub.dev) 确认当前版本号。
- 禁止凭记忆或示例复制过时版本号。

## 已完成任务

> 服务层模块的用法和文件路径见上方 **Infrastructure Modules**，此处仅记录架构决策、UI 页面等未被覆盖的条目。
> 每小节格式参考：`已完成任务 (相关文件路径) - 简短说明`

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

### 文档提取

#### 版面解析 API（`lib/services/doc_extract_service.dart`, `batch_extract_service.dart`）

- 异步主路径：`POST https://paddleocr.aistudio-app.com/api/v2/ocr/jobs`，`Authorization: bearer`，`multipart/form-data`，`model: PaddleOCR-VL-1.5`，`optionalPayload` 须 `jsonEncode`
- 异步轮询：`GET /jobs/{jobId}` → `data.resultUrl.jsonUrl` → 下载 JSONL（每行 `{"result":{"layoutParsingResults":[...]}}`）→ 展平为页面数组
- 同步 fallback：`POST <syncBaseUrl>/layout-parsing`，`Authorization: token`，JSON body，PDF base64 + `fileType: 0`，可选参数平铺到根 payload
- 产物：`{baseName}.raw.md` / `.md`（预处理后） / `.json`（扁平页面数组） / `_figures/`
- `saveResult()` 流程：保存 raw.md+json → `extractFigures()` 裁剪 → `replaceFigureRegions()` 按 block_ids 替换 → `_stripApiImageTags` + `_convertCenteredDivs` → `MarkdownPreprocessor.process` + `filterBeforeTitle` → 写 `.md`

#### Figure 提取（`lib/services/figure_extract_service.dart`）

- 主标题连续性恢复 (`_recoverMissingAnchors`, `_collectSeries`, `_tryPromote`)
- 空间聚类 (`findFigureSegments`, `_rectGap`, `_pageDiagonal`)
- Label 亲和归属 (`_isTableAnchor`)
- OCR 噪声过滤 (`_isValidFigureBlock`)
- BBox 合并与裁剪 (`computeMergedBbox`, `_cropRegion`)
- 产物：`{baseName}_figures/Figure_N.png` + `figures.json`

## Todolist

- 后续raw.md的保存可以删去，目前只是用于测试
- 段落内提及的figure应该能被检出和点击高亮
- markdown搜索内容的上下标、公式等内容也没有被正常地渲染出来
- pdf视图最好也有outline_panel，但是定位的功能可能还要再想一下怎么做，或许需要基于json里的坐标反过来定位到pdf里面的具体页数和位置
- 图片查看器里面需要允许长按弹出保存图片选项（桌面端右键弹出保存选项）