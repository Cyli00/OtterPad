import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_logger.dart';
import '../core/l10n.dart';
import '../core/rust_backend.dart';
import '../core/rust_models.dart';
import '../data/models/book/document.dart';
import '../router/app_router.dart' show rootNavigatorKey;
import '../services/pdf_thumbnail_service.dart';
import '../src/rust/api.dart';
import '../src/rust/api/acquisition.dart';
import '../src/rust/api/metadata.dart' as rust;
import '../src/rust/error.dart';
import '../utils/doc_paths.dart';

enum AddByIdentifierResult { success, duplicate }

enum MetadataStatus { none, partial, complete }

enum AddFileResultType { imported, duplicate }

class AddFileResult {
  final AddFileResultType type;
  final Document? document;
  final MetadataStatus metadataStatus;

  const AddFileResult({
    required this.type,
    this.document,
    this.metadataStatus = MetadataStatus.none,
  });
}

class RebuildResult {
  final int addedCount;
  final int removedCount;
  final int repairedCount;
  final int unresolvedCount;
  final int noFileCount;
  final bool cancelled;

  const RebuildResult({
    required this.addedCount,
    required this.removedCount,
    required this.repairedCount,
    required this.unresolvedCount,
    required this.noFileCount,
    required this.cancelled,
  });
}

class RebuildProgress {
  final int? current;
  final int? total;
  final String fileName;
  final String status;

  const RebuildProgress({
    this.current,
    this.total,
    required this.fileName,
    required this.status,
  });
}

/// 文献库列表，按 `addedAt` 升序。数据在 Rust，写入后 [bumpLibrary] 刷新。
class DocumentsNotifier extends AsyncNotifier<List<Document>> {
  Backend get _rust => RustBackend.instance;

  @override
  Future<List<Document>> build() async {
    ref.watch(libraryEpochProvider);
    final rows = await _rust.documents(limit: kAllRows, offset: 0);
    return [for (final d in rows.reversed) documentFromRust(d)];
  }

  void reload() => bumpLibrary(ref);

