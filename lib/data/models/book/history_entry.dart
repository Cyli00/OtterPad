/// 单次阅读事件：记录文档 id、打开时间、阅读进度。
///
/// 阅读历史作为独立事件流存储，而非 Document 模型的衍生字段——
/// 这样后续要加阅读时长/进度/次数等维度时不必改动 Document。
///
/// `progress` 含义：0.0 = 未读/未滚动；1.0 = 读到底。PDF 模式用
/// `currentPage / totalPages`，Markdown 模式用 `scrollTop / (scrollHeight - viewHeight)`。
///
/// `anchorBlock` 是 Markdown 阅读位置的内容块锚点（`#content` 顶层块索引）：
/// 比率在布局参数（字号/窗口尺寸）变化后会落错页，横向翻页恢复时优先用它。
/// null = PDF 进度或未设置。
class HistoryEntry {
  final String docId;
  final DateTime openedAt;
  final double progress;
  final int? anchorBlock;

  const HistoryEntry({
    required this.docId,
    required this.openedAt,
    this.progress = 0.0,
    this.anchorBlock,
  });
}