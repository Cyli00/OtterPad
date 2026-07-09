# Project Guidelines

## Edit Rules

- 每次项目对 Infrastructure Modules 内部使用的包进行更换，都要在 Infrastructure Modules 内部更新。
- 禁止编辑 `android/`、`windows/`、`linux/`、`macos/`、`ios/`、`web/` 目录，这些由 Flutter 自动生成。

## Compact/Handoff Rules

**优先压缩**需要基于检索推理的 Flutter 相关任务，而非预训练知识。

## Behavior

- 不确定就问，不要猜。多种理解方式时列出选项。
- 不写没被要求的功能、抽象、"灵活性"。200 行能用 50 行解决就重写。
- 不"顺手改进"相邻代码。不重构没坏的东西。匹配现有风格。
- 发现无关死代码只提醒不删。自己产生的孤儿必须清理。每一行 diff 都应追溯到用户请求。
- 多步任务先列计划：`步骤 → 验证方式`。澄清问题在实现之前提出。

## 动画时序

`AnimationConstants` (`lib/core/animation_constants.dart`)：`kAnimFast`（180ms）微交互 · `kAnim`（240ms）标准过渡 · `kAnimSlow`（320ms）大转场。曲线 `kAnimCurve`（easeOutCubic）/ `kAnimCurveReverse`（easeInCubic）。禁止硬编码 Duration。

## 触觉反馈

`Haptics` (`lib/services/haptics.dart`)：`soft()` 日常点击 · `light()` 轻量确认 · `medium()` 破坏性操作。禁止直接 `HapticFeedback.*`。

## 转场动画

- 路由：`FadeThroughTransition` + `kAnimSlow`，通过 `_buildAnimatedPage()` 封装
- 页内切换：`SharedAxisTransition` horizontal + `kAnimSlow`
- 对话框：`showAppDialog()`
- 禁止用 `flutter_animate` 的 `.slideY()` / `.fade()` 做路由级转场

## UI 组件范式

组件视觉参数定义在 [flutter-design](.claude/skills/flutter-design/SKILL.md) skill 中，编码前必须查阅。

## 布局边界与窄屏适配

- `x.clamp(lo, hi)` 中 `hi` 由「尺寸 − 内容」算出时，必须 `hi = math.max(lo, …)` 兜底。否则窄屏上 `hi < lo` 抛 `ArgumentError`，release 下被静默吞成灰框——表现为整个 overlay/widget 不可见、只在窄机型复现，极难定位。
- 工具栏/浮层等按内容自适应宽度的组件，必须约束 `maxWidth ≤ 屏宽 − 边距`，超出时横向滚动。最窄主流机型逻辑宽度按 **360dp** 计，不要假设内容一定放得下。
- 禁止硬编码可能超出窄屏的固定宽度，或假设逻辑宽度/高度 ≥ 某常量。机型不兼容多源于此，本地 debug 屏宽够大测不出，必须按最窄机型推演。

## 多语言 (i18n)

- 用户可见字符串必须 ARB 国际化。模板 `lib/l10n/app_en.arb`，中文 `app_zh.arb`。改后 `flutter gen-l10n`。
- Widget 层 `context.l10n.keyName`，服务层 `rootNavigatorKey.currentContext`。插值用 `{placeholder}`。
- 不需要国际化：AI prompt、正则、代码注释、技术标识符。

## Dependency 更新

添加或更新 `pubspec.yaml` 依赖时必须先到 pub.dev 确认最新稳定版，禁止凭记忆复制版本号。

---

## 基础模块禁令

格式：`模块 (路径) — 禁令`。完整功能说明见源码，这里只列禁止绕过的接缝。

### 启动与运行时

- **main** (`lib/main.dart`) — 新增启动态服务挂在这里。禁止绕过 `GStorage` 自行推断根目录。
- **ReaderLocalhostServer** (`lib/services/reader_localhost_server.dart`) — 禁止 WebView 直接加载 `file://`。
- **ShareReceiverService** (`lib/services/share_receiver_service.dart`) — 移动端分享/打开文件唯一入口（MethodChannel）。禁止 UI 自己监听 share intent 或绕过它导入。

### 通知与任务

- **SnackBarService** (`lib/services/snackbar_service.dart`) — 禁止直接 `ScaffoldMessenger.showSnackBar()`。
- **TaskActivityProvider** (`lib/providers/task_activity_provider.dart`) — 后台任务进度统一 `report` 到这里。禁止各自弹进度。
- **TaskRunner** (`lib/providers/task_runner.dart`) — 后台任务模板 mixin，生命周期走 `executeTaskBody`。
- **TaskProvider** (`lib/providers/task_provider.dart`) — 全局任务调度。禁止把单篇文献任务塞回全局 TaskType。
- **DocumentLifecycleProvider** (`lib/providers/document_lifecycle_provider.dart`) — 禁止绕过它修改跨模块状态。
- **DocumentTaskProvider** (`lib/providers/document_task_provider.dart`) — 单篇文献任务入口。禁止 Widget 自管 CancelToken。
- **SelectionProvider** (`lib/providers/selection_provider.dart`) — 列表多选，`sourceContext` 隔离页面来源。

