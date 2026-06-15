import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import 'backup_restore_service.dart';

/// 单篇文献的备份指纹，三个维度分开存以便区分变更原因：
/// [content] = PDF 内容（contentHash）；[meta] = 元数据 + 批注；
/// [files] = 文献目录内数据文件（translations.json / chats…）的签名。
class DocFingerprint {
  final String content;
  final String meta;
  final String files;

  const DocFingerprint({
    required this.content,
    required this.meta,
    required this.files,
  });

  bool sameAs(DocFingerprint other) =>
      content == other.content && meta == other.meta && files == other.files;

  Map<String, dynamic> toJson() => {'c': content, 'm': meta, 'f': files};

  factory DocFingerprint.fromJson(Map<String, dynamic> json) => DocFingerprint(
    content: json['c'] as String? ?? '',
    meta: json['m'] as String? ?? '',
    files: json['f'] as String? ?? '',
  );
}

/// 一次成功备份的快照：何时、何范围、备到哪、当时每篇文献的指纹。
class BackupSnapshot {
  final DateTime at;
  final BackupScope scope;
  final String remote;
  final String device;
  final Map<String, DocFingerprint> docs;

  const BackupSnapshot({
    required this.at,
    required this.scope,
    required this.remote,
    required this.device,
    required this.docs,
  });

  Map<String, dynamic> toJson() => {
    'v': 1,
    'at': at.toIso8601String(),
    'scope': scope.name,
    'remote': remote,
    'device': device,
    'docs': {for (final e in docs.entries) e.key: e.value.toJson()},
  };

  static BackupSnapshot? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    final rawDocs = json['docs'];
    return BackupSnapshot(
      at: at,
      scope: BackupScope.values.asNameMap()[json['scope']] ?? BackupScope.full,
      remote: json['remote'] as String? ?? '',
      device: json['device'] as String? ?? '',
      docs: {
        if (rawDocs is Map<String, dynamic>)
          for (final e in rawDocs.entries)
            if (e.value is Map<String, dynamic>)
              e.key: DocFingerprint.fromJson(e.value as Map<String, dynamic>),
      },
    );
  }
}

/// 备份指纹清单——「上次备份了什么」的唯一记录。
///
/// 备份成功时由 BackupOrchestrator 落一份快照到 settings box；云同步
/// 状态（已同步 / 有变更 / 从未备份）由「现算指纹 vs 快照」纯本地比对
/// 得出，不发网络请求。这是 ZIP 全量备份模式能诚实表达的语义：状态指
/// 「相对上次备份是否有变化」，而非远端逐文件对齐。
class BackupFingerprintService {
  BackupFingerprintService._();

  static const _storageKey = 'last_backup_snapshot';

  /// 计算全部文献的当前指纹。只 stat 不读文件内容，百级文献量为
  /// 毫秒级 IO；PDF 内容维度直接复用导入时算好的 [Document.contentHash]。
  static Future<Map<String, DocFingerprint>> compute(
    List<Document> docs,
  ) async {
    final result = <String, DocFingerprint>{};
    for (final doc in docs) {
      final highlightsJson = GStorage.highlights.get(doc.id) as String? ?? '';
      final meta = _sha256Text(
        '${jsonEncode(doc.toJson())}\x00$highlightsJson',
      );
      result[doc.id] = DocFingerprint(
        content: doc.contentHash ?? '',
        meta: meta,
        files: await _dirSignature(doc.id),
      );
    }
    return result;
  }

  /// 文献目录内「会被备份的数据文件」的 (路径, 大小, mtime) 聚合 hash。
  /// 过滤规则与 dataOnly 打包共用（includeInDataOnly），保证状态显示与
  /// 实际备份内容一致。目录不存在（无文件条目）返回空串。
  static Future<String> _dirSignature(String documentId) async {
    final dir = Directory(p.join(GStorage.libraryDirPath, documentId));
    if (!await dir.exists()) return '';
    final lines = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: GStorage.libraryDirPath)
          .replaceAll('\\', '/');
      if (!BackupRestoreService.includeInDataOnly(relative)) continue;
      final stat = await entity.stat();
      lines.add(
        '$relative\x00${stat.size}\x00${stat.modified.millisecondsSinceEpoch}',
      );
    }
    if (lines.isEmpty) return '';
    lines.sort();
    return _sha256Text(lines.join('\n'));
  }

  static Future<void> saveSnapshot(BackupSnapshot snapshot) =>
      GStorage.setting.put(_storageKey, jsonEncode(snapshot.toJson()));

  static BackupSnapshot? loadSnapshot() {
    final raw = GStorage.setting.get(_storageKey) as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      return BackupSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static String _sha256Text(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
