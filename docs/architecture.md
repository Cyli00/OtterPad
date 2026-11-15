# OtterPad 0.2.0 架构

状态：Flutter 已全部改接 Rust 后端：文献库、导入、OCR、阅读器（原生重排正文 + Rust 分块渲染的 PDF 视图）、全文/选区翻译、问 AI、笔记、备份恢复、Zotero、存储管理与更新均调用 `rust/src/api/`；drift、WebView 阅读器、pdfrx 与 Dart 业务服务已删除。`v0.1.7` tag 是最后一版 Dart 后端 + WebView 阅读器，也是业务行为的参考实现；0.1.x 设计文档在 `archive/0.1/`。

## 为什么重写

0.1.x 在四处到了瓶颈：长解析文档在 WebView 中滚动卡顿（DOM + KaTeX）、长 PDF 翻页缩放卡顿（Dart 侧译文排版、字符对齐与绘制层）、解析后处理慢（图表归属、题注配对、段落索引在 Dart 中计算）、首屏等待长。0.2.0 一次性重写：计算与数据全部下沉到 Rust，渲染全部改为 Flutter 原生绘制，不再使用 WebView。

参照项目 `fqapp`（同为 GPLv3，可直接借鉴代码）的分工：它的 Rust 核心负责网络、加解密与缓存，**文字排版和分页在 Flutter 侧用 `TextPainter` 完成**（`lib/widgets/reader/reader_chapter_layout.dart`、`reader_paged_view.dart`）。OtterPad 沿用这条边界：Rust 不排重排正文的文字。

## 分层

| 层 | 职责 |
| --- | --- |
| Flutter（`lib/`） | 只做 UI：页面、Riverpod 状态、重排正文的测量/分页/绘制、公式（`flutter_math_fork`）、PDF 位图与叠加层显示 |
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
- 长任务（OCR、AI 流、翻译、迁移、渲染批次）返回 Stream 推送进度或 token，并可按任务 id 取消；失败通过携带 `OtterError` 的 `Failed` 终止事件返回，避免 FRB Stream 方法的异步返回错误成为 Dart 未处理异常。取消即丢弃在途 future，已提交的文件写入不回滚。
- 错误统一为 `OtterError { code, detail }`：`code` 是稳定枚举，Dart 映射到 ARB 文案；`detail` 只进日志。Rust 不产出用户可见文案。
- 重计算跑在 Rust 线程池，Dart 主 isolate 不等待它们；同步 FFI 调用只用于 O(1) 读取。
- PDF 位图等大块二进制优先零拷贝传给 Dart。

## 渲染

**重排正文**：`document` 输出文档块（标题、段落、列表、引用、图、表、独立公式），每块有稳定的块 id、带行内公式的 inline runs，以及到 PDF 页面区域的来源映射。Flutter 用 `TextPainter` 测量并支持竖向连续滚动与横向分页两种模式，所有平台都可切换。选区、高亮、搜索命中都画成 `TextSpan` 背景，不另加覆盖层。

**锚点**：`(blockId, language, utf16 start/end)` 加上原文引文 `quote/prefix/suffix`。块 id 失配时按引文重新定位，失败保留为未定位标注。

**PDF**：Rust 按缩放级别渲染分块位图（单块上限 16MB），内存有上限的 LRU 缓存；Flutter（`lib/pages/reader/pdf/`）按页宽排版、纵向滚动，Ctrl/⌘+滚轮与捏合缩放，渲染倍率按 1/4 倍频取整，每页只请求可见区域的 512px 分块。全文搜索逐页调用 Rust `search_pdf_page`，字符不跨 FFI。文字选择的命中与选区矩形在 Dart 用缓存的单页字符计算（Rust 的 `hit_test_pdf`/`pdf_selection_rectangles` 每次都要传整页字符，不适合拖动时逐帧调用）。封面缩略图同样由 Rust 渲染首页。全文译文可叠加在 PDF 页面上：`ReaderDocument.block_regions` 把块的 OCR 区域按 `structure.json` 的 `page_size` 换算成页面比例坐标，Flutter 在原位铺白底并按 PDF 点排版译文（含行内公式），整体随缩放变换；跨栏/跨页的块按各区域原文长度切分译文。PDF 只有原文/译文两态，双语投影为译文。图表题注没有可信文字框，保留原文；标注只在重排正文中显示。

