# Project Guidelines

## Edit Rules

- 每次项目对 Infrastructure Modules 内部使用的包进行更换，都要在 Infrastructure Modules 内部更新
- 禁止编辑 `android/`、`windows/`、`linux/`、`macos/`、`ios/`、`web/` 目录，这些由 Flutter 自动生成。

## Compact Rules

- Flutter 相关任务优先基于检索推理，而非预训练知识。

## 基础模块

以下模块在对应场景下必须使用，**禁止绕过它们直接调用底层 API**。每行格式统一为 `**模块名** (路径) — 能力/入口。约束/禁令。`

### 启动与运行时

- **main 初始化链路** (`lib/main.dart`) — 启动顺序：`windowManager` 桌面标题栏 → `pdfrxFlutterInitialize()` → 并行 `GStorage.init()` / `AgentModelCapability.init()` / `BackMatterDetector.instance.init()` → `ReaderLocalhostServer.instance.start(documentRoot: GStorage.appRootPath)` → `proxyProvider.applyInitial()`。新增依赖启动态的服务必须挂在这里，且不能绕过 `GStorage` 自行推断根目录。
- **ReaderLocalhostServer** (`lib/services/reader_localhost_server.dart`) — 阅读器本地静态文件服务，app 启动后通过 `ReaderLocalhostServer.instance.start()` 绑定 `127.0.0.1:0`，root 为 `GStorage.appRootPath`（`<AppSupport>/OtterPad/`，`db/` 与 `library/` 的共同父）。`urlForPath()` 只允许 root 内文件，URL 形如 `http://localhost:PORT/library/<documentId>/.reader.html`；`/_assets/*` 从 `rootBundle` 服务 `assets/`（KaTeX CSS/JS/字体）。HTML 文件返回 `Cache-Control: no-store`，其他静态资源按类型缓存。禁止 WebView 直接加载 `file://` 阅读器 HTML 或自行暴露任意文件路径。

### 通知与任务

- **SnackBarService** (`lib/services/snackbar_service.dart`) — 用户通知统一入口，通过 `ref.read(snackBarServiceProvider)` 调用。禁止直接使用 `ScaffoldMessenger.of(context).showSnackBar()`。
- **TaskRunner** (`lib/providers/task_runner.dart`) — 后台任务通用模板 mixin（进度 SnackBar + 取消 + 状态管理），`runTask<T>()` 封装 token 创建 → 进度条 → 执行体 → 成功/取消/异常处理。`TaskType` / `TaskInfo` 定义在 `lib/providers/task_types.dart`。
- **TaskProvider** (`lib/providers/task_provider.dart`) — 全局耗时操作调度入口，mixin `TaskRunner`，通过 `ref.read(taskProvider.notifier)` 调用。当前管理 `addFiles` / `addByIdentifier` / `rebuild` / `redownloadPdf`，状态为 `Map<TaskType, TaskInfo>`。禁止把单篇文献后台任务继续塞回全局 `TaskType`。
- **DocumentLifecycleProvider** (`lib/providers/document_lifecycle_provider.dart`) — 文献生命周期写入口，统一表达导入 PDF、标识符建档、绑定/重新下载 PDF、重建文库、删除文献、记录打开、加入/移出收藏夹，并协调 documents / favorites / highlights / history / 缩略图 / 文献目录。禁止页面、任务编排、阅读器动作直接绕过它修改这些跨模块状态。
- **DocumentTaskProvider** (`lib/providers/document_task_provider.dart`) — 单篇文献维度后台任务入口，任务 Key 为 `documentId + DocumentTaskType`，当前管理 `extractDocument` / `generateSummaryImage`，批量提取通过创建多条 DocumentTask 聚合展示；同一文献同时只允许一个任务活跃，不同文献最多 5 个并发。禁止 Widget 自管 `CancelToken` 直接调用文档提取/摘要图服务。
- **SelectionProvider** (`lib/providers/selection_provider.dart`) — 文献库/收藏夹/无文件条目等列表多选状态入口，`sourceContext` 隔离页面来源。禁止各列表页面各自维护一套多选集合导致跨页串扰。

### 数据存储

