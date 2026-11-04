# 更新记录

每个版本用 `<!-- release:en -->` 与 `<!-- release:zh -->` 分成英文、中文两段。`scripts/prepare_release.sh` 会把英文安装包放在这两段之前。

## [0.1.8]

<!-- release:en -->

### Added

- Added Persian (فارسی) as a translation target.
- Reader and PDF translations use a right-to-left layout for Persian and Arabic.

### Fixed

- Formulas, code, and tables stay left to right inside right-to-left translations, so math, code, and table columns are not reordered (Fixes #3).

<!-- release:zh -->

### 新增

- 翻译目标语言新增波斯语（فارسی）。
- 阅读器与 PDF 译文对波斯语和阿拉伯语使用从右向左排版。

### 修复

- 从右向左的译文里，公式、代码和表格保持从左向右，数学符号、代码片段和表格列不会被重排（Fixes #3）。

## [0.1.7]

<!-- release:en -->

### Improved

- Improved motion and transitions for navigation, onboarding, and the reader, and added support for the reduce-motion setting.
- Unified the settings page layout and field styling, and moved the web search settings.
- Improved task progress and result notifications, reader controls, and figure display.
- Updated the macOS app icon and improved the CocoaPods build setup.

### Fixed

- Fixed PDF translation readability, and fonts not following the display settings.
- Improved Claude model thinking parameters, streaming output length, and refusal handling.

### Other

- Removed paper export and AI figure repair.

<!-- release:zh -->

### 优化

- 优化导航、引导和阅读器的动效与过渡，并支持减少动态效果设置。
- 统一设置页面布局和输入框样式，调整网络搜索设置的位置。
- 改进任务进度与结果提示、阅读器控件及图表展示。
- 更新 macOS 应用图标并改进 CocoaPods 构建配置。

### 修复

- 修复 PDF 译文可读性及字体跟随设置的问题。
- 改进 Claude 模型的思考参数、流式输出长度和拒绝回复处理。

### 其他

- 移除文献导出和 AI 图表修复功能。

## [0.1.6]

<!-- release:en -->

### Added

- The figure gallery can use tables from parse results, and figures can be exported or copied.
- Desktop builds can discover system fonts, and display settings can choose the app font.
- The website adds Chinese and English landing pages and a usage guide.

### Improved

- Improved how figures relate to full captions, including cropping and the reader layout.
- Improved the reader dock, WebView lifecycle, and expand interactions so switching flickers less.
- Improved the caption-translation preview and navigation hints so explanations are not repeated.

### Fixed

- Fixed interrupted reader tab sessions, translation refresh, and model request URL normalization.
- Removed the bilingual highlight overlay so PDF and WebView mappings no longer disagree.

<!-- release:zh -->

### 新增

- 图册支持使用解析结果中的表格数据，并提供图表导出与复制操作。
- 桌面端支持发现系统字体，显示设置可选择应用字体。
- 网站补充中英文落地页与使用指南。

### 优化

- 改进图表与完整图注的关联、裁剪和阅读器展示布局。
- 优化阅读器停靠栏、WebView 生命周期及展开交互，减少切换时闪烁。
- 优化图注翻译预览和导航栏提示，避免重复说明。

### 修复

- 修复中断的阅读器页签会话、翻译内容刷新及模型请求地址规范化问题。
- 移除双语高亮蒙版，避免 PDF 与 WebView 映射不一致。

## [0.1.5]

<!-- release:en -->

### Added

- The reader supports original, translated, and bilingual PDF reading, plus full-text translation that updates paragraph by paragraph.
- Added MinerU document parsing. It shares structured text and figure extraction results with PaddleOCR.
- Desktop builds can import papers and local PDFs from the Zotero client.
- Added export of Markdown notes, and of BibTeX and RIS citations.

### Improved

- Improved wide-screen navigation, the reader sidebar, window sizing, and desktop interaction.
- Body text and the figure gallery share a caption-translation cache, and existing translations are restored after re-parsing.
- Improved DOI, arXiv, and PubMed metadata parsing and PDF retrieval.
- Backup restore adds integrity checks and rollback after an interruption. A failed import or delete keeps the existing data.
- AI and OCR settings are managed separately, proxy configuration is unified, and the Chinese and English interface copy is filled in.

### Fixed

- Fixed upgrading old libraries, search-index consistency, and background task conflicts during restore.
- Fixed parsing and translation continuing to process results after cancellation.
- Android self-update selects an APK for the ABIs the device supports, so 32-bit devices do not download the arm64 package.

### Upgrade notes

This release ships Android ARM64 and ARMv7 packages, and desktop packages for the first time: a Windows x64 installer and a portable build, plus a macOS (Apple silicon) DMG.

The macOS package is not code-signed or notarized. On first launch, allow it in System Settings → Privacy & Security. A Linux desktop build is not included.

On first launch the database upgrades from schema 1 to 2. Keep a full backup of the previous version before installing over it. The upgraded database is not meant for rolling back to the old version.

<!-- release:zh -->

### 新增

- 阅读器支持原文、译文与双语 PDF 阅读，以及逐段更新的全文翻译。
- 支持 MinerU 文档解析，与 PaddleOCR 共用结构化正文和图表提取结果。
- 支持在桌面端从 Zotero 客户端导入文献与本地 PDF。
- 支持导出 Markdown 笔记和 BibTeX、RIS 引用。

### 优化

- 改进宽屏导航、阅读器侧栏、窗口尺寸与桌面交互。
- 正文和图册共用图注翻译缓存，重新解析后恢复已有译文。
- 改进 DOI、arXiv 和 PubMed 的元数据解析与 PDF 获取。
- 备份恢复增加完整性检查和中断回退，导入、删除失败时保留原有资料。
- AI 与 OCR 设置分开管理，统一代理配置并补充中英文界面文案。

### 修复

- 修复旧库升级、搜索索引一致性及恢复期间后台任务冲突等问题。
- 修复解析与翻译取消后仍继续处理结果的问题。
- Android 自更新按设备支持的架构选择 APK，避免 32 位设备下载 arm64 安装包。

### 升级说明

本次提供 Android ARM64 和 ARMv7 安装包，并首次提供桌面端安装包：Windows x64 安装器与免安装便携版，以及 macOS（Apple 芯片）DMG。

macOS 安装包暂未做代码签名与公证，首次打开需在「系统设置 → 隐私与安全性」中放行。Linux 桌面端本版未提供。

数据库首次启动时从 schema 1 升级到 2。建议覆盖安装前保留旧版完整备份；升级后的数据库不用于旧版回退。
