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

格式：`模块 (路径) — 禁令`。本表只收「代码推不出来」的坑（绑死具体 bug 或反直觉的不变量），不是完整接缝索引——未列出不代表可绕过，常规 seam 读源码即可发现；遇到新的反直觉坑再补进来。

### 启动与运行时

- **ReaderLocalhostServer** (`lib/services/reader_localhost_server.dart`) — 禁止 WebView 直接加载 `file://`。

### 数据存储

- **GStorage** (`lib/core/storage/storage.dart`) — Drift 主库 + 文件系统根目录管理。禁止绕过 `appDatabaseProvider` 直接自建 AppDatabase 实例。禁止直接 `getApplicationSupportDirectory()` 拼路径。
- **appDatabaseProvider** (`lib/core/storage/app_database_provider.dart`) — 数据 provider 的 Drift 实例唯一来源。reopen（备份恢复）后必须 `ref.invalidate(appDatabaseProvider)`，禁止自建 AppDatabase 实例或绕过它直接 `GStorage.db`。
- **SecureCredentialVault** (`lib/core/storage/secure_credential_vault.dart`) — API key / secret 唯一存取。禁止写进 `GStorage`。
- **DocPaths** (`lib/utils/doc_paths.dart`) — 禁止 `p.basenameWithoutExtension` 或持久化绝对路径拼接。
- **BackupRestoreService** (`lib/services/backup_restore_service.dart`) — 禁止手写 ZIP 或直接覆盖数据库文件不经 `GStorage.close()`/`reopen()`。
- **BackupRemote** (`lib/services/backup_remote.dart`) — S3/WebDAV 唯一接缝。禁止按 `remoteType` 自写 if/else 分发。

### Agent API 与模型

- **AgentModelCapability** (`lib/services/agent_model_capability.dart`) — 模型能力数据模型（含 `webSearch`）。能力解析优先级链在 `AgentProviderInstance.capabilityFor`：用户手动覆写 > 远程能力表 > 正则推断。禁止绕过此链或硬编码能力判断。
- **ModelCapabilityStore** (`lib/services/model_capability_store.dart`) — 远程模型能力规则集唯一接缝（modelcaps geosite 订阅：jsdelivr CDN 拉取 + ETag/Last-Modified 条件请求 + 本地文件缓存 + TTL 后台刷新）。缓存落 `GStorage.dbDirPath`，元数据走 `GStorage.setting`，HTTP 复用 `AgentHttp`。禁止自抓 modelcaps 仓库、另存能力缓存或在别处自写远程能力查询。
- **AgentChatService** (`lib/services/agent_chat_service.dart`) — 禁止自写 `switch(provider)` 拼请求体。
- **BuiltInToolNames** (`lib/services/builtin_tools.dart`) — 禁止硬编码工具名字符串或自写厂商域名判断。

### 全文搜索

- **FTS5 / jieba 分词** — 全文搜索唯一实现（`documents_fts` 虚表 + jieba tokenizer）。禁止自写中文分词、拼音搜索或 LIKE 替代逻辑。搜索降级（LIKE）由 `searchDocuments` 自动处理，调用点不应自行判断降级时机。

### 网络 / PDF / 标识符

- **ProxyProvider** (`lib/providers/proxy_provider.dart`) — 禁止在单个服务上单独配置代理。
- **PdfProcessLock** (`lib/services/pdf_process_lock.dart`) — 完整 PDF 加载必须在 `run()` 内串行执行。
- **PdfThumbnailService** (`lib/services/pdf_thumbnail_service.dart`) — 禁止为缩略图加载完整 PDF。
- **IdentifierResolver** (`lib/services/identifier_resolver.dart`) — 禁止直接调用出版商 API 或 Unpaywall。
- **ChineseMetadataExtractor** (`lib/services/chinese_metadata_extractor.dart`) — 是否中文走 `ChineseTextDetector`，禁止自写 CJK 正则。

### Zotero / 文档提取

- **ZoteroSyncService** (`lib/services/zotero_sync_service.dart`) — 禁止在此落盘或做 `Document` 映射。
- **ZoteroItemMapper** (`lib/services/zotero_item_mapper.dart`) — 禁止让 Zotero 字段渗入 `Document`。
- **DocumentStructure** (`lib/services/document_structure.dart`) — `extract.json` 唯一防腐层。禁止 `jsonDecode` 后直挖 `parsing_res_list`。
- **LayoutMetadataExtractor** (`lib/services/layout_metadata_extractor.dart`) — 从 `extract.json` 首页提取中文书籍题录，是否中文走 `ChineseTextDetector`。禁止自写 CJK 题录正则。

### 阅读器

- **ReaderSettingsProvider** (`lib/providers/reader_settings_provider.dart`) — 主题色走 `resolveReaderPalette()`。枚举只能尾追。
- **webview_reader_html** (`lib/pages/reader/widgets/webview_reader_html.dart`) — 静态样式/脚本在 `assets/reader/`。禁止内联回 Dart、禁止依赖 CDN。
- **escapeJsLiteral** (`lib/utils/js_string_escape.dart`) — 向 WebView 注入 JS 时字符串转义唯一函数。禁止手拼 JS 字符串字面量。
- **FigureViewer** (`lib/pages/reader/widgets/figure_viewer.dart`) — 复制图片用 `Pasteboard.writeImage()`，禁止 `Clipboard.setData`。
- 底部面板禁止直接 `settings.backgroundColor`，用 `resolveReaderPalette()`。

### 国际化

- **L10nExtension** (`lib/core/l10n.dart`) — `context.l10n` 简写。禁止直接 import `app_localizations.dart`。

### 其他

- **Material Symbols** — 全项目唯一图标集。禁止 `Icons.xxx`。
- **OnboardingNotifier** (`lib/providers/onboarding_provider.dart`) — 首启引导状态机，`hasSeenOnboarding` 存 `GStorage.setting`。禁止自行判断/持久化首启标志。
- **SystemSpecs** (`lib/services/system_specs.dart`) — About 系统标签 / issue 系统信息。Android 版本走 `device_info_plus` 的 `version.release`。禁止用 `Platform.operatingSystemVersion` 取首段数字推断 Android 版本（Build.DISPLAY 会误判成 3 等）。

@TODO.md