- **GStorage** (`lib/core/storage/storage.dart`) — Hive box 统一访问入口（`GStorage.setting` / `documents` / `favorites` / `highlights` / `history`）+ 文件系统根目录 (`appRootPath` = `<AppSupport>/OtterPad/`、`dbDirPath` = `<root>/db/`、`libraryDirPath` = `<root>/library/`)。`init()` 只负责根目录和 box 打开；历史物理目录迁移保留为启动期兼容，不再重写 Hive 内绝对路径。禁止直接调用 `Hive.openBox()` 或 `getApplicationDocumentsDirectory()` 拼路径；旧 `dataDirPath` 标 `@Deprecated`，新代码用 `dbDirPath`。
- **DocPaths** (`lib/utils/doc_paths.dart`) — 文献文件路径中心工具，从稳定 `documentId` 派生 `library/<documentId>/source.pdf` 及 `.md` / `.json` / `figures/` / `summary/` 等衍生路径；低层提取服务传入实际 PDF 路径时仍可兼容。禁止用 `p.basenameWithoutExtension` 或持久化绝对路径自行拼接衍生产物。
- **StorageCleanupService** (`lib/services/storage_cleanup_service.dart`) — 缓存/数据清理统一入口。新增缓存目录时在 `cacheEntries` 列表追加 `CacheEntry`；新增数据目录时在 `dataEntries` 追加。禁止在 UI 层直接删除缓存目录。
- **BackupProvider** (`lib/providers/backup_provider.dart`) — 备份远端配置状态入口，管理 `BackupRemoteType`（S3 / WebDAV）、`BackupWebDavState`、`BackupS3State`，并统一做远端路径/endpoint/object key 规范化。禁止在设置页或服务里散落保存备份凭据。
- **BackupRestoreService** (`lib/services/backup_restore_service.dart`) — 本地 ZIP 备份/恢复入口。归档内部仍使用兼容键名 `docs/` / `data/`，恢复时映射到当前 `library/` / `db/`；文献身份由 Hive 中的稳定 `documentId` 与目录名对应，不再保存或重写文献绝对路径。禁止手写 ZIP 结构或直接覆盖 Hive 文件而不经过 `GStorage.close()` / `reopen()`。
- **BackupS3Service** (`lib/services/backup_s3_service.dart`) — S3 / S3-compatible 远端上传下载入口，内部实现 AWS Signature V4，支持 path-style / virtual-host style。禁止在 UI 层拼签名请求。

### Agent API 与模型

- **AgentApiProvider** (`lib/providers/api_provider.dart`) — Agent API 配置中心（OpenAI / Anthropic / Gemini / OpenAI 兼容），每个 provider 独立保存 baseUrl / apiKey / models / per-model params；`defaultModelId` / `fastModelId` / `imageModelId` 是跨 provider 全局唯一角色，Hive 中存为 `provider:modelId`。API 调用通过 `ref.watch(effectiveAgentApiProvider)` 取有效配置；跨 provider 生图等场景用 `AgentApiNotifier.loadForProvider()` / `globalImageRole`。禁止在调用点自行猜当前 provider 是否就是目标模型 provider。
- **AgentModelParams / ThinkingLevel** (`lib/providers/api_provider.dart`) — 模型参数结构化存储，统一 temperature / topP / maxTokens / systemPrompt / topK / `ThinkingLevel` / OpenAI Responses 参数 / Gemini penalties / web search。禁止用散落的字符串 key 在 UI 和服务间传参。
- **AgentModelCapability** (`lib/services/agent_model_capability.dart`) — 从模型 ID 推断能力（text/image input/output/embedding），启动时 `init()` 加载 `assets/config/image_models.json`。`isImageGenerationModel()` 判断是否支持图像生成。禁止硬编码模型能力判断。
- **AiSettingsPrompt** (`lib/services/ai_settings_prompt.dart`) — AI 配置缺失提示统一入口，负责检查文本模型/生图模型角色与 API Key，并提供"前往设置"动作。禁止各调用点自写不一致的 AI 设置错误文案。

### 翻译系统

- **TranslationService** (`lib/services/translation_service.dart`) — 轻量翻译入口（单次 `translate()` + 流式 `translateStream()`），内部按 provider 分发到 OpenAI/Anthropic/Gemini API，7 天 SHA-key 缓存。优先使用 fast model。
- **DocumentTranslationService** (`lib/services/document_translation_service.dart`) — 文档级翻译（段落粒度），`translate()` 采用单段独立请求 + 8 worker 并发，单段失败最多重试 2 次，失败仅保留该段原文。结果持久化到 `translations.json`（通过 `DocPaths.translations()` 获取路径），写盘通过 Future 链串行化并每 8 段节流保存。取消后不再启动新段，已在飞请求自然完成。
- **DocumentTranslationProvider** (`lib/providers/document_translation_provider.dart`) — 每文档翻译状态机（idle/loading/done/failed），Family provider 以稳定 `documentId` 为 key。`cycleMode()` 切换双语/原文/译文，`retranslate()` 清缓存重翻。高频进度走 `ValueNotifier` 不重建状态。
- **TranslationConfigProvider** (`lib/providers/translation_config_provider.dart`) — 翻译设置（system/user prompt、目标语言、temperature、显示风格、跳过章节），持久化到 Hive。
- **MarkdownParagraphExtractor** (`lib/services/markdown_paragraph_extractor.dart`) — 从 Markdown 提取可翻译段落（跳过代码块/数学/图片/表格），返回 `TranslatableParagraph`（含 offset/hash/kind）。
- **BackMatterDetector** (`lib/services/back_matter_detector.dart`) — 学术论文后置区域检测单一数据源，启动时加载 `assets/config/back_matter_sections.json`，按 references / acknowledgments / authors_contributions / funding_data / supplementary_appendix / ethics_legends 六类输出。翻译跳过与摘要图压缩必须共用它，禁止再新增硬编码 References 正则。
- **TranslationSkipSections** (`lib/services/translation_skip_sections.dart`) — 翻译跳过区域适配层，从 `BackMatterDetector.availableSections` 派生 UI 勾选项与 `DetectedSkipSection`。由 `MarkdownParagraphExtractor` 内部调用；未勾选的后置区域合并为单段翻译。
- **TranslationStyle** (`lib/services/translation_style.dart`) — 翻译显示风格策略模式（themed/bold/italic/weakened/dashed/highlight/blur/quote），`resolveTranslationStyle(id)` 查找。使用 `[[tr]]...[[/tr]]` 自定义标记。
- **MarkdownTranslationWeaver** (`lib/utils/markdown_translation_weaver.dart`) — 将翻译结果按段落偏移拼接回 Markdown，支持双语/纯译文两种模式，`applyTranslationToMarkdown()` 入口。

