# Project Guidelines

## Edit Rules

- 每次项目对 Infrastructure Modules 内部使用的包进行更换，都要在 Infrastructure Modules 内部更新。
- 禁止编辑 `android/`、`windows/`、`linux/`、`macos/`、`ios/`、`web/` 目录，这些由 Flutter 自动生成。

## Compact/Handoff Rules

**优先压缩**需要基于检索推理的 Flutter 相关任务，而非预训练知识。

## Behavior Guideline

## 先想再写

- 明确说出你的假设。不确定就问，不要猜。
- 多种理解方式时列出选项，不要默默选一个。
- 存在更简单的方案时主动提出，该反驳就反驳。

## 简单优先

- 不写没被要求的功能、抽象、"灵活性"。
- 不为不可能的场景写错误处理。
- 200 行能用 50 行解决就重写。

## 精确修改

- 不"顺手改进"相邻代码、注释或格式。
- 不重构没坏的东西。匹配现有风格，即使你会写不同。
- 发现无关死代码只提醒，不删。
- 自己的改动产生的孤儿（unused import/变量/函数）必须清理。
- 每一行 diff 都应能追溯到用户的请求。

**目标驱动**

- 把任务转化为可验证目标，多步任务先列计划：`步骤 → 验证方式`。
- 澄清问题在实现之前提出，不是出错之后。

## 基础模块

以下模块在对应场景下必须使用，**禁止绕过它们直接调用底层 API**。格式：`模块名 (路径) — 禁令/约束`。

### 启动与运行时

- **main 初始化链路** (`lib/main.dart`) — 新增启动态服务必须挂在这里。禁止绕过 `GStorage` 自行推断根目录。
- **ReaderLocalhostServer** (`lib/services/reader_localhost_server.dart`) — 阅读器本地 HTTP 服务。禁止 WebView 直接加载 `file://` 或自行暴露文件路径。

### 通知与任务

- **SnackBarService** (`lib/services/snackbar_service.dart`) — 禁止直接使用 `ScaffoldMessenger.showSnackBar()`。
- **TaskRunner** (`lib/providers/task_runner.dart`) — 后台任务模板 mixin，`TaskType`/`TaskInfo` 在 `task_types.dart`。
- **TaskProvider** (`lib/providers/task_provider.dart`) — 全局任务调度。禁止把单篇文献任务塞回全局 TaskType。
- **DocumentLifecycleProvider** (`lib/providers/document_lifecycle_provider.dart`) — 文献生命周期写入口。禁止页面/任务/阅读器直接绕过它修改跨模块状态。
- **DocumentTaskProvider** (`lib/providers/document_task_provider.dart`) — 单篇文献任务入口（max 5 并发）。禁止 Widget 自管 CancelToken。
- **SelectionProvider** (`lib/providers/selection_provider.dart`) — 列表多选状态，`sourceContext` 隔离页面来源。

### 数据存储

- **GStorage** (`lib/core/storage/storage.dart`) — Hive box 统一访问 + 文件系统根目录。禁止直接调用 `Hive.openBox()` 或 `getApplicationDocumentsDirectory()` 拼路径。
- **DocPaths** (`lib/utils/doc_paths.dart`) — 文献文件路径中心工具。禁止用 `p.basenameWithoutExtension` 或持久化绝对路径自行拼接。
- **StorageCleanupService** (`lib/services/storage_cleanup_service.dart`) — 禁止在 UI 层直接删除缓存目录。
- **BackupProvider** (`lib/providers/backup_provider.dart`) — 禁止在设置页或服务里散落保存备份凭据。
- **BackupRestoreService** (`lib/services/backup_restore_service.dart`) — 禁止手写 ZIP 结构或直接覆盖 Hive 文件而不经过 `GStorage.close()`/`reopen()`。
- **BackupS3Service** (`lib/services/backup_s3_service.dart`) — 禁止在 UI 层拼签名请求。

### Agent API 与模型

- **AgentApiProvider** (`lib/providers/api_provider.dart`) — API 配置中心，`defaultModelId`/`fastModelId`/`imageModelId` 跨 provider 全局唯一。禁止在调用点自行猜 provider。
- **AgentModelParams** (`lib/providers/api_provider.dart`) — 禁止用散落字符串 key 在 UI 和服务间传参。
- **AgentModelCapability** (`lib/services/agent_model_capability.dart`) — 禁止硬编码模型能力判断。
- **AiSettingsPrompt** (`lib/services/ai_settings_prompt.dart`) — 禁止各调用点自写 AI 设置错误文案。

### 翻译系统

