import '../services/document_duplicate_index.dart';
import '../core/storage/storage_activity.dart';
import '../core/l10n.dart';
import '../router/app_router.dart' show rootNavigatorKey;
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import '../core/storage/db_convert.dart';
import 'package:path/path.dart' as p;

import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/app_database_provider.dart';
import '../core/storage/storage.dart';
import '../core/storage/document_file_operations.dart';
import '../core/storage/zotero_local_store.dart';
import '../data/models/book/document.dart';
import '../services/chinese_metadata_extractor.dart';
import '../services/chinese_text_detector.dart';
import '../services/document_metadata_checks.dart';
import '../services/document_metadata_parser.dart';
import '../services/document_structure.dart';
import '../services/download/pdf_fetch_service.dart';
import '../services/identifier_parser.dart';
import '../services/identifier_resolver.dart';
import '../services/layout_metadata_extractor.dart';
import '../services/metadata_search_service.dart';
import '../services/pdf_identifier_extractor.dart';
import '../services/pdf_metadata_extractor.dart';
import '../services/pdf_thumbnail_service.dart';
import '../utils/doc_paths.dart';
import '../utils/uuid.dart';
import '../core/app_logger.dart';

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

class _MetadataRepairResult {
  final Document document;
  final MetadataStatus status;

  const _MetadataRepairResult({required this.document, required this.status});
}

/// 文献库列表（ADR-0001：Drift `watch()` 异步视图，DB 唯一真值源）。
///
/// `build()` 返回 `documents` 表按 `addedAt` 升序的 `watch()` 流（ADR-0006）；
/// 写方法非乐观——只写 DB，流自动刷新 `state`（`AsyncValue<List<Document>>`）。
/// 删除走 `DELETE FROM documents`，FK CASCADE 清 4 子表 + FTS 触发器清
/// `documents_fts`（ADR-0003），流自动反映。
class DocumentsNotifier extends StreamNotifier<List<Document>> {
  @override
  Stream<List<Document>> build() {
    final db = ref.watch(appDatabaseProvider);
    return (db.select(db.documents)
          ..orderBy([(t) => OrderingTerm.asc(t.addedAt)]))
        .map(documentFromRow)
        .watch();
  }

  /// 重新订阅流（备份恢复等场景由编排者经 `appDatabaseProvider` 失效触发，
  /// 此处保留给少数直接调用点）。
  void reload() => ref.invalidateSelf();

  /// Drift 实例统一经 [appDatabaseProvider] 取（唯一来源，禁止直用 GStorage.db）。
  AppDatabase get _db => ref.read(appDatabaseProvider);

  /// upsert 单篇到 Drift（FTS5 触发器自动同步 documents_fts）。
  Future<void> _upsertDoc(Document d) async {
    await _db.into(_db.documents).insertOnConflictUpdate(documentCompanion(d));
  }

