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
- **TaskRunner** (`lib/providers/task_runner.dart`) — 后台任务通用模板 mixin（进度 SnackBar + 取消 + 状态管理），`runTask<T>()` 封装 token 创建 → 进度条 → 执行体 → 成功/取消/异常处理。`TaskType` / `TaskInfo` 定义在 `lib/providers/task_types.dart`。
- **TaskProvider** (`lib/providers/task_provider.dart`) — 耗时操作调度入口，mixin `TaskRunner`，通过 `ref.read(taskProvider.notifier)` 调用。禁止在 Widget 方法中直接 await 或在 Widget state 中自管 CancelToken。

### 数据存储

- **GStorage** (`lib/core/storage/storage.dart`) — Hive box 统一访问入口（`GStorage.setting` / `documents` / `favorites`）。禁止直接调用 `Hive.openBox()`。
- **DocPaths** (`lib/utils/doc_paths.dart`) — 文献文件路径中心工具，从 `pdfPath` 派生所有衍生文件路径（`.md`/`.json`/`figures/`/`summary/`）。禁止用 `p.basenameWithoutExtension` 自行拼接衍生路径。
- **StorageCleanupService** (`lib/services/storage_cleanup_service.dart`) — 缓存/数据清理统一入口。新增缓存目录时在 `cacheEntries` 列表追加 `CacheEntry`；新增数据目录时在 `dataEntries` 追加。禁止在 UI 层直接删除缓存目录。

### Agent API 与模型

- **AgentApiProvider** (`lib/providers/api_provider.dart`) — Agent API 配置中心（OpenAI / Anthropic / Gemini / OpenAI 兼容），管理 `defaultModelId` / `fastModelId` / `imageModelId` 三个模型槽位 + `AgentModelParams`（temperature / topP / thinking / web search 等）。通过 `ref.read(agentApiProvider)` / `ref.watch(effectiveAgentApiProvider)` 访问。
- **AgentModelCapability** (`lib/services/agent_model_capability.dart`) — 从模型 ID 推断能力（text/image input/output/embedding），启动时 `init()` 加载 `assets/config/image_models.json`。`isImageGenerationModel()` 判断是否支持图像生成。禁止硬编码模型能力判断。

### 翻译系统

- **TranslationService** (`lib/services/translation_service.dart`) — 轻量翻译入口（单次 `translate()` + 流式 `translateStream()`），内部按 provider 分发到 OpenAI/Anthropic/Gemini API，7 天 SHA-key 缓存。优先使用 fast model。
- **DocumentTranslationService** (`lib/services/document_translation_service.dart`) — 文档级批量翻译（段落粒度），`translate()` 按 6000 字符 / 10 段落分批，结果持久化到 `translations.json`（通过 `DocPaths.translations()` 获取路径）。支持取消。
- **DocumentTranslationProvider** (`lib/providers/document_translation_provider.dart`) — 每文档翻译状态机（idle/loading/done/failed），Family provider 以 PDF 路径为 key。`cycleMode()` 切换双语/原文/译文，`retranslate()` 清缓存重翻。高频进度走 `ValueNotifier` 不重建状态。
- **TranslationConfigProvider** (`lib/providers/translation_config_provider.dart`) — 翻译设置（system/user prompt、目标语言、temperature、显示风格、跳过章节），持久化到 Hive。
- **MarkdownParagraphExtractor** (`lib/services/markdown_paragraph_extractor.dart`) — 从 Markdown 提取可翻译段落（跳过代码块/数学/图片/表格），返回 `TranslatableParagraph`（含 offset/hash/kind）。
- **TranslationSkipSections** (`lib/services/translation_skip_sections.dart`) — 定义并检测翻译跳过区域（References / Bibliography / 参考文献等标题），由 `MarkdownParagraphExtractor` 内部调用。
- **TranslationStyle** (`lib/services/translation_style.dart`) — 翻译显示风格策略模式（themed/bold/italic/weakened/dashed/highlight/blur/quote），`resolveTranslationStyle(id)` 查找。使用 `[[tr]]...[[/tr]]` 自定义标记。
- **MarkdownTranslationWeaver** (`lib/utils/markdown_translation_weaver.dart`) — 将翻译结果按段落偏移拼接回 Markdown，支持双语/纯译文两种模式，`applyTranslationToMarkdown()` 入口。

