import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/secure_credential_vault.dart';
import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import '../data/models/book/highlight.dart';
import '../data/models/collection/favorite.dart';
import '../providers/history_provider.dart';
import 'backup_restore_service.dart';

/// 备份合并服务：将备份数据与本地数据合并（增量同步），而非覆盖。
///
/// 核心策略：按 ID 去重、只添加不存在的数据，不做版本比较。
/// 参考 kelivo 的 merge 模式设计，适配 OtterPad 的 Hive + JSON 存储模型。
class BackupMergeService {
  static const _mergePrefix = '_merge_';

  static const _localOnlySettingsKeys = {
    'proxy_mode',
    'proxy_host',
    'proxy_port',
    'backup_remote_type',
    'backup_webdav_server_url',
    'backup_webdav_username',
    'backup_webdav_password',
    'backup_webdav_remote_dir',
    'backup_webdav_file_name',
    'backup_s3_endpoint',
    'backup_s3_region',
    'backup_s3_bucket',
    'backup_s3_access_key_id',
    'backup_s3_secret_access_key',
    'backup_s3_object_key',
    'backup_s3_use_path_style',
  };

  static Future<MergeResult> merge({
    required Directory extractedDataDir,
    required Directory? extractedDocsDir,
    required BackupRestoreScope scope,
    void Function(String message)? onProgress,
  }) async {
    final mergeTempDir = await _createMergeTempDir();
    var stats = const MergeResult();

    try {
      final boxNames = _boxNamesForScope(scope);

      for (final name in boxNames) {
        final src = File(p.join(extractedDataDir.path, '$name.hive'));
        if (await src.exists()) {
          await src.copy(p.join(mergeTempDir.path, '$_mergePrefix$name.hive'));
        }
      }

      final backupBoxes = <String, Box>{};
      for (final name in boxNames) {
        final mergeFile = File(
          p.join(mergeTempDir.path, '$_mergePrefix$name.hive'),
        );
        if (await mergeFile.exists()) {
          backupBoxes[name] = await Hive.openBox(
            '$_mergePrefix$name',
            path: mergeTempDir.path,
          );
        }
      }

      try {
        if (scope.restoreLibrary) {
          if (backupBoxes.containsKey('documents')) {
            onProgress?.call('正在合并文献...');
            stats = stats.copyWith(
              documentsAdded: await _mergeDocuments(backupBoxes['documents']!),
            );
          }
          if (backupBoxes.containsKey('highlights')) {
            onProgress?.call('正在合并标注...');
            stats = stats.copyWith(
              highlightsAdded: await _mergeHighlights(
                backupBoxes['highlights']!,
              ),
            );
          }
          if (backupBoxes.containsKey('favorites')) {
            onProgress?.call('正在合并收藏夹...');
            await _mergeFavorites(backupBoxes['favorites']!);
          }
          if (backupBoxes.containsKey('history')) {
            onProgress?.call('正在合并阅读历史...');
            await _mergeHistory(backupBoxes['history']!);
          }
          if (extractedDocsDir != null) {
            onProgress?.call('正在合并文献文件...');
            stats = stats.copyWith(
              filesCopied: await _mergeLibraryFiles(extractedDocsDir),
            );
          }
        }

        if (scope.restoreSettings && backupBoxes.containsKey('settings')) {
          onProgress?.call('正在合并设置...');
          stats = stats.copyWith(
            settingsAdded: await _mergeSettings(backupBoxes['settings']!),
          );
        }

        if (scope == BackupRestoreScope.full &&
            backupBoxes.containsKey('zotero_sync')) {
          onProgress?.call('正在合并 Zotero 同步数据...');
          await _mergeZoteroSync(backupBoxes['zotero_sync']!);
        }
      } finally {
        for (final box in backupBoxes.values) {
          await box.close();
        }
      }
    } finally {
      if (await mergeTempDir.exists()) {
        await mergeTempDir.delete(recursive: true);
      }
    }

    await GStorage.flush();
    return stats;
  }

  // ─── Documents ──────────────────────────────────────────────────────────────

