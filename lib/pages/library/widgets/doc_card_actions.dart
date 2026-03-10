import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/documents_provider.dart';
import '../../reader/view.dart';

/// 文献卡片统一交互入口
///
/// 所有使用 [DocListCard] / [DocumentCard] 的页面（文献库、收藏夹、无文件条目等）
/// 都应通过此类获取回调，避免交互逻辑分散在各页面中导致不同步。
class DocCardActions {
  /// 点击卡片 → 打开 PDF 阅读器
  static void openReader(BuildContext context, Document doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderPage(document: doc)),
    );
  }

  /// 删除文献（从文库移除 + 删除磁盘文件）
  static void delete(WidgetRef ref, String docId) {
    ref.read(documentsProvider.notifier).delete(docId);
  }
}
