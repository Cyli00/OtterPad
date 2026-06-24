## Todolist

- 删除 raw.md 保存（测试用）
- 段落内 figure 引用检出与点击高亮
- 基于元数据的文献推荐算法（Jaccard → Major Topic → 非 PubMed 兜底 → MeSH Tree+IDF）
- 依赖大版本升级（需同时进行，win32 6.x 绑定）：
  - file_picker ^8→^11：`FilePicker.platform.X()` → `FilePicker.X()` 静态调用（5 个文件）
  - share_plus ^10→^13：`Share` → `SharePlus` 类重命名（3 个文件）
  - package_info_plus ^9→^10：无 API 变更，随 share_plus 一起升（win32 ^6 依赖）