  /// 批量 upsert。必须走 `ON CONFLICT DO UPDATE`（insertAllOnConflictUpdate）：
  /// SQLite 的 `INSERT OR REPLACE` 是 DELETE+INSERT，foreign_keys=ON 时内部
  /// 删除会执行 ON DELETE CASCADE——对已存在文档 REPLACE 会把它的高亮/历史/
  /// 收藏关联/Zotero 映射整批级联清空。
  Future<void> _upsertDocs(Iterable<Document> docs) async {
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.documents, [
        for (final d in docs) documentCompanion(d),
      ]);
    });
  }

  Future<void> _deleteDoc(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.documents)..where((t) => t.id.equals(id))).go();
      await ZoteroLocalStore(_db).removeDocument(id);
    });
  }

  /// 按 id 从 DB 查单篇（唯一真值源）——不读 watch() 流 state，
  /// 避免 StreamNotifier 流未 emit 时漏判。
  Future<Document?> _findById(String id) async {
    final row = await (_db.select(
      _db.documents,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : documentFromRow(row);
  }

  /// 从 DB 读全部文献（唯一真值源）——不读 watch() 流 state 查重。
  Future<List<Document>> _allDocsFromDb() async {
    final rows = await _db.select(_db.documents).get();
    return rows.map(documentFromRow).toList();
  }

  /// 文献库根目录——所有文献自包含目录的父目录。
  static Future<Directory> getDocsDir() async {
    final dir = Directory(GStorage.libraryDirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<AddFileResult> addFile(
    String sourcePath, {
    CancelToken? cancelToken,
  }) => StorageActivity.run(() async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return const AddFileResult(type: AddFileResultType.duplicate);
    }

    final contentHash = await DocPaths.computeHash(sourceFile);
    // 判重走 DB 查询（唯一真值源）——不依赖 watch() 流 state：StreamNotifier
    // 异步，流未 emit 时列表为空会漏判，导致 _upsertDoc 触发 contentHash
    // UNIQUE 约束冲突，addFile 抛异常、文件成孤儿。
    final existingRow = await (_db.select(
      _db.documents,
    )..where((t) => t.contentHash.equals(contentHash))).getSingleOrNull();
    if (existingRow != null) {
      return AddFileResult(
        type: AddFileResultType.duplicate,
        document: documentFromRow(existingRow),
      );
    }

    final documentId = _newDocumentId();

    final initialMetadata = DocumentMetadataParser.parseFilePath(sourcePath);
    final doc = Document(
      id: documentId,
      title: initialMetadata.title ?? p.basenameWithoutExtension(sourcePath),
      authors: initialMetadata.authors,
      journal: initialMetadata.journal,
      year: initialMetadata.year,
      doi: initialMetadata.doi,
      contentHash: contentHash,
      addedAt: DateTime.now(),
    );

    // 立即入库：卡片先出现（文件名级初始元数据），元数据后台提取更新。
    await DocumentFileOperations(_db, GStorage.libraryDirPath).run(
      documentId,
      deleting: false,
      action: () async {
        await _writePdfForDocument(documentId, sourceFile);
        await _upsertDoc(doc);
      },
    );

    unawaited(
      PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(doc.id)),
    );

    // 元数据提取异步：不阻塞 addFile 返回，批量导入时多个文件快速建卡，
    // 元数据后台逐篇提取 + upsert（watch() 流自动刷新卡片）。
    final metadataToken = CancelToken();
    if (cancelToken != null) {
      if (cancelToken.isCancelled) metadataToken.cancel();
      cancelToken.whenCancel.then((_) => metadataToken.cancel());
    }
    unawaited(
      _repairAndUpdate(doc, cancelToken: metadataToken).catchError((
        Object e,
        StackTrace st,
      ) {
        if (e is DioException && CancelToken.isCancel(e)) return;
        log.w('[Documents] 后台元数据修复失败：${doc.id}', error: e, stackTrace: st);
      }),
    );

    return AddFileResult(
      type: AddFileResultType.imported,
      document: doc,
      metadataStatus: MetadataStatus.none,
    );
  });

  /// 后台提取元数据并更新（异步，不阻塞 addFile）。提取耗时数秒（联网），
  /// 期间文献可能被删除或被用户编辑：回写做字段级合并（用户改过的字段不
  /// 覆盖），并用带 where 的 UPDATE 落库——行已删时更新 0 行，不复活已删文献。
  Future<void> _repairAndUpdate(Document doc, {CancelToken? cancelToken}) =>
      StorageActivity.run(() async {
        // 提前取库实例：本方法 fire-and-forget，避免 await 之后 ref 已被释放。
        final database = _db;
        final repaired = await _repairDocument(doc, cancelToken: cancelToken);
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        final row = await (database.select(
          database.documents,
        )..where((t) => t.id.equals(doc.id))).getSingleOrNull();
        if (row == null) return;
        final merged = _mergeRepaired(
          doc,
          documentFromRow(row),
          repaired.document,
        );
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        await (database.update(
          database.documents,
        )..where((t) => t.id.equals(doc.id))).write(documentCompanion(merged));
      }, cancel: () => cancelToken?.cancel());

  /// 字段级合并提取结果：以 addFile 时的快照为基线，用户在提取窗口内改过的
  /// 字段（当前行 ≠ 快照）保留当前值，未动过的字段采用提取结果。
  Document _mergeRepaired(
    Document snapshot,
    Document current,
    Document repaired,
  ) {
    bool sameList(List<String> a, List<String> b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    return Document(
      id: current.id,
      title: current.title == snapshot.title ? repaired.title : current.title,
      authors: sameList(current.authors, snapshot.authors)
          ? repaired.authors
          : current.authors,
      journal: current.journal == snapshot.journal
          ? repaired.journal
          : current.journal,
      year: current.year == snapshot.year ? repaired.year : current.year,
      doi: current.doi == snapshot.doi ? repaired.doi : current.doi,
      keywords: sameList(current.keywords, snapshot.keywords)
          ? repaired.keywords
          : current.keywords,
      contentHash: current.contentHash == snapshot.contentHash
          ? repaired.contentHash
          : current.contentHash,
      addedAt: current.addedAt,
    );
  }

  Future<(Document, AddByIdentifierResult)> addByIdentifier(
    String identifier, {
    CancelToken? cancelToken,
  }) => StorageActivity.run(() async {
    final resolved = await IdentifierResolver.instance.resolve(
      identifier,
      cancelToken: cancelToken,
    );

    // 判重走 DB 查询（唯一真值源）——不依赖 watch() 流 state（StreamNotifier
    // 异步，流未 emit 时列表为空会漏判，导致重复纯元数据条目入库）。
    final allDocs = await _allDocsFromDb();
    final duplicate = allDocs.any(
      (doc) => DocumentMetadataChecks.isDuplicate(doc, resolved),
    );
    if (duplicate) {
      return (resolved, AddByIdentifierResult.duplicate);
    }

    var doc = resolved.copyWith(id: _newDocumentId(), contentHash: null);

    await DocumentFileOperations(_db, GStorage.libraryDirPath).run(
      doc.id,
      deleting: false,
      action: () async {
        // PDF 下载：DOI 管道优先；PMID 输入且 DOI 无果时走 PMC 开放获取兜底。
        final parsed = IdentifierParser.parse(identifier);
        final pdfPath = DocPaths.pdf(doc.id);
        String downloadedPath = '';
        if (!DocumentMetadataChecks.isBlank(doc.doi)) {
          downloadedPath = await PdfFetchService.instance.fetchByDoi(
            doi: doc.doi!,
            year: doc.year,
            authors: doc.authors,
            title: doc.title,
            fallbackId: doc.id,
            targetPath: pdfPath,
            cancelToken: cancelToken,
          );
        }
        if (downloadedPath.isEmpty && parsed.type == IdentifierType.pmid) {
          downloadedPath = await PdfFetchService.instance.fetchByPmid(
            pmid: parsed.value,
            year: doc.year,
            authors: doc.authors,
            title: doc.title,
            fallbackId: doc.id,
            targetPath: pdfPath,
            cancelToken: cancelToken,
          );
        }
        if (downloadedPath.isNotEmpty) {
          doc = doc.copyWith(
            contentHash: await DocPaths.computeHash(File(pdfPath)),
          );
        }

        await _upsertDoc(doc);
      },
    );
    if (doc.contentHash != null) {
      unawaited(
        PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(doc.id)),
      );
    }
    return (doc, AddByIdentifierResult.success);
  });

  /// 批量导入已带元数据的文献（如 Zotero 同步），不经过 `IdentifierResolver`
  /// 重新联网解析。每篇以 `contentHash: null` 入库（纯元数据、暂无 PDF），
  /// 后续 rebuild 会对带 DOI 的自动补回 PDF。
  ///
  /// 返回与 [incoming] 等长、同序的结果列表：重复项返回库中已存在的那篇，
  /// 新增项返回分配了 id 后的新文献——便于调用方记录外部 key ↔ documentId 映射。
  Future<List<Document>> importDocuments(
    List<Document> incoming, {
    DocumentDuplicateIndex? index,
  }) => StorageActivity.run(() async {
    if (incoming.isEmpty) return const [];

    final duplicates = index ?? DocumentDuplicateIndex(await _allDocsFromDb());
    final results = <Document>[];
    final additions = <Document>[];
    for (final candidate in incoming) {
      final existing = duplicates.find(candidate);
      if (existing != null) {
        results.add(existing);
        continue;
      }
      final doc = candidate.copyWith(id: _newDocumentId(), contentHash: null);
      additions.add(doc);
      duplicates.put(doc);
      results.add(doc);
    }

    if (additions.isNotEmpty) {
      await _upsertDocs(additions);
    }
    return results;
  });

  Future<RebuildResult> rebuild({
    void Function(RebuildProgress)? onProgress,
    CancelToken? cancelToken,
  }) => StorageActivity.run(() async {
    final l10n = rootNavigatorKey.currentContext?.l10n;
    final docsDir = await getDocsDir();
    var addedCount = 0;
    var removedCount = 0;
    var repairedCount = 0;

    onProgress?.call(
      RebuildProgress(
        fileName: l10n?.libraryName ?? '',
        status: l10n?.rebuildScanningFiles ?? '',
      ),
    );

    // 基线从 DB 读（唯一真值源）：流未 emit 时 state 为空，若以空基线 upsert，
    // 全部已有文档会被 title=UUID 的占位行覆盖，元数据尽失。
    var docs = await _allDocsFromDb();
    final knownIds = docs.map((doc) => doc.id).toSet();
    await for (final entity in docsDir.list()) {
      if (cancelToken?.isCancelled == true) break;
      if (entity is! Directory) continue;
      final documentId = p.basename(entity.path);
      if (knownIds.contains(documentId)) continue;

      final pdf = File(DocPaths.pdf(documentId));
      if (!await pdf.exists()) continue;
      final contentHash = await DocPaths.computeHash(pdf);
      docs = [
        ...docs,
        Document(
          id: documentId,
          title: documentId,
          authors: const [],
          contentHash: contentHash,
          addedAt: DateTime.now(),
        ),
      ];
      knownIds.add(documentId);
      addedCount++;
    }

    onProgress?.call(
      RebuildProgress(
        fileName: l10n?.libraryName ?? '',
        status: l10n?.rebuildCheckingFiles ?? '',
      ),
    );

    final validDocs = <Document>[];
    for (final doc in docs) {
      final pdf = File(DocPaths.pdf(doc.id));
      if (doc.contentHash == null) {
        if (await pdf.exists()) {
          validDocs.add(
            doc.copyWith(contentHash: await DocPaths.computeHash(pdf)),
          );
        } else {
          validDocs.add(doc);
        }
        continue;
      }

      if (await pdf.exists()) {
        validDocs.add(doc);
        continue;
      }
      removedCount++;
      validDocs.add(doc.copyWith(contentHash: null));
    }
    docs = validDocs;

    // 无文件条目不纳入重构：rebuild 只发现新 PDF、校验完整性、修复已有文件的元数据。
    // 为无文件条目补回 PDF 由用户主动触发（无文件条目页多选下载 / 按标识符添加）。
    final toRepair = docs.where(DocumentMetadataChecks.needsRepair).toList();
    if (toRepair.isNotEmpty) {
      final updates = <String, Document>{};
      for (var i = 0; i < toRepair.length; i++) {
        if (cancelToken?.isCancelled == true) break;
        final doc = toRepair[i];
        onProgress?.call(
          RebuildProgress(
            current: i + 1,
            total: toRepair.length,
            fileName: p.basename(DocPaths.pdf(doc.id)),
            status: l10n?.rebuildExtractingMetadata ?? '',
          ),
        );

        final repaired = await _repairDocument(doc, cancelToken: cancelToken);
        updates[doc.id] = repaired.document;
        if (repaired.status != MetadataStatus.none) {
          repairedCount++;
        }
      }

      if (updates.isNotEmpty) {
        docs = [for (final doc in docs) updates[doc.id] ?? doc];
      }
    }

    await _upsertDocs(docs);

    final noFileCount = docs.where((doc) => doc.contentHash == null).length;
    final unresolvedCount = docs
        .where(DocumentMetadataChecks.needsRepair)
        .length;

    return RebuildResult(
      addedCount: addedCount,
      removedCount: removedCount,
      repairedCount: repairedCount,
      unresolvedCount: unresolvedCount,
      noFileCount: noFileCount,
      cancelled: cancelToken?.isCancelled == true,
    );
  });

  Future<void> updateDocument(
    String id, {
    String? title,
    List<String>? authors,
    String? journal,
    String? year,
    String? doi,
  }) => StorageActivity.run(() async {
    // 按 id 走 DB 查询（流未 emit 时 state 为空会找不到，导致编辑静默不生效）。
    final existing = await _findById(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      title: title,
      authors: authors,
      journal: journal,
      year: year,
      doi: doi,
    );
    await _upsertDoc(updated);
  });

  Future<void> attachFile(String docId, String sourcePath) =>
      StorageActivity.run(() async {
        // 按 id 走 DB 查询（流未 emit 时 state 为空会找不到，导致补文件静默不执行）。
        final existing = await _findById(docId);
        if (existing == null) return;

        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists()) return;

        final contentHash = await DocPaths.computeHash(sourceFile);
        await _writePdfForDocument(docId, sourceFile, clearDerived: true);

        var updated = existing.copyWith(contentHash: contentHash);
        if (DocumentMetadataChecks.needsRepair(updated)) {
          updated = (await _repairDocument(updated)).document;
        }

        await _upsertDoc(updated);
        unawaited(
          PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(docId)),
        );
      });

  Future<Document?> mergeSourceMetadata(
    String id,
    Document incoming,
    Document? previous,
  ) => _db.transaction(() async {
    final current = await _findById(id);
    if (current == null) return null;
    final merged = DocumentMetadataChecks.mergeFromSource(
      current,
      incoming,
      previous,
    );
    if (!DocumentMetadataChecks.sameCore(current, merged) ||
        current.keywords.join('\u0000') != merged.keywords.join('\u0000')) {
      await _upsertDoc(merged);
    }
    return merged;
  });

  Future<bool> attachMissingFile(
    String docId,
    String sourcePath, {
    CancelToken? cancelToken,
  }) => StorageActivity.run(() async {
    void checkCancelled() {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    }

    checkCancelled();
    if (await _findById(docId) == null) return false;
    final destination = File(DocPaths.pdf(docId));
    if (await destination.exists()) return false;
    await Directory(DocPaths.docDir(docId)).create(recursive: true);
    final staged = File(
      p.join(DocPaths.docDir(docId), '.zotero-${generateUuid()}.part'),
    );
    try {
      final output = await staged.open(mode: FileMode.write);
      try {
        await for (final chunk in File(sourcePath).openRead()) {
          checkCancelled();
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      checkCancelled();
      final input = await staged.open();
      try {
        final header = await input.read(1024);
        if (!String.fromCharCodes(header).contains('%PDF-')) {
          throw const FormatException('invalid_pdf');
        }
      } finally {
        await input.close();
      }
      final hash = await DocPaths.computeHash(staged);
      checkCancelled();
      return await _db.transaction(() async {
        final current = await _findById(docId);
        if (current == null || await destination.exists()) return false;
        checkCancelled();
        // 完整副本验证通过后才发布；提交期间不再响应取消，避免留下半次文件绑定。
        await staged.rename(destination.path);
        try {
          await _upsertDoc(current.copyWith(contentHash: hash));
        } catch (_) {
          await destination.delete();
          rethrow;
        }
        return true;
      });
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  });

  Future<bool> redownloadPdf(String docId, {CancelToken? cancelToken}) =>
      StorageActivity.run(() async {
        // 按 id 走 DB 查询（流未 emit 时 state 为空会找不到，导致重下载静默不执行）。
        final found = await _findById(docId);
        if (found == null) return false;
        var doc = found;

        // 无 DOI 时，用标题搜索补全元数据（可能拿到 DOI）
        if (DocumentMetadataChecks.isBlank(doc.doi) &&
            !DocumentMetadataChecks.looksLikePlaceholderTitle(doc)) {
          try {
            final searchResult = await MetadataSearchService.instance
                .searchByTitle(doc.title, cancelToken: cancelToken);
            if (searchResult != null) {
              doc = _applyResolvedDocument(doc, searchResult);
              await _upsertDoc(doc);
            }
          } catch (e) {
            if (e is DioException && CancelToken.isCancel(e)) rethrow;
            log.d('标题搜索补全 DOI 失败: $e');
          }
        }

        if (DocumentMetadataChecks.isBlank(doc.doi)) return false;

        // 下载到 source.pdf.tmp 临时路径，绕开 IdentifierResolver._downloadPdf 的
        // "exists → skip" 短路；成功后再原子替换。失败时旧 PDF 与 derived 完整保留。
        final pdfPath = DocPaths.pdf(docId);
        final tempPath = '$pdfPath.tmp';
        final tempFile = File(tempPath);
        try {
          if (await tempFile.exists()) await tempFile.delete();

          final downloadedPath = await PdfFetchService.instance.fetchByDoi(
            doi: doc.doi!,
            year: doc.year,
            authors: doc.authors,
            title: doc.title,
            fallbackId: doc.id,
            targetPath: tempPath,
            cancelToken: cancelToken,
          );
          if (downloadedPath.isEmpty) return false;

          final newHash = await DocPaths.computeHash(File(downloadedPath));
          final contentChanged = doc.contentHash != newHash;

          if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
          await File(downloadedPath).rename(pdfPath);

          // 内容变化 → 旧 extract.md / figures / summary / 翻译缓存与缩略图全部失效。
          if (contentChanged) {
            await _clearDerivedFiles(docId);
            await PdfThumbnailService.instance.deleteCacheEntry(pdfPath);
          }

          var updated = doc.copyWith(contentHash: newHash);

          // 下载后用 PDF 内容补全可能缺失的元数据
          if (DocumentMetadataChecks.needsRepair(updated)) {
            updated = (await _repairDocument(
              updated,
              cancelToken: cancelToken,
            )).document;
          }

          await _upsertDoc(updated);
          unawaited(PdfThumbnailService.instance.getThumbnailPath(pdfPath));
          return true;
        } catch (error) {
          if (error is DioException && CancelToken.isCancel(error)) rethrow;
          log.d('重新下载 PDF 失败: $error');
          if (await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
          return false;
        }
      });

  Future<void> delete(String id) => StorageActivity.run(() async {
    await DocumentFileOperations(
      _db,
      GStorage.libraryDirPath,
    ).run(id, deleting: true, action: () => _deleteDoc(id));
    try {
      await PdfThumbnailService.instance.deleteCacheEntry(DocPaths.pdf(id));
    } catch (error) {
      log.d('删除缩略图失败: $error');
    }
  });

  Future<void> _writePdfForDocument(
    String documentId,
    File sourceFile, {
    bool clearDerived = false,
  }) async {
    final docDir = Directory(DocPaths.docDir(documentId));
    if (clearDerived && await docDir.exists()) {
      await docDir.delete(recursive: true);
    }
    if (!await docDir.exists()) await docDir.create(recursive: true);

    final destPath = DocPaths.pdf(documentId);
    final destFile = File(destPath);
    if (await destFile.exists()) await destFile.delete();
    await sourceFile.copy(destPath);
  }

  /// 清理文献目录下除 `source.pdf` 外的所有派生产物（extract.md / figures /
  /// summary / 翻译缓存 / .reader.html 等）。PDF 内容变化后调用，避免旧抽取
  /// 产物与新 PDF 混搭。
  Future<void> _clearDerivedFiles(String documentId) async {
    final docDir = Directory(DocPaths.docDir(documentId));
    if (!await docDir.exists()) return;
    await for (final entity in docDir.list()) {
      if (p.basename(entity.path) == DocPaths.pdfName) continue;
      try {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else {
          await entity.delete();
        }
      } catch (e) {
        log.d('清理派生文件失败 ${entity.path}: $e');
      }
    }
  }

  Future<_MetadataRepairResult> _repairDocument(
    Document doc, {
    CancelToken? cancelToken,
  }) async {
    if (doc.contentHash == null) {
      return _MetadataRepairResult(document: doc, status: MetadataStatus.none);
    }

    final original = doc;
    final pdfPath = DocPaths.pdf(doc.id);

    try {
      final fallbackMetadata = DocumentMetadataParser.parseFilePath(pdfPath);
      final pdfMetadata = await PdfMetadataExtractor.instance.extract(pdfPath);
      var combinedMetadata = fallbackMetadata.merge(pdfMetadata);
      doc = _applyMetadata(doc, combinedMetadata);

      // 修正历史遗留 / 未拆分的 CNKI 标题（title 形如 "标题_作者"）。
      // _repairDocument 解析的是存储后的 source.pdf，拿不到原始文件名，
      // 因此这里直接对当前 title 再跑一次拆分，让后续正文定位用纯标题。
      final titleSplit = DocumentMetadataParser.parseText(doc.title);
      if (titleSplit.title != null && titleSplit.authors.isNotEmpty) {
        doc = doc.copyWith(title: titleSplit.title);
        if (doc.authors.isEmpty) {
          doc = doc.copyWith(authors: titleSplit.authors);
        }
      }

      // OCR 版面结构中的 doc_title / 作者行补全（教材等非期刊文献）
      final extractJsonPath = DocPaths.json(doc.id);
      if (File(extractJsonPath).existsSync()) {
        final structure = await DocumentStructure.load(extractJsonPath);
        if (structure.pages.isNotEmpty) {
          final layoutMeta = LayoutMetadataExtractor.extractFromFirstPage(
            structure.pages.first.blocks,
          );
          combinedMetadata = combinedMetadata.merge(layoutMeta);
          doc = _applyMetadata(doc, combinedMetadata);
        }
      }

      // 提取一次首页文本，供标识符提取与中文正文元数据提取复用
      final pageText = await PdfIdentifierExtractor.instance.extractText(
        pdfPath,
      );

      // 中文文献：从正文首页补全期刊 / 完整作者 / 年份 / DOI
      final looksChinese =
          ChineseTextDetector.isChinese(doc.title) ||
          (pageText != null && ChineseTextDetector.isChinese(pageText));
      if (looksChinese && pageText != null) {
        final cn = ChineseMetadataExtractor.parseFromText(
          pageText,
          knownTitle: doc.title,
        );
        combinedMetadata = combinedMetadata.merge(cn);
        doc = _applyMetadata(doc, combinedMetadata);
      }

      // 标识符解析：中文 DOI（如 10.13193）CrossRef 多解析不了，
      // 单独容错——失败不回滚已从正文提取的期刊/作者/年份。
      final identifier =
          combinedMetadata.doi ??
          PdfIdentifierExtractor.extractIdentifierFromText(pageText)?.value;
      if (!DocumentMetadataChecks.isBlank(identifier)) {
        try {
          final resolved = await IdentifierResolver.instance.resolve(
            identifier!,
            cancelToken: cancelToken,
          );
          doc = _applyResolvedDocument(doc, resolved);
        } catch (e) {
          log.d('标识符解析失败（保留已提取元数据）: $e');
        }
      }

      // 标识符解析未完成时，用标题搜索回退
      if (!DocumentMetadataChecks.isComplete(doc) &&
          !DocumentMetadataChecks.looksLikePlaceholderTitle(doc)) {
        try {
          final searchResult = await MetadataSearchService.instance
              .searchByTitle(doc.title, cancelToken: cancelToken);
          if (searchResult != null) {
            doc = _applyResolvedDocument(doc, searchResult);
          }
        } catch (e) {
          log.d('标题搜索失败: $e');
        }
      }
    } catch (error) {
      log.d('元数据修复失败: $error');
      doc = _applyMetadata(doc, DocumentMetadataParser.parseFilePath(pdfPath));
    }

    return _MetadataRepairResult(
      document: doc,
      status: _metadataStatus(original, doc),
    );
  }

  Document _applyResolvedDocument(Document target, Document resolved) {
    return _applyMetadata(
      target,
      DocumentMetadata(
        title: resolved.title,
        authors: resolved.authors,
        journal: resolved.journal,
        year: resolved.year,
        doi: resolved.doi,
      ),
    ).copyWith(
      keywords: resolved.keywords.isNotEmpty
          ? resolved.keywords
          : target.keywords,
    );
  }

  Document _applyMetadata(Document doc, DocumentMetadata metadata) {
    final title = DocumentMetadataChecks.normalizeMetadataValue(metadata.title);
    final journal = DocumentMetadataChecks.normalizeMetadataValue(
      metadata.journal,
    );
    final year = DocumentMetadataChecks.normalizeMetadataValue(metadata.year);
    final doi = DocumentMetadataChecks.normalizeMetadataValue(
      metadata.doi,
    )?.toLowerCase();

    return doc.copyWith(
      title: title ?? doc.title,
      authors: metadata.authors.isNotEmpty ? metadata.authors : doc.authors,
      journal: journal ?? doc.journal,
      year: year ?? doc.year,
      doi: doi ?? doc.doi,
    );
  }

  MetadataStatus _metadataStatus(Document before, Document after) {
    if (DocumentMetadataChecks.sameCore(before, after)) {
      return MetadataStatus.none;
    }
    return DocumentMetadataChecks.isComplete(after)
        ? MetadataStatus.complete
        : MetadataStatus.partial;
  }

  String _newDocumentId() => generateUuid();
}

/// 文献库列表（AsyncValue；流自动反映 DB 变更）。
final documentsProvider =
    StreamNotifierProvider<DocumentsNotifier, List<Document>>(
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

/// 派生 provider 保持同步：内部解包 [documentsProvider] 的 AsyncValue，
/// 让 bookshelf / no_file 等消费点零改动（ADR-0001）。
final noFileDocsCountProvider = Provider<int>((ref) {
  return (ref.watch(documentsProvider).value ?? const <Document>[])
      .where((doc) => doc.contentHash == null)
      .length;
});

final noFileDocsProvider = Provider<List<Document>>((ref) {
  return (ref.watch(documentsProvider).value ?? const <Document>[])
      .where((doc) => doc.contentHash == null)
      .toList();
});

final validDocsProvider = Provider<List<Document>>((ref) {
  return (ref.watch(documentsProvider).value ?? const <Document>[])
      .where((doc) => doc.contentHash != null)
      .toList();
});