  static Future<int> _mergeDocuments(Box backupBox) async {
    final currentBox = GStorage.documents;

    final currentRaw = currentBox.get('documents') as List<dynamic>? ?? [];
    final currentDocs = currentRaw
        .map(
          (e) => Document.fromJson(
            Map<String, dynamic>.from(jsonDecode(e as String)),
          ),
        )
        .toList();

    final currentById = {for (final d in currentDocs) d.id: d};
    final currentByDoi = <String, Document>{};
    for (final d in currentDocs) {
      final doi = d.doi?.trim().toLowerCase();
      if (doi != null && doi.isNotEmpty) currentByDoi[doi] = d;
    }

    final backupRaw = backupBox.get('documents') as List<dynamic>? ?? [];
    final backupDocs = backupRaw
        .map(
          (e) => Document.fromJson(
            Map<String, dynamic>.from(jsonDecode(e as String)),
          ),
        )
        .toList();

    bool enriched = false;
    final additions = <Document>[];

    for (final bd in backupDocs) {
      if (currentById.containsKey(bd.id)) {
        final cd = currentById[bd.id]!;
        final result = _enrichDocument(cd, bd);
        if (!identical(result, cd)) {
          currentById[bd.id] = result;
          enriched = true;
        }
        continue;
      }

      final bdDoi = bd.doi?.trim().toLowerCase();
      if (bdDoi != null &&
          bdDoi.isNotEmpty &&
          currentByDoi.containsKey(bdDoi)) {
        continue;
      }

      if (_hasTitleMatch(currentDocs, additions, bd)) continue;

      additions.add(bd);
      if (bdDoi != null && bdDoi.isNotEmpty) currentByDoi[bdDoi] = bd;
    }

    if (enriched || additions.isNotEmpty) {
      final merged = [...currentById.values, ...additions];
      final encoded = merged.map((d) => jsonEncode(d.toJson())).toList();
      await currentBox.put('documents', encoded);
    }
    return additions.length;
  }

  static Document _enrichDocument(Document current, Document backup) {
    final enrichHash =
        current.contentHash == null && backup.contentHash != null;
    final enrichJournal =
        _isBlank(current.journal) && !_isBlank(backup.journal);
    final enrichYear = _isBlank(current.year) && !_isBlank(backup.year);
    final enrichDoi = _isBlank(current.doi) && !_isBlank(backup.doi);
    final enrichKeywords =
        current.keywords.isEmpty && backup.keywords.isNotEmpty;
    final enrichAuthors = current.authors.isEmpty && backup.authors.isNotEmpty;

    if (!enrichHash &&
        !enrichJournal &&
        !enrichYear &&
        !enrichDoi &&
        !enrichKeywords &&
        !enrichAuthors) {
      return current;
    }

    return Document(
      id: current.id,
      title: current.title,
      authors: enrichAuthors ? backup.authors : current.authors,
      journal: enrichJournal ? backup.journal : current.journal,
      year: enrichYear ? backup.year : current.year,
      doi: enrichDoi ? backup.doi : current.doi,
      keywords: enrichKeywords ? backup.keywords : current.keywords,
      contentHash: enrichHash ? backup.contentHash : current.contentHash,
      addedAt: current.addedAt,
    );
  }

  static bool _hasTitleMatch(
    List<Document> existingDocs,
    List<Document> pendingAdditions,
    Document candidate,
  ) {
    final candidateTitle = _normalizeKey(candidate.title);
    if (candidateTitle.isEmpty) return false;

    for (final existing in [...existingDocs, ...pendingAdditions]) {
      final existingTitle = _normalizeKey(existing.title);
      if (existingTitle != candidateTitle) continue;

      final eYear = _normalizeKey(existing.year);
      final cYear = _normalizeKey(candidate.year);
      if (eYear.isNotEmpty && cYear.isNotEmpty && eYear == cYear) return true;

      final eAuthor = existing.authors.isEmpty
          ? ''
          : _normalizeKey(existing.authors.first);
      final cAuthor = candidate.authors.isEmpty
          ? ''
          : _normalizeKey(candidate.authors.first);
      if (eAuthor.isNotEmpty && cAuthor.isNotEmpty && eAuthor == cAuthor) {
        return true;
      }
    }
    return false;
  }

  // ─── Highlights ─────────────────────────────────────────────────────────────

