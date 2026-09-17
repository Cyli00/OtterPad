# 设置与 API 模块

AI 与 OCR 配置分别由 `providers/agent_api_provider.dart` 和 `providers/doc_extract_api_provider.dart` 管理。原 `api_provider.dart` 的调用点已迁移，不再保留混合入口。拆分沿用原有设置键、凭据槽、服务商 ID、模型参数序列化和枚举顺序。

| 文件 | 职责 |
| --- | --- |
| `data/models/ai/agent_protocol.dart` | AI 协议、默认端点与 URL 规则 |
| `data/models/ai/agent_config.dart` | 服务商实例、模型参数与解析后的配置数据 |
| `data/models/ai/agent_model_capability.dart` | 模型能力数据、序列化与无缓存的推断规则 |
| `data/models/ocr/doc_extract_config.dart` | OCR 提供商、解析选项与配置数据 |
| `services/model_capability_store.dart` | 远程能力缓存，以及 `AgentProviderCapabilities` 扩展的能力查询 |

纯数据模块不依赖 Riverpod、存储或服务。需要加载配置或修改设置的调用点依赖对应 provider；只消费配置的请求构造、结果转换等服务直接依赖数据模块。能力查询沿用“用户手动设置 → 远程能力表 → 默认推断”的顺序，调用 `capabilityFor` 时显式导入能力缓存服务。

## 文案与设置控件

提供商配置按槽独立保存 API Key / Token，切换提供商时不清空其他提供商的输入。用量仅在没有远程配额查询接口时采用本地记账估算，界面需明确标识估算及配额性质；这些行为约束由本模块维护，不放入 UI 设计 skill。

备份恢复枚举只保留业务语义，界面通过 `context.l10n` 取得名称与说明。阅读器主题、字体、翻页方式和译文样式的展示映射放在 `l10n/reader_labels.dart`。历史分组保存日期类别及月份，月份由 ARB 的 `DateTime` 格式按当前语言显示；切换语言不需要重建历史数据。文库重建进度按项目约定从根导航上下文取得本地化文案。

`core/app_theme.dart` 统一生成明暗主题，并提供滑块的尺寸配置。阅读器局部主题显式使用同一份滑块配置，其配色仍来自阅读器自己的 `ColorScheme`。

`widgets/setting_controls.dart` 提供帮助图标、设置标题、重置按钮与设置滑块。滑块以 `null` 表示默认状态，始终显示实际数值；OCR 的默认值在调用处转换为此状态。已在分组内留边距的调用点使用零内边距。桌面阅读器滑块仍保留本地拖动状态和松手提交，只共享主题，不改变保存频率。

## PDF 字符循环

`reader_layout_geometry.dart` 与 `reader_pdf_typesetting.dart` 在模块内复用正则。字符对齐使用的区域扩边矩形在循环前计算一次。空白匹配、UTF-16 偏移、连字处理、公式识别及对齐阈值保持原语义。

验证以 `flutter analyze --no-pub` 和已有模型能力、OCR 设置、用量、服务商预设、PDF 排版回归为主。桌面交互手感与实际帧率仍需运行应用验收。

## 图表归属与本地解析蒙版

PaddleOCR 的候选聚类、题注配对和正文替换以 `v0.1.4`（`4c8fb7b`）为演进起点；MinerU 适配以审查计划锁定的 `cde4696` 为起点，集成到 `dev`。不回退整个应用，也不覆盖当前请求、发布和来源选择接口。