### 数据存储

- **GStorage** (`lib/core/storage/storage.dart`) — 禁止直接 `Hive.openBox()` 或 `getApplicationSupportDirectory()` 拼路径。
- **SecureCredentialVault** (`lib/core/storage/secure_credential_vault.dart`) — API key / secret 唯一存取。禁止写进 `GStorage`。
- **DocPaths** (`lib/utils/doc_paths.dart`) — 禁止 `p.basenameWithoutExtension` 或持久化绝对路径拼接。
- **StorageCleanupService** (`lib/services/storage_cleanup_service.dart`) — 禁止 UI 层直接删缓存目录。
- **StorageUsageService** (`lib/services/storage_usage_service.dart`) — 存储用量统计唯一来源。禁止 UI 自行遍历目录算大小。
- **BackupProvider** (`lib/providers/backup_provider.dart`) — 禁止散落保存备份凭据。
- **BackupRestoreService** (`lib/services/backup_restore_service.dart`) — 禁止手写 ZIP 或直接覆盖 Hive 不经 `GStorage.close()`/`reopen()`。
- **BackupMergeService** (`lib/services/backup_merge_service.dart`) — 禁止在 restore/merge 流程外拼装 Hive box 合并。
- **BackupS3Service** (`lib/services/backup_s3_service.dart`) — 禁止 UI 层拼 S3 签名请求。
- **BackupRemote** (`lib/services/backup_remote.dart`) — S3/WebDAV 唯一接缝。禁止按 `remoteType` 自写 if/else 分发。
- **BackupOrchestrator** (`lib/providers/backup_orchestrator.dart`) — 备份/恢复编排唯一入口。禁止自行拼接 RestoreService + Remote 链路。
- **BackupFingerprintService** (`lib/services/backup_fingerprint.dart`) — 禁止另存备份时间戳或自写指纹比对。
- **AutoBackupProvider** (`lib/providers/auto_backup_provider.dart`) — 禁止另起定时器触发备份。
- **SyncStatusProvider** (`lib/providers/sync_status_provider.dart`) — 云同步状态唯一真值源。禁止 UI 自行比对指纹或发网络请求判定。

### Agent API 与模型

- **AgentApiProvider** (`lib/providers/api_provider.dart`) — 多实例 API 配置中心。禁止调用点自行猜 provider/实例。`AgentModelParams` 同文件，禁止散落字符串传参。
- **AgentModelCapability** (`lib/services/agent_model_capability.dart`) — 禁止硬编码模型能力判断。
- **AgentChatService** (`lib/services/agent_chat_service.dart`) — 多模态对话唯一出口。禁止自写 `switch(provider)` 拼请求体。
- **BuiltInToolNames** (`lib/services/builtin_tools.dart`) — 禁止硬编码工具名字符串或自写厂商域名判断。
- **TavilySearchService** (`lib/services/tavily_search_service.dart`) — 禁止自存 Tavily Key 或绕过它请求 Tavily API。
- **UrlContextService** (`lib/services/url_context_service.dart`) — 客户端 URL 提取回退。禁止自写网页抓取/正文提取。
- **DocumentChatService** (`lib/services/document_chat_service.dart`) — 问 AI 唯一出口。禁止 UI 直接调 AgentChatService。
- **DocumentChatProvider** (`lib/providers/document_chat_provider.dart`) — 禁止页面自管发送状态或 CancelToken。
- **Prompts / PromptDef** (`lib/services/prompts.dart`) — LLM prompt 唯一文本源。禁止硬编码 prompt 或自写 `{{}}` 替换。
- **PromptStore** (`lib/services/prompt_store.dart`) — 禁止自写 prompt 默认值回退/存储/重置逻辑。
- **AiSettingsPrompt** (`lib/services/ai_settings_prompt.dart`) — 禁止各调用点自写 AI 设置错误文案。

### 翻译系统

- **DocumentTranslationService** (`lib/services/document_translation_service.dart`) — 文档级翻译（段落粒度，8 worker）。
- **BackMatterDetector** (`lib/services/back_matter_detector.dart`) — 禁止新增硬编码 References 正则。
- **ProtectedSpans** (`lib/services/translation_protected_spans.dart`) — 禁止在译路自写公式/代码保护正则。
- **TranslationHighlightParser** (`lib/services/translation_highlight_parser.dart`) — 翻译弹窗 `%%%%` 分隔符高亮解析。禁止在 UI 层自写分隔/定位逻辑。

### 图像生成