**图表资产**：OCR 的 `ocr-current.json` 只指向完整 generation；身份摘要包含原始结果、结构、文档模型及资产字节，图片变化也会生成新目录。每个 generation 内的 `figures/figures.json` 使用 `algorithm_version=5`，保留旧清单的 `figures`、`img`、`figure_title`、`caption_refs` 字段，并记录 `segment_ids`、`visual_regions` 与 PNG 尺寸。PDFium 在 3 倍缩放下按视觉块并集分带裁剪；连续页的同一图表保留各页来源映射并合成预览。旧版清单与 `generation_*/` 相对图片路径继续可读；问 AI、摘要图和阅读模型均读取当前 generation。

## 存储

- 根目录 `<AppSupport>/OtterPad/v2/`：`otter.db`、`library/<docId>/`（`source.pdf`、OCR 原始结果、派生产物）、`logs/`。与 0.1.x 的 `<AppSupport>/OtterPad/{db,library,logs}` 并列，迁移期间互不覆盖。
- 设置存在 SQLite 的 settings 表；只有界面临时状态留在 Dart。
- 密钥（API Key、WebDAV/S3/Zotero 凭据）由 Rust 存在数据根的 `credentials.json`（与 `v2/` 并列，Unix 上 0600，明文），不使用系统钥匙串，也不写入数据库或日志；恢复备份替换 `v2/` 时不受影响。用户在备份设置里设置口令（本身存为凭据 `backup_credentials_password`）后，手动、自动和远端备份都附带 `credentials.enc`：PBKDF2-HMAC-SHA256 60 万次派生密钥、AES-256-GCM 加密（`aws-lc-rs`，已随 rustls 编入）；未设口令时备份不含凭据。恢复范围包含设置时，提交恢复可附带口令：Rust 先解密校验，口令错误返回 `Authentication` 且不改动数据、保留预览供重试，成功后把凭据合并写入。旧版本解包时忽略该条目。Dart 的 `CredentialVault` 启动时读入内存供同步读取，写入先交给 Rust 落盘。0.1.x 存在系统安全存储中的密钥不迁移，需要重新填写。保护程度与应用数据目录相同：能读取该目录的本机程序也能读取凭据。

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

2026-11-01 核实记录（源码/分发清单核实与运行验收分开记录）：