### 图像生成

- **ImageGenerationService** (`lib/services/image_generation_service.dart`) — 图像生成入口（OpenAI / Gemini），`generate(ImageGenerationRequest)` 支持参考图输入 + 取消。不支持 Anthropic。
- **DocumentSummaryImageService** (`lib/services/document_summary_image_service.dart`) — 文档摘要信息图生成管线：收集参考图 → 压缩 Markdown → 构建 prompt → 调用 ImageGenerationService → 保存图片 + 元数据 JSON。产物路径通过 `DocPaths.summaryDir()` / `summaryImage()` / `summaryMeta()` 获取。
- **ImageGenerationConfigProvider** (`lib/providers/image_generation_config_provider.dart`) — 摘要图生成设置（宽高比、保真度、prompt 模板、最大参考图数），持久化到 Hive。

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

- **WebViewMarkdownReader** (`lib/pages/reader/widgets/webview_markdown_reader.dart`) — **主渲染路径**。用 `flutter_inappwebview`（Windows WebView2）渲染 Markdown，提供浏览器原生多段落选择 + SVG 高亮覆盖层。Dart 侧将 Markdown 转 HTML（`webview_reader_html.dart`，内含 CSS + JS）→ 写入文档目录临时文件 → `loadUrl(file://...)` 加载。公开 `WebViewMarkdownReaderState`，通过 `GlobalKey` 暴露 `scrollToBlockIndex()` / `highlightSearch()` / `flashImage()` / `activateNearestSearchResult()` 等方法。KaTeX CDN 渲染 LaTeX。JS → Flutter 通信走 `callHandler`（选择、高亮点击、图片点击、滚动方向），Flutter → JS 走 `evaluateJavascript`。
- **webview_reader_html** (`lib/pages/reader/widgets/webview_reader_html.dart`) — HTML 模板生成器：`buildReaderHtml()` 组装完整 HTML 文档（CSS 主题变量 + JS Overlayer/Selection/Bridge）。`_LatexInlinePreserve` / `_LatexBlockPreserve` 保护 `$...$` / `$$...$$` 免被 markdown emphasis 破坏。`_TranslationInlineSyntax` 将 `[[tr]]...[/tr]]` 转为 `<span class="translated">`。`_convertFigCaptions()` 将 `<img alt="fig:...">` 转为 `<figure><img><figcaption>` 结构。JS 层 Overlayer 参照 anx-reader 实现：存储 Range 对象 + `ResizeObserver` 防抖 150ms + `redraw()` 全量重算解决 KaTeX/图片 reflow 漂移。CSS 性能优化：`contain: content` 布局隔离、`content-visibility: auto` 图片延迟渲染、`passive` 滚动事件。
- **SelectionToolbar** (`lib/pages/reader/widgets/selection_toolbar.dart`) — `showReaderContextMenu()` 弹出 StatefulWidget OverlayEntry：5 色高亮圆点 + 复制/笔记/翻译/删除图标按钮 + **可展开笔记面板**（暗色 TextField + 保存按钮，关闭时自动保存）。新建高亮的笔记走 `onCreateForNote` 回调先创建高亮再展开面板。
- **ReaderNotesSheet** (`lib/pages/reader/widgets/reader_notes_sheet.dart`) — `showReaderNotesSheet()` 底部面板，列出当前文献所有高亮与笔记。卡片可展开（`AnimatedSize`）：折叠态标注文本单行 + 笔记 `titleSmall` w600 最多 2 行；展开态显示全部。支持编辑笔记（Dialog）和删除。底部栏"笔记"按钮入口。
- **Highlight** (`lib/data/models/book/highlight.dart`) — 高亮标记模型，含 `id` / `documentId` / `text` / `color`（hex String）/ `note` / `groupId`。`kHighlightColors` 定义 5 个预设色（Amber/Green/Blue/Red/Purple）。
- **HighlightProvider** (`lib/providers/highlight_provider.dart`) — 按文献 ID（filePath）管理高亮的 Riverpod `StateNotifier.family`，Hive 持久化。`add(text, color:)` / `remove(id)` / `updateColor(id, color)` / `updateNote(id, note)`。删除文献时由 `DocCardActions.delete()` 级联清理 `GStorage.highlights.delete(filePath)`。
- **双路径高亮策略**：新建高亮走 `addHighlightFromSelection()`（精确 Range，支持含 KaTeX 公式的文本），持久化恢复走 `addByText()`（TreeWalker 文本搜索，跳过 `.katex-mathml` 保留 `.katex-html`）。`_selectionHighlightIds` 集合防止 `_syncHighlights` 二次添加。
- **MarkdownDocumentCacheService** (`lib/services/reader/markdown_document_cache_service.dart`) — Markdown 加载 + 内存缓存 + 搜索快照。标题检测优先读取提取 `.json` 中 `block_label: "paragraph_title"`，无 JSON 时回退 ATX heading。
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
- 品牌重命名 NightReader → 獭祭鱼 OtterPad，含存储路径迁移 (`lib/core/storage/storage.dart` `_migrateLegacyAppPaths()`)

