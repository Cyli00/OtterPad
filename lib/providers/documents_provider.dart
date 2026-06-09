import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import '../services/chinese_metadata_extractor.dart';
import '../services/chinese_text_detector.dart';
import '../services/document_metadata_checks.dart';
import '../services/document_metadata_parser.dart';
import '../services/identifier_resolver.dart';
import '../services/metadata_search_service.dart';
import '../services/pdf_identifier_extractor.dart';
import '../services/pdf_metadata_extractor.dart';
import '../services/pdf_thumbnail_service.dart';
import '../utils/doc_paths.dart';
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

class DocumentsNotifier extends StateNotifier<List<Document>> {
  final Box _box;

  DocumentsNotifier(this._box) : super([]) {
    _load();
  }

  void _load() {
    final raw = _box.get('documents') as List<dynamic>?;
    if (raw == null) {
      state = [];
      return;
    }

    state = raw
        .map(
          (entry) => Document.fromJson(
            Map<String, dynamic>.from(jsonDecode(entry as String)),
          ),
        )
        .toList();
  }

  void reload() {
    _load();
  }

  Future<void> _save() async {
    final encoded = state.map((doc) => jsonEncode(doc.toJson())).toList();
    await _box.put('documents', encoded);
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
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return const AddFileResult(type: AddFileResultType.duplicate);
    }

    final contentHash = await DocPaths.computeHash(sourceFile);
    final existingDoc = state.cast<Document?>().firstWhere(
      (doc) => doc != null && doc.contentHash == contentHash,
      orElse: () => null,
    );
    if (existingDoc != null) {
      return AddFileResult(
        type: AddFileResultType.duplicate,
        document: existingDoc,
      );
    }

    final documentId = _newDocumentId();
    await _writePdfForDocument(documentId, sourceFile);

    final initialMetadata = DocumentMetadataParser.parseFilePath(sourcePath);
    var doc = Document(
      id: documentId,
      title: initialMetadata.title ?? p.basenameWithoutExtension(sourcePath),
      authors: initialMetadata.authors,
      journal: initialMetadata.journal,
      year: initialMetadata.year,
      doi: initialMetadata.doi,
      contentHash: contentHash,
      addedAt: DateTime.now(),
    );

    state = [...state, doc];

    final repaired = await _repairDocument(doc, cancelToken: cancelToken);
    doc = repaired.document;
    state = [
      for (final entry in state)
        if (entry.id == doc.id) doc else entry,
    ];
    await _save();

