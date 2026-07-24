import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../core/storage/app_database.dart' as db;
import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import '../data/models/book/history_entry.dart';
import '../data/models/collection/favorite.dart';
import '../providers/zotero_sync_provider.dart';
import 'backup_restore_service.dart';

/// 备份合并服务：将备份数据与本地数据合并（增量同步），而非覆盖。
///
/// 核心策略：按 ID 去重、只添加不存在的数据，不做版本比较。
/// 备份是单个 SQLite 文件（otter.db）；merge 在临时目录打开备份库为第二个
/// Drift 连接，按表读出后用领域规则并入活库（GStorage.db），最后刷新缓存。
class BackupMergeService {
  /// 这些 settings 键是本地独占（代理 / 远端备份凭据等），不从备份合并。
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
    required String backupDbPath,
    required Directory? extractedDocsDir,
    required BackupRestoreScope scope,
    void Function(String message)? onProgress,
  }) async {
    var stats = const MergeResult();
    final backupDb = db.AppDatabase.file(backupDbPath);
    try {
      if (scope.restoreLibrary) {
        onProgress?.call('正在合并文献...');
        stats = stats.copyWith(
          documentsAdded: await _mergeDocuments(backupDb),
        );
        onProgress?.call('正在合并标注...');
        stats = stats.copyWith(
          highlightsAdded: await _mergeHighlights(backupDb),
        );
        onProgress?.call('正在合并收藏夹...');
        await _mergeFavorites(backupDb);
        onProgress?.call('正在合并阅读历史...');
        await _mergeHistory(backupDb);
        if (extractedDocsDir != null) {
          onProgress?.call('正在合并文献文件...');
          stats = stats.copyWith(
            filesCopied: await _mergeLibraryFiles(extractedDocsDir),
          );
        }
      }
      if (scope.restoreSettings) {
        onProgress?.call('正在合并设置...');
        stats = stats.copyWith(
          settingsAdded: await _mergeSettings(backupDb),
        );
      }
      if (scope == BackupRestoreScope.full) {
        onProgress?.call('正在合并 Zotero 同步数据...');
        await _mergeZoteroSync(backupDb);
      }
    } finally {
      await backupDb.close();
    }

    // 活库已并入备份数据，但内存缓存陈旧——刷新后由调用方 invalidate provider。
    await GStorage.refreshCache();
    return stats;
  }

  // ─── Documents ──────────────────────────────────────────────────────────────

  static Future<int> _mergeDocuments(db.AppDatabase backupDb) async {
    final live = GStorage.cache.documents;
    final liveById = {for (final d in live) d.id: d};
    final liveByDoi = <String, Document>{};
    for (final d in live) {
      final doi = d.doi?.trim().toLowerCase();
      if (doi != null && doi.isNotEmpty) liveByDoi[doi] = d;
    }

    final backupDocs =
        (await backupDb.select(backupDb.documents).get())
            .map(documentFromRow)
            .toList();

    final toUpsert = <Document>[];
    final additions = <Document>[];

    for (final bd in backupDocs) {
      if (liveById.containsKey(bd.id)) {
        final cd = liveById[bd.id]!;
        final result = _enrichDocument(cd, bd);
        if (!identical(result, cd)) {
          liveById[bd.id] = result;
          toUpsert.add(result);
        }
        continue;
      }

      final bdDoi = bd.doi?.trim().toLowerCase();
      if (bdDoi != null &&
          bdDoi.isNotEmpty &&
          liveByDoi.containsKey(bdDoi)) {
        continue;
      }

      if (_hasTitleMatch(live, additions, bd)) continue;

      additions.add(bd);
      toUpsert.add(bd);
      if (bdDoi != null && bdDoi.isNotEmpty) liveByDoi[bdDoi] = bd;
    }

    if (toUpsert.isNotEmpty) {
      await GStorage.db.batch((b) {
        for (final d in toUpsert) {
          b.insert(
            GStorage.db.documents,
            documentCompanion(d),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
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

  static Future<int> _mergeHighlights(db.AppDatabase backupDb) async {
    final liveIds = (await GStorage.db.select(GStorage.db.highlights).get())
        .map((r) => r.id)
        .toSet();
    final backupRows = await backupDb.select(backupDb.highlights).get();
    final toAdd = backupRows.where((r) => !liveIds.contains(r.id)).toList();
    if (toAdd.isEmpty) return 0;
    await GStorage.db.batch((b) {
      for (final r in toAdd) {
        b.insert(
          GStorage.db.highlights,
          highlightCompanion(highlightFromRow(r)),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
    return toAdd.length;
  }

  // ─── Favorites ──────────────────────────────────────────────────────────────

  static Future<void> _mergeFavorites(db.AppDatabase backupDb) async {
    final liveFavIds = (await GStorage.db.select(GStorage.db.favorites).get())
        .map((r) => r.id)
        .toSet();
    final backupFavRows = await backupDb.select(backupDb.favorites).get();
    final backupFdRows =
        await backupDb.select(backupDb.favoriteDocuments).get();
    final backupDocsByFav = <String, List<String>>{};
    for (final r in backupFdRows) {
      backupDocsByFav.putIfAbsent(r.favoriteId, () => []).add(r.docId);
    }

    for (final bf in backupFavRows) {
      final docIds = backupDocsByFav[bf.id] ?? const <String>[];
      if (liveFavIds.contains(bf.id)) {
        // 已存在：documentIds 取并集（新关联 insert-or-ignore）
        final liveDocIds = (await (GStorage.db.select(
                  GStorage.db.favoriteDocuments,
                )
                      ..where((t) => t.favoriteId.equals(bf.id)))
                .get())
            .map((r) => r.docId)
            .toSet();
        final newDocIds =
            docIds.where((id) => !liveDocIds.contains(id)).toList();
        if (newDocIds.isEmpty) continue;
        await GStorage.db.batch((b) {
          for (final id in newDocIds) {
            b.insert(
              GStorage.db.favoriteDocuments,
              favoriteDocumentCompanion(bf.id, id),
              mode: InsertMode.insertOrIgnore,
            );
          }
        });
      } else {
        // 新增收藏夹 + 其关联
        await GStorage.db.into(GStorage.db.favorites).insertOnConflictUpdate(
              favoriteCompanion(
                Favorite(
                  id: bf.id,
                  emoji: bf.emoji,
                  name: bf.name,
                  documentIds: docIds,
                  createdAt: DateTime.fromMillisecondsSinceEpoch(
                    bf.createdAt,
                  ),
                ),
              ),
            );
        if (docIds.isNotEmpty) {
          await GStorage.db.batch((b) {
            for (final id in docIds) {
              b.insert(
                GStorage.db.favoriteDocuments,
                favoriteDocumentCompanion(bf.id, id),
                mode: InsertMode.insertOrIgnore,
              );
            }
          });
        }
      }
    }
  }

  // ─── History ────────────────────────────────────────────────────────────────

  static Future<void> _mergeHistory(db.AppDatabase backupDb) async {
    final liveByDocId = {
      for (final e in GStorage.cache.history) e.docId: e,
    };
    final backupRows = await backupDb.select(backupDb.history).get();
    final merged = Map<String, HistoryEntry>.from(liveByDocId);
    var changed = false;
    for (final r in backupRows) {
      final be = historyFromRow(r);
      final ce = liveByDocId[be.docId];
      if (ce == null) {
        merged[be.docId] = be;
        changed = true;
      } else if (be.openedAt.isAfter(ce.openedAt)) {
        merged[be.docId] = be;
        changed = true;
      } else if (be.openedAt == ce.openedAt && be.progress > ce.progress) {
        merged[be.docId] = be;
        changed = true;
      }
    }
    if (!changed) return;
    final list = merged.values.toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final capped = list.length > 500 ? list.sublist(0, 500) : list;
    await GStorage.db.batch((b) {
      for (final e in capped) {
        b.insert(
          GStorage.db.history,
          historyCompanion(e),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  // ─── Settings ───────────────────────────────────────────────────────────────

  static Future<int> _mergeSettings(db.AppDatabase backupDb) async {
    final liveKeys = GStorage.setting.keys.toSet();
    var added = 0;
    final backupRows = await backupDb.select(backupDb.settings).get();
    for (final r in backupRows) {
      if (_localOnlySettingsKeys.contains(r.settingKey)) continue;
      if (liveKeys.contains(r.settingKey)) continue;
      await GStorage.setting.put(r.settingKey, _decode(r.value));
      added++;
    }
    return added;
  }

  static Object? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  // ─── Zotero Sync ───────────────────────────────────────────────────────────

  static Future<void> _mergeZoteroSync(db.AppDatabase backupDb) async {
    // 库版本取 max
    final backupVerRow = await (backupDb.select(backupDb.meta)
          ..where((t) => t.metaKey.equals('zotero_library_version')))
        .getSingleOrNull();
    final backupVer =
        backupVerRow == null ? 0 : (int.tryParse(backupVerRow.value) ?? 0);
    if (backupVer > GStorage.cache.zoteroLibraryVersion) {
      await ZoteroSyncStore.setLibraryVersion(backupVer);
    }
    // zotero_items 只补缺
    final liveKeys = GStorage.cache.zoteroItems.keys.toSet();
    final backupRows = await backupDb.select(backupDb.zoteroItems).get();
    for (final r in backupRows) {
      if (liveKeys.contains(r.zoteroKey)) continue;
      if (r.docId == null) continue;
      await ZoteroSyncStore.recordItem(r.zoteroKey, r.docId!, r.version);
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