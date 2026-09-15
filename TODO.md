## Todolist

- 删除 raw.md 保存（测试用）
- 基于元数据的文献推荐算法（Jaccard → Major Topic → 非 PubMed 兜底 → MeSH Tree+IDF）
- 依赖大版本升级（需同时进行，win32 6.x 绑定）：
  - file_picker ^8→^11：`FilePicker.platform.X()` → `FilePicker.X()` 静态调用（5 个文件）
  - share_plus ^10→^13：`Share` → `SharePlus` 类重命名（3 个文件）
  - package_info_plus ^9→^10：无 API 变更，随 share_plus 一起升（win32 ^6 依赖）
- 引入PP-OCRv6移动端模型做一些精细处理，减少对api请求的过度依赖
- MinerU Pipeline 与 VLM（尤其 2.5）结构化输出不完全兼容：VLM 的 `model.json`、`middle.json` 字段和坐标语义有变化；`span.pdf` 仅适用于 Pipeline。当前实现仍有部分 Pipeline 分支，后续若重新开放需单独做格式适配和真实样本回归。
- 当前阶段只支持 MinerU VLM：模型设置项、状态字段与存储键已删除，请求固定发送 `model_version=vlm`；历史 Pipeline 结果解析保留只读兼容，待完成独立适配和真实样本回归后再恢复。
- 示例文档结构化结果里有 `table: 4`、`chart: 48`、`image: 41`，但 `figures.mineru.json` 只有 6 条且 `kind` 全为 `figure`，没有任何 table/chart 条目；MinerU 的 `extra_formats: html` 导出里表格是真 `<table>`。可用于把表格从截图改为可选中 HTML 表格，待单独评估（需先确认 HTML 与 app block 的对齐方式）。
