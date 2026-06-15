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

- **SnackBarService** (`lib/services/snackbar_service.dart`) — 全局 SnackBar 唯一出口，单槽渲染（瞬时结果与进度互相让位、结束回收）；观察 `taskActivityProvider` 自动呈现进度。禁止直接使用 `ScaffoldMessenger.showSnackBar()`。
- **TaskActivityProvider** (`lib/providers/task_activity_provider.dart`) — 正在运行的后台任务**活集合**单一真值源（`report`/`finish`/`cancelAll`，`ActiveTask`/`ListenableProgress`）。后台任务进度统一 `report` 到这里，由 SnackBar surface（及未来多文档任务面板）观察渲染。禁止后台任务各自直接弹进度 SnackBar。
- **TaskRunner** (`lib/providers/task_runner.dart`) — 后台任务模板 mixin，`TaskType`/`TaskInfo` 在 `task_types.dart`；执行生命周期统一走 `executeTaskBody`（与 `DocumentTaskNotifier` 共用 completed/cancelled/failed 三态处理）。
- **TaskProvider** (`lib/providers/task_provider.dart`) — 全局任务调度。禁止把单篇文献任务塞回全局 TaskType。
- **DocumentLifecycleProvider** (`lib/providers/document_lifecycle_provider.dart`) — 文献生命周期写入口。禁止页面/任务/阅读器直接绕过它修改跨模块状态。
- **DocumentTaskProvider** (`lib/providers/document_task_provider.dart`) — 单篇文献任务入口（max 5 并发）。禁止 Widget 自管 CancelToken。
- **SelectionProvider** (`lib/providers/selection_provider.dart`) — 列表多选状态，`sourceContext` 隔离页面来源。

### 数据存储

- **GStorage** (`lib/core/storage/storage.dart`) — Hive box 统一访问 + 文件系统根目录。禁止直接调用 `Hive.openBox()` 或 `getApplicationSupportDirectory()` 拼路径。
- **SecureCredentialVault** (`lib/core/storage/secure_credential_vault.dart`) — 所有 API key / secret / 密码的唯一存取接缝（同步读内存缓存 + 异步写各平台 Keystore/Keychain/DPAPI/libsecret）。禁止把 secret 写进 `GStorage`。
- **DocPaths** (`lib/utils/doc_paths.dart`) — 文献文件路径中心工具。禁止用 `p.basenameWithoutExtension` 或持久化绝对路径自行拼接。
- **StorageCleanupService** (`lib/services/storage_cleanup_service.dart`) — 禁止在 UI 层直接删除缓存目录。
- **BackupProvider** (`lib/providers/backup_provider.dart`) — 禁止在设置页或服务里散落保存备份凭据。
- **BackupRestoreService** (`lib/services/backup_restore_service.dart`) — ZIP 打包/恢复实现。创建侧 `BackupScope`（full / dataOnly），dataOnly 的文件过滤谓词 `includeInDataOnly` 是「数据文件」判定的单一来源（指纹服务共用）；dataOnly 备份覆盖恢复时自动从 `.bak` 拷回重文件防丢 PDF。禁止手写 ZIP 结构或直接覆盖 Hive 文件而不经过 `GStorage.close()`/`reopen()`。
- **BackupMergeService** (`lib/services/backup_merge_service.dart`) — 备份增量合并（按 ID 去重、只增不覆盖、不做版本比较）。本地专属配置（代理 / 备份凭据）不参与合并。禁止在 restore/merge 流程外自行拼装 Hive box 合并逻辑。
- **BackupS3Service** (`lib/services/backup_s3_service.dart`) — S3 SigV4 签名请求实现（含 `listObjects`/`deleteObject`）。禁止在 UI 层拼签名请求。
- **BackupRemote** (`lib/services/backup_remote.dart`) — S3 / WebDAV 远端备份的唯一接缝（`ping`/`upload`/`download`/`list`/`delete`，实例绑定远端目录、方法只接受文件名），`resolveBackupRemote()` 按配置解析 adapter。禁止调用点按 `remoteType` 自写 if/else 分发或裸操作 webdav client / BackupS3Service。
- **BackupOrchestrator** (`lib/providers/backup_orchestrator.dart`) — 备份/恢复编排唯一实现：打包→时间戳上传→保留 3 份 prune→落指纹快照；下载→排空 Active Task→恢复→刷新受影响 provider。设置页与自动备份都只调它。禁止页面/任务自行拼接 BackupRestoreService + BackupRemote 链路。
- **BackupFingerprintService** (`lib/services/backup_fingerprint.dart`) — 「上次备份了什么」的唯一记录：每篇文献 content/meta/files 三维指纹 + `BackupSnapshot` 快照（settings box）。禁止另存备份时间戳或自写指纹比对。
- **AutoBackupProvider / AutoBackupScheduler** (`lib/providers/auto_backup_provider.dart`) — 自动备份配置（周期/范围）与调度（main 挂载：启动 2min 首查 + 每小时 tick；闸门：到期且指纹有变化）。禁止另起定时器触发备份。
- **SyncStatusProvider** (`lib/providers/sync_status_provider.dart`) — 云同步三态（已同步/有变更/从未备份 + 变更原因）唯一真值源，现算指纹 vs 快照纯本地比对；云图标角标与云同步页共用。禁止 UI 自行比对指纹或发网络请求判定同步状态。

