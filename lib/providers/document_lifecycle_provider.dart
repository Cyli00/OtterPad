import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/book/document.dart';
import 'documents_provider.dart';
import 'favorites_provider.dart';
import 'history_provider.dart';

/// 文献生命周期入口：页面和任务编排通过这里表达文献写操作。
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
    void Function()? onFetchingPdf,
  }) {
    return _documents.addByIdentifier(
      identifier,
      cancelToken: cancelToken,
      onFetchingPdf: onFetchingPdf,
    );
  }

  Future<RebuildResult> rebuildLibrary({
    void Function(RebuildProgress)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _documents.rebuild(onProgress: onProgress, cancelToken: cancelToken);
  }

  Future<void> attachPdf(String documentId, String sourcePath) {
    return _documents.attachFile(documentId, sourcePath);
  }

  Future<bool> attachMissingPdf(
    String documentId,
    String sourcePath, {
    CancelToken? cancelToken,
  }) => _documents.attachMissingFile(
    documentId,
    sourcePath,
    cancelToken: cancelToken,
  );

  Future<bool> redownloadPdf(String documentId, {CancelToken? cancelToken}) {
    return _documents.redownloadPdf(documentId, cancelToken: cancelToken);
  }

  /// Rust 删除文献时级联清除笔记、历史、收藏关联与 Zotero 映射。
  Future<void> deleteDocument(String documentId) =>
      _documents.delete(documentId);

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