- **TranslationService** (`lib/services/translation_service.dart`) — 轻量翻译入口，优先使用 fast model。
- **DocumentTranslationService** (`lib/services/document_translation_service.dart`) — 文档级翻译（段落粒度，8 worker 并发），结果持久化到 `translations.json`。
- **DocumentTranslationProvider** (`lib/providers/document_translation_provider.dart`) — 每文档翻译状态机，Family provider 以 `documentId` 为 key。
- **BackMatterDetector** (`lib/services/back_matter_detector.dart`) — 后置区域检测单一数据源。禁止新增硬编码 References 正则。
- **TranslationStyle** (`lib/services/translation_style.dart`) — 使用 `[[tr]]...[[/tr]]` 自定义标记。
- 其他翻译模块：`TranslationConfigProvider`、`MarkdownParagraphExtractor`、`TranslationSkipSections`、`MarkdownTranslationWeaver`。

### 图像生成

- **ImageGenerationService** (`lib/services/image_generation_service.dart`) — 支持 OpenAI / Gemini，不支持 Anthropic。
- **DocumentSummaryImageService** (`lib/services/document_summary_image_service.dart`) — 产物路径通过 `DocPaths` 获取。
- **SummaryImageProvider** (`lib/providers/summary_image_provider.dart`) — 禁止多个 Widget 各自维护生成态。

### 网络代理

- **ProxyProvider** (`lib/providers/proxy_provider.dart`) — 自动同步到所有 Dio 实例。禁止在单个服务上单独配置代理。

### PDF 处理

- **PdfProcessLock** (`lib/services/pdf_process_lock.dart`) — 完整 PDF 加载必须在 `run()` 内串行执行。
- **PdfThumbnailService** (`lib/services/pdf_thumbnail_service.dart`) — 禁止为缩略图直接加载完整 PDF。

### 标识符与元数据

- **IdentifierParser** (`lib/services/identifier_parser.dart`) — 禁止自行编写标识符正则。
- **IdentifierResolver** (`lib/services/identifier_resolver.dart`) — PubMed 走 `efetch.fcgi`（XML）。禁止直接调用出版商 API 或 Unpaywall。
- 其他：`DocumentMetadataParser`、`PdfIdentifierExtractor`（须通过 PdfProcessLock）、`PdfMetadataExtractor`。

### 文档提取

- **BatchExtractService** (`lib/services/batch_extract_service.dart`) — 主提取路径（异步 Job API）。
- **DocExtractService** (`lib/services/doc_extract_service.dart`) — 同步 fallback + `saveResult()` 保存入口（内部自动调用 FigureExtractService）。
- **FigureExtractService** (`lib/services/figure_extract_service.dart`) — 由 `saveResult()` 内部调用，独立调用前须 `init()`。

### 阅读器

- **ReaderSettingsProvider** (`lib/providers/reader_settings_provider.dart`) — 主题颜色必须通过 `resolveReaderPalette()` 派生。枚举只能尾追。
- **ReaderSessionProvider** (`lib/providers/reader_session_provider.dart`) — 禁止在 `ReaderPage` 散落维护 Markdown 缓存/搜索状态/直接写 `highlightProvider`。
- **WebViewMarkdownReader** (`lib/pages/reader/widgets/webview_markdown_reader.dart`) — 主渲染路径，Dart markdown→HTML→localhost server 加载。主题/字号变化只更新 CSS 变量。
- **webview_reader_html** (`lib/pages/reader/widgets/webview_reader_html.dart`) — KaTeX 走本地 `assets/katex/`。禁止依赖 CDN。
- **ReaderTopToolbar / ReaderBottomBar** — 禁止把新按钮直接堆回 `ReaderPage` 的 build 里。
- **搜索** — PDF 走 `pdfrx` PdfTextSearcher；Markdown 走 `MarkdownDocumentCacheService` 搜索快照。禁止每次输入全量解析。
- **双路径高亮** — 新建走精确 Range（`addHighlightFromSelection`），恢复走文本搜索（`addByText`）。
- **FigureViewer** (`lib/pages/reader/widgets/figure_viewer.dart`) — 复制图片用 `Pasteboard.writeImage()`，禁止用 `Clipboard.setData`。
- **底部面板** — 禁止直接访问 `settings.backgroundColor`，用 `resolveReaderPalette()`。

### 其他

- **Material Symbols** (`package:material_symbols_icons/symbols.dart`) — 全项目唯一图标集。禁止使用 `Icons.xxx`。
- **SpringDismissible** (`lib/widgets/spring_dismissible.dart`) — 弹性滑动删除组件。
- **WindowChrome** (`lib/widgets/window_chrome.dart`) — 禁止在页面级 Scaffold 挂 chrome，窗口装饰只属于 app 外层。

## 转场动画

- 路由转场：`FadeThroughTransition`，300ms `Curves.easeOut`，统一通过 `_buildAnimatedPage()` 封装
- 页内切换（如 PDF↔Markdown）：`SharedAxisTransition` horizontal，300ms
- 禁止用 `flutter_animate` 的 `.slideY()` / `.fade()` 做路由级转场

## UI 组件范式

组件视觉参数定义在 [flutter-design](.claude/skills/flutter-design/SKILL.md) skill 中，编码前必须查阅。

## Dependency 更新

添加或更新 `pubspec.yaml` 依赖时必须先到 pub.dev 确认最新稳定版，禁止凭记忆复制版本号。

@TODO.md
