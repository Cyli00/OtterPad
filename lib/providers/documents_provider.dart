import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import '../services/document_metadata_parser.dart';
import '../services/identifier_resolver.dart';
import '../services/pdf_identifier_extractor.dart';
import '../services/pdf_metadata_extractor.dart';
import '../services/pdf_thumbnail_service.dart';
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
  final int downloadedCount;
  final int repairedCount;
  final int unresolvedCount;
  final int noFileCount;
  final bool cancelled;

  const RebuildResult({
    required this.addedCount,
    required this.removedCount,
    required this.downloadedCount,
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

    final duplicate = state.any((doc) => _isDuplicateDocument(doc, resolved));
    if (duplicate) {
      return (resolved, AddByIdentifierResult.duplicate);
    }

    var doc = resolved.copyWith(id: _newDocumentId(), contentHash: null);

    if (!_isBlank(doc.doi)) {
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

  Future<RebuildResult> rebuild({
    void Function(RebuildProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final docsDir = await getDocsDir();
    var addedCount = 0;
    var removedCount = 0;
    var downloadedCount = 0;
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

    final toDownload = state
        .where((doc) => doc.contentHash == null && !_isBlank(doc.doi))
        .toList();
    if (toDownload.isNotEmpty) {
      final updates = <String, Document>{};
      for (var i = 0; i < toDownload.length; i++) {
        if (cancelToken?.isCancelled == true) break;
        final doc = toDownload[i];
        onProgress?.call(
          RebuildProgress(
            current: i + 1,
            total: toDownload.length,
            fileName: doc.title,
            status: '正在根据 DOI 补回 PDF...',
          ),
        );
        final downloaded = await _downloadPdfIntoDocument(
          doc,
          cancelToken: cancelToken,
        );
        if (downloaded != null) {
          updates[doc.id] = downloaded;
          downloadedCount++;
          unawaited(
            PdfThumbnailService.instance.getThumbnailPath(DocPaths.pdf(doc.id)),
          );
        }
      }
      if (updates.isNotEmpty) {
        state = [for (final doc in state) updates[doc.id] ?? doc];
      }
    }

    final toRepair = state.where(_needsMetadataRepair).toList();
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
    final unresolvedCount = state.where(_needsMetadataRepair).length;

    return RebuildResult(
      addedCount: addedCount,
      removedCount: removedCount,
      downloadedCount: downloadedCount,
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
    if (_needsMetadataRepair(updated)) {
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
    final doc = state.cast<Document?>().firstWhere(
      (entry) => entry != null && entry.id == docId,
      orElse: () => null,
    );
    if (doc == null || _isBlank(doc.doi)) return false;

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

      final updated = doc.copyWith(contentHash: newHash);
      state = [
        for (final entry in state)
          if (entry.id == docId) updated else entry,
      ];
      await _save();
      unawaited(PdfThumbnailService.instance.getThumbnailPath(pdfPath));
      return true;
    } catch (error) {
      debugPrint('重新下载 PDF 失败: $error');
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
        debugPrint('删除文件失败: $error');
      }
    }

    state = state.where((doc) => doc.id != id).toList();
    await _save();
  }

  Future<Document?> _downloadPdfIntoDocument(
    Document doc, {
    CancelToken? cancelToken,
  }) async {
    if (_isBlank(doc.doi)) return null;
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
        debugPrint('清理派生文件失败 ${entity.path}: $e');
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
      final combinedMetadata = fallbackMetadata.merge(pdfMetadata);
      doc = _applyMetadata(doc, combinedMetadata);

      final identifier =
          combinedMetadata.doi ??
          (await PdfIdentifierExtractor.instance.extractIdentifier(
            pdfPath,
          ))?.value;
      if (!_isBlank(identifier)) {
        final resolved = await IdentifierResolver.instance.resolve(
          identifier!,
          metadataOnly: true,
          cancelToken: cancelToken,
        );
        doc = _applyResolvedDocument(doc, resolved);
      }
    } catch (error) {
      debugPrint('元数据修复失败: $error');
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
    final title = _normalizeMetadataValue(metadata.title);
    final journal = _normalizeMetadataValue(metadata.journal);
    final year = _normalizeMetadataValue(metadata.year);
    final doi = _normalizeMetadataValue(metadata.doi)?.toLowerCase();

    return doc.copyWith(
      title: title ?? doc.title,
      authors: metadata.authors.isNotEmpty ? metadata.authors : doc.authors,
      journal: journal ?? doc.journal,
      year: year ?? doc.year,
      doi: doi ?? doc.doi,
    );
  }

  bool _needsMetadataRepair(Document doc) {
    if (doc.contentHash == null) return false;
    return _looksLikePlaceholderTitle(doc) ||
        doc.authors.isEmpty ||
        _isBlank(doc.year) ||
        (_isBlank(doc.journal) && _isBlank(doc.doi));
  }

  bool _hasCompleteMetadata(Document doc) {
    return !_looksLikePlaceholderTitle(doc) &&
        doc.authors.isNotEmpty &&
        !_isBlank(doc.year) &&
        (!_isBlank(doc.journal) || !_isBlank(doc.doi));
  }

  MetadataStatus _metadataStatus(Document before, Document after) {
    if (_sameCoreMetadata(before, after)) return MetadataStatus.none;
    return _hasCompleteMetadata(after)
        ? MetadataStatus.complete
        : MetadataStatus.partial;
  }

  bool _sameCoreMetadata(Document left, Document right) {
    if (_normalizeMetadataValue(left.title) !=
        _normalizeMetadataValue(right.title)) {
      return false;
    }
    if (_normalizeMetadataValue(left.journal) !=
        _normalizeMetadataValue(right.journal)) {
      return false;
    }
    if (_normalizeMetadataValue(left.year) !=
        _normalizeMetadataValue(right.year)) {
      return false;
    }
    if (_normalizeMetadataValue(left.doi) !=
        _normalizeMetadataValue(right.doi)) {
      return false;
    }
    if (left.authors.length != right.authors.length) return false;
    for (var i = 0; i < left.authors.length; i++) {
      if (_normalizeMetadataValue(left.authors[i]) !=
          _normalizeMetadataValue(right.authors[i])) {
        return false;
      }
    }
    return true;
  }

  bool _isDuplicateDocument(Document existing, Document candidate) {
    if (!_isBlank(existing.doi) && !_isBlank(candidate.doi)) {
      return existing.doi!.toLowerCase() == candidate.doi!.toLowerCase();
    }

    final normalizedTitle = _normalizeComparisonKey(existing.title);
    final candidateTitle = _normalizeComparisonKey(candidate.title);
    if (normalizedTitle.isEmpty ||
        candidateTitle.isEmpty ||
        normalizedTitle != candidateTitle) {
      return false;
    }

    final existingYear = _normalizeComparisonKey(existing.year);
    final candidateYear = _normalizeComparisonKey(candidate.year);
    if (existingYear.isNotEmpty &&
        candidateYear.isNotEmpty &&
        existingYear == candidateYear) {
      return true;
    }

    final existingAuthor = existing.authors.isEmpty
        ? ''
        : _normalizeComparisonKey(existing.authors.first);
    final candidateAuthor = candidate.authors.isEmpty
        ? ''
        : _normalizeComparisonKey(candidate.authors.first);
    return existingAuthor.isNotEmpty && existingAuthor == candidateAuthor;
  }

  bool _looksLikePlaceholderTitle(Document doc) {
    final normalizedTitle = _normalizeComparisonKey(doc.title);
    if (normalizedTitle.isEmpty) return true;
    return normalizedTitle == _normalizeComparisonKey(doc.id);
  }

  String _normalizeComparisonKey(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String? _normalizeMetadataValue(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  bool _isBlank(String? value) {
    return value == null || value.trim().isEmpty;
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