### 数据模型

- Document 模型与文件导入 (`lib/data/models/book/document.dart`, `lib/providers/documents_provider.dart`) — 含 `keywords: List<String>` 字段，PubMed 路径填充 MeSH + 作者 Keyword，其他路径暂为空
- 收藏夹系统 (`lib/data/models/collection/favorite.dart`, `lib/providers/favorites_provider.dart`)
- 备份与恢复 (`lib/services/backup_restore_service.dart`, `lib/services/backup_s3_service.dart`, `lib/providers/backup_provider.dart`)

### 用户界面

- 文献库页面 (`lib/pages/library/`) — 网格/列表视图、卡片、封面、内联多选模式、批量提取进度面板
- 书架与收藏夹 (`lib/pages/shelf/`)
- 设置页面 (`lib/pages/setting/`) — API、外观、网络、OCR、Agent 模型管理、翻译设置、摘要图生成设置
- 大纲参考文献解析 (`lib/pages/reader/widgets/outline_panel.dart`) — 支持编号格式（`1.`/`1)`/`[1]`）和 Author-Year 段落格式，二级回退
- WebView 阅读器 (`lib/pages/reader/widgets/webview_markdown_reader.dart`, `webview_reader_html.dart`) — 替换原生 `markdown_widget` + `SelectionArea` 为 `flutter_inappwebview` WebView 渲染。Dart 侧 markdown→HTML（`markdown ^7.3.0` + LaTeX 保护语法）→ KaTeX CDN 数学渲染 → SVG Overlayer 高亮覆盖层 → JS↔Flutter 双向桥接（选择/高亮点击/图片/滚动方向）。搜索高亮走 JS DOM 操作（TreeWalker + `<mark>` 包裹）。图片定位走 `flashImage()` 脉冲光晕动画。
- 高亮标注系统 (`lib/data/models/book/highlight.dart`, `lib/providers/highlight_provider.dart`, `selection_toolbar.dart`) — 5 色预设（Amber/Green/Blue/Red/Purple），Hive 持久化，SVG 覆盖层渲染（anx-reader Overlayer 模式：存储 Range + ResizeObserver redraw），点击编辑/删除/换色，内嵌笔记面板，双路径高亮（新建走精确 Range，恢复走文本搜索）
- 笔记管理面板 (`lib/pages/reader/widgets/reader_notes_sheet.dart`) — 底部栏"笔记"入口，展示当前文献所有标注与笔记，可展开卡片交互（AnimatedSize），编辑笔记 / 删除
- 文献删除级联清理 (`lib/pages/library/widgets/doc_card_actions.dart`) — 删除文献时级联清理高亮（`GStorage.highlights.delete`）+ 阅读历史（`historyProvider.removeDoc`），原有清理包括磁盘文件 / 缩略图 / 收藏夹引用

### 文档提取

#### 版面解析 API（`lib/services/doc_extract_service.dart`, `batch_extract_service.dart`）