| 模块 | 内部依赖与职责 |
| --- | --- |
| `document_structure.dart` | 保留原始来源字段、页尺寸与文字物理页；MinerU layout/V2 的嵌套题注、列表文本及 discarded_blocks 参与召回，不推造跨页文字坐标 |
| `figure_extract_service.dart` | caption-first：所有文本标签（含页眉页脚）参与召回；连续脚注行框允许向下推进的交叠及左对齐短行；跨页提示参与整页图与下一页题注配对，但仍保留正文阻断和双向唯一约束；题注来源锚点确定身份，无题注视觉不建立阅读实体 |
| `figure_markdown.dart` | 按源块、完整资源路径和底稿字符范围替换；JSON 有确认题注但 Markdown 遗漏时，以源块阅读顺序和可见邻居补入题注实体，已有续文只消费一次；展示阶段过滤普通页眉／页脚／页码，不过滤已确认题注、续行或普通脚注；代码块受保护，已绑定题注但裁片缺失时保留源资源 |
| `doc_extract_service.dart`、`mineru_result_converter.dart` | 分别适配两路原资源，调用共享归属与替换；页坐标不可验证时回退已本地化源图 |
| `extraction_artifacts.dart` | 持久化发布、双来源快照和资源保留；清理代际图片时保留原图、组合图及每页分片 |
| `table_parse_service.dart` | 只读当前 `extract.json`，通过 `DocumentStructure` 和清单的页号／块 ID／来源版本匹配已有表格与图表内容；不依赖模型配置、网络或旧 LLM 缓存 |
| `table_parse_result.dart` | 转换 OCR 已有 HTML／Markdown 表格，保留字符串、合并跨度；拒绝越界和重叠单元格，生成 TSV、Markdown 与安全转义 HTML，不猜补数值 |
| `table_parse_sheet.dart` | `FigureDataOverlay` 在查看器原图区显示本地解析层，复用 `SelectionArea`、`HtmlWidget` 和双向滚动，不另开解析弹窗 |
| `figure_viewer.dart` | 可见复制／导出菜单、原图与蒙版切换、蒙版透明度、缩放复位、键盘翻页和题注收放；复用剪贴板、文件选择器、分享与主题组件 |

清单 `algorithm_version: 4` 保留 `visual_regions`、`source_refs`、`replacement_refs`、`source_version`、`assignment`、`notes`，`caption_refs` 增加可选 `start/end` 原块字符范围；旧单页字段继续可读。未知变换不沿用固定 DPI 猜测，只回退有明确原生题注归属的源图。WebView 用 `figure_title` 类与 `data-caption-id` 绑定题注；阅读索引同步拆分混合正文，不为子范围伪造 PDF 坐标。

题注词库由 `assets/config/caption_patterns.json` 维护，加载器动态读取语言节点的 `figure/table/other`，不再维护固定语言白名单。`number_pattern` 覆盖层级、附录、罗马数字、子图编号及常见本地数字；`supplementary_number_pattern` 标识 `Figure S12` 类编号。`number_first` 处理 PLOS 的 `S12 Fig.` / `S12 Table` 和匈牙利语的 `12. ábra` / `12. táblázat`。`supplementary.standalone` 按类别组织，修饰词也可与表格前缀组合；补充材料表格不会被统一归成 figure。词库扩展只增加召回候选，不改变空间归属与裁剪规则；不能仅靠前缀正则断言它一定不是正文引用。

词汇与格式依据：[Polyglossia 各语言题注定义](https://github.com/reutenauer/polyglossia/tree/master/tex)、[PLOS 补充材料规范](https://journals.plos.org/plosone/s/supporting-information)、[JAMA 作者规范](https://jamanetwork.com/journals/jama/pages/instructions-for-authors)、[IEEE 作者格式示例](https://ewh.ieee.org/conf/ests05/Author-Instructions.pdf)、[Nature 已发表论文中的 Extended Data 和 Supplementary 标题](https://www.nature.com/articles/s41586-020-2249-1)。配置回归入口为 `test/services/caption_patterns_test.dart`，涵盖各语言加载、类别、补充材料、完整编号及正文误召回反例。

查看器不再调用 LLM 转录表格，也不读取或写入 `table_parses/`；用户已有缓存不删除。每次打开查看器读取当前提取 JSON，清单来源版本不符时拒绝展示解析数据，缺失或损坏时保留原图及其导出。跨页分片按清单顺序保留、按页号和块 ID 去重，不合并猜测续页表头。蒙版为可选择、可滚动的结构化内容对照层，不声称 HTML 单元格与原图像素精确对齐；JSON 缺少单元格坐标时不伪造坐标。表格及图表原始文本可以复制 Markdown，结构化表格可复制 TSV；HTML 导出保留合并格，TSV／Markdown 展平跨度。原图复制在剪贴板插件支持的平台提供；移动端使用原生分享导出数据。题注翻译和主动 AI 问答保持独立，不参与本地解析。

回归入口：`test/services/caption_first_test.dart`、`figure_unified_test.dart`、`figure_source_contract_test.dart`、`mineru_result_converter_test.dart`、`reader_document_index_test.dart`；指定文档回放用 `caption_first_fixture_test.dart`（环境变量 `CAPTION_FIRST_FIXTURE` 指向文献目录，只在临时副本裁图）。表格交互另有 `table_parse_contract_test.dart`、`test/pages/reader/table_parse_sheet_test.dart`、`figure_gallery_test.dart`。仓库忽略 `test/`，运行显式路径无需修改 `.gitignore`。
