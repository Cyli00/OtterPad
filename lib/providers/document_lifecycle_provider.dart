import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/book/document.dart';
import 'documents_provider.dart';
import 'favorites_provider.dart';
import 'history_provider.dart';

/// 文献生命周期入口：页面和任务编排通过这里表达文献写操作。
///
/// `DocumentsNotifier` 只作为文献列表持久化 Adapter 使用；收藏夹、历史、
/// 高亮和磁盘目录等级联规则集中在这里。
class DocumentLifecycleNotifier {
  DocumentLifecycleNotifier(this._ref);

  final Ref _ref;

  DocumentsNotifier get _documents => _ref.read(documentsProvider.notifier);

  Future<AddFileResult> importPdf(
    String sourcePath, {
    CancelToken? cancelToken,
  }) {
    return _documents.addFile(sourcePath, cancelToken: cancelToken);
  }

  Future<(Document, AddByIdentifierResult)> createByIdentifier(
    String identifier, {
    CancelToken? cancelToken,
  }) {
    return _documents.addByIdentifier(identifier, cancelToken: cancelToken);
  }

  Future<RebuildResult> rebuildLibrary({
    void Function(RebuildProgress)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _documents.rebuild(onProgress: onProgress, cancelToken: cancelToken);
  }

  /// 批量导入已带元数据的文献（Zotero 同步入口）。
  Future<List<Document>> importDocuments(List<Document> documents) {
    return _documents.importDocuments(documents);
  }

  Future<void> attachPdf(String documentId, String sourcePath) {
    return _documents.attachFile(documentId, sourcePath);
  }

  Future<bool> redownloadPdf(String documentId, {CancelToken? cancelToken}) {
    return _documents.redownloadPdf(documentId, cancelToken: cancelToken);
  }

  Future<void> deleteDocument(String documentId) async {
    // SQL delete 触发 FK CASCADE（清 highlights/history/favorite_documents/
    // zotero_items 的 DB 行）+ FTS5 触发器清 documents_fts + FS 清理 +
    // watch() 流自动刷新各数据 provider；ZoteroSnapshot 经其流自动同步。
    // 故删除编排塌缩为这一句（ADR-0001 / ADR-0003）。
    await _documents.delete(documentId);
  }

  void recordOpen(String documentId) {
    _ref.read(historyProvider.notifier).record(documentId);
  }

  Future<void> addToFavorite(String favoriteId, String documentId) {
    return _ref
        .read(favoritesProvider.notifier)
        .addDocument(favoriteId, documentId);
  }

  /// 批量加入收藏夹——返回真正新增的篇数（已在里面的自动跳过）。
  Future<int> addToFavoriteBatch(
    String favoriteId,
    Iterable<String> documentIds,
  ) {
    return _ref
        .read(favoritesProvider.notifier)
        .addDocuments(favoriteId, documentIds);
  }

  Future<void> removeFromFavorite(String favoriteId, String documentId) {
    return _ref
        .read(favoritesProvider.notifier)
        .removeDocument(favoriteId, documentId);
  }
}

final documentLifecycleProvider = Provider<DocumentLifecycleNotifier>((ref) {
  return DocumentLifecycleNotifier(ref);
});
