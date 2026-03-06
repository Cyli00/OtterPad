import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/storage/storage.dart';
import '../data/models/book/document.dart';

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
    // 2. 文件已不存在的条目
    final valid = docs.where((d) {
      if (d.filePath.isEmpty) return false;
      if (d.filePath.startsWith('assets/')) return false;
      return File(d.filePath).existsSync();
    }).toList();
    state = valid;

    if (valid.length != docs.length) {
      _save(); // 回写，清除失效条目
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

  /// 添加用户选择的文件（复制到应用目录）
  Future<Document?> addFile(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) return null;

    final docsDir = await getDocsDir();
    final fileName = p.basename(sourcePath);
    final destPath = p.join(docsDir.path, fileName);

    // 避免重复导入
    if (state.any((d) => d.filePath == destPath)) return null;

    await file.copy(destPath);

    final doc = Document(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: fileName.replaceAll('.pdf', ''),
      authors: [],
      filePath: destPath,
      addedAt: DateTime.now(),
    );

    state = [...state, doc];
    await _save();
    return doc;
  }

  /// 通过标识符添加文献（DOI / PMID / arXiv ID）
  ///
  /// TODO: 接入 CrossRef / PubMed / arXiv API 解析元数据并下载 PDF
  Future<Document?> addByIdentifier(String identifier) async {
    // 标识符解析功能尚未实现
    return null;
  }

  /// 重构文库：扫描本地目录，同步文献列表
  Future<void> rebuild() async {
    final docsDir = await getDocsDir();
    final existingPaths = state.map((d) => d.filePath).toSet();
    bool changed = false;

    // 添加目录中存在但列表中没有的文件
    await for (final entity in docsDir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
        if (!existingPaths.contains(entity.path)) {
          final fileName = p.basenameWithoutExtension(entity.path);
          final doc = Document(
            id: '${DateTime.now().millisecondsSinceEpoch}_${entity.path.hashCode}',
            title: fileName,
            authors: [],
            filePath: entity.path,
            addedAt: DateTime.now(),
          );
          state = [...state, doc];
          changed = true;
        }
      }
    }

    // 移除文件已不存在的条目
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
      await _save();
    }
  }

  /// 更新文献元数据
  Future<void> update(
    String id, {
    String? title,
    List<String>? authors,
    String? journal,
    String? year,
    String? doi,
  }) async {
    state = [
      for (final d in state)
        if (d.id == id)
          d.copyWith(
            title: title,
            authors: authors,
            journal: journal,
            year: year,
            doi: doi,
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
