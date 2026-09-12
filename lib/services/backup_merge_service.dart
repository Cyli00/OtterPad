import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../core/storage/app_database.dart' as db;
import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
import '../core/storage/settings_store.dart';
import '../core/storage/zotero_snapshot.dart';
import '../data/models/book/document.dart';
import '../data/models/book/highlight.dart';
import '../data/models/book/history_entry.dart';
import '../data/models/collection/favorite.dart';
import '../providers/zotero_sync_provider.dart';
import 'backup_restore_service.dart';

/// 备份合并服务：将备份数据与本地数据合并（增量同步），而非覆盖。
///
/// 核心策略：按 ID 去重、只添加不存在的数据，不做版本比较。
/// 备份是单个 SQLite 文件（otter.db）；merge 在临时目录打开备份库为第二个
/// Drift 连接，按表读出后用领域规则并入活库（GStorage.db）。
///
/// 文档去重产生 `backupDocId → liveDocId` 重映射（ADR-0004）：DOI/题录判重
/// 命中时，备份文档不插入，但其子记录（标注/收藏关联/Zotero/历史）的 `docId`
/// 经该映射指向保留的本地文档；引用不存在文档的孤儿子记录跳过并计数。
/// live 基线直读 Drift（对齐 G7），watch() 流自动反映合并结果（ADR-0001）。
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
    var idMap = <String, String>{};
    try {
      if (scope.restoreLibrary) {
        onProgress?.call('正在合并文献...');
        final (additions, docIdMap) = await _mergeDocuments(backupDb);
        idMap = docIdMap;
        stats = stats.copyWith(documentsAdded: additions);
        onProgress?.call('正在合并标注...');
        final (hlAdded, hlSkipped) = await _mergeHighlights(backupDb, idMap);
        stats = stats.copyWith(
          highlightsAdded: hlAdded,
          skippedOrphans: stats.skippedOrphans + hlSkipped,
        );
        onProgress?.call('正在合并收藏夹...');
        final favSkipped = await _mergeFavorites(backupDb, idMap);
        stats = stats.copyWith(
          skippedOrphans: stats.skippedOrphans + favSkipped,
        );
        onProgress?.call('正在合并阅读历史...');
        final histSkipped = await _mergeHistory(backupDb, idMap);
        stats = stats.copyWith(
          skippedOrphans: stats.skippedOrphans + histSkipped,
        );
        if (extractedDocsDir != null) {
          onProgress?.call('正在合并文献文件...');
          stats = stats.copyWith(
            filesCopied: await _mergeLibraryFiles(extractedDocsDir, idMap),
          );
        }
      }
      if (scope.restoreSettings) {
        onProgress?.call('正在合并设置...');
        stats = stats.copyWith(settingsAdded: await _mergeSettings(backupDb));
      }
      if (scope == BackupRestoreScope.full) {
        onProgress?.call('正在合并 Zotero 同步数据...');
        final zotSkipped = await _mergeZoteroSync(backupDb, idMap);
        stats = stats.copyWith(
          skippedOrphans: stats.skippedOrphans + zotSkipped,
        );
      }
    } finally {
      await backupDb.close();
    }
    // ADR-0001：不再 refreshCache——活库 watch() 流自动反映合并写入，
    // 编排者经 appDatabaseProvider 失效让 provider 重订阅。
    return stats;
  }

  // ─── Documents ──────────────────────────────────────────────────────────────

  /// 返回 (新增篇数, backupDocId → liveDocId 重映射)。
  static Future<(int, Map<String, String>)> _mergeDocuments(
    db.AppDatabase backupDb,
  ) async {
    final live = (await GStorage.db.select(GStorage.db.documents).get())
        .map(documentFromRow)
        .toList();
    final liveById = {for (final d in live) d.id: d};
    final liveByDoi = <String, Document>{};
    for (final d in live) {
      final doi = d.doi?.trim().toLowerCase();
      if (doi != null && doi.isNotEmpty) liveByDoi[doi] = d;
    }

    final backupDocs = (await backupDb.select(backupDb.documents).get())
        .map(documentFromRow)
        .toList();

    final toUpsert = <Document>[];
    final additions = <Document>[];
    final idMap = <String, String>{};

    for (final bd in backupDocs) {
      if (liveById.containsKey(bd.id)) {
        final cd = liveById[bd.id]!;
        final result = _enrichDocument(cd, bd);
        if (!identical(result, cd)) {
          liveById[bd.id] = result;
          toUpsert.add(result);
        }
        idMap[bd.id] = bd.id;
        continue;
      }

      final bdDoi = bd.doi?.trim().toLowerCase();
      if (bdDoi != null && bdDoi.isNotEmpty && liveByDoi.containsKey(bdDoi)) {
        // DOI 判重：不插入，映射到命中的本地文档
        idMap[bd.id] = liveByDoi[bdDoi]!.id;
        continue;
      }

      final titleMatch = _findTitleMatch(live, additions, bd);
      if (titleMatch != null) {
        // 题录判重：不插入，映射到命中的本地文档
        idMap[bd.id] = titleMatch.id;
        continue;
      }

      additions.add(bd);
      toUpsert.add(bd);
      idMap[bd.id] = bd.id;
      if (bdDoi != null && bdDoi.isNotEmpty) liveByDoi[bdDoi] = bd;
    }

    if (toUpsert.isNotEmpty) {
      // 必须 ON CONFLICT DO UPDATE：INSERT OR REPLACE 是 DELETE+INSERT，
      // foreign_keys=ON 时对同 id 已存在文档（_enrichDocument 命中）REPLACE
      // 会 CASCADE 清空它本地独有的高亮/历史/收藏关联/Zotero 映射。
      await GStorage.db.batch((b) {
        b.insertAllOnConflictUpdate(GStorage.db.documents, [
          for (final d in toUpsert) documentCompanion(d),
        ]);
      });
    }
    return (additions.length, idMap);
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

  /// 题录判重：标题匹配 + (年份 | 首作者)。返回命中的已存在文档（用于重映射）。
  static Document? _findTitleMatch(
    List<Document> existingDocs,
    List<Document> pendingAdditions,
    Document candidate,
  ) {
    final candidateTitle = _normalizeKey(candidate.title);
    if (candidateTitle.isEmpty) return null;

    for (final existing in [...existingDocs, ...pendingAdditions]) {
      final existingTitle = _normalizeKey(existing.title);
      if (existingTitle != candidateTitle) continue;

      final eYear = _normalizeKey(existing.year);
      final cYear = _normalizeKey(candidate.year);
      if (eYear.isNotEmpty && cYear.isNotEmpty && eYear == cYear) {
        return existing;
      }

      final eAuthor = existing.authors.isEmpty
          ? ''
          : _normalizeKey(existing.authors.first);
      final cAuthor = candidate.authors.isEmpty
          ? ''
          : _normalizeKey(candidate.authors.first);
      if (eAuthor.isNotEmpty && cAuthor.isNotEmpty && eAuthor == cAuthor) {
        return existing;
      }
    }
    return null;
  }

  // ─── Highlights ─────────────────────────────────────────────────────────────

  /// 返回 (新增条数, 因 docId 无映射跳过的孤儿数)。
  static Future<(int, int)> _mergeHighlights(
    db.AppDatabase backupDb,
    Map<String, String> idMap,
  ) async {
    final liveIds = (await GStorage.db.select(GStorage.db.highlights).get())
        .map((r) => r.id)
        .toSet();
    final backupRows = await backupDb.select(backupDb.highlights).get();
    var skipped = 0;
    final remapped = <Highlight>[];
    for (final r in backupRows) {
      final h = highlightFromRow(r);
      final liveDocId = idMap[h.documentId];
      if (liveDocId == null) {
        skipped++;
        continue;
      }
      // highlight id 冲突 → insertOrIgnore 语义（跳过，不改既有冲突策略）
      if (liveIds.contains(h.id)) continue;
      remapped.add(
        Highlight(
          id: h.id,
          documentId: liveDocId,
          text: h.text,
          note: h.note,
          color: h.color,
          groupId: h.groupId,
          createdAt: h.createdAt,
        ),
      );
    }
    if (remapped.isEmpty) return (0, skipped);
    await GStorage.db.batch((b) {
      for (final h in remapped) {
        b.insert(
          GStorage.db.highlights,
          highlightCompanion(h),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
    return (remapped.length, skipped);
  }

  // ─── Favorites ──────────────────────────────────────────────────────────────

  /// 返回因 docId 无映射跳过的孤儿关联数。
  static Future<int> _mergeFavorites(
    db.AppDatabase backupDb,
    Map<String, String> idMap,
  ) async {
    var skipped = 0;
    final liveFavIds = (await GStorage.db.select(GStorage.db.favorites).get())
        .map((r) => r.id)
        .toSet();
    final backupFavRows = await backupDb.select(backupDb.favorites).get();
    final backupFdRows = await backupDb
        .select(backupDb.favoriteDocuments)
        .get();
    final backupDocsByFav = <String, List<String>>{};
    for (final r in backupFdRows) {
      backupDocsByFav.putIfAbsent(r.favoriteId, () => []).add(r.docId);
    }

    for (final bf in backupFavRows) {
      final rawDocIds = backupDocsByFav[bf.id] ?? const <String>[];
      // 重映射每个关联 docId；孤儿跳过计数
      final remappedDocIds = <String>[];
      for (final docId in rawDocIds) {
        final live = idMap[docId];
        if (live == null) {
          skipped++;
          continue;
        }
        remappedDocIds.add(live);
      }

      if (liveFavIds.contains(bf.id)) {
        // 已存在：documentIds 取并集（新关联 insert-or-ignore）
        final liveDocIds =
            (await (GStorage.db.select(
                  GStorage.db.favoriteDocuments,
                )..where((t) => t.favoriteId.equals(bf.id))).get())
                .map((r) => r.docId)
                .toSet();
        final newDocIds = remappedDocIds
            .where((id) => !liveDocIds.contains(id))
            .toList();
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
        await GStorage.db
            .into(GStorage.db.favorites)
            .insertOnConflictUpdate(
              favoriteCompanion(
                Favorite(
                  id: bf.id,
                  emoji: bf.emoji,
                  name: bf.name,
                  documentIds: const [],
                  createdAt: DateTime.fromMillisecondsSinceEpoch(bf.createdAt),
                ),
              ),
            );
        if (remappedDocIds.isNotEmpty) {
          await GStorage.db.batch((b) {
            for (final id in remappedDocIds) {
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
    return skipped;
  }

  // ─── History ────────────────────────────────────────────────────────────────

  /// 返回因 docId 无映射跳过的孤儿数。500 上限事务化强制修剪（ADR-0004/P1-1）。
  static Future<int> _mergeHistory(
    db.AppDatabase backupDb,
    Map<String, String> idMap,
  ) async {
    var skipped = 0;
    final liveRows = await GStorage.db.select(GStorage.db.history).get();
    final liveByDocId = {for (final r in liveRows) r.docId: historyFromRow(r)};
    final backupRows = await backupDb.select(backupDb.history).get();
    final merged = Map<String, HistoryEntry>.from(liveByDocId);
    var changed = false;
    for (final r in backupRows) {
      final be = historyFromRow(r);
      final liveDocId = idMap[be.docId];
      if (liveDocId == null) {
        skipped++;
        continue;
      }
      final remapped = HistoryEntry(
        docId: liveDocId,
        openedAt: be.openedAt,
        progress: be.progress,
        anchorBlock: be.anchorBlock,
      );
      final ce = liveByDocId[remapped.docId];
      if (ce == null) {
        merged[remapped.docId] = remapped;
        changed = true;
      } else if (be.openedAt.isAfter(ce.openedAt)) {
        merged[remapped.docId] = remapped;
        changed = true;
      } else if (be.openedAt == ce.openedAt && be.progress > ce.progress) {
        merged[remapped.docId] = remapped;
        changed = true;
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final capped = list.length > 500 ? list.sublist(0, 500) : list;
    final cappedDocIds = {for (final e in capped) e.docId};

    // 事务：upsert capped（仅当有变更）+ 删除集合外旧行（始终修剪）。
    await GStorage.db.transaction(() async {
      if (changed) {
        for (final e in capped) {
          await GStorage.db
              .into(GStorage.db.history)
              .insertOnConflictUpdate(historyCompanion(e));
        }
      }
      if (cappedDocIds.isEmpty) {
        await GStorage.db.delete(GStorage.db.history).go();
      } else {
        await (GStorage.db.delete(
          GStorage.db.history,
        )..where((t) => t.docId.isNotIn(cappedDocIds))).go();
      }
    });
    return skipped;
  }

  // ─── Settings ───────────────────────────────────────────────────────────────

  static Future<int> _mergeSettings(db.AppDatabase backupDb) async {
    final liveKeys = GStorage.setting.keys.toSet();
    var added = 0;
    final backupRows = await backupDb.select(backupDb.settings).get();
    for (final r in backupRows) {
      if (_localOnlySettingsKeys.contains(r.settingKey)) continue;
      if (liveKeys.contains(r.settingKey)) continue;
      await GStorage.setting.put(
        r.settingKey,
        SettingsStore.decodeRaw(r.value),
      );
      added++;
    }
    return added;
  }

  // ─── Zotero Sync ───────────────────────────────────────────────────────────

  /// 返回因 docId 无映射跳过的孤儿数。
  static Future<int> _mergeZoteroSync(
    db.AppDatabase backupDb,
    Map<String, String> idMap,
  ) async {
    var skipped = 0;
    // 库版本取 max
    final backupVerRow =
        await (backupDb.select(backupDb.meta)
              ..where((t) => t.metaKey.equals('zotero_library_version')))
            .getSingleOrNull();
    final backupVer = backupVerRow == null
        ? 0
        : (int.tryParse(backupVerRow.value) ?? 0);
    if (backupVer > ZoteroSnapshot.libraryVersion) {
      await ZoteroSyncStore.setLibraryVersion(backupVer);
    }
    // zotero_items 只补缺（docId 重映射）
    final liveKeys = ZoteroSnapshot.items.keys.toSet();
    final backupRows = await backupDb.select(backupDb.zoteroItems).get();
    for (final r in backupRows) {
      if (liveKeys.contains(r.zoteroKey)) continue;
      if (r.docId == null) continue;
      final liveDocId = idMap[r.docId!];
      if (liveDocId == null) {
        skipped++;
        continue;
      }
      await ZoteroSyncStore.recordItem(r.zoteroKey, liveDocId, r.version);
    }
    return skipped;
  }

  // ─── Library files ──────────────────────────────────────────────────────────

  static Future<int> _mergeLibraryFiles(
    Directory extractedDocsDir,
    Map<String, String> idMap,
  ) async {
    if (!await extractedDocsDir.exists()) return 0;
    final libraryDir = Directory(GStorage.libraryDirPath);
    if (!await libraryDir.exists()) {
      await libraryDir.create(recursive: true);
    }
    var filesCopied = 0;
    await for (final entity in extractedDocsDir.list()) {
      if (entity is! Directory) continue;
      final docId = p.basename(entity.path);
      // 目标目录经 idMap 重映射（ADR-0004）：DOI/题录判重命中时备份文档映射
      // 到本地文档，文件必须落进本地 id 的目录——按备份原 id 拷会成孤儿目录，
      // 文献显示"有文件"却打不开。备份库中无对应文档行的悬空目录跳过。
      final liveDocId = idMap[docId];
      if (liveDocId == null) continue;
      final targetDir = Directory(p.join(libraryDir.path, liveDocId));
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
  final int skippedOrphans;

  const MergeResult({
    this.documentsAdded = 0,
    this.highlightsAdded = 0,
    this.filesCopied = 0,
    this.settingsAdded = 0,
    this.skippedOrphans = 0,
  });

  MergeResult copyWith({
    int? documentsAdded,
    int? highlightsAdded,
    int? filesCopied,
    int? settingsAdded,
    int? skippedOrphans,
  }) {
    return MergeResult(
      documentsAdded: documentsAdded ?? this.documentsAdded,
      highlightsAdded: highlightsAdded ?? this.highlightsAdded,
      filesCopied: filesCopied ?? this.filesCopied,
      settingsAdded: settingsAdded ?? this.settingsAdded,
      skippedOrphans: skippedOrphans ?? this.skippedOrphans,
    );
  }

  bool get hasChanges =>
      documentsAdded > 0 ||
      highlightsAdded > 0 ||
      filesCopied > 0 ||
      settingsAdded > 0;
}