- 异步主路径：`POST https://paddleocr.aistudio-app.com/api/v2/ocr/jobs`，`Authorization: bearer`，`multipart/form-data`，`model: PaddleOCR-VL-1.5`，`optionalPayload` 须 `jsonEncode`
- 异步轮询：`GET /jobs/{jobId}` → `data.resultUrl.jsonUrl` → 下载 JSONL（每行 `{"result":{"layoutParsingResults":[...]}}`）→ 展平为页面数组
- 同步 fallback：`POST <syncBaseUrl>/layout-parsing`，`Authorization: token`，JSON body，PDF base64 + `fileType: 0`，可选参数平铺到根 payload
- 产物：`extract.raw.md` / `extract.md`（预处理后） / `extract.json`（扁平页面数组） / `figures/`（哈希目录内固定名称，路径通过 `DocPaths` 获取）
- `saveResult()` 流程：保存 raw.md+json → `extractFigures()` 裁剪 → `replaceFigureRegions()` 按 block_ids 替换 → `_stripApiImageTags` + `_convertCenteredDivs` → `MarkdownPreprocessor.process` + `filterBeforeTitle` → 写 `.md`

#### Figure 提取（`lib/services/figure_extract_service.dart`）

- 主标题连续性恢复 (`_recoverMissingAnchors`, `_collectSeries`, `_tryPromote`)
- 空间聚类 (`findFigureSegments`, `_rectGap`, `_pageDiagonal`)
- Label 亲和归属 (`_isTableAnchor`)
- OCR 噪声过滤 (`_isValidFigureBlock`)
- BBox 合并与裁剪 (`computeMergedBbox`, `_cropRegion`)
- 产物：`figures/Figure_N.png` + `figures/figures.json`（哈希目录内，路径通过 `DocPaths.figuresDir` / `figuresManifest` 获取）

## Todolist

- **发布前**：将所有平台包名前缀从 `com.example` 改为真实域名（Android `build.gradle.kts` + `MainActivity.kt` 目录、iOS/macOS `project.pbxproj` + `AppInfo.xcconfig`、Linux `CMakeLists.txt`）
- 后续raw.md的保存可以删去，目前只是用于测试
- 段落内提及的figure应该能被检出和点击高亮
- 删除物理文件 `lib/pages/reader/widgets/appearance_panel.dart`（已在 refactor 中清空为占位，受工具限制无法 rm）
- WebView 阅读器 Phase 2：本地 KaTeX 打包（离线支持）、翻译样式多风格 CSS（当前仅 themed）、笔记对话框
- 阅读器字体/排版扩展：边距 slider、行距 slider
  - 需要扩展 `ReaderSettingsState` 加 `margin` / `lineHeight` 字段（参照现有 `fontSize` 的 Hive 存储范式），WebView 侧通过 CSS 变量 `--margin` / `--line-height` 传递
  - UI 按 Slider 统一范式（`_sliderRow` 胶囊 + nullable 签名）补控件
- 多文档并发任务管理入口：翻译 / 摘要图生成等后台任务统一面板，查看进度、可取消、与文献一一对应。需重构 `TaskProvider` 从全局单任务模型改为按文档分组的任务队列，新增 UI 面板（类 IDE 后台任务面板）
- 基于元数据的文献推荐算法，分阶段推进：
  1. **Jaccard 基线**（零成本）：PubMed 文献用 `Document.keywords`（MeSH + 作者 KeywordList）直接算集合相似度 `|A∩B|/|A∪B|`
  2. **Major Topic 过滤**：给 `Document` 补 `primaryKeywords` 或把 keywords 结构升级为 `{name, isPrimary}`，efetch XML 里解析 `MeshHeading/DescriptorName[@MajorTopicYN="Y"]`，只用核心主题算相似度（过滤 `Humans`/`Animals`/`Male` 等背景噪声词）
  3. **非 PubMed 文献兜底**：用快速 Agent 模型跑 abstract 抽关键词，单独存 `extractedKeywords` 字段，**不要**和受控 MeSH 混入同一字段（自由文本 vs 受控词表不能直接算 Jaccard）
  4. **MeSH Tree Number + IDF**（高级）：在 efetch 里额外解析 `DescriptorName` 的 tree numbers，配合本地 MeSH 树表（~2MB JSON）按层级距离算相似度；同时全库扫一遍建 IDF 权重，稀有词权重高
  - 架构原则：PubMed 文献走 MeSH 路径，其他领域走 embedding / 抽取关键词路径，**在更高层融合信号**，不要强行塞进同一个向量空间