- **FRB：已接入 Flutter 应用，macOS 调试构建已运行。** crates.io 与 [pub.dev](https://pub.dev/packages/flutter_rust_bridge) 当前稳定版均为 `2.13.0`，Rust 依赖与生成器均固定该版本。其[零拷贝约定](https://github.com/fzyzcjy/flutter_rust_bridge/blob/v2.13.0/website/docs/guides/types/translatable/zero-copy.md)是原生平台异步/Stream 返回 `Vec<u8>` 等类型时自动使用 external typed data，不能泛化为所有调用模式零拷贝；`Bitmap` 这类结构体里的字节走 SSE 逐字节编码，macOS 调试构建实测 7.8MB 约 219ms、1MB 约 36ms。应用内由 FRB `integrate` 模板生成的 `rust_builder/`（cargokit）随 `flutter build` 编译 Rust；`flutter_rust_bridge.yaml` 把 Dart 绑定生成到 `lib/src/rust`，关闭内置 build_runner（它带 `--delete-conflicting-outputs`，资产图失效时会删除其他生成文件），codegen 后执行 `dart run build_runner build`，并用 `rustfmt --edition 2024` 格式化 `rust/src/frb_generated.rs`。联合类型使用 `freezed ^3.2.5`。`scripts/generate_rust_bridge.py` 仍用于仓库外独立工程的 FFI 往返检查。只允许运行时与本地 Zotero 快照作为 opaque 句柄，业务 DTO 必须生成具体类型，内部凭据字段不会生成访问器。macOS 插件需额外链接 `SystemConfiguration`；Android/Windows 构建尚未执行。
- **PDFium：macOS 应用内已加载，其他平台待实测。** `pdfium-render 0.9.4` 固定 `pdfium_7881` ABI；`rust/pdfium-binaries.json` 锁定 [pdfium-binaries](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F7881) 的四个发布目标与 Linux 测试宿主归档、SHA-256。应用通过 `rust_builder/hook/build.dart`（Dart native assets）按该清单下载、校验并以 `otter_pdfium` 名称打包。Dart 的 `bundledPdfiumLibrary()` 按平台给出路径注入 `BackendOptions.pdfiumLibrary`；macOS 沙盒应用内已打开真实 PDF，Windows/Linux 路径按 Flutter 打包布局推定、未实测。`scripts/fetch_pdfium.py` 用于 Rust 测试，保留 `LICENSE` 和完整 `licenses/`；应用内的许可展示尚未接入。真实旧 PDF 的 9 页、57 个正文段落均已对齐到实际字符。
- **FTS5：已实现并通过本机 SQLite 测试。** 采用 `rusqlite 0.41.1` 的 bundled SQLite 和 `jieba-rs 0.11.0`，通过 `rusqlite::ffi` 按 [SQLite FTS5 tokenizer API](https://www.sqlite.org/fts5.html#custom_tokenizers)逐连接注册 `otter_jieba`，不依赖动态加载扩展。索引包含完整词和同位置的搜索子词，查询按完整词分词后逐项引用并用 AND 连接；支持中文词、复合词子词、中英混合和大小写匹配，不接受用户输入的 FTS 运算符。已验证插入/更新/删除的索引同步、重开连接、UTF-8 高亮偏移和无效 UTF-8 写入回滚；已补全拼、首字母和有界多音字索引；索引修订号保存在 `meta`，旧索引在打开连接时重建。Android/Windows 运行验收留待统一安排。
- **公式性能：未验证。** `flutter_math_fork` 长文档帧耗时依赖 Flutter 阅读器实现，待真实长文档实测；没有用模拟数据的单元测试替代帧耗时实测。

## 当前后端实现范围

手写生产 Rust 文件按职责拆分，控制在 500 行以内；FRB 生成文件和配置数据保持工具/原始格式。

- `storage`：固定 Rust `1.99.1`，bundled SQLite、逐连接 FTS5 中文分词、WAL/FULL/外键。只打开 `<AppSupport>/OtterPad/v2/otter.db`，初始 schema 1、`application_id=OTP2`，拒绝外部、未来版本和非空无版本数据库。元数据、收藏、历史、笔记与设置已具备事务读写；文献检索合并 FTS 与全字段 LIKE，保留 DOI、年份及任意子串召回。
- `document`/`ocr`：PaddleOCR、MinerU 请求与取消、原始产物的不可变 generation 和最后发布的指针、稳定块 id/语义行内样式/表格、UTF-16 锚点、图表与题注归属。已对真实旧 PaddleOCR 的同一份 9 页 243 块数据运行 v0.1.7 Dart 与 Rust，对齐全部结构字段及 4 张图表的题注、块成员和源字符范围。此后有意偏离 v0.1.7 的配对规则：图与题注上下或左右排列时只把两者之间的块视为阻挡（通栏图配半栏题注不再被另一栏正文挡住，该数据的第 5 张图因此补齐；侧边题注下方接正文也不再算阻挡）；跨栏题注的右半段被 PaddleOCR 分组并进正文块时，按组内面积比例取回对应段落接到题注，正文块不再占用该区域的译文叠加位置；非题注标签块里匹配出的题注扣分，等距时让位于题注块。`rust/tests/figure_layouts.rs` 以明确预期覆盖这些版面。图表裁剪使用实际 PDF 像素验证，涵盖旋转页与跨页合成；MinerU v2 坐标由实际 PDF 页尺寸重建。OCR 大响应转换运行在阻塞线程池。补齐 Paddle v2 异步提交、轮询与 JSONL/Markdown 结果读取，批量入口最多并行处理 4 篇；单篇失败保留其余结果，成功发布后按提供商记录本地页数用量。
- `pdf`：Rust 持有 PDFium 文档、分块 RGBA 渲染、字节预算 LRU、旋转页字符几何、OCR 字符对齐、搜索/命中/选区矩形，以及显式溢出的译文布局。新增实际字体字节驱动的 Rustybuzz 整形、Unicode 双向文字/脚本分段和换行；输出最终行、基线、字形位置及 UTF-16 字符簇，缺字明确返回错误。Flutter 展示与字体接线不在本次范围。
- `library`：PDF 导入与去重、给已有元数据附加 PDF、可恢复删除、收藏/历史/标注，以及 DOI/PMID/arXiv/ISBN 的解析和元数据查询。补齐本地 PDF 与标识符导入编排、出版商页面/开放获取/PubMed→PMC 下载、重下载替换，以及文件名/PDF Info/XMP/中文首页/书籍版面元数据补全。导入恢复记录使用 `library/.import-*/journal.json` v1；PDF 替换记录使用 `.pdf-replace-<docId>.json` v1，替换保留笔记和会话，清除旧 PDF 的派生产物。
- `migrate`：只读旧 SQLite/复制旧资产，逐文档事务与迁移标记、取消续迁、稳定 hash 重映射译文、尽力定位旧笔记且保留未定位原始锚点。真实旧目录的副本已迁移两篇文献并验证取消续迁；该真实样本无笔记或翻译行，这些路径由实际旧 schema 的数据夹具覆盖。旧库与原始文件未修改。
- `ai`/`translate`：Responses、Anthropic、Gemini、OpenAI 兼容协议，多模态、思考参数、SSE、结构化输出降级、原生/外部搜索工具、URL 上下文、图片协议、模型列表与条件更新能力缓存；按语言保存全文译文；全文翻译按服务端点自适应并发（上限 20，跨文档共享），429 时减半并暂停（1s 起翻倍，封顶 30s），连续成功逐步恢复，无成功且累计减速 8 次后停止整批，取消或停止都保存已完成段落。实际本地 HTTP 测试覆盖协议往返、断流、重试、网络取消和 API Key 不跟随重定向；未调用付费模型。聊天文件保留旧会话锚点与活动，使用文件内容修订号拒绝过期覆盖。
- `sync`：WebDAV 集合与文件操作、S3 SigV4 与流式传输、完整/仅数据备份、覆盖/合并及按库/设置恢复、校验和与崩溃恢复标记。备份使用真实 SQLite 快照，删除误存凭据并清除页内残留，重建 FTS 的 rowid 关联；旧版 v3 ZIP 走同一迁移器。新增打包→上传→快照→保留最近 3 份版本备份的 Rust 编排；`last_backup_snapshot` 写入 v2 指纹格式，旧 Dart v1 指纹触发重新建立基线。自动备份 Stream 在启动 2 分钟后首查、随后每小时读取设置，按周期和文献变更判断是否上传。Zotero 云端按库版本增量导入；本地 API 检查实例与分页版本，保留用户编辑并复制所选 PDF。合并恢复会重映射云端与本地 Zotero 记录，跨账号不会混用云端游标。
- `runtime`/`credentials`/`logging`：逐数据根限制单个运行时，SQLite 与 PDFium 由专用工作线程持有，恢复/删除与长任务互斥；启动先处理恢复标记、删除操作的恢复记录和旧数据迁移，按原设置执行缓存清理。凭据由 `credentials.json` 载入并在修改时原子写回（损坏的文件改名为 `.invalid` 保留，以空凭据启动）；文件日志受设置控制，按日保留 7 天，只记录操作名与稳定错误码。`api` 为文献、笔记、PDF、文档/锚点、AI/翻译、会话、OCR、备份和 Zotero 提供独立强类型入口及可取消 Stream。
- `prompts`/`maintenance`/`update`：提示词默认值、覆盖、必需占位符校验和重置；存储用量分类、按组清理和缓存清理；GitHub release 解析、按设备 ABI 顺序选择 APK、忽略版本及下载进度；启动延迟检查读取自动更新偏好，忽略版本仅抑制自动提示。字体/设备信息读取、分享接收、安装 Intent、交互反馈留在宿主平台/UI 边界。
- 长 PDF：PaddleOCR 超过 1000 页、MinerU 超过 200 页时按页段提交，全部完成后按页序合并（`ocr/chunks.rs`）；Paddle 页序以列表为准，同名图片改名，任一页段失败不发布。
- 全文翻译以文档模型的块为单位，译文键为 `revision(block.markdown.trim())`，与迁移的 0.1.x 译文一致；`ReaderDocument.translation_keys` 与 `blocks` 一一对应，阅读器按键叠加译文（RTL 目标语言的译文块按 RTL 排版）。
- Flutter 只保留界面与宿主能力：文件选择、分享、APK 安装 Intent；PDF 视图与缩略图只负责显示 Rust 渲染的位图。
- 待后续：PDF 页面上的标注、题注译文与宽屏左右双语（0.1.x 有）；重新解析（不重新 OCR）入口；PDFium 许可文本接入许可页；公式性能实测；Android/Windows 应用构建与运行验收。