### Agent API 与模型

- **AgentApiProvider** (`lib/providers/api_provider.dart`) — API 配置中心，现为**多实例**（`AgentProviderInstance` 有序列表，同协议可多开、按 `instanceId` 寻址）。专家/快速/生图三个全局角色仍唯一，持久化为 `"instanceId:modelId"`。调用层读已解析视图 `effectiveAgentApiProvider`（`AgentApiState`），禁止在调用点自行猜 provider/实例。
- **AgentModelParams** (`lib/providers/api_provider.dart`) — 禁止用散落字符串 key 在 UI 和服务间传参。
- **AgentModelCapability** (`lib/services/agent_model_capability.dart`) — 禁止硬编码模型能力判断。
- **AgentChatService** (`lib/services/agent_chat_service.dart`) — 多模态对话唯一出口，非流式 `send` + 流式 `sendStream`（4 provider 请求构造 / 响应提取 / 结构化输出降级阶梯 / 瞬时重试 / 搜索工具回环：Kimi `$web_search` 服务端执行、Tavily 客户端执行，上限 3 轮）。禁止在 service 里自写 `switch(provider)` 拼请求体或逐家提取响应。注：`TranslationService` 的流式 SSE 仍各自实现，暂未收敛。
- **BuiltInToolNames / BuiltInToolsHelper** (`lib/services/builtin_tools.dart`) — 内置工具标识常量（search / urlContext）与 provider+model 官方支持检测 `isSupported`（兼容端按 baseUrl 域名识别 `CompatSearchVendor`：qwen/zhipu/kimi/mimo；`tavily` 是伪厂商，由 AgentChatService 在无原生搜索且已配置 Tavily 时主动升级）。禁止在请求构造 / 设置 UI 里硬编码工具名字符串或自写厂商域名判断。
- **TavilySearchService** (`lib/services/tavily_search_service.dart`) — Tavily 搜索客户端，为无原生联网的兼容端模型提供 function calling 搜索回退；API Key 的唯一存取接缝（存 SecureCredentialVault），已接入 ProxyProvider。禁止调用点自存 Tavily Key 或绕过它直接请求 Tavily API。
- **UrlContextService** (`lib/services/url_context_service.dart`) — 客户端 URL 内容提取回退（OpenAI / 兼容端无原生 URL 工具时抓取网页转文本注入上下文），已接入 ProxyProvider。Anthropic `web_fetch` / Gemini `url_context` 原生路径不经过这里。禁止在调用点自写网页抓取/正文提取。
- **DocumentChatService** (`lib/services/document_chat_service.dart`) — 问 AI 服务：会话文件存取（`library/{id}/chats/`）+ 文献上下文组装 + 角色解析（专家/快速各自 `loadInstance`）+ 请求发送的唯一出口。禁止 UI 直接调 AgentChatService 发文献问答。
- **DocumentChatProvider** (`lib/providers/document_chat_provider.dart`) — 问 AI 对话状态机（family by documentId：发送/流式增量/中断/会话切换/URL 回退接线）。禁止页面自管发送状态或 CancelToken。
- **AiSettingsPrompt** (`lib/services/ai_settings_prompt.dart`) — 禁止各调用点自写 AI 设置错误文案。
- **Prompts / PromptDef** (`lib/services/prompts.dart`) — 全代码库 LLM prompt 的唯一文本源：可定制 prompt 是 `PromptDef` 声明（id / storageKey / 默认文本 / 必需占位符），不可定制 prompt（如排版修复的 yFirst 变体）是同文件函数；占位符插值统一走 `renderPrompt`。改 prompt 措辞只碰这个文件。禁止在 service / provider 里硬编码 prompt 文本或自写 `{{}}` 替换。
- **PromptStore** (`lib/services/prompt_store.dart`) — 可定制 prompt 五件套（解析/保存/重置/是否默认/占位符校验）的唯一实现：空白 = 未定制回退默认，缺必需占位符拒绝保存并返回缺失列表。新 prompt 开放定制 = 在 `prompts.dart` 加一条 PromptDef 声明。禁止在 config provider 里自写 prompt 的默认值回退 / 存储 / 重置逻辑。

