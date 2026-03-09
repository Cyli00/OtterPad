import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import '../services/identifier_resolver.dart';
import '../services/pdf_doi_extractor.dart';

/// addByIdentifier 的结果类型
enum AddByIdentifierResult { success, duplicate }

/// rebuild() 进度信息
class RebuildProgress {
  final int current;
  final int total;
  final String fileName;
  final String status;

  const RebuildProgress({
    required this.current,
    required this.total,
    required this.fileName,
    required this.status,
  });
}

/// 文献库状态管理
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
        .map((e) => Document.fromJson(
            Map<String, dynamic>.from(jsonDecode(e as String))))
        .toList();

    // 自动清理：
    // 1. 旧版 asset 路径条目（已废弃，无法用 openFile 打开）
    // 2. 文件已不存在的条目（但保留 filePath 为空的纯元数据条目）
    final valid = docs.where((d) {
      if (d.filePath.isEmpty) return true;
      if (d.filePath.startsWith('assets/')) return false;
      return File(d.filePath).existsSync();
    }).toList();
    state = valid;

    if (valid.length != docs.length) {
      _save();
    }
  }

  Future<void> _save() async {
    final encoded = state.map((d) => jsonEncode(d.toJson())).toList();
    await _box.put('documents', encoded);
  }

  /// 获取文献存储目录
  static Future<Directory> getDocsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final docsDir = Directory(p.join(appDir.path, 'NightReader', 'docs'));
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    return docsDir;
  }

  /// 从文件名解析基础元数据（最后兜底）
  /// 支持格式: "YYYY-Authors-Title.pdf"
  static ({String title, List<String> authors, String? year}) _parseFileName(
      String filePath) {
    final baseName = p.basenameWithoutExtension(filePath);
    final parts = baseName.split('-');

    if (parts.length >= 3) {
      final yearCandidate = parts[0].trim();
      final authorPart = parts[1].trim();
      final titlePart = parts.sublist(2).join('-').trim();

      if (RegExp(r'^\d{4}$').hasMatch(yearCandidate) &&
          titlePart.isNotEmpty) {
        return (title: titlePart, authors: [authorPart], year: yearCandidate);
      }
    }

    return (title: baseName, authors: <String>[], year: null);
  }

  /// 对单个文档执行元数据修复: PDF DOI 提取 → CrossRef 解析 → 重命名 → 文件名兜底
  Future<Document> _repairDocument(Document doc, {CancelToken? cancelToken}) async {
    try {
      final doi = await PdfDoiExtractor.instance.extractDoi(doc.filePath);
      if (doi == null) {
        final parsed = _parseFileName(doc.filePath);
        if (parsed.authors.isNotEmpty || parsed.year != null) {
          return doc.copyWith(
            title: parsed.title,
            authors: parsed.authors,
            year: parsed.year,
          );
        }
        return doc;
      }

      final resolved = await IdentifierResolver.instance.resolve(doi, cancelToken: cancelToken);
      doc = doc.copyWith(
        itemType: resolved.itemType,
        title: resolved.title,
        authors: resolved.authors,
        journal: resolved.journal,
        journalAbbr: resolved.journalAbbr,
        publisher: resolved.publisher,
        volume: resolved.volume,
        issue: resolved.issue,
        pages: resolved.pages,
        year: resolved.year,
        date: resolved.date,
        doi: resolved.doi,
        pmid: resolved.pmid,
        pmcid: resolved.pmcid,
        arxivId: resolved.arxivId,
        isbn: resolved.isbn,
        issn: resolved.issn,
        url: resolved.url,
        abstractText: resolved.abstractText,
        language: resolved.language,
      );

      // 自动重命名
      try {
        final newName = IdentifierResolver.buildPdfFileName(
          year: doc.year,
          authors: doc.authors,
          title: doc.title,
          fallbackId: p.basenameWithoutExtension(doc.filePath),
        );

        final dir = p.dirname(doc.filePath);
        var newPath = p.join(dir, newName);

        if (newPath != doc.filePath) {
          if (await File(newPath).exists()) {
            final nameWithoutExt = p.basenameWithoutExtension(newName);
            int counter = 2;
            while (await File(newPath).exists()) {
              newPath = p.join(dir, '$nameWithoutExt ($counter).pdf');
              counter++;
            }
          }
          await File(doc.filePath).rename(newPath);
          doc = doc.copyWith(filePath: newPath);
        }
      } catch (e) {
        debugPrint('重命名失败: $e');
      }

      return doc;
    } catch (e) {
      debugPrint('元数据修复失败: $e');
      final parsed = _parseFileName(doc.filePath);
      if (parsed.authors.isNotEmpty || parsed.year != null) {
        return doc.copyWith(
          title: parsed.title,
          authors: parsed.authors,
          year: parsed.year,
        );
      }
      return doc;
    }
  }

  /// 添加用户选择的文件（复制到应用目录，立即解析元数据）
  Future<Document?> addFile(String sourcePath, {CancelToken? cancelToken}) async {
    final file = File(sourcePath);
    if (!await file.exists()) return null;

    final docsDir = await getDocsDir();
    final fileName = p.basename(sourcePath);
    final destPath = p.join(docsDir.path, fileName);

    // 避免重复导入
    if (state.any((d) => d.filePath == destPath)) return null;

    await file.copy(destPath);

    var doc = Document(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: p.basenameWithoutExtension(destPath),
      authors: [],
      filePath: destPath,
      addedAt: DateTime.now(),
    );

    // 先加入 state，让 UI 立即显示条目
    state = [...state, doc];

    // 立即修复元数据（DOI 提取 → CrossRef → 重命名 → 文件名兜底）
    doc = await _repairDocument(doc, cancelToken: cancelToken);
    state = [
      for (final d in state)
        if (d.id == doc.id) doc else d,
    ];
    await _save();
    return doc;
  }

  /// 通过标识符添加文献（DOI / PMID / arXiv ID / ISBN）
  ///
  /// 返回 (Document, AddByIdentifierResult) 或抛出 IdentifierResolveException
  Future<(Document, AddByIdentifierResult)> addByIdentifier(
      String identifier, {CancelToken? cancelToken}) async {
    final doc = await IdentifierResolver.instance.resolve(identifier, cancelToken: cancelToken);

    // 去重检查
    final isDuplicate = state.any((d) {
      if (doc.doi != null && doc.doi!.isNotEmpty && d.doi == doc.doi) {
        return true;
      }
      if (doc.pmid != null && doc.pmid!.isNotEmpty && d.pmid == doc.pmid) {
        return true;
      }
      if (doc.arxivId != null &&
          doc.arxivId!.isNotEmpty &&
          d.arxivId == doc.arxivId) {
        return true;
      }
      if (doc.isbn != null && doc.isbn!.isNotEmpty && d.isbn == doc.isbn) {
        return true;
      }
      return false;
    });

    if (isDuplicate) {
      return (doc, AddByIdentifierResult.duplicate);
    }

    state = [...state, doc];
    await _save();
    return (doc, AddByIdentifierResult.success);
  }

  /// 判断文献是否需要元数据修复（有标识符说明已通过 API 获取过完整数据）
  bool _needsMetadataRepair(Document doc) {
    if (doc.filePath.isEmpty) return false;
    if (doc.doi != null && doc.doi!.isNotEmpty) return false;
    if (doc.pmid != null && doc.pmid!.isNotEmpty) return false;
    if (doc.arxivId != null && doc.arxivId!.isNotEmpty) return false;
    if (doc.isbn != null && doc.isbn!.isNotEmpty) return false;
    return true;
  }

  /// 重构文库：扫描新文件、清理缺失文件、自动补全元数据并重命名
  Future<void> rebuild({
    void Function(RebuildProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final docsDir = await getDocsDir();
    final existingPaths = state.map((d) => d.filePath).toSet();
    bool changed = false;

    // Phase A — 扫描新文件
    await for (final entity in docsDir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
        if (!existingPaths.contains(entity.path)) {
          final parsed = _parseFileName(entity.path);
          final doc = Document(
            id: '${DateTime.now().millisecondsSinceEpoch}_${entity.path.hashCode}',
            title: parsed.title,
            authors: parsed.authors,
            year: parsed.year,
            filePath: entity.path,
            addedAt: DateTime.now(),
          );
          state = [...state, doc];
          changed = true;
        }
      }
    }

    // Phase A — 清理缺失文件
    final validDocs = <Document>[];
    for (final doc in state) {
      if (doc.filePath.isEmpty || await File(doc.filePath).exists()) {
        validDocs.add(doc);
      } else {
        changed = true;
      }
    }
    if (changed) {
      state = validDocs;
    }

    // Phase B + C — 元数据修复 + 自动重命名
    final toRepair = state.where(_needsMetadataRepair).toList();
    for (int i = 0; i < toRepair.length; i++) {
      if (cancelToken?.isCancelled == true) break;
      final doc = toRepair[i];
      onProgress?.call(RebuildProgress(
        current: i + 1,
        total: toRepair.length,
        fileName: p.basename(doc.filePath),
        status: '正在修复元数据...',
      ));

      final repaired = await _repairDocument(doc, cancelToken: cancelToken);
      state = [
        for (final d in state)
          if (d.id == doc.id) repaired else d,
      ];
    }

    await _save();
  }

  /// 更新文献元数据
  Future<void> update(
    String id, {
    String? itemType,
    String? title,
    List<String>? authors,
    String? journal,
    String? journalAbbr,
    String? publisher,
    String? volume,
    String? issue,
    String? pages,
    String? year,
    String? date,
    String? doi,
    String? pmid,
    String? pmcid,
    String? arxivId,
    String? isbn,
    String? issn,
    String? url,
    String? abstractText,
    String? language,
  }) async {
    state = [
      for (final d in state)
        if (d.id == id)
          d.copyWith(
            itemType: itemType,
            title: title,
            authors: authors,
            journal: journal,
            journalAbbr: journalAbbr,
            publisher: publisher,
            volume: volume,
            issue: issue,
            pages: pages,
            year: year,
            date: date,
            doi: doi,
            pmid: pmid,
            pmcid: pmcid,
            arxivId: arxivId,
            isbn: isbn,
            issn: issn,
            url: url,
            abstractText: abstractText,
            language: language,
          )
        else
          d,
    ];
    await _save();
  }

  /// 删除文献
  Future<void> delete(String id) async {
    state = state.where((d) => d.id != id).toList();
    await _save();
  }
}

final documentsProvider =
    StateNotifierProvider<DocumentsNotifier, List<Document>>((ref) {
  return DocumentsNotifier(GStorage.documents);
});

/// 视图模式：true=网格，false=列表
final viewModeProvider = StateProvider<bool>((ref) => true);