  static Future<int> _mergeHighlights(Box backupBox) async {
    final currentBox = GStorage.highlights;
    var added = 0;

    for (final key in backupBox.keys) {
      final backupRaw = backupBox.get(key) as String?;
      if (backupRaw == null) continue;

      final backupHighlights = (jsonDecode(backupRaw) as List<dynamic>)
          .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
          .toList();

      final currentRaw = currentBox.get(key) as String?;
      if (currentRaw == null) {
        await currentBox.put(key, backupRaw);
        added += backupHighlights.length;
        continue;
      }

      final currentHighlights = (jsonDecode(currentRaw) as List<dynamic>)
          .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
          .toList();
      final currentIds = currentHighlights.map((h) => h.id).toSet();

      final additions = backupHighlights
          .where((h) => !currentIds.contains(h.id))
          .toList();
      if (additions.isEmpty) continue;

      final merged = [...currentHighlights, ...additions];
      final json = jsonEncode(merged.map((h) => h.toJson()).toList());
      await currentBox.put(key, json);
      added += additions.length;
    }
    return added;
  }

  // ─── Favorites ──────────────────────────────────────────────────────────────

  static Future<void> _mergeFavorites(Box backupBox) async {
    final currentBox = GStorage.favorites;

    final currentRaw = currentBox.get('favorites') as List<dynamic>? ?? [];
    final currentFavs = currentRaw
        .map(
          (e) => Favorite.fromJson(
            Map<String, dynamic>.from(jsonDecode(e as String)),
          ),
        )
        .toList();
    final currentById = {for (final f in currentFavs) f.id: f};

    final backupRaw = backupBox.get('favorites') as List<dynamic>? ?? [];
    final backupFavs = backupRaw
        .map(
          (e) => Favorite.fromJson(
            Map<String, dynamic>.from(jsonDecode(e as String)),
          ),
        )
        .toList();

    bool changed = false;
    final additions = <Favorite>[];

    for (final bf in backupFavs) {
      if (currentById.containsKey(bf.id)) {
        final cf = currentById[bf.id]!;
        final existingIds = cf.documentIds.toSet();
        final newIds = bf.documentIds
            .where((id) => !existingIds.contains(id))
            .toList();
        if (newIds.isNotEmpty) {
          currentById[bf.id] = cf.copyWith(
            documentIds: [...cf.documentIds, ...newIds],
          );
          changed = true;
        }
      } else {
        additions.add(bf);
        changed = true;
      }
    }

    if (changed) {
      final merged = [...currentById.values, ...additions];
      merged.sort((a, b) {
        if (a.isDefault) return -1;
        if (b.isDefault) return 1;
        return 0;
      });
      final encoded = merged.map((f) => jsonEncode(f.toJson())).toList();
      await currentBox.put('favorites', encoded);
    }
  }

  // ─── History ────────────────────────────────────────────────────────────────