### 图像生成

- **ImageGenerationService** (`lib/services/image_generation_service.dart`) — 图像生成入口（OpenAI / Gemini），`generate(ImageGenerationRequest)` 支持参考图输入 + 取消。不支持 Anthropic。
- **DocumentSummaryImageService** (`lib/services/document_summary_image_service.dart`) — 文档摘要信息图生成管线：收集参考图 → 压缩 Markdown → 构建 prompt → 调用 ImageGenerationService → 保存图片 + 元数据 JSON。产物路径通过 `DocPaths.summaryDir()` / `summaryImage()` / `summaryMeta()` 获取。
- **ImageGenerationConfigProvider** (`lib/providers/image_generation_config_provider.dart`) — 摘要图生成设置（宽高比、保真度、prompt 模板、最大参考图数），持久化到 Hive。
- **SummaryImageProvider** (`lib/providers/summary_image_provider.dart`) — 每文档摘要图 UI 状态（`imagePath` / `revision` / `generating`）入口，读取磁盘初始状态并在生成完成后驱动大纲图表页刷新。禁止在多个 Widget 中各自 `File.existsSync()` 后维护互相独立的生成态。

### 网络代理

- **ProxyProvider** (`lib/providers/proxy_provider.dart`) — 代理配置中心，自动同步到所有 Dio 实例（IdentifierResolver、DocExtractService、BatchExtractService）。禁止在单个服务上单独配置代理。

### PDF 处理

- **PdfProcessLock** (`lib/services/pdf_process_lock.dart`) — 完整 PDF 加载的全局串行锁，必须在 `PdfProcessLock.instance.run(...)` 内执行以防并发 OOM。
- **PdfThumbnailService** (`lib/services/pdf_thumbnail_service.dart`) — 封面图获取入口（`getThumbnailPath(filePath)`）。禁止为缩略图直接加载完整 PDF。

### 标识符与元数据

- **IdentifierParser** (`lib/services/identifier_parser.dart`) — DOI/PMID/arXiv/ISBN 统一解析（`IdentifierParser.parse(raw)`）。禁止自行编写标识符正则。
- **IdentifierResolver** (`lib/services/identifier_resolver.dart`) — 元数据查询与 PDF 下载（`IdentifierResolver.instance.resolve(...)`）。PubMed 路径使用 `efetch.fcgi`（XML）而非 `esummary`，可提取 MeSH Descriptor + 作者 KeywordList 填充 `Document.keywords`。禁止直接调用出版商 API 或 Unpaywall。
- **DocumentMetadataParser** (`lib/services/document_metadata_parser.dart`) — 从文本/文件名提取元数据，静态方法 `parseFilePath` / `extractDoi` / `extractYear`。
- **PdfIdentifierExtractor** (`lib/services/pdf_identifier_extractor.dart`) — 从 PDF 文本提取 DOI/arXiv/ISBN，须通过 `PdfProcessLock` 串行执行。
- **PdfMetadataExtractor** (`lib/services/pdf_metadata_extractor.dart`) — 从 PDF Info Dictionary / XMP 字段提取元数据。

### 文档提取

