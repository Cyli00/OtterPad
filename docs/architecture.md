# OtterPad 0.2.0 架构

状态：目标架构，尚未实现。`v0.1.7` tag 是最后一版 Dart 后端 + WebView 阅读器，也是业务行为的参考实现（`lib/services`、`lib/core/storage`、`lib/data`）；0.1.x 设计文档在 `archive/0.1/`。

## 为什么重写

0.1.x 在四处到了瓶颈：长解析文档在 WebView 中滚动卡顿（DOM + KaTeX）、长 PDF 翻页缩放卡顿（Dart 侧译文排版、字符对齐与绘制层）、解析后处理慢（图表归属、题注配对、段落索引在 Dart 中计算）、首屏等待长。0.2.0 一次性重写：计算与数据全部下沉到 Rust，渲染全部改为 Flutter 原生绘制，不再使用 WebView。

参照项目 `fqapp`（同为 GPLv3，可直接借鉴代码）的分工：它的 Rust 核心负责网络、加解密与缓存，**文字排版和分页在 Flutter 侧用 `TextPainter` 完成**（`lib/widgets/reader/reader_chapter_layout.dart`、`reader_paged_view.dart`）。OtterPad 沿用这条边界：Rust 不排重排正文的文字。

## 分层

| 层 | 职责 |
| --- | --- |
| Flutter（`lib/`） | 只做 UI：页面、Riverpod 状态、重排正文的测量/分页/绘制、公式（`flutter_math_fork`）、PDF 位图与叠加层显示、读取系统安全存储中的密钥并注入 Rust |
| Rust（`rust/`，crate `otter_core`） | 全部业务与数据：持久化、文献库、OCR 接入、文档模型、PDF、AI、翻译、搜索、备份同步、Zotero、0.1.x 迁移 |

阅读器整体重写；文献库、设置、聊天等页面保留现有 UI，数据源改接 Rust。

### Rust 模块

| 模块 | 职责 | 0.1.x 行为参考 |
| --- | --- | --- |
| `storage` | rusqlite（bundled SQLite）、schema 迁移、FTS5 + 中文分词 | `lib/core/storage/` |
| `library` | 文献、收藏、历史、导入、DOI/元数据解析、文件布局 | `identifier_resolver.dart`、`document_file_operations.dart` |
| `ocr` | PaddleOCR / MinerU VLM 客户端，原始结果落盘 | `doc_extract_service.dart`、`mineru_extract_service.dart`、`batch_extract_service.dart` |
| `document` | 统一文档块模型、段落身份、锚点、图表与题注归属、表格解析 | `document_structure.dart`、`figure_extract_service.dart`、`figure_markdown.dart`、`table_parse_*` |
| `pdf` | PDFium（pdfium-render）：分块渲染与缓存、字符提取、OCR 对齐、译文布局计算 | `reader_pdf_*.dart` |
| `ai` | 各服务商协议、流式输出、工具调用（联网搜索） | `agent_chat_service.dart`、`lib/data/models/ai/` |
| `translate` | 段落/全文/题注翻译与缓存 | `document_translation_service.dart` |
| `sync` | WebDAV / S3 备份恢复、Zotero | `backup_*`、`zotero_*` |
| `migrate` | 0.1.x 数据导入（见下文） | — |

## Flutter ↔ Rust 接口

- flutter_rust_bridge v2，强类型 API：Rust 的 struct/enum 生成 Dart 类型。不提供 loopback HTTP 或 `request(route, json)` 式单入口。
- 入口集中在 `rust/src/api/`；生成物 `lib/src/rust/`、`rust/src/frb_generated.rs` 只由 codegen 产出。
- 长任务（OCR、AI 流、翻译、迁移、渲染批次）返回 Stream 推送进度或 token，并可按任务 id 取消；取消即丢弃在途 future，已提交的文件写入不回滚。
- 错误统一为 `OtterError { code, detail }`：`code` 是稳定枚举，Dart 映射到 ARB 文案；`detail` 只进日志。Rust 不产出用户可见文案。
- 重计算跑在 Rust 线程池，Dart 主 isolate 不等待它们；同步 FFI 调用只用于 O(1) 读取。
- PDF 位图等大块二进制优先零拷贝传给 Dart。

## 渲染

**重排正文**：`document` 输出文档块（标题、段落、列表、引用、图、表、独立公式），每块有稳定的块 id、带行内公式的 inline runs，以及到 PDF 页面区域的来源映射。Flutter 用 `TextPainter` 测量并支持竖向连续滚动与横向分页两种模式，所有平台都可切换。选区、高亮、搜索命中都画成 `TextSpan` 背景，不另加覆盖层。