  /// 导入本地 PDF：先以文件名与 PDF 信息入库（卡片立即出现），联网补全
  /// 元数据在后台进行。
  Future<AddFileResult> addFile(
    String sourcePath, {
    CancelToken? cancelToken,
  }) async {
    if (!await File(sourcePath).exists()) {
      return const AddFileResult(type: AddFileResultType.duplicate);
    }
    final report = await _acquire(
      _rust.importLocalPdf(
        source: sourcePath,
        allowNetwork: false,
        taskId: rustTaskId('import', cancelToken),
      ),
    );
    bumpLibrary(ref);
    final doc = documentFromRust(report.document);
    if (!report.changed) {
      return AddFileResult(type: AddFileResultType.duplicate, document: doc);
    }
    unawaited(
      PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(doc.id)),
    );
    unawaited(
      _repair(doc.id, cancelToken: cancelToken).catchError((Object e) {
        if (!isCancellation(e)) {
          log.w('[Documents] 后台元数据补全失败：${doc.id}', error: e);
        }
        return MetadataStatus.none;
      }),
    );
    return AddFileResult(type: AddFileResultType.imported, document: doc);
  }

  Future<(Document, AddByIdentifierResult)> addByIdentifier(
    String identifier, {
    CancelToken? cancelToken,
    void Function()? onFetchingPdf,
  }) async {
    Document? saved;
    var duplicate = false;
    var downloading = false;
    try {
      final report = await _acquire(
        _rust.importIdentifier(
          input: identifier,
          downloadPdf: true,
          taskId: rustTaskId('identifier', cancelToken),
        ),
        onEvent: (event) {
          switch (event) {
            case AcquisitionEvent_MetadataSaved(
              :final document,
              duplicate: final d,
            ):
              saved = documentFromRust(document);
              duplicate = d;
            case AcquisitionEvent_Downloading() when !downloading:
              downloading = true;
              onFetchingPdf?.call();
            default:
          }
        },
      );
      saved = documentFromRust(report.document);
    } catch (e) {
      // 元数据已入库而 PDF 获取失败：按「已添加、无 PDF」处理。
      if (saved == null || isCancellation(e)) rethrow;
      log.d('[Documents] PDF 下载失败，保留元数据条目：$e');
    } finally {
      bumpLibrary(ref);
    }
    final doc = saved!;
    if (doc.contentHash != null) {
      unawaited(
        PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(doc.id)),
      );
    }
    return (
      doc,
      duplicate
          ? AddByIdentifierResult.duplicate
          : AddByIdentifierResult.success,
    );
  }

  /// 校验文件完整性并补全缺失元数据。孤立文件与导入恢复由 Rust 启动时处理。
  Future<RebuildResult> rebuild({
    void Function(RebuildProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final l10n = rootNavigatorKey.currentContext?.l10n;
    onProgress?.call(
      RebuildProgress(fileName: '', status: l10n?.rebuildCheckingFiles ?? ''),
    );
    var removedCount = 0;
    final docs = <Document>[];
    for (final row in await _rust.documents(limit: kAllRows, offset: 0)) {
      var doc = documentFromRust(row);
      if (doc.contentHash != null &&
          !await File(DocPaths.pdf(doc.id)).exists()) {
        doc = doc.copyWith(contentHash: null);
        await _rust.putDocument(document: documentToRust(doc));
        removedCount++;
      }
      docs.add(doc);
    }
    final toRepair = [
      for (final d in docs)
        if (rust.metadataNeedsRepair(document: documentToRust(d))) d,
    ];
    var repairedCount = 0;
    final repairedIds = <String>{};
    for (var i = 0; i < toRepair.length; i++) {
      if (cancelToken?.isCancelled == true) break;
      final doc = toRepair[i];
      onProgress?.call(
        RebuildProgress(
          current: i + 1,
          total: toRepair.length,
          fileName: doc.title,
          status: l10n?.rebuildExtractingMetadata ?? '',
        ),
      );
      try {
        final status = await _repair(doc.id, cancelToken: cancelToken);
        if (status != MetadataStatus.none) repairedCount++;
        if (status == MetadataStatus.complete) repairedIds.add(doc.id);
      } catch (e) {
        if (isCancellation(e)) break;
        log.d('[Documents] 元数据修复失败：${doc.id} $e');
      }
    }
    bumpLibrary(ref);
    return RebuildResult(
      addedCount: 0,
      removedCount: removedCount,
      repairedCount: repairedCount,
      unresolvedCount: toRepair.length - repairedIds.length,
      noFileCount: docs.where((d) => d.contentHash == null).length,
      cancelled: cancelToken?.isCancelled == true,
    );
  }

  Future<void> updateDocument(
    String id, {
    String? title,
    List<String>? authors,
    String? journal,
    String? year,
    String? doi,
  }) async {
    final existing = await _rust.document(id: id);
    if (existing == null) return;
    final updated = documentFromRust(existing).copyWith(
      title: title,
      authors: authors,
      journal: journal,
      year: year,
      doi: doi,
    );
    await _rust.putDocument(document: documentToRust(updated));
    bumpLibrary(ref);
  }

  /// 替换文献 PDF；旧 PDF 的派生产物由 Rust 清除，笔记与会话保留。
  Future<void> attachFile(String docId, String sourcePath) async {
    await _rust.attachPdf(
      documentId: docId,
      source: sourcePath,
      replaceExisting: true,
      taskId: rustTaskId('attach'),
    );
    bumpLibrary(ref);
    await PdfThumbnailService.instance.deleteCacheEntry(DocPaths.pdf(docId));
    unawaited(
      PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(docId)),
    );
  }

  /// 给无文件条目补 PDF；已有 PDF 时不替换，返回是否新绑定了文件。
  Future<bool> attachMissingFile(
    String docId,
    String sourcePath, {
    CancelToken? cancelToken,
  }) async {
    final before = await _rust.document(id: docId);
    if (before == null || before.contentHash != null) return false;
    final after = await _rust.attachPdf(
      documentId: docId,
      source: sourcePath,
      replaceExisting: false,
      taskId: rustTaskId('attach', cancelToken),
    );
    bumpLibrary(ref);
    return after.contentHash != null;
  }

  /// 按 DOI 重新下载并替换 PDF；返回 PDF 内容是否变化。
  Future<bool> redownloadPdf(String docId, {CancelToken? cancelToken}) async {
    try {
      final report = await _acquire(
        _rust.downloadDocumentPdf(
          options: PdfDownloadOptions(documentId: docId, replaceExisting: true),
          taskId: rustTaskId('download', cancelToken),
        ),
      );
      if (report.changed) {
        await PdfThumbnailService.instance.deleteCacheEntry(
          DocPaths.pdf(docId),
        );
        unawaited(
          PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(docId)),
        );
      }
      return report.changed;
    } catch (e) {
      if (isCancellation(e)) rethrow;
      log.d('[Documents] 重新下载 PDF 失败：$e');
      return false;
    } finally {
      bumpLibrary(ref);
    }
  }

  Future<void> delete(String id) async {
    await _rust.deleteDocument(id: id, taskId: rustTaskId('delete'));
    bumpLibrary(ref);
    try {
      await PdfThumbnailService.instance.deleteCacheEntry(DocPaths.pdf(id));
    } catch (error) {
      log.d('删除缩略图失败: $error');
    }
  }

  Future<MetadataStatus> _repair(String id, {CancelToken? cancelToken}) async {
    await for (final event in _rust.repairMetadata(
      options: rust.MetadataRepairOptions(documentId: id, allowNetwork: true),
      taskId: rustTaskId('metadata', cancelToken),
    )) {
      switch (event) {
        case rust.MetadataEvent_Completed(:final report):
          bumpLibrary(ref);
          return switch (report.status) {
            rust.MetadataStatus.none => MetadataStatus.none,
            rust.MetadataStatus.partial => MetadataStatus.partial,
            rust.MetadataStatus.complete => MetadataStatus.complete,
          };
        case rust.MetadataEvent_Failed(:final error):
          throw error;
        default:
      }
    }
    throw const OtterError(
      code: ErrorCode.cancelled,
      detail: 'metadata stream ended',
    );
  }
}