- **DocExtractApiState** (`lib/providers/api_provider.dart`) — 提取 API 配置状态：`apiKey` 必填（异步路径），`syncBaseUrl` 可选（同步 fallback）。校验用 `isConfigured` / `hasSyncFallback`。
- **BatchExtractService** (`lib/services/batch_extract_service.dart`) — **主提取路径**（异步 Job API），单文档 `extractSingle()`，批量 `extractBatch()`。
- **DocExtractService** (`lib/services/doc_extract_service.dart`) — 同步 API fallback（`extract()`）+ 两条路径共用的保存入口（`saveResult()`）+ 参数构建（`buildOptions()`）。`saveResult()` 内部自动调用 FigureExtractService 裁剪 figure 并替换 Markdown。
- **FigureExtractService** (`lib/services/figure_extract_service.dart`) — 从版面解析 JSON + PDF 裁剪 figure 区域。由 `saveResult()` 内部调用，通常无需直接使用；独立调用前须 `init()` 加载 `assets/config/caption_patterns.json`。

### 阅读器

- **ReaderSettingsProvider** (`lib/providers/reader_settings_provider.dart`) — 阅读器设置入口，持久化 `ReaderTheme` / `ReaderFont` / `fontSize` / `DefaultReadingMode` / `ToolbarOpacity`。枚举持久化依赖 `.index` 的只能尾追，视觉顺序变化放 UI 层处理。主题实际颜色必须通过 `resolveReaderPalette()` 派生。
- **ReaderSessionProvider** (`lib/providers/reader_session_provider.dart`) — 单篇文献阅读会话入口，管理 PDF/Markdown 切换、Markdown 加载与搜索快照、搜索结果导航、沉浸式工具栏状态、摘要图路径和标注/笔记写入动作。`ReaderPage` 只保留 Flutter/PDF/WebView Adapter 与弹窗展示；禁止在 `ReaderPage` 重新散落维护 Markdown 缓存、搜索状态或直接写 `highlightProvider`。
- **WebViewMarkdownReader** (`lib/pages/reader/widgets/webview_markdown_reader.dart`) — **主渲染路径**。用 `flutter_inappwebview`（Windows WebView2）渲染 Markdown，提供浏览器原生多段落选择 + SVG 高亮覆盖层。Dart 侧将 Markdown 转 HTML（`webview_reader_html.dart`，内含 CSS + JS）→ 写入文献目录内 `<documentDir>/.reader.html`（与 figures/ 同 origin、自包含、随文献删除一并清理）→ 通过 `ReaderLocalhostServer` 的 `http://localhost:<port>/library/<documentId>/.reader.html` 加载。reload 时 URL 附 `?v=<ms>` cache-buster 双保险绕过 WebView 缓存。公开 `WebViewMarkdownReaderState`，通过 `GlobalKey` 暴露 `scrollToBlockIndex()` / `highlightSearch()` / `flashImage()` / `activateNearestSearchResult()` 等方法。主题/字号/字体变化只更新 CSS 变量，不重载 DOM；高亮恢复走 `addHighlightsBatch()` 单次 IPC。JS → Flutter 通信走 `callHandler`（选择、高亮点击、图片点击、滚动方向），Flutter → JS 走 `evaluateJavascript`。
- **webview_reader_html** (`lib/pages/reader/widgets/webview_reader_html.dart`) — HTML 模板生成器：`buildReaderHtml()` 组装完整 HTML 文档（`<base href>` + CSS 主题变量 + JS Overlayer/Selection/Bridge）。KaTeX 走本地 `assets/katex/`，由 `ReaderLocalhostServer` 的 `/_assets/katex/*` 路由服务，禁止依赖 CDN。`_LatexInlinePreserve` / `_LatexBlockPreserve` 保护 `$...$` / `$$...$$` 免被 markdown emphasis 破坏。`_TranslationInlineSyntax` 将 `[[tr]]...[/tr]]` 转为 `<span class="translated">`。`_convertFigCaptions()` 将 `<img alt="fig:...">` 转为 `<figure><img><figcaption>` 结构。图片路径保留相对 URL 并注入 `loading="lazy"` / `decoding="async"`。JS 层 Overlayer 参照 anx-reader 实现：存储 Range 对象 + `ResizeObserver` 防抖 150ms + `redraw()` 全量重算解决 KaTeX/图片 reflow 漂移；批量恢复高亮共享一次 TreeWalker 文本索引。CSS 性能优化：`contain: content` 布局隔离、`content-visibility: auto` 图片延迟渲染、`passive` 滚动事件。
- **ReaderTopToolbar / ReaderBottomBar** (`lib/pages/reader/widgets/reader_top_toolbar.dart`, `reader_bottom_bar.dart`) — 阅读器工具栏拆分组件。顶栏负责返回、搜索、PDF/Markdown 切换、提取/重新提取、收藏、文献信息、总结图、重新排版/重翻译；底栏仅 Markdown 模式显示，负责大纲、翻译/模式循环、笔记、外观、字体。禁止把新按钮直接堆回 `ReaderPage` 的 build 里。
- **ReaderSearchBars / ReaderSearchNavigator / SearchOverlay** (`lib/pages/reader/widgets/reader_search_bars.dart`, `reader_search_navigator.dart`, `search_overlay.dart`) — 搜索 UI 拆分。PDF 搜索走 `pdfrx` 的 `PdfTextSearcher`；Markdown 搜索走 `MarkdownDocumentCacheService` 预构建的搜索快照 + WebView DOM 高亮。禁止对长 Markdown 每次输入都重新全量解析。
- **SelectionToolbar** (`lib/pages/reader/widgets/selection_toolbar.dart`) — `showReaderContextMenu()` 弹出 StatefulWidget OverlayEntry：5 色高亮圆点 + 复制/笔记/翻译/删除图标按钮 + **可展开笔记面板**（暗色 TextField + 保存按钮，关闭时自动保存）。新建高亮的笔记走 `onCreateForNote` 回调先创建高亮再展开面板。
- **ReaderNotesSheet** (`lib/pages/reader/widgets/reader_notes_sheet.dart`) — `showReaderNotesSheet()` 底部面板，列出当前文献所有高亮与笔记。卡片可展开（`AnimatedSize`）：折叠态标注文本单行 + 笔记 `titleSmall` w600 最多 2 行；展开态显示全部。支持编辑笔记（Dialog）和删除。底部栏"笔记"按钮入口。
- **ReaderFavoriteSheet / ReaderDocumentInfoSheet** (`lib/pages/reader/widgets/reader_favorite_sheet.dart`, `reader_document_info_sheet.dart`) — 阅读器内收藏夹移入/移出与文献信息底部面板。单篇文献加入/移出收藏夹必须走 `DocumentLifecycleProvider`，收藏夹自身创建/重命名仍走 `favoritesProvider`；文献信息只展示 `Document` 当前状态，不在 Sheet 内直接修正文献模型。
- **Highlight** (`lib/data/models/book/highlight.dart`) — 高亮标记模型，含 `id` / `documentId` / `text` / `color`（hex String）/ `note` / `groupId`。`kHighlightColors` 定义 5 个预设色（Amber/Green/Blue/Red/Purple）。
- **HighlightProvider** (`lib/providers/highlight_provider.dart`) — 按稳定 `documentId` 管理高亮的 Riverpod `StateNotifier.family`，Hive 持久化。`add(text, color:)` / `remove(id)` / `updateColor(id, color)` / `updateNote(id, note)`。删除文献时由 `DocumentLifecycleProvider.deleteDocument()` 级联清理 `GStorage.highlights.delete(documentId)`。
- **双路径高亮策略**：新建高亮走 `addHighlightFromSelection()`（精确 Range，支持含 KaTeX 公式的文本），持久化恢复走 `addByText()`（TreeWalker 文本搜索，跳过 `.katex-mathml` 保留 `.katex-html`）。`_selectionHighlightIds` 集合防止 `_syncHighlights` 二次添加。
- **MarkdownDocumentCacheService** (`lib/services/reader/markdown_document_cache_service.dart`) — Markdown 加载 + LRU 内存缓存 + 搜索快照缓存。搜索块按二级标题与空行切段，并把基础 Markdown/LaTeX 转成纯文本。提取完成后可用 `primeResolvedContent()` 预热，避免首次切到 Markdown 再读盘。
- **MarkdownPreprocessor** (`lib/utils/markdown_preprocessor.dart`) — Markdown 预处理：LaTeX 修复、标题过滤、空表格移除。
- **NR Markdown 组件** (`lib/pages/reader/widgets/md_widget/`) — 原生 Flutter 渲染组件集（LaTeX / 图片 / 标记 / 搜索高亮 / 翻译段落等）。**仅用于提取结果预览**（`extract_result_page.dart`），阅读器主路径已迁移到 WebView。
- **TranslationPopup** (`lib/pages/reader/widgets/translation_popup.dart`) — 选中文本后弹出的流式翻译对话框（毛玻璃背景 + 高亮源文 + 增量渲染 + 复制菜单），通过 `showTranslationPopup()` 打开。
- **FigureViewer** (`lib/pages/reader/widgets/figure_viewer.dart`) — Figure 全屏查看器（宽度优先适配 + Ctrl+滚轮/手势缩放 + 下滑退出 + 长按/右键菜单含保存/复制），通过 `showFigureViewer()` 打开。保存：桌面走 `FilePicker.saveFile` + `File.copy`，移动走 `Share.shareXFiles` 借系统菜单"保存到相册"；复制图片到剪贴板：桌面用 `Pasteboard.writeImage(bytes)`（`package:pasteboard`），禁止自行拼 `Clipboard.setData`（只支持文本）。
- **阅读器底部面板** (`lib/pages/reader/widgets/reader_text_sheet.dart`, `reader_theme_sheet.dart`, `reader_background.dart`) — 两个 `showModalBottomSheet` 入口：`showReaderTextSheet` 管字号/字体族；`showReaderThemeSheet` 管颜色（复用 `themeProvider` 的 seed color）+ 背景（`ReaderTheme` 的 5 个值：`themed` / `sepia` / `green` / `night` / `dark`）。`ReaderPalette` 覆写了 `==` / `hashCode`，保证 `themed` 模式下相同颜色不会触发 WebView 虚假重载。禁止在 widgets 里直接访问 `settings.backgroundColor` 来拿背景色——用 `resolveReaderPalette()`。
- **阅读器沉浸式模式** (`lib/pages/reader/view.dart`) — Markdown 模式下向下滚动自动隐藏工具栏（`_toolbarsVisible`），顶/底工具栏用 `AnimatedSlide`（220ms `Curves.easeOut`）上下滑出。滚动方向由 WebView JS 检测（throttled scroll 事件）通过 `onScrollDirection` 回调到 Flutter 层。底部工具栏含翻译模式切换（双语/原文/译文循环）和摘要图生成入口。