- **ImageGenerationService** (`lib/services/image_generation_service.dart`) — 支持 OpenAI / Gemini，不支持 Anthropic。
- **SummaryImageProvider** (`lib/providers/summary_image_provider.dart`) — 禁止多个 Widget 各自维护生成态。

### 网络 / PDF / 标识符

- **ProxyProvider** (`lib/providers/proxy_provider.dart`) — 禁止在单个服务上单独配置代理。
- **PdfProcessLock** (`lib/services/pdf_process_lock.dart`) — 完整 PDF 加载必须在 `run()` 内串行执行。
- **PdfThumbnailService** (`lib/services/pdf_thumbnail_service.dart`) — 禁止为缩略图加载完整 PDF。
- **IdentifierParser** (`lib/services/identifier_parser.dart`) — 禁止自写标识符正则。
- **IdentifierResolver** (`lib/services/identifier_resolver.dart`) — 禁止直接调用出版商 API 或 Unpaywall。
- **MetadataSearchService** (`lib/services/metadata_search_service.dart`) — 禁止绕过它直接拼出版商搜索请求。
- **ChineseMetadataExtractor** (`lib/services/chinese_metadata_extractor.dart`) — 是否中文走 `ChineseTextDetector`，禁止自写 CJK 正则。

### Zotero / 文档提取

- **ZoteroSyncService** (`lib/services/zotero_sync_service.dart`) — 禁止在此落盘或做 `Document` 映射。
- **ZoteroItemMapper** (`lib/services/zotero_item_mapper.dart`) — 禁止让 Zotero 字段渗入 `Document`。
- **ZoteroSyncProvider** (`lib/providers/zotero_sync_provider.dart`) — 禁止散落保存 Zotero 凭据。
- **DocumentStructure** (`lib/services/document_structure.dart`) — `extract.json` 唯一防腐层。禁止 `jsonDecode` 后直挖 `parsing_res_list`。
- **LayoutMetadataExtractor** (`lib/services/layout_metadata_extractor.dart`) — 从 `extract.json` 首页提取中文书籍题录，是否中文走 `ChineseTextDetector`。禁止自写 CJK 题录正则。

### 阅读器

- **ReaderSettingsProvider** (`lib/providers/reader_settings_provider.dart`) — 主题色走 `resolveReaderPalette()`。枚举只能尾追。
- **ReaderSessionProvider** (`lib/providers/reader_session_provider.dart`) — 禁止在 `ReaderPage` 散落维护缓存/搜索状态。
- **webview_reader_html** (`lib/pages/reader/widgets/webview_reader_html.dart`) — 静态样式/脚本在 `assets/reader/`。禁止内联回 Dart、禁止依赖 CDN。
- **escapeJsLiteral** (`lib/utils/js_string_escape.dart`) — 向 WebView 注入 JS 时字符串转义唯一函数。禁止手拼 JS 字符串字面量。
- **ReaderSheetHost** (`lib/pages/reader/widgets/reader_sheet_host.dart`) — 禁止在阅读器内用 `showModalBottomSheet`。
- **MajorSectionMatcher** (`lib/services/major_section_matcher.dart`) — 主章节判定（配置 `assets/config/major_sections.json`）。禁止自写章节标题正则。
- **FigureViewer** (`lib/pages/reader/widgets/figure_viewer.dart`) — 复制图片用 `Pasteboard.writeImage()`，禁止 `Clipboard.setData`。
- 底部面板禁止直接 `settings.backgroundColor`，用 `resolveReaderPalette()`。

### 国际化

- **LocaleNotifier** (`lib/providers/locale_provider.dart`) — 禁止 UI 层自行切换 locale。
- **L10nExtension** (`lib/core/l10n.dart`) — `context.l10n` 简写。禁止直接 import `app_localizations.dart`。

### 其他

- **Material Symbols** — 全项目唯一图标集。禁止 `Icons.xxx`。
- **TactilePress** (`lib/widgets/tactile_press.dart`) — 新增可点击卡片/列表项优先使用。
- **showAppDialog** (`lib/widgets/app_dialog.dart`) — 禁止自行编写 `showGeneralDialog` 转场。
- **WindowChrome** (`lib/widgets/window_chrome.dart`) — 禁止在页面级 Scaffold 挂 chrome。
- **OnboardingNotifier** (`lib/providers/onboarding_provider.dart`) — 首启引导状态机，`hasSeenOnboarding` 存 `GStorage.setting`。禁止自行判断/持久化首启标志。
- **SystemSpecs** (`lib/services/system_specs.dart`) — About 系统标签 / issue 系统信息。Android 版本走 `device_info_plus` 的 `version.release`。禁止用 `Platform.operatingSystemVersion` 取首段数字推断 Android 版本（Build.DISPLAY 会误判成 3 等）。

@TODO.md