### 翻译系统

- **TranslationService** (`lib/services/translation_service.dart`) — 轻量翻译入口，优先使用 fast model。
- **DocumentTranslationService** (`lib/services/document_translation_service.dart`) — 文档级翻译（段落粒度，8 worker 并发），结果持久化到 `translations.json`。
- **DocumentTranslationProvider** (`lib/providers/document_translation_provider.dart`) — 每文档翻译状态机，Family provider 以 `documentId` 为 key。
- **BackMatterDetector** (`lib/services/back_matter_detector.dart`) — 后置区域检测单一数据源。禁止新增硬编码 References 正则。
- **TranslationStyle** (`lib/services/translation_style.dart`) — 使用 `[[tr]]...[[/tr]]` 自定义标记。
- **ProtectedSpans** (`lib/services/translation_protected_spans.dart`) — 翻译行内公式（`$…$` / `\(…\)` / `\[…\]`）与行内代码的占位符往返唯一实现：译前 `mask` 换 `[[mN]]`、译后 `restore`。划词高亮标记 `⟪⟫` 是硬边界。禁止在译路自写公式/代码保护正则。
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
- **MetadataSearchService** (`lib/services/metadata_search_service.dart`) — 无标识符时按标题搜学术库回退（`IdentifierResolver` 的平行接缝，多源按优先级 `canSearch`→`search`）。禁止绕过它在调用点直接拼出版商搜索请求。
- **ChineseMetadataExtractor** (`lib/services/chinese_metadata_extractor.dart`) — 中文期刊 PDF 首页文本元数据提取。是否中文走 `ChineseTextDetector`，禁止自行写 CJK 判定正则。
- 其他：`DocumentMetadataParser`、`PdfIdentifierExtractor`（须通过 PdfProcessLock）、`PdfMetadataExtractor`、`ChineseTextDetector`（CJK 检测单一来源）、`ChineseNameUtils`。

### Zotero 同步

- **ZoteroSyncService** (`lib/services/zotero_sync_service.dart`) — Zotero Web API v3 只读客户端（认证 / 分页 / 增量拉取），返回原始 item JSON，接入 `ProxyProvider`。禁止在此落盘或做 `Document` 映射。
- **ZoteroItemMapper** (`lib/services/zotero_item_mapper.dart`) — Zotero item ↔ `Document` 唯一防腐层（消化 itemType / creators / 字段差异）。禁止让 Zotero 字段细节渗入 `Document` 或 `IdentifierResolver`；落盘 id 由 `DocumentsNotifier.importDocuments` 分配。
- **ZoteroSyncProvider** (`lib/providers/zotero_sync_provider.dart`) — Zotero 凭据状态（API Key）。禁止在设置页 / 服务里散落保存 Zotero 凭据。

