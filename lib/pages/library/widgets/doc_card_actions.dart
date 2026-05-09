import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/storage.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/favorites_provider.dart';
import '../../../providers/history_provider.dart';
import '../../../router/app_routes.dart';

/// 文献卡片统一交互入口
///
/// 所有使用 [DocListCard] / [DocumentCard] 的页面（文献库、收藏夹、无文件条目等）
/// 都应通过此类获取回调，避免交互逻辑分散在各页面中导致不同步。
class DocCardActions {
  /// 点击卡片 → 记录阅读历史并打开 PDF 阅读器
  static void openReader(BuildContext context, WidgetRef ref, Document doc) {
    ref.read(historyProvider.notifier).record(doc.id);
    context.push(AppRoutes.reader, extra: doc);
  }

  /// 删除文献（级联：文库条目 + 磁盘文件 + 提取产物 + 缩略图 + 收藏夹 + 高亮 + 历史）
  static Future<void> delete(WidgetRef ref, String docId) async {
    final docs = ref.read(documentsProvider);
    final doc = docs.cast<Document?>().firstWhere(
      (d) => d != null && d.id == docId,
      orElse: () => null,
    );
    if (doc != null && doc.filePath.isNotEmpty) {
      await ref.read(favoritesProvider.notifier).removeDocFromAll(doc.filePath);
      GStorage.highlights.delete(doc.filePath);
    }
    ref.read(historyProvider.notifier).removeDoc(docId);
    await ref.read(documentsProvider.notifier).delete(docId);
  }
}