**锚点**：`(blockId, language, utf16 start/end)` 加上原文引文 `quote/prefix/suffix`。块 id 失配时按引文重新定位，失败保留为未定位标注。

**PDF**：Rust 按缩放级别渲染分块位图，内存有上限的 LRU 缓存；译文、标注、选区的几何也由 Rust 计算，Flutter 只负责绘制。去掉 pdfrx。

## 存储

- 根目录 `<AppSupport>/OtterPad/v2/`：`otter.db`、`library/<docId>/`（`source.pdf`、OCR 原始结果、派生产物）、`logs/`。与 0.1.x 的 `<AppSupport>/OtterPad/{db,library,logs}` 并列，迁移期间互不覆盖。
- 设置存在 SQLite 的 settings 表；只有界面临时状态留在 Dart。
- 密钥（API Key、WebDAV/S3/Zotero 凭据）继续存系统安全存储（`flutter_secure_storage`），沿用 0.1.x `SecureCredentialVault` 的键名，因此无需迁移。启动和修改时由 Dart 交给 Rust，Rust 只在内存中持有，不写入数据库、日志或备份明文。

## 0.1.x 数据迁移

沿用包名与签名，覆盖安装。首次启动检测到 `<AppSupport>/OtterPad/db/otter.db` 且 v2 没有迁移标记时，运行 `migrate`，进度通过 Stream 显示。原则：**复制不移动、按文献幂等可续、用户写下的内容不丢**。

| 数据 | 0.1.x 来源 | 处理 |
| --- | --- | --- |
| 文献元数据、收藏、收藏关系、阅读历史、Zotero 映射、meta | `otter.db` 的 `documents`、`favorites`、`favorite_documents`、`history`、`zotero_items`、`meta` 表 | 原样导入；`history.anchorBlock` 尽力换算，失败只保留 `progress` |
| 设置 | `settings` 表（JSON 值） | 按键名映射导入，无对应项的丢弃 |
| PDF、OCR 原始结果、MinerU 导出包、图片 | `library/<docId>/` 下的 `source.pdf`、`extract.*.json`、`*.raw.md`、`mineru.exports.zip`、`figures/` | 复制；`document` 从原始结果重建文档模型与图表清单，不重新调用 OCR 接口 |
| 标注与笔记 | `highlights` 表，`anchor` 为 `ReaderAnchor` v1 JSON | 按 `quote/prefix/suffix` 在新模型中重新定位；定位失败的保留为未定位笔记，不删除 |
| 全文译文 | `library/<docId>/translations.json` | 按原文哈希对到新段落，对不上的丢弃（可重新翻译） |
| 问 AI 会话、摘要图 | `chats/*.json`、`summary/` | 原样导入 |
| 选区翻译缓存 | `translations` 表（7 天 TTL） | 丢弃 |
| WebView 产物、日志 | `.reader.html*`、`logs/` | 丢弃 |

每篇文献导入成功后写标记；中断或失败时应用照常可用，下次启动从未完成的文献继续。全部完成后写 v2 迁移标记。0.1.x 目录保留到用户在存储设置中手动清理。0.1.x 的备份压缩包走同一迁移器恢复。

## 构建与平台

- 用 flutter_rust_bridge 的 integrate 模板（cargokit）接入，`flutter run/build` 时自动编译 Rust。
- 平台：Android `aarch64-linux-android`、`armv7-linux-androideabi`，Windows `x86_64-pc-windows-msvc`，macOS `aarch64-apple-darwin`。iOS、Linux 暂不发布。
- 工具链版本与 CI 步骤见 `docs/release.md`。

## 实现前需核实

以下是方案依赖但尚未验证的事实，核实结果写回本文：

- flutter_rust_bridge 当前稳定版、v2 的零拷贝 API，以及 integrate 模板是否会改动禁止编辑的平台目录（`android/`、`macos/`、`windows/`）。
- pdfium-render 需要随包分发各平台的 PDFium 动态库：来源、许可与打包方式。
- rusqlite 不直接提供 FTS5 自定义 tokenizer 接口：中文分词需评估 jieba-rs + FFI 注册 tokenizer，或沿用 `sqlite3_simple` 的 C 扩展静态链接。
- `flutter_math_fork` 在上千个公式的长文档里的帧耗时（懒构建 + 绘制缓存是否足够）。
