# Extract service 分析

当前实现已经把 MinerU 与 PaddleOCR 的图块归属、子图合并和 PDF 裁剪统一到 `FigureExtractService`。重新提取会自动生成阅读版 Markdown 并刷新已打开的阅读器；漏图风险主要来自题注召回不足、归属有歧义后的过滤，以及这些结果没有充分暴露给调用方。

[打开交互架构图](extract-service.html) · [图源 JSON](extract-service.architecture.json) · [交付回执](extract-service.handoff.json)

范围：2026-09-13 当前工作区代码，包括未提交内容。本图表达结果流转，方法之间的返回与再次调用合并为一条主路径；文件发布到阅读器的箭头包含任务完成通知，`ExtractionArtifacts` 本身不直接调用阅读器。没有把图绑定到 HEAD：Archify 的提交证据验证读取提交中的文件，会遗漏当前工作区改动。下面是实际检查过的本地代码依据。本次只新增分析产物，没有修改业务代码，没有调用远端 OCR 或操作个人文献库。

## 1. 实际调用链

| 阶段 | 当前实现 | 代码依据 |
|---|---|---|
| 任务入口 | 阅读器选择提供商，`DocumentTaskNotifier.extractDocument` 排队、报告进度并选择分支 | [document_task_provider.dart:154](../../lib/providers/document_task_provider.dart#L154) |
| Paddle 请求 | 阅读器的单文献提取实际走 `BatchExtractService.extractSingle`，不是直接走 `DocExtractService.extract` 的同步接口 | [document_task_provider.dart:1012](../../lib/providers/document_task_provider.dart#L1012) |
| MinerU 请求 | 申请上传地址、上传、轮询、下载 ZIP；转换与保存交给 converter | [mineru_extract_service.dart:275](../../lib/services/mineru_extract_service.dart#L275) |
| MinerU 适配 | 优先采用 layout/middle 结构，否则采用 v2；保留父块关系、来源图片及顺序；再读取 PDF 文本补回题注 | [mineru_result_converter.dart:60](../../lib/services/mineru_result_converter.dart#L60) |
| 统一结构 | `DocumentStructure` 统一页面、块、关系与 144 DPI 坐标；v2 按页面宽高分别换算，没有题注坐标时不编造 bbox | [document_structure.dart:354](../../lib/services/document_structure.dart#L354) |
| 归属与裁剪 | 两条路径均进入 `extractStructureFigures`；生成包含图、caption 来源和块引用的 manifest | [figure_extract_service.dart:3149](../../lib/services/figure_extract_service.dart#L3149) |
| 阅读版生成 | Paddle 走 `replaceFigureRegions` 与清理管线；MinerU 走 `buildReaderMarkdown`，按来源图片、题注引用重建 | [doc_extract_service.dart:182](../../lib/services/doc_extract_service.dart#L182)、[mineru_result_converter.dart:418](../../lib/services/mineru_result_converter.dart#L418) |
| 产物发布 | 写入当前正文／JSON／图清单，同时保存提供商各自底稿；图片使用独立 generation 目录 | [extraction_artifacts.dart:53](../../lib/services/extraction_artifacts.dart#L53) |
| 阅读器更新 | 监听 completed，重读 Markdown，递增 `contentRevision`，更新缓存和文档索引，清除旧图清单缓存 | [reader_session_provider.dart:229](../../lib/providers/reader_session_provider.dart#L229)、[view.dart:1624](../../lib/pages/reader/view.dart#L1624) |

## 2. 子图聚类与 caption 定位如何完成

归属并非单纯寻找最近的一行文字。`_pair` 优先考虑原生 `parentId`，其次是 `groupId`，再结合距离、栏位、图表类别和正文阻挡。相同优先级下有近似合理的多个 caption 时放弃猜配。从已确认的归属出发继续合并相邻子图，但检查合并区域是否跨过正文或侵入另一张图。

跨页匹配先形成视觉簇，再检查相邻页候选与跨页边界。内部子图字母、短文字和图内注释会根据空间位置及原生关系加入。主 caption 及延续文字的来源引用用于 Markdown 替换，区别于参与实际裁图的视觉区域。[归属实现](../../lib/services/figure_extract_service.dart#L1330)、[跨页实现](../../lib/services/figure_extract_service.dart#L1638)

MinerU 的 PDF 题注补回发生在归属之前。它读取统一结构中已有页面的 PDF 文本层，在本页或相邻页有视觉块时进行恢复，得到文字和字符矩形再构建题注定位。它不是新增一轮图片 OCR；没有可用文本层，或结构结果完全遗漏了相应页面时，这条恢复路径有明确限制。[pdf_caption_recovery.dart:11](../../lib/services/pdf_caption_recovery.dart#L11)

## 3. 重提与重新排版的区别

| 操作 | 远端请求 | 本地结果 | 阅读器行为 |
|---|---|---|---|
| 重新提取 | 重新上传并运行所选 OCR | 重新适配、归属、裁图、生成 Markdown、发布产物 | 成功事件后自动刷新，并进入 Markdown 预览 |
| 重新排版 | 不调用 OCR | 选择已保存来源，重跑本地处理；有多个来源时需明确选择 | 调用 `useExtractedMarkdown` 发布新内容版本 |
| AI 修缮 figure | 单独的模型请求 | 审计图块归属，再裁图与重建正文 | 独立操作；当前阅读器会阻止对 MinerU 结果执行 |

[本地重排分派](../../lib/services/doc_extract_service.dart#L261)、[重排后更新](../../lib/pages/reader/view.dart#L440)、[MinerU 的 AI 修缮限制](../../lib/pages/reader/view.dart#L483)

这里的自动排版指提取结果的阅读版 Markdown。它不等于重新翻译全文，也不等于把译文写回一个新的 PDF 文件。此次未审计 PDF 译文覆盖层的字体选择。

旧版 MinerU JSON 如果没有 `_mineru_assets`，重排只用已有清单重建 Markdown，不会凭不可靠几何重新裁图。要获得完整新版几何处理，需要重新提取一次。[兼容分支](../../lib/services/mineru_result_converter.dart#L219)

## 4. 最值得处理的边界

1. **未归属图块的诊断没有沿完整管线保留下来。** `_pair` 记录 `reason: unresolved`，`extractStructureFigures` 返回 diagnostics；MinerU 的 `_extract` 只取 `.entries`，两条发布路径也没有把这些 diagnostics 传入最终清单。用户看到的可能只是图少了，无法判断是 caption 缺失、配对冲突还是后续 Markdown 锚点过滤。建议优先保留逐页、逐块的未归属原因，并区分“提取完成”和“存在待确认图块”。[结果诊断](../../lib/services/figure_extract_service.dart#L3249)、[MinerU 调用方](../../lib/services/mineru_result_converter.dart#L338)

2. **没有可用 caption 的图不会成为可见 figure。** 这能避免装饰图污染，但对无题注插图或 OCR 丢题注的扫描 PDF 会损失召回。不能把“远端任务 done”解释为“所有图完整”。当前测试明确验证所有 profile 都丢弃无题注图片；需要把它作为产品策略审视，而非仅靠调阈值处理。[显示过滤](../../lib/services/figure_extract_service.dart#L175)、[对应测试](../../test/services/figure_unified_test.dart#L218)

3. **取消传播在本地处理阶段不一致。** MinerU 在开始转换与发布前检查 token，但题注恢复、共享归属裁剪阶段未贯穿 token；Paddle 在保存前检查取消，`saveResult` 本身不接收取消 token。因而网络取消测试通过，并不能证明本地裁图过程中能立刻停下或一定阻止发布。这是调用链可见的边界，本轮未做该时机的专项复现。

4. **文件发布有异常回滚，但不是多文件原子事务。** 实现先暂存、再逐文件 rename，遇到捕获到的 IO 异常进行回滚；新图片分代能保护旧阅读器引用。进程在多次 rename 之间退出，或者发布期间另一个读取方直接读文件，仍可能遇到中间状态。不要把它描述成具备进程崩溃恢复保证的事务。[publishExtractionArtifacts](../../lib/services/extraction_artifacts.dart#L194)

建议下一步只处理第一项：让现有 `FigureExtractDiagnostics` 随提取产物持久化，并记录 caption 召回、归属和 Markdown 过滤各阶段的差异。这样下一次出现“Figure 5 消失”时，可以直接定位丢失阶段，再针对实际原因修复。

## 5. 本轮验证

执行现有本地测试，**32 passed**：

```bash
flutter test test/services/figure_unified_test.dart test/services/mineru_result_converter_test.dart test/providers/reader_extraction_refresh_test.dart test/services/mineru_polling_test.dart --reporter expanded
```

覆盖跨页完整视觉簇、下一页底部 caption、正文阻挡、两种 provider 的统一几何、PDF 题注补回、双来源保存与切换、旧版兼容、重排、阅读器刷新，以及模拟网络轮询和取消。没有重新调用 MinerU／PaddleOCR 服务，也没有重跑个人六张图文献；这些测试证明上述固定样例，不能代表任意论文上的提取准确率。

图交付：showcase 9/9，0 errors，0 warnings；Chrome 在 1440×900、1600×1000、1920×1080、2048×1320 均无页面溢出。已检查最小和最大尺寸的浅色／深色四张截图，连线没有穿越其他节点，文字未裁切。浏览器自动证据与截图视觉复核分开记录；未手动逐项测试交互菜单和导出操作。