/// 等待取得文献的流结束，返回最终报告；`Failed` 事件抛出其错误。
Future<PdfDownloadReport> _acquire(
  Stream<AcquisitionEvent> events, {
  void Function(AcquisitionEvent)? onEvent,
}) async {
  await for (final event in events) {
    onEvent?.call(event);
    switch (event) {
      case AcquisitionEvent_Completed(:final report):
        return report;
      case AcquisitionEvent_Failed(:final error):
        throw error;
      default:
    }
  }
  throw const OtterError(
    code: ErrorCode.cancelled,
    detail: 'acquisition stream ended',
  );
}

/// 文献库列表（AsyncValue；写入后刷新）。
final documentsProvider =
    AsyncNotifierProvider<DocumentsNotifier, List<Document>>(
      DocumentsNotifier.new,
    );

class ViewModeNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final viewModeProvider = NotifierProvider<ViewModeNotifier, bool>(
  ViewModeNotifier.new,
);

final noFileDocsCountProvider = Provider<int>((ref) {
  return (ref.watch(documentsProvider).value ?? const <Document>[])
      .where((d) => d.contentHash == null)
      .length;
});

final noFileDocsProvider = Provider<List<Document>>((ref) {
  return (ref.watch(documentsProvider).value ?? const <Document>[])
      .where((d) => d.contentHash == null)
      .toList();
});

final validDocsProvider = Provider<List<Document>>((ref) {
  return (ref.watch(documentsProvider).value ?? const <Document>[])
      .where((d) => d.contentHash != null)
      .toList();
});
