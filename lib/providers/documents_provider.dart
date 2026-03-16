import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import '../services/document_metadata_parser.dart';
import '../services/identifier_resolver.dart';
import '../services/pdf_identifier_extractor.dart';
import '../services/pdf_metadata_extractor.dart';
import '../services/pdf_thumbnail_service.dart';

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

    final docs = raw
        .map(
          (entry) => Document.fromJson(
            Map<String, dynamic>.from(jsonDecode(entry as String)),
          ),
        )
        .toList();

    final validDocs = docs.where((doc) {
      if (doc.filePath.isEmpty) return true;
      if (doc.filePath.startsWith('assets/')) return false;
      return File(doc.filePath).existsSync();
    }).toList();

    state = validDocs;
    if (validDocs.length != docs.length) {
      _save();
    }
  }

  Future<void> _save() async {
    final encoded = state.map((doc) => jsonEncode(doc.toJson())).toList();
    await _box.put('documents', encoded);
  }

  static Future<Directory> getDocsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final docsDir = Directory(p.join(appDir.path, 'NightReader', 'docs'));
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    return docsDir;
  }

  Future<AddFileResult> addFile(
    String sourcePath, {
    CancelToken? cancelToken,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return const AddFileResult(type: AddFileResultType.duplicate);
    }

    final docsDir = await getDocsDir();
    final normalizedSourcePath = p.normalize(sourcePath);
    final existingDoc = state.cast<Document?>().firstWhere(
      (doc) => doc != null && p.normalize(doc.filePath) == normalizedSourcePath,
      orElse: () => null,
    );
    if (existingDoc != null) {
      return AddFileResult(
        type: AddFileResultType.duplicate,
        document: existingDoc,
      );
    }

    final destPath = await _buildUniqueDestinationPath(
      docsDir.path,
      p.basename(sourcePath),
    );
    if (p.normalize(sourcePath) == p.normalize(destPath)) {
      return AddFileResult(
        type: AddFileResultType.duplicate,
        document: state.cast<Document?>().firstWhere(
          (doc) =>
              doc != null && p.normalize(doc.filePath) == p.normalize(destPath),
          orElse: () => null,
        ),
      );
    }

    await sourceFile.copy(destPath);

    final initialMetadata = DocumentMetadataParser.parseFilePath(destPath);
    var doc = Document(
      id: _newId(destPath),
      title: initialMetadata.title ?? p.basenameWithoutExtension(destPath),
      authors: initialMetadata.authors,
      journal: initialMetadata.journal,
      year: initialMetadata.year,
      doi: initialMetadata.doi,
      filePath: destPath,
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

    unawaited(PdfThumbnailService.instance.getThumbnailPath(doc.filePath));

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
      cancelToken: cancelToken,
    );

    final duplicate = state.any((doc) => _isDuplicateDocument(doc, resolved));
    if (duplicate) {
      return (resolved, AddByIdentifierResult.duplicate);
    }

    state = [...state, resolved];
    await _save();
    if (resolved.filePath.isNotEmpty) {
      unawaited(
        PdfThumbnailService.instance.getThumbnailPath(resolved.filePath),
      );
    }
    return (resolved, AddByIdentifierResult.success);
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
      const RebuildProgress(
        fileName: 'NightReader 文库',
        status: '正在扫描 PDF 文件...',
      ),
    );

    final pdfFiles = <File>[];
    await for (final entity in docsDir.list()) {
      if (cancelToken?.isCancelled == true) break;
      if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
        pdfFiles.add(entity);
      }
    }

    final knownPaths = state
        .where((doc) => doc.filePath.isNotEmpty)
        .map((doc) => p.normalize(doc.filePath))
        .toSet();

    for (final file in pdfFiles) {
      if (cancelToken?.isCancelled == true) break;
      final normalizedPath = p.normalize(file.path);
      if (knownPaths.contains(normalizedPath)) continue;

      final initialMetadata = DocumentMetadataParser.parseFilePath(file.path);
      state = [
        ...state,
        Document(
          id: _newId(file.path),
          title: initialMetadata.title ?? p.basenameWithoutExtension(file.path),
          authors: initialMetadata.authors,
          journal: initialMetadata.journal,
          year: initialMetadata.year,
          doi: initialMetadata.doi,
          filePath: file.path,
          addedAt: DateTime.now(),
        ),
      ];
      knownPaths.add(normalizedPath);
      addedCount++;
    }

    onProgress?.call(
      const RebuildProgress(fileName: 'NightReader 文库', status: '正在检查文件完整性...'),
    );

    final validDocs = <Document>[];
    for (final doc in state) {
      if (doc.filePath.isEmpty || await File(doc.filePath).exists()) {
        validDocs.add(doc);
        continue;
      }

      removedCount++;
      if (!_isBlank(doc.doi)) {
        validDocs.add(doc.copyWith(filePath: ''));
      }
    }
    state = validDocs;

    final toDownload = state
        .where((doc) => doc.filePath.isEmpty && !_isBlank(doc.doi))
        .toList();
    if (toDownload.isNotEmpty) {
      final updates = <String, Document>{};
      for (int i = 0; i < toDownload.length; i++) {
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

        try {
          final downloadedPath = await IdentifierResolver.instance
              .downloadPdfByDoi(
                doi: doc.doi!,
                year: doc.year,
                authors: doc.authors,
                title: doc.title,
                fallbackId: doc.id,
                cancelToken: cancelToken,
              );
          if (downloadedPath.isNotEmpty) {
            updates[doc.id] = doc.copyWith(filePath: downloadedPath);
            downloadedCount++;
            unawaited(
              PdfThumbnailService.instance.getThumbnailPath(downloadedPath),
            );
          }
        } catch (error) {
          debugPrint('根据 DOI 下载 PDF 失败: $error');
        }
      }

      if (updates.isNotEmpty) {
        state = [for (final doc in state) updates[doc.id] ?? doc];
      }
    }

    final toRepair = state.where(_needsMetadataRepair).toList();
    if (toRepair.isNotEmpty) {
      final updates = <String, Document>{};
      for (int i = 0; i < toRepair.length; i++) {
        if (cancelToken?.isCancelled == true) break;
        final doc = toRepair[i];
        onProgress?.call(
          RebuildProgress(
            current: i + 1,
            total: toRepair.length,
            fileName: p.basename(doc.filePath),
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

    final noFileCount = state.where((doc) => doc.filePath.isEmpty).length;
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

    final docsDir = await getDocsDir();
    final preferredName = IdentifierResolver.buildPdfFileName(
      year: existing.year,
      authors: existing.authors,
      title: existing.title,
      fallbackId: p.basenameWithoutExtension(sourcePath),
    );
    final destPath = await _buildUniqueDestinationPath(
      docsDir.path,
      preferredName,
    );

    final sourceFile = File(sourcePath);
    if (p.normalize(sourcePath) == p.normalize(destPath)) {
      state = [
        for (final doc in state)
          if (doc.id == docId) doc.copyWith(filePath: destPath) else doc,
      ];
      await _save();
      return;
    }

    if (p.normalize(p.dirname(sourcePath)) == p.normalize(docsDir.path)) {
      await sourceFile.rename(destPath);
    } else {
      await sourceFile.copy(destPath);
    }

    var updated = existing.copyWith(filePath: destPath);
    if (_needsMetadataRepair(updated)) {
      updated = (await _repairDocument(updated)).document;
    }

    state = [
      for (final doc in state)
        if (doc.id == docId) updated else doc,
    ];
    await _save();
    unawaited(PdfThumbnailService.instance.getThumbnailPath(updated.filePath));
  }

  Future<bool> redownloadPdf(String docId, {CancelToken? cancelToken}) async {
    final doc = state.cast<Document?>().firstWhere(
      (entry) => entry != null && entry.id == docId,
      orElse: () => null,
    );
    if (doc == null || _isBlank(doc.doi)) return false;

    try {
      final downloadedPath = await IdentifierResolver.instance.downloadPdfByDoi(
        doi: doc.doi!,
        year: doc.year,
        authors: doc.authors,
        title: doc.title,
        fallbackId: doc.id,
        cancelToken: cancelToken,
      );
      if (downloadedPath.isEmpty) return false;

      state = [
        for (final entry in state)
          if (entry.id == docId)
            entry.copyWith(filePath: downloadedPath)
          else
            entry,
      ];
      await _save();
      unawaited(PdfThumbnailService.instance.getThumbnailPath(downloadedPath));
      return true;
    } catch (error) {
      debugPrint('重新下载 PDF 失败: $error');
      return false;
    }
  }

  Future<void> delete(String id) async {
    final doc = state.cast<Document?>().firstWhere(
      (entry) => entry != null && entry.id == id,
      orElse: () => null,
    );
    if (doc != null && doc.filePath.isNotEmpty) {
      final filePath = doc.filePath;
      try {
        final file = File(filePath);
        if (await file.exists()) await file.delete();

        final basePath = p.withoutExtension(filePath);
        for (final ext in ['.md', '.html']) {
          final artifact = File('$basePath$ext');
          if (await artifact.exists()) await artifact.delete();
        }
        final imagesDir = Directory('${basePath}_images');
        if (await imagesDir.exists()) {
          await imagesDir.delete(recursive: true);
        }

        await PdfThumbnailService.instance.deleteCacheEntry(filePath);
      } catch (error) {
        debugPrint('删除文件失败: $error');
      }
    }

    state = state.where((doc) => doc.id != id).toList();
    await _save();
  }

  Future<_MetadataRepairResult> _repairDocument(
    Document doc, {
    CancelToken? cancelToken,
  }) async {
    final original = doc;

    try {
      final fallbackMetadata = DocumentMetadataParser.parseFilePath(
        doc.filePath,
      );
      final pdfMetadata = await PdfMetadataExtractor.instance.extract(
        doc.filePath,
      );
      final combinedMetadata = fallbackMetadata.merge(pdfMetadata);
      doc = _applyMetadata(doc, combinedMetadata);

      final identifier =
          combinedMetadata.doi ??
          (await PdfIdentifierExtractor.instance.extractIdentifier(
            doc.filePath,
          ))?.value;
      if (!_isBlank(identifier)) {
        final resolved = await IdentifierResolver.instance.resolve(
          identifier!,
          metadataOnly: true,
          cancelToken: cancelToken,
        );
        doc = _applyResolvedDocument(doc, resolved);
      }

      doc = await _renameFileFromMetadata(doc);
    } catch (error) {
      debugPrint('元数据修复失败: $error');
      doc = _applyMetadata(
        doc,
        DocumentMetadataParser.parseFilePath(doc.filePath),
      );
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
    if (doc.filePath.isEmpty) return false;
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
    for (int i = 0; i < left.authors.length; i++) {
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
    if (doc.filePath.isEmpty) return false;
    final normalizedTitle = _normalizeComparisonKey(doc.title);
    final fileNameTitle = _normalizeComparisonKey(
      p.basenameWithoutExtension(doc.filePath),
    );
    return normalizedTitle.isEmpty || normalizedTitle == fileNameTitle;
  }

  Future<Document> _renameFileFromMetadata(Document doc) async {
    if (doc.filePath.isEmpty) return doc;

    final currentPath = p.normalize(doc.filePath);
    final currentName = p.basename(currentPath);
    final targetName = IdentifierResolver.buildPdfFileName(
      year: doc.year,
      authors: doc.authors,
      title: doc.title,
      fallbackId: p.basenameWithoutExtension(currentName),
    );
    if (currentName == targetName) return doc;

    final directory = p.dirname(currentPath);
    var targetPath = p.join(directory, targetName);
    if (p.normalize(targetPath) == currentPath) return doc;

    if (await File(targetPath).exists()) {
      final baseName = p.basenameWithoutExtension(targetName);
      var counter = 2;
      while (await File(targetPath).exists()) {
        targetPath = p.join(directory, '$baseName ($counter).pdf');
        counter++;
      }
    }

    await File(doc.filePath).rename(targetPath);
    await PdfThumbnailService.instance.migrateCacheEntry(
      doc.filePath,
      targetPath,
    );
    return doc.copyWith(filePath: targetPath);
  }

  Future<String> _buildUniqueDestinationPath(
    String directory,
    String preferredName,
  ) async {
    final extension = p.extension(preferredName).isEmpty
        ? '.pdf'
        : p.extension(preferredName);
    final baseName = p.basenameWithoutExtension(preferredName);
    var candidate = p.join(directory, '$baseName$extension');
    var counter = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(directory, '$baseName ($counter)$extension');
      counter++;
    }
    return candidate;
  }

  String _newId(String seed) {
    return '${DateTime.now().microsecondsSinceEpoch}_${seed.hashCode.abs()}';
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
}

final documentsProvider =
    StateNotifierProvider<DocumentsNotifier, List<Document>>((ref) {
      return DocumentsNotifier(GStorage.documents);
    });

final viewModeProvider = StateProvider<bool>((ref) => true);

final noFileDocsCountProvider = Provider<int>((ref) {
  return ref
      .watch(documentsProvider)
      .where((doc) => doc.filePath.isEmpty)
      .length;
});

final noFileDocsProvider = Provider<List<Document>>((ref) {
  return ref
      .watch(documentsProvider)
      .where((doc) => doc.filePath.isEmpty)
      .toList();
});

final validDocsProvider = Provider<List<Document>>((ref) {
  return ref
      .watch(documentsProvider)
      .where((doc) => doc.filePath.isNotEmpty)
      .toList();
});

/// 过滤出尚未提取（尚未生成 .html 文件）的有效文档，供批量提取页面使用
final unextractedDocsProvider = Provider<List<Document>>((ref) {
  return ref.watch(validDocsProvider).where((doc) {
    if (doc.filePath.isEmpty) return false;
    final htmlPath = '${p.withoutExtension(doc.filePath)}.html';
    return !File(htmlPath).existsSync();
  }).toList();
});