### 文档提取

- **BatchExtractService** (`lib/services/batch_extract_service.dart`) — 主提取路径（异步 Job API）。
- **DocExtractService** (`lib/services/doc_extract_service.dart`) — 同步 fallback + `saveResult()` 保存入口（内部自动调用 FigureExtractService）。
- **FigureExtractService** (`lib/services/figure_extract_service.dart`) — 由 `saveResult()` 内部调用，独立调用前须 `init()`。
- **DocumentStructure** (`lib/services/document_structure.dart`) — `extract.json`（PaddleOCR `parsing_res_list`：`block_label` / `block_bbox` / `block_content`）的唯一防腐层与类型化视图（`LayoutBlock` / `StructurePage`），容忍数组根与 `layoutParsingResults` 对象根。禁止在调用点 `jsonDecode` 后直挖 `parsing_res_list`。

### 阅读器

- **ReaderSettingsProvider** (`lib/providers/reader_settings_provider.dart`) — 主题颜色必须通过 `resolveReaderPalette()` 派生。枚举只能尾追。
- **ReaderSessionProvider** (`lib/providers/reader_session_provider.dart`) — 禁止在 `ReaderPage` 散落维护 Markdown 缓存/搜索状态/直接写 `highlightProvider`。
- **WebViewMarkdownReader** (`lib/pages/reader/widgets/webview_markdown_reader.dart`) — 主渲染路径，Dart markdown→HTML→localhost server 加载。主题/字号变化只更新 CSS 变量。
- **webview_reader_html** (`lib/pages/reader/widgets/webview_reader_html.dart`) — 只生成每文档动态 HTML + 注入 `:root` CSS 变量（含工具栏让位的 `--top-inset`）；静态样式/脚本已外置到 `assets/reader/reader.css`、`assets/reader/reader.js`，经 localhost `/_assets/*` 提供。KaTeX 走本地 `assets/katex/`。禁止把样式/脚本内联回 Dart 字符串、禁止依赖 CDN。
- **ReaderSheetHost** (`lib/pages/reader/widgets/reader_sheet_host.dart`) — 阅读器内嵌 bottom sheet 宿主（z-order 低于底栏，弹出时底栏仍可见可交互）。阅读器内所有 sheet（信息/大纲/笔记/主题/字体/收藏）走 host 的 `show()`，关闭用 `ReaderSheetHost.closeOf(context)`。禁止在阅读器内用 `showModalBottomSheet`。
- **ReaderTopToolbar / ReaderBottomBar** — 禁止把新按钮直接堆回 `ReaderPage` 的 build 里。
- **搜索** — PDF 走 `pdfrx` PdfTextSearcher；Markdown 走 `MarkdownDocumentCacheService` 搜索快照。禁止每次输入全量解析。结果卡展示「以匹配为中心的摘要窗口」，匹配判定与高亮共用同一 `RegExp`（支持 Match Case / Whole Word）。
- **MajorSectionMatcher** (`lib/services/major_section_matcher.dart`) — 主章节标题判定单一数据源（配置 `assets/config/major_sections.json`），与 `BackMatterDetector` 同接缝的两个 adapter。搜索结果分组仅认主章节标题，全文零命中时回退全 `##` 分组。禁止自写章节标题正则。
- **双路径高亮** — 新建走精确 Range（`addHighlightFromSelection`），恢复走文本搜索（`addByText`）。
- **FigureViewer** (`lib/pages/reader/widgets/figure_viewer.dart`) — 复制图片用 `Pasteboard.writeImage()`，禁止用 `Clipboard.setData`。
- **底部面板** — 禁止直接访问 `settings.backgroundColor`，用 `resolveReaderPalette()`。

### 国际化