  static Future<void> _mergeHistory(Box backupBox) async {
    final currentBox = GStorage.history;

    final currentRaw = currentBox.get('entries') as List<dynamic>? ?? [];
    final currentEntries = currentRaw
        .map((e) => HistoryEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final byDocId = {for (final e in currentEntries) e.docId: e};

    final backupRaw = backupBox.get('entries') as List<dynamic>? ?? [];
    final backupEntries = backupRaw
        .map((e) => HistoryEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    bool changed = false;
    for (final be in backupEntries) {
      final ce = byDocId[be.docId];
      if (ce == null) {
        byDocId[be.docId] = be;
        changed = true;
      } else if (be.openedAt.isAfter(ce.openedAt)) {
        byDocId[be.docId] = be;
        changed = true;
      } else if (be.openedAt == ce.openedAt && be.progress > ce.progress) {
        byDocId[be.docId] = be;
        changed = true;
      }
    }

    if (changed) {
      final merged = byDocId.values.toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
      if (merged.length > 500) merged.removeRange(500, merged.length);
      await currentBox.put('entries', merged.map((e) => e.toMap()).toList());
    }
  }

  // ─── Settings ───────────────────────────────────────────────────────────────

  static Future<int> _mergeSettings(Box backupBox) async {
    final currentBox = GStorage.setting;
    var added = 0;

    for (final key in backupBox.keys) {
      if (key is! String) continue;
      if (_localOnlySettingsKeys.contains(key)) continue;
      // 凭据已迁出 Hive（见 SecureCredentialVault）：旧备份里可能残留明文 key，
      // 一律不导入，与"凭据不随备份迁移"的策略保持一致。
      if (SecureCredentialVault.isCredentialKey(key)) continue;
      if (currentBox.containsKey(key)) continue;

      await currentBox.put(key, backupBox.get(key));
      added++;
    }
    return added;
  }

  // ─── Zotero Sync ───────────────────────────────────────────────────────────

  static Future<void> _mergeZoteroSync(Box backupBox) async {
    final currentBox = GStorage.zoteroSync;

    final currentVersion =
        currentBox.get('_libraryVersion', defaultValue: 0) as int;
    final backupVersion =
        backupBox.get('_libraryVersion', defaultValue: 0) as int;
    if (backupVersion > currentVersion) {
      await currentBox.put('_libraryVersion', backupVersion);
    }

    for (final key in backupBox.keys) {
      if (key is! String || !key.startsWith('item:')) continue;
      if (currentBox.containsKey(key)) continue;
      await currentBox.put(key, backupBox.get(key));
    }
  }

  // ─── Library files ──────────────────────────────────────────────────────────

  static Future<int> _mergeLibraryFiles(Directory extractedDocsDir) async {
    if (!await extractedDocsDir.exists()) return 0;

    final libraryDir = Directory(GStorage.libraryDirPath);
    if (!await libraryDir.exists()) {
      await libraryDir.create(recursive: true);
    }

    var filesCopied = 0;

    await for (final entity in extractedDocsDir.list()) {
      if (entity is! Directory) continue;
      final docId = p.basename(entity.path);
      final targetDir = Directory(p.join(libraryDir.path, docId));

      if (!await targetDir.exists()) {
        await _copyDirectory(entity, targetDir);
        filesCopied += await _countFiles(entity);
      } else {
        filesCopied += await _copyMissingFiles(entity, targetDir);
      }
    }
    return filesCopied;
  }

  static Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: true)) {
      final relative = p.relative(entity.path, from: src.path);
      final targetPath = p.join(dst.path, relative);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(targetPath)).create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  static Future<int> _copyMissingFiles(Directory src, Directory dst) async {
    var copied = 0;
    await for (final entity in src.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: src.path);
      final targetFile = File(p.join(dst.path, relative));
      if (!await targetFile.exists()) {
        await Directory(p.dirname(targetFile.path)).create(recursive: true);
        await entity.copy(targetFile.path);
        copied++;
      }
    }
    return copied;
  }

  static Future<int> _countFiles(Directory dir) async {
    var count = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) count++;
    }
    return count;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  static Set<String> _boxNamesForScope(BackupRestoreScope scope) {
    switch (scope) {
      case BackupRestoreScope.full:
        return {
          'documents',
          'highlights',
          'favorites',
          'history',
          'settings',
          'zotero_sync',
        };
      case BackupRestoreScope.libraryOnly:
        return {'documents', 'highlights', 'favorites', 'history'};
      case BackupRestoreScope.settingsOnly:
        return {'settings'};
    }
  }

  static Future<Directory> _createMergeTempDir() async {
    final tempDir = await getTemporaryDirectory();
    final mergeDir = Directory(
      p.join(
        tempDir.path,
        'OtterPad',
        'merge_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (!await mergeDir.exists()) {
      await mergeDir.create(recursive: true);
    }
    return mergeDir;
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  static String _normalizeKey(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class MergeResult {
  final int documentsAdded;
  final int highlightsAdded;
  final int filesCopied;
  final int settingsAdded;

  const MergeResult({
    this.documentsAdded = 0,
    this.highlightsAdded = 0,
    this.filesCopied = 0,
    this.settingsAdded = 0,
  });

  MergeResult copyWith({
    int? documentsAdded,
    int? highlightsAdded,
    int? filesCopied,
    int? settingsAdded,
  }) {
    return MergeResult(
      documentsAdded: documentsAdded ?? this.documentsAdded,
      highlightsAdded: highlightsAdded ?? this.highlightsAdded,
      filesCopied: filesCopied ?? this.filesCopied,
      settingsAdded: settingsAdded ?? this.settingsAdded,
    );
  }

  bool get hasChanges =>
      documentsAdded > 0 ||
      highlightsAdded > 0 ||
      filesCopied > 0 ||
      settingsAdded > 0;
}