    unawaited(
      PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(doc.id)),
    );

    return AddFileResult(
      type: AddFileResultType.imported,
      document: doc,
      metadataStatus: repaired.status,
    );
  }

  Future<(Document, AddByIdentifierResult)> addByIdentifier(
    String identifier, {
    CancelToken? cancelToken,
  }) async {
    final resolved = await IdentifierResolver.instance.resolve(
      identifier,
      metadataOnly: true,
      cancelToken: cancelToken,
    );

    final duplicate = state.any(
      (doc) => DocumentMetadataChecks.isDuplicate(doc, resolved),
    );
    if (duplicate) {
      return (resolved, AddByIdentifierResult.duplicate);
    }

    var doc = resolved.copyWith(id: _newDocumentId(), contentHash: null);

    if (!DocumentMetadataChecks.isBlank(doc.doi)) {
      final downloaded = await _downloadPdfIntoDocument(
        doc,
        cancelToken: cancelToken,
      );
      if (downloaded != null) doc = downloaded;
    }

    state = [...state, doc];
    await _save();
    if (doc.contentHash != null) {
      unawaited(
        PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(doc.id)),
      );
    }
    return (doc, AddByIdentifierResult.success);
  }

  /// 批量导入已带元数据的文献（如 Zotero 同步），不经过 `IdentifierResolver`
  /// 重新联网解析。每篇以 `contentHash: null` 入库（纯元数据、暂无 PDF），
  /// 后续 rebuild 会对带 DOI 的自动补回 PDF。
  ///
  /// 返回与 [incoming] 等长、同序的结果列表：重复项返回库中已存在的那篇，
  /// 新增项返回分配了 id 后的新文献——便于调用方记录外部 key ↔ documentId 映射。
  Future<List<Document>> importDocuments(List<Document> incoming) async {
    if (incoming.isEmpty) return const [];

    final results = <Document>[];
    final additions = <Document>[];
    for (final candidate in incoming) {
      final existing = [...state, ...additions].cast<Document?>().firstWhere(
        (doc) =>
            doc != null && DocumentMetadataChecks.isDuplicate(doc, candidate),
        orElse: () => null,
      );
      if (existing != null) {
        results.add(existing);
        continue;
      }
      final doc = candidate.copyWith(id: _newDocumentId(), contentHash: null);
      additions.add(doc);
      results.add(doc);
    }

    if (additions.isNotEmpty) {
      state = [...state, ...additions];
      await _save();
    }
    return results;
  }

  Future<RebuildResult> rebuild({
    void Function(RebuildProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final docsDir = await getDocsDir();
    var addedCount = 0;
    var removedCount = 0;
    var repairedCount = 0;

    onProgress?.call(
      const RebuildProgress(fileName: 'OtterPad 文库', status: '正在扫描 PDF 文件...'),
    );

    final knownIds = state.map((doc) => doc.id).toSet();
    await for (final entity in docsDir.list()) {
      if (cancelToken?.isCancelled == true) break;
      if (entity is! Directory) continue;
      final documentId = p.basename(entity.path);
      if (knownIds.contains(documentId)) continue;

      final pdf = File(DocPaths.pdf(documentId));
      if (!await pdf.exists()) continue;
      final contentHash = await DocPaths.computeHash(pdf);
      state = [
        ...state,
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
      const RebuildProgress(fileName: 'OtterPad 文库', status: '正在检查文件完整性...'),
    );

    final validDocs = <Document>[];
    for (final doc in state) {
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
    state = validDocs;

    // 无文件条目不纳入重构：rebuild 只发现新 PDF、校验完整性、修复已有文件的元数据。
    // 为无文件条目补回 PDF 由用户主动触发（无文件条目页多选下载 / 按标识符添加）。
    final toRepair = state.where(DocumentMetadataChecks.needsRepair).toList();
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
            status: '正在提取 PDF 元数据...',
          ),
        );

        final repaired = await _repairDocument(doc, cancelToken: cancelToken);
        updates[doc.id] = repaired.document;
        if (repaired.status != MetadataStatus.none) {
          repairedCount++;
        }
      }

      if (updates.isNotEmpty) {
        state = [for (final doc in state) updates[doc.id] ?? doc];
      }
    }

    await _save();

    final noFileCount = state.where((doc) => doc.contentHash == null).length;
    final unresolvedCount = state
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
  }

  Future<void> update(
    String id, {
    String? title,
    List<String>? authors,
    String? journal,
    String? year,
    String? doi,
  }) async {
    state = [
      for (final doc in state)
        if (doc.id == id)
          doc.copyWith(
            title: title,
            authors: authors,
            journal: journal,
            year: year,
            doi: doi,
          )
        else
          doc,
    ];
    await _save();
  }

  Future<void> attachFile(String docId, String sourcePath) async {
    final existing = state.cast<Document?>().firstWhere(
      (doc) => doc != null && doc.id == docId,
      orElse: () => null,
    );
    if (existing == null) return;

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    final contentHash = await DocPaths.computeHash(sourceFile);
    await _writePdfForDocument(docId, sourceFile, clearDerived: true);

    var updated = existing.copyWith(contentHash: contentHash);
    if (DocumentMetadataChecks.needsRepair(updated)) {
      updated = (await _repairDocument(updated)).document;
    }

    state = [
      for (final doc in state)
        if (doc.id == docId) updated else doc,
    ];
    await _save();
    unawaited(
      PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(docId)),
    );
  }

  Future<bool> redownloadPdf(String docId, {CancelToken? cancelToken}) async {
    final found = state.cast<Document?>().firstWhere(
      (entry) => entry != null && entry.id == docId,
      orElse: () => null,
    );
    if (found == null) return false;
    // found 已被空检查提升为非空，var doc 因此推断为非空 Document，
    // 后续条件块内的重新赋值不会丢失类型提升。
    var doc = found;

    // 无 DOI 时，用标题搜索补全元数据（可能拿到 DOI）
    if (DocumentMetadataChecks.isBlank(doc.doi) &&
        !DocumentMetadataChecks.looksLikePlaceholderTitle(doc)) {
      try {
        final searchResult = await MetadataSearchService.instance.searchByTitle(
          doc.title,
          cancelToken: cancelToken,
        );
        if (searchResult != null) {
          doc = _applyResolvedDocument(doc, searchResult);
          state = [
            for (final entry in state)
              if (entry.id == docId) doc else entry,
          ];
          await _save();
        }
      } catch (e) {
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

      final downloadedPath = await IdentifierResolver.instance.downloadPdfByDoi(
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

      final existingPdf = File(pdfPath);
      if (await existingPdf.exists()) await existingPdf.delete();
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

      state = [
        for (final entry in state)
          if (entry.id == docId) updated else entry,
      ];
      await _save();
      unawaited(PdfThumbnailService.instance.getThumbnailPath(pdfPath));
      return true;
    } catch (error) {
      log.d('重新下载 PDF 失败: $error');
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      return false;
    }
  }

  Future<void> delete(String id) async {
    final doc = state.cast<Document?>().firstWhere(
      (entry) => entry != null && entry.id == id,
      orElse: () => null,
    );
    if (doc != null) {
      try {
        final docDir = Directory(DocPaths.docDir(id));
        if (await docDir.exists()) {
          await docDir.delete(recursive: true);
        }
        await PdfThumbnailService.instance.deleteCacheEntry(DocPaths.pdf(id));
      } catch (error) {
        log.d('删除文件失败: $error');
      }
    }

    state = state.where((doc) => doc.id != id).toList();
    await _save();
  }

  Future<Document?> _downloadPdfIntoDocument(
    Document doc, {
    CancelToken? cancelToken,
  }) async {
    if (DocumentMetadataChecks.isBlank(doc.doi)) return null;
    final pdfPath = DocPaths.pdf(doc.id);
    final downloadedPath = await IdentifierResolver.instance.downloadPdfByDoi(
      doi: doc.doi!,
      year: doc.year,
      authors: doc.authors,
      title: doc.title,
      fallbackId: doc.id,
      targetPath: pdfPath,
      cancelToken: cancelToken,
    );
    if (downloadedPath.isEmpty) return null;
    final contentHash = await DocPaths.computeHash(File(downloadedPath));
    return doc.copyWith(contentHash: contentHash);
  }

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
        if (doc.authors.isEmpty)
          doc = doc.copyWith(authors: titleSplit.authors);
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
            metadataOnly: true,
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

  String _newDocumentId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}

final documentsProvider =
    StateNotifierProvider<DocumentsNotifier, List<Document>>((ref) {
      return DocumentsNotifier(GStorage.documents);
    });

final viewModeProvider = StateProvider<bool>((ref) => true);

final noFileDocsCountProvider = Provider<int>((ref) {
  return ref
      .watch(documentsProvider)
      .where((doc) => doc.contentHash == null)
      .length;
});

final noFileDocsProvider = Provider<List<Document>>((ref) {
  return ref
      .watch(documentsProvider)
      .where((doc) => doc.contentHash == null)
      .toList();
});

final validDocsProvider = Provider<List<Document>>((ref) {
  return ref
      .watch(documentsProvider)
      .where((doc) => doc.contentHash != null)
      .toList();
});

/// 过滤出尚未提取（尚未生成 .md 文件）的有效文献。
final unextractedDocsProvider = Provider<List<Document>>((ref) {
  return ref.watch(validDocsProvider).where((doc) {
    return !File(DocPaths.md(doc.id)).existsSync();
  }).toList();
});