- **LocaleNotifier** (`lib/providers/locale_provider.dart`) — App locale 状态（null = 跟随系统）。持久化到 GStorage，`MaterialApp.router` 的 `locale` 字段绑定此 provider。禁止在 UI 层自行切换 locale。
- **L10nExtension** (`lib/core/l10n.dart`) — `BuildContext.l10n` 简写 extension，同时 re-export `AppLocalizations`。新文件只需 `import 'core/l10n.dart'` 即可获得完整 l10n 访问能力。禁止直接 import `app_localizations.dart` 或手写 `AppLocalizations.of(context)!`。

### 其他

- **Material Symbols** (`package:material_symbols_icons/symbols.dart`) — 全项目唯一图标集。禁止使用 `Icons.xxx`。
- **SpringDismissible** (`lib/widgets/spring_dismissible.dart`) — 弹性滑动删除组件。
- **WindowChrome** (`lib/widgets/window_chrome.dart`) — 禁止在页面级 Scaffold 挂 chrome，窗口装饰只属于 app 外层。
- **TactilePress** (`lib/widgets/tactile_press.dart`) — 统一按压态交互组件（ColorTween + micro-scale + Haptics 集成）。替代 InkWell 涟漪。新增可点击卡片/列表项应优先使用。
- **showAppDialog** (`lib/widgets/app_dialog.dart`) — 统一对话框转场（Scale+Fade+BackdropFilter blur）。禁止在 dialog 中自行编写 `showGeneralDialog` 转场。

### 动画时序

- **AnimationConstants** (`lib/core/animation_constants.dart`) — 全局三档动画时序常量。禁止在 Widget 中硬编码 Duration 魔法数字。
  - `kAnimFast`（180ms）：微交互（hover、选择切换、勾选、工具栏）
  - `kAnim`（240ms）：标准过渡（状态变化、内容切换、面板收起）
  - `kAnimSlow`（320ms）：大转场（路由、弹窗、面板展开）
  - `kAnimCurve`（easeOutCubic）/ `kAnimCurveReverse`（easeInCubic）：统一缓动曲线

### 触觉反馈

- **Haptics** (`lib/services/haptics.dart`) — 集中式触觉反馈（平台自适应、全局开关、fire-and-forget）。禁止直接调用 `HapticFeedback.*`。
  - `Haptics.soft()`：日常点击反馈
  - `Haptics.light()`：轻量确认
  - `Haptics.medium()`：破坏性操作（删除、长按进入模式）

## 转场动画

- 路由转场：`FadeThroughTransition`，`kAnimSlow`，统一通过 `_buildAnimatedPage()` 封装
- 页内切换（如 PDF↔Markdown）：`SharedAxisTransition` horizontal，`kAnimSlow`
- 对话框转场：`showAppDialog()`，Scale(0.92→1)+Fade+BackdropFilter blur
- 禁止用 `flutter_animate` 的 `.slideY()` / `.fade()` 做路由级转场

## UI 组件范式

组件视觉参数定义在 [flutter-design](.claude/skills/flutter-design/SKILL.md) skill 中，编码前必须查阅。

## 多语言 (i18n)

- 所有用户可见字符串必须通过 ARB 国际化，禁止在 UI 层硬编码中文或英文。
- 翻译源文件在 `lib/l10n/app_en.arb`（模板）和 `lib/l10n/app_zh.arb`。新增字符串两个文件都要加。
- 新增或修改 ARB 后运行 `flutter gen-l10n` 重新生成 `lib/l10n/app_localizations*.dart`。
- Widget 层通过 `import '../../core/l10n.dart'` 引入，用 `context.l10n.keyName` 访问。
- 服务层无 BuildContext 时通过 `rootNavigatorKey.currentContext` 获取（定义在 `lib/router/app_router.dart`）。
- 含插值的字符串在 ARB 中用 `{placeholder}` 定义参数，生成方法签名如 `l10n.deletedDocuments(count)`。
- Locale 状态由 **LocaleNotifier** (`lib/providers/locale_provider.dart`) 管理，持久化到 GStorage。
- 不需要国际化的内容：AI prompt、正则模式、代码注释、内部技术标识符。

## Dependency 更新

添加或更新 `pubspec.yaml` 依赖时必须先到 pub.dev 确认最新稳定版，禁止凭记忆复制版本号。

@TODO.md