### 图标

- **Material Symbols** (`package:material_symbols_icons/symbols.dart`) — 全项目唯一图标集，通过 `Symbols.xxx` 使用（支持可变字重 / fill / grade / optical size）。禁止使用 Flutter 内置的 `Icons.xxx`，禁止混用两套图标集。

### 动画组件

- **SpringDismissible** (`lib/widgets/spring_dismissible.dart`) — 弹性滑动删除组件（欠阻尼弹簧回弹），threshold 0.55 / dismissVelocity 1200 px/s。用于列表项滑动删除交互。

### 桌面窗口

- **WindowChrome** (`lib/widgets/window_chrome.dart`) — 桌面端自定义标题栏，替换原生 title bar。通过 `app.dart` 的 `MaterialApp.router.builder` 在路由内容上方注入（仅 `isDesktopChromeTarget == true` 时）。包含 4 个按钮：置顶（toggle `windowManager.setAlwaysOnTop`）/ 最小化 / 最大化↔还原（监听 `WindowListener.onWindowMaximize` 同步状态）/ 关闭。整条 chrome 被 `DragToMoveArea` 包裹，空白区拖拽移动窗口。初始化在 `main.dart`：桌面分支 `windowManager.ensureInitialized()` + `TitleBarStyle.hidden`。禁止在页面级 Scaffold 里再挂 chrome，窗口装饰只属于 app 外层。

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

## UI 组件范式

Slider / TextField / Dialog / Bottom Sheet / Card 等组件的精确视觉参数定义在 [flutter-design](.claude/skills/flutter-design/SKILL.md) skill 中，编码前必须查阅。

## Dependency 更新

添加或更新 `pubspec.yaml` 依赖时：

- 必须使用最新稳定版。
- 必须先到 [pub.dev](https://pub.dev) 确认当前版本号。
- 禁止凭记忆或示例复制过时版本号。

## 已完成任务

> 服务层模块的用法、路径和约束见上方**基础模块**，此处仅记录基础模块未覆盖的架构决策、数据模型和 UI 页面。

### 架构与基础设施

- Riverpod 状态管理 (`lib/providers/`) — 全局状态 flutter_riverpod，局部 UI 保留 setState
- MD3 主题系统与动态配色 (`lib/common/theme/app_theme.dart`, `lib/providers/theme_provider.dart`)
- go_router 声明式路由 + StatefulShellRoute 标签导航 (`lib/router/app_router.dart`, `lib/router/app_routes.dart`)
- 响应式布局 (`lib/widgets/layout/adaptive_scaffold.dart`, `lib/utils/responsive.dart`)
- 启动运行时统一初始化 (`lib/main.dart`) — `pdfrx`、`GStorage`、模型能力、BackMatterDetector、ReaderLocalhostServer、ProxyProvider 按固定顺序启动
- 品牌重命名 NightReader → 獭祭鱼 OtterPad，含存储根目录迁移 (`lib/core/storage/storage.dart` `_migrateLegacyDirectories()`)
- 跨平台数据目录统一到 `<AppSupport>/OtterPad/`（替代 `<AppDocs>`，iOS/Android sandbox 私有，不暴露 Files App / Finder），子目录改名 `data/` → `db/`、`docs/` → `library/`，每篇文献自包含目录（PDF + 抽取产物 + 翻译/笔记 JSON + `.reader.html` HTML 缓存）。启动期仅保留物理目录 rename（跨卷 fallback 复制），Hive 不再持久化文献绝对路径
- 文献生命周期入口 (`lib/providers/document_lifecycle_provider.dart`) — 文献导入、标识符建档、绑定/重下 PDF、重建、删除、打开记录、收藏夹移入/移出统一收口，`DocumentsNotifier` 降为文献列表状态与持久化 Adapter

### 数据模型

- Document 模型与文件导入 (`lib/data/models/book/document.dart`, `lib/providers/documents_provider.dart`) — `id` 为稳定文献身份，`contentHash` 为当前 PDF 内容指纹，`contentHash == null` 表示无文件条目；模型不保存 `filePath`，路径由 `DocPaths` 基于 `documentId` 派生；含 `keywords: List<String>` 字段，PubMed 路径填充 MeSH + 作者 Keyword，其他路径暂为空
- 收藏夹系统 (`lib/data/models/collection/favorite.dart`, `lib/providers/favorites_provider.dart`) — 收藏夹保存 `documentIds` 稳定引用，不保存 PDF 绝对路径；单篇文献加入/移出收藏夹由 `DocumentLifecycleProvider` 调用
- 备份与恢复 (`lib/services/backup_restore_service.dart`, `lib/services/backup_s3_service.dart`, `lib/providers/backup_provider.dart`) — 本地 ZIP + WebDAV / S3 远端配置，归档格式兼容旧 `docs` / `data` 键名

### 用户界面

- 文献库页面 (`lib/pages/library/`) — 网格/列表视图、卡片、封面、内联多选模式、批量提取进度面板
- 书架与收藏夹 (`lib/pages/shelf/`)
- 设置页面 (`lib/pages/setting/`) — API、外观、网络、OCR、备份、Agent 模型管理、翻译设置、摘要图生成设置
- 阅读器工具栏拆分 (`reader_top_toolbar.dart`, `reader_bottom_bar.dart`, `reader_search_bars.dart`, `reader_search_navigator.dart`) — 顶栏承载文档动作，底栏承载阅读动作，PDF/Markdown 搜索各走独立 UI
- 大纲与图表面板 (`lib/pages/reader/widgets/outline_panel.dart`) — Figures / References 双 Tab，Figures 中内嵌 Graphical Summary；参考文献支持编号格式（`1.`/`1)`/`[1]`）和 Author-Year 段落格式，二级回退
- WebView 阅读器 (`lib/pages/reader/widgets/webview_markdown_reader.dart`, `webview_reader_html.dart`, `lib/services/reader_localhost_server.dart`) — 替换原生 `markdown_widget` + `SelectionArea` 为 `flutter_inappwebview` WebView 渲染。Dart 侧 markdown→HTML（`markdown ^7.3.0` + LaTeX 保护语法）→ 本地 HTTP 服务加载 HTML/图片/KaTeX 离线资源 → SVG Overlayer 高亮覆盖层 → JS↔Flutter 双向桥接（选择/高亮点击/图片/滚动方向）。搜索高亮走 JS DOM 操作（TreeWalker + `<mark>` 包裹）。图片定位走 `flashImage()` 脉冲光晕动画。
- 高亮标注系统 (`lib/data/models/book/highlight.dart`, `lib/providers/highlight_provider.dart`, `selection_toolbar.dart`) — 5 色预设（Amber/Green/Blue/Red/Purple），Hive 持久化，SVG 覆盖层渲染（anx-reader Overlayer 模式：存储 Range + ResizeObserver redraw），点击编辑/删除/换色，内嵌笔记面板，双路径高亮（新建走精确 Range，恢复走文本搜索）
- 笔记管理面板 (`lib/pages/reader/widgets/reader_notes_sheet.dart`) — 底部栏"笔记"入口，展示当前文献所有标注与笔记，可展开卡片交互（AnimatedSize），编辑笔记 Dialog / 删除
- 阅读器收藏与信息面板 (`reader_favorite_sheet.dart`, `reader_document_info_sheet.dart`) — 阅读器内移入/移出收藏夹、创建收藏夹、查看当前文献元数据
- 文献删除级联清理 (`lib/providers/document_lifecycle_provider.dart`, `lib/pages/library/widgets/doc_card_actions.dart`) — 删除文献必须通过 `DocumentLifecycleProvider.deleteDocument()`，级联清理收藏夹引用、高亮（`GStorage.highlights.delete(documentId)`）、阅读历史、磁盘目录与缩略图缓存；UI 动作只调用生命周期入口

### 文档提取

#### 版面解析 API（`lib/services/doc_extract_service.dart`, `batch_extract_service.dart`）

- 异步主路径：`POST https://paddleocr.aistudio-app.com/api/v2/ocr/jobs`，`Authorization: bearer`，`multipart/form-data`，`model: PaddleOCR-VL-1.5`，`optionalPayload` 须 `jsonEncode`
- 异步轮询：`GET /jobs/{jobId}` → `data.resultUrl.jsonUrl` → 下载 JSONL（每行 `{"result":{"layoutParsingResults":[...]}}`）→ 展平为页面数组
- 同步 fallback：`POST <syncBaseUrl>/layout-parsing`，`Authorization: token`，JSON body，PDF base64 + `fileType: 0`，可选参数平铺到根 payload
- 产物：`extract.raw.md` / `extract.md`（预处理后） / `extract.json`（扁平页面数组） / `figures/`（`library/<documentId>/` 内固定名称，路径通过 `DocPaths` 获取）
- `saveResult()` 流程：保存 raw.md+json → `extractFigures()` 裁剪 → `replaceFigureRegions()` 按 block_ids 替换 → `_stripApiImageTags` + `_convertCenteredDivs` → `MarkdownPreprocessor.process` + `filterBeforeTitle` → 写 `.md`

#### Figure 提取（`lib/services/figure_extract_service.dart`）

- 主标题连续性恢复 (`_recoverMissingAnchors`, `_collectSeries`, `_tryPromote`)
- 空间聚类 (`findFigureSegments`, `_rectGap`, `_pageDiagonal`)
- Label 亲和归属 (`_isTableAnchor`)
- OCR 噪声过滤 (`_isValidFigureBlock`)
- BBox 合并与裁剪 (`computeMergedBbox`, `_cropRegion`)
- 产物：`figures/Figure_N.png` + `figures/figures.json`（`library/<documentId>/` 内，路径通过 `DocPaths.figuresDir` / `figuresManifest` 获取）

## Todolist

- **多设备阅读同步**（参考 anx-reader）：在已统一的 `<AppSupport>/OtterPad/library/` 自包含目录布局基础上，实现：
  1. **WebDAV / iCloud Drive 同步层**：`library/` 整个目录 + `db/<box>.hive` 增量推送/拉取（按 modtime + content hash）
  2. **冲突解决**：同一文献在多端同时编辑高亮/笔记时按时间戳 + 设备 ID 合并；hive 内 `Highlight` / `Document` 需要补 `lastModified` 字段
  3. **设备 ID 管理**：首次启动生成 UUID 存 settings box，作为冲突解决的 origin tag
  4. **同步状态 UI**：设置页加同步状态/最后同步时间/手动触发/冲突解决面板
  - 现状已就绪：`<AppSupport>/OtterPad/` 跨平台一致、`library/<documentId>/` 自包含（PDF + 抽取产物 + HTML 缓存 + 翻译/笔记 JSON），同步只需扫这一个目录树
- **发布前**：将所有平台包名前缀从 `com.example` 改为真实域名（Android `build.gradle.kts` + `MainActivity.kt` 目录、iOS/macOS `project.pbxproj` + `AppInfo.xcconfig`、Linux `CMakeLists.txt`）
- 后续raw.md的保存可以删去，目前只是用于测试
- 段落内提及的figure应该能被检出和点击高亮
- 删除物理文件 `lib/pages/reader/widgets/appearance_panel.dart`（已在 refactor 中清空为占位，受工具限制无法 rm）
- WebView 阅读器 Phase 2：为 `weakened` / `dashed` / `highlight` / `blur` 等译文样式补齐 WebView CSS，目前这些样式仍共用 `.translated` 的主题色渲染
- 阅读器字体/排版扩展：边距 slider、行距 slider
  - 需要扩展 `ReaderSettingsState` 加 `margin` / `lineHeight` 字段（参照现有 `fontSize` 的 Hive 存储范式），WebView 侧通过 CSS 变量 `--margin` / `--line-height` 传递
  - UI 按 Slider 统一范式（`_sliderRow` 胶囊 + nullable 签名）补控件
- 多文档后台任务统一面板：在现有 `DocumentTaskProvider`（文档任务队列，max=5）基础上，把翻译等后台任务接入同一文档任务视图，提供全局查看进度、取消、失败重试入口（类 IDE 后台任务面板）
- 基于元数据的文献推荐算法，分阶段推进：
  1. **Jaccard 基线**（零成本）：PubMed 文献用 `Document.keywords`（MeSH + 作者 KeywordList）直接算集合相似度 `|A∩B|/|A∪B|`
  2. **Major Topic 过滤**：给 `Document` 补 `primaryKeywords` 或把 keywords 结构升级为 `{name, isPrimary}`，efetch XML 里解析 `MeshHeading/DescriptorName[@MajorTopicYN="Y"]`，只用核心主题算相似度（过滤 `Humans`/`Animals`/`Male` 等背景噪声词）
  3. **非 PubMed 文献兜底**：用快速 Agent 模型跑 abstract 抽关键词，单独存 `extractedKeywords` 字段，**不要**和受控 MeSH 混入同一字段（自由文本 vs 受控词表不能直接算 Jaccard）
  4. **MeSH Tree Number + IDF**（高级）：在 efetch 里额外解析 `DescriptorName` 的 tree numbers，配合本地 MeSH 树表（~2MB JSON）按层级距离算相似度；同时全库扫一遍建 IDF 权重，稀有词权重高
  - 架构原则：PubMed 文献走 MeSH 路径，其他领域走 embedding / 抽取关键词路径，**在更高层融合信号**，不要强行塞进同一个向量空间
