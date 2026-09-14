import '../core/storage/storage_activity.dart';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/app_database.dart' as db;
import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
import '../core/storage/settings_store.dart';
import '../core/storage/restore_checkpoint.dart';
import '../core/storage/storage_exception.dart';
import '../core/storage/document_file_operations.dart';
import '../data/models/collection/favorite.dart';
import 'backup_merge_service.dart';
import '../utils/doc_paths.dart';

/// 备份创建范围（与恢复侧 [BackupRestoreScope] 对称的另一半）。
///
/// [dataOnly] 排除可重新获取/重新生成的大文件（PDF 原文、extract 提取
/// 产物、figures、summary 生成图），保留用户生产数据（设置、元数据、
/// 批注、translations.json、chats）。恢复后文献落入「无文件条目」，
/// 重新关联 PDF 的 UI 动线已存在。
enum BackupScope {
  full,
  dataOnly;

  bool get includeHeavyFiles => this == BackupScope.full;
}

enum BackupRestoreScope {
  full,
  libraryOnly,
  settingsOnly;

  bool get restoreLibrary => this != BackupRestoreScope.settingsOnly;
  bool get restoreSettings => this != BackupRestoreScope.libraryOnly;
}

enum RestoreMode { overwrite, merge }

/// 备份/恢复服务。备份形态：单个 SQLite 文件（otter.db，经 VACUUM INTO
/// 一致快照）+ library/ 目录 + manifest，打包成 ZIP。
class BackupRestoreService {
  static const _archiveRoot = 'otter_pad_backup';
  static const _manifestPath = '$_archiveRoot/manifest.json';
  static const _libraryDir = '$_archiveRoot/library';
  static const _dbDir = '$_archiveRoot/db';
  static const _dbFileName = 'otter.db';
  // formatVersion 3：Hive box 文件 → 单个 SQLite 文件。
  static const _formatVersion = 3;
  static bool _busy = false;

  static Future<T> _runExclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const StorageException(StorageFailure.operationInProgress);
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  static String buildBackupFileName([DateTime? time]) {
    final value = time ?? DateTime.now();
    String two(int input) => input.toString().padLeft(2, '0');
    return 'otter_pad_backup_'
        '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}.zip';
  }

  /// [manifestExtra] 由调用方附加进 manifest.json（设备名、文献数等），
  /// 供恢复前预览。
  static Future<String> createBackupArchive({
    BackupScope scope = BackupScope.full,
    Map<String, dynamic>? manifestExtra,
  }) => _runExclusive(
    () => _createBackupArchive(scope: scope, manifestExtra: manifestExtra),
  );

  static Future<String> _createBackupArchive({
    required BackupScope scope,
    Map<String, dynamic>? manifestExtra,
  }) async {
    final createdAt = DateTime.now();
    await GStorage.flush();

    final revision = await _databaseRevision();
    final files = await compute(_fileChecksums, [
      GStorage.libraryDirPath,
      scope.name,
    ]);
    final manifest = <String, dynamic>{
      ...?manifestExtra,
      'app': 'OtterPad',
      'formatVersion': _formatVersion,
      'createdAt': createdAt.toIso8601String(),
      'scope': scope.name,
      'libraryRoot': GStorage.libraryDirPath,
      'dbRoot': GStorage.dbDirPath,
      'dbFile': _dbFileName,
      'fileChecksums': files,
    };

    final backupTemp = await _getBackupTempDir();
    final tempDir = await backupTemp.createTemp('archive_');
    final outputPath = p.join(
      backupTemp.path,
      '${p.basename(tempDir.path)}_${buildBackupFileName(createdAt)}',
    );
    // 独立目录防止不同次备份共用快照文件，也保留中断后留下的旧产物。
    final snapshotPath = p.join(tempDir.path, 'snapshot_$_dbFileName');
    final snapshotFile = File(snapshotPath);
    // SQLite VACUUM INTO 不支持参数化，路径须字面拼入；转义单引号防破坏 SQL
    // （snapshotPath 来自系统临时目录，正常不含单引号，此处为防御性兜底）。
    final safeSnapshotPath = snapshotPath.replaceAll("'", "''");
    try {
      await GStorage.db.customStatement("VACUUM INTO '$safeSnapshotPath'");
      manifest['databaseChecksum'] =
          (await sha256.bind(snapshotFile.openRead()).first).toString();
      // 打包在后台 isolate 流式进行（只 zip 文件，不碰 DB 连接）。
      await compute(_createArchiveInIsolate, <String>[
        outputPath,
        GStorage.libraryDirPath,
        snapshotPath,
        const JsonEncoder.withIndent('  ').convert(manifest),
        scope.name,
      ]);
      final after = await compute(_fileChecksums, [
        GStorage.libraryDirPath,
        scope.name,
      ]);
      if (!mapEquals(files, after) || revision != await _databaseRevision()) {
        throw const StorageException(StorageFailure.changedDuringBackup);
      }
    } catch (_) {
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      // 打包失败也要清快照，防残留卡死后续所有备份。
      try {
        await snapshotFile.delete();
        await tempDir.delete();
      } catch (_) {}
    }
    return outputPath;
  }

  static Future<(int, int)> _databaseRevision() async {
    final changes = await GStorage.db
        .customSelect('SELECT total_changes() AS c')
        .getSingle();
    final version = await GStorage.db
        .customSelect('PRAGMA data_version')
        .getSingle();
    return (changes.read<int>('c'), version.read<int>('data_version'));
  }

  static Future<Map<String, String>> _fileChecksums(List<String> args) async {
    if (await DocumentFileOperations.hasPending(args[0])) {
      throw const StorageException(StorageFailure.changedDuringBackup);
    }
    final directory = Directory(args[0]);
    final scope = BackupScope.values.byName(args[1]);
    final result = <String, String>{};
    if (!await directory.exists()) return result;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = _toArchivePath(
        p.relative(entity.path, from: directory.path),
      );
      if (!scope.includeHeavyFiles && !includeInDataOnly(relative)) continue;
      result[relative] = (await sha256.bind(entity.openRead()).first)
          .toString();
    }
    return result;
  }

  static Future<void> _createArchiveInIsolate(List<String> args) async {
    final outputPath = args[0];
    final libraryDir = Directory(args[1]);
    final snapshotPath = args[2];
    final manifestJson = args[3];
    final scope = BackupScope.values.byName(args[4]);

    final encoder = ZipFileEncoder();
    encoder.create(outputPath);
    try {
      // manifest 经临时文件加入（ZipFileEncoder 没有字符串条目接口）。
      final manifestTmp = File('$outputPath.manifest.tmp');
      manifestTmp.writeAsStringSync(manifestJson);
      try {
        await encoder.addFile(manifestTmp, _manifestPath);
      } finally {
        manifestTmp.deleteSync();
      }

      await _addDirectoryStreamed(
        encoder,
        libraryDir,
        _libraryDir,
        include: scope.includeHeavyFiles ? null : includeInDataOnly,
      );
      // 单个 SQLite 快照作为 db/otter.db
      await encoder.addFile(File(snapshotPath), '$_dbDir/$_dbFileName');
    } finally {
      await encoder.close();
    }
  }

  /// dataOnly 范围的文献目录过滤：排除 PDF 原文 / extract 提取产物 /
  /// figures / summary 生成图，保留 translations.json、chats 等用户数据。
  /// [relativePath] 相对 library 根，形如 `{docId}/source.pdf`。
  /// 也是备份指纹的「数据文件」判定来源（BackupFingerprintService）——
  /// 两处必须共用同一规则，否则状态显示与实际打包内容漂移。
  static bool includeInDataOnly(String relativePath) {
    const excludedFiles = {
      'source.pdf',
      'extract.raw.md',
      'extract.md',
      'extract.json',
      'extract.paddleocr.json',
      'extract.paddleocr.raw.md',
      'extract.mineru.json',
      'extract.mineru.raw.md',
      'mineru.exports.zip',
    };
    const excludedDirs = {'figures', 'summary'};
    final parts = p.split(relativePath);
    if (parts.length < 2) return true;
    return parts.length == 2
        ? !excludedFiles.contains(parts[1])
        : !excludedDirs.contains(parts[1]);
  }

  static Future<void> _addDirectoryStreamed(
    ZipFileEncoder encoder,
    Directory sourceDir,
    String archiveRoot, {
    bool Function(String relativePath)? include,
  }) async {
    if (!await sourceDir.exists()) return;
    await for (final entity in sourceDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: sourceDir.path);
      if (include != null && !include(relative)) continue;
      await encoder.addFile(entity, '$archiveRoot/${_toArchivePath(relative)}');
    }
  }

  static Future<MergeResult?> restoreBackupArchive({
    required String archivePath,
    required BackupRestoreScope scope,
    RestoreMode mode = RestoreMode.overwrite,
    void Function(String)? onProgress,
  }) => _runExclusive(
    () => StorageActivity.restore(
      () => _restoreBackupArchive(
        archivePath: archivePath,
        scope: scope,
        mode: mode,
        onProgress: onProgress,
      ),
    ),
  );

  static Future<MergeResult?> _restoreBackupArchive({
    required String archivePath,
    required BackupRestoreScope scope,
    required RestoreMode mode,
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('正在解压备份文件...');
    final tempRoot = await _createRestoreTempRoot();
    final extractedDbPath = p.join(tempRoot.path, 'db', _dbFileName);
    final extractedDocsDir = Directory(p.join(tempRoot.path, 'library'));

    try {
      await _extractArchiveToDirectory(archivePath, tempRoot.path);
      final backupScope = _readManifestScope(tempRoot.path);
      await _validateChecksums(
        tempRoot.path,
        extractedDbPath,
        extractedDocsDir,
      );
      try {
        await db.AppDatabase.validateBackup(
          extractedDbPath,
          allowOrphans: mode == RestoreMode.merge,
        );
      } on StorageException {
        rethrow;
      } catch (_) {
        throw const StorageException(StorageFailure.invalidBackup);
      }
      await extractedDocsDir.create(recursive: true);

      if (mode == RestoreMode.merge) {
        Future<MergeResult> merge() => BackupMergeService.merge(
          backupDbPath: extractedDbPath,
          extractedDocsDir: scope.restoreLibrary ? extractedDocsDir : null,
          scope: scope,
          onProgress: onProgress,
        );
        if (!scope.restoreLibrary) {
          try {
            return await GStorage.db.transaction(merge);
          } finally {
            await GStorage.reloadSettings();
          }
        }
        return await _withLiveRollback(() async {
          final library = Directory(GStorage.libraryDirPath);
          await library.rename('${library.path}.bak');
          await _copyDirectory(Directory('${library.path}.bak'), library);
          return merge();
        });
      }

      // ── Overwrite ───────────────────────────────────────────────────
      if (scope == BackupRestoreScope.full) {
        await _overwriteFull(extractedDbPath, extractedDocsDir, backupScope);
      } else if (scope == BackupRestoreScope.libraryOnly) {
        await _withLiveRollback(
          () => _overwriteLibraryTables(
            extractedDbPath,
            extractedDocsDir,
            backupScope,
          ),
        );
      } else {
        // settingsOnly
        await _overwriteSettings(extractedDbPath);
      }
      return null;
    } finally {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    }
  }

  /// full 覆盖：close → 替换 otter.db + library/ → reopen。
  static Future<void> _overwriteFull(
    String extractedDbPath,
    Directory extractedDocsDir,
    BackupScope backupScope,
  ) async {
    final docsDir = Directory(GStorage.libraryDirPath);
    final dbFile = File(p.join(GStorage.dbDirPath, _dbFileName));
    final checkpoint = RestoreCheckpoint(dbFile.path, docsDir.path);
    await checkpoint.begin();
    try {
      await GStorage.close();
      await _replaceDirectory(docsDir, extractedDocsDir, keepBackup: true);
      await _replaceFile(File(extractedDbPath), dbFile, keepBackup: true);
      await GStorage.reopen();
      if (backupScope == BackupScope.dataOnly) {
        await _restoreHeavyFilesFromBak(docsDir);
      }
      await checkpoint.commit();
    } catch (_) {
      await GStorage.close();
      await checkpoint.recover();
      await GStorage.reopen();
      rethrow;
    }
  }

  static Future<T> _withLiveRollback<T>(Future<T> Function() action) async {
    final databasePath = p.join(GStorage.dbDirPath, _dbFileName);
    final checkpoint = RestoreCheckpoint(databasePath, GStorage.libraryDirPath);
    final staging = await Directory(
      GStorage.dbDirPath,
    ).createTemp('restore_snapshot_');
    var began = false;
    try {
      await checkpoint.begin();
      began = true;
      final snapshot = File(p.join(staging.path, _dbFileName));
      final escaped = snapshot.path.replaceAll("'", "''");
      await GStorage.db.customStatement("VACUUM INTO '$escaped'");
      // 快照写完后才发布 .bak；进程中断不能把半个快照当成旧库。
      await snapshot.rename('$databasePath.bak');
      final result = await action();
      await checkpoint.commit();
      return result;
    } catch (_) {
      if (began) {
        await GStorage.close();
        await checkpoint.recover();
        await GStorage.reopen();
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// libraryOnly 覆盖：表级替换 library 表（保留 settings/meta）+ library/ 目录。
  static Future<void> _overwriteLibraryTables(
    String extractedDbPath,
    Directory extractedDocsDir,
    BackupScope backupScope,
  ) async {
    final docsDir = Directory(GStorage.libraryDirPath);
    await _replaceDirectory(docsDir, extractedDocsDir, keepBackup: true);
    final backupDb = db.AppDatabase.file(extractedDbPath);
    try {
      await GStorage.db.transaction(() async {
        // 先删活库的 library 表（CASCADE 自动清 highlights/history/
        // favorite_documents/zotero_items；favorites 单独删清关联表）。
        await GStorage.db.delete(GStorage.db.favorites).go();
        await GStorage.db.delete(GStorage.db.documents).go();
        // 再从备份插入（父表先，子表后，满足 FK）
        await _copyTable(
          backupDb,
          backupDb.documents,
          GStorage.db.documents,
          (r) => documentCompanion(documentFromRow(r)),
        );
        await _copyTable(
          backupDb,
          backupDb.favorites,
          GStorage.db.favorites,
          (r) => favoriteCompanion(
            Favorite(
              id: r.id,
              emoji: r.emoji,
              name: r.name,
              documentIds: const [],
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ),
          ),
        );
        await _copyTable(
          backupDb,
          backupDb.highlights,
          GStorage.db.highlights,
          (r) => highlightCompanion(highlightFromRow(r)),
        );
        await _copyTable(
          backupDb,
          backupDb.history,
          GStorage.db.history,
          (r) => historyCompanion(historyFromRow(r)),
        );
        await _copyTable(
          backupDb,
          backupDb.favoriteDocuments,
          GStorage.db.favoriteDocuments,
          (r) => favoriteDocumentCompanion(r.favoriteId, r.docId),
        );
        await _copyTable(
          backupDb,
          backupDb.zoteroItems,
          GStorage.db.zoteroItems,
          (r) => zoteroItemCompanion(r.zoteroKey, r.docId, r.version),
        );
        // zotero_items 已整体替换为备份状态，同步游标必须一并回到备份时点：
        // 否则本地游标高于备份 items 状态，增量同步 `?since=游标` 会永远
        // 跳过备份时点到本地游标之间新增的条目。
        final backupVerRow =
            await (backupDb.select(backupDb.meta)
                  ..where((t) => t.metaKey.equals('zotero_library_version')))
                .getSingleOrNull();
        if (backupVerRow != null) {
          await GStorage.db
              .into(GStorage.db.meta)
              .insertOnConflictUpdate(
                metaCompanion('zotero_library_version', backupVerRow.value),
              );
        } else {
          await (GStorage.db.delete(
            GStorage.db.meta,
          )..where((t) => t.metaKey.equals('zotero_library_version'))).go();
        }
      });
    } finally {
      await backupDb.close();
    }
    if (backupScope == BackupScope.dataOnly) {
      await _restoreHeavyFilesFromBak(docsDir);
    }
  }

  /// settingsOnly 覆盖：表级替换 settings 表（保留其余）。
  ///
  /// 直接 delete/insert settings 表是 SettingsStore 禁令的**有意豁免**：
  /// 此处语义是事务内整表原子替换，逐键走 `SettingsStore.put` 会失去原子性；
  /// 写完由 `GStorage.reloadSettings()` 重建缓存，保证缓存与表一致。
  static Future<void> _overwriteSettings(String extractedDbPath) async {
    final backupDb = db.AppDatabase.file(extractedDbPath);
    try {
      await GStorage.db.transaction(() async {
        await GStorage.db.delete(GStorage.db.settings).go();
        final backupRows = await backupDb.select(backupDb.settings).get();
        await GStorage.db.batch((b) {
          for (final r in backupRows) {
            b.insert(
              GStorage.db.settings,
              settingCompanion(r.settingKey, SettingsStore.decodeRaw(r.value)),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      });
    } finally {
      await backupDb.close();
    }
    await GStorage.reloadSettings();
  }

  /// 把备份表的全部行批量插入活库（已先清空活库对应表）。
  ///
  /// 泛型化（替代原 dynamic）：T 为 Drift 表类，R 为生成行类，
  /// [toCompanion] 在 `R` → `UpdateCompanion<R>` 间转换，编译期即守住
  /// 「表 ↔ 行 ↔ companion」三方类型对应，避免调用方传错转换函数。
  static Future<void> _copyTable<T extends Table, R extends DataClass>(
    db.AppDatabase backupDb,
    TableInfo<T, R> backupTable,
    TableInfo<T, R> liveTable,
    UpdateCompanion<R> Function(R row) toCompanion,
  ) async {
    final rows = await backupDb.select(backupTable).get();
    if (rows.isEmpty) return;
    await GStorage.db.batch((b) {
      for (final r in rows) {
        b.insert(liveTable, toCompanion(r), mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 在 Isolate 中解压 ZIP 到磁盘，避免主线程 OOM。
  static Future<void> _extractArchiveToDirectory(
    String archivePath,
    String tempRootPath,
  ) async {
    await compute(_extractInIsolate, [archivePath, tempRootPath]);
  }

  static void _extractInIsolate(List<String> args) {
    final archivePath = args[0];
    final tempRootPath = args[1];
    final input = InputFileStream(archivePath);
    try {
      final archive = ZipDecoder().decodeStream(input);

      const libraryPrefix = '$_archiveRoot/library/';
      const dbPrefix = '$_archiveRoot/db/';

      for (final file in archive) {
        // manifest 单独落到解压根，供恢复侧读取备份范围等元信息。
        if (file.name == _manifestPath && file.isFile) {
          File(p.join(tempRootPath, 'manifest.json'))
            ..createSync(recursive: true)
            ..writeAsBytesSync(file.readBytes() ?? const <int>[]);
          continue;
        }
        String? relative;
        String? subDir;
        if (file.name.startsWith(libraryPrefix)) {
          relative = file.name.substring(libraryPrefix.length);
          subDir = 'library';
        } else if (file.name.startsWith(dbPrefix)) {
          relative = file.name.substring(dbPrefix.length);
          subDir = 'db';
        }
        if (relative == null || relative.isEmpty || subDir == null) continue;

        final parts = relative.split('/');
        final targetPath = p.joinAll([tempRootPath, subDir, ...parts]);

        if (!p.isWithin(p.join(tempRootPath, subDir), targetPath)) continue;

        if (!file.isFile) {
          Directory(targetPath).createSync(recursive: true);
          continue;
        }

        Directory(p.dirname(targetPath)).createSync(recursive: true);
        final output = OutputFileStream(targetPath);
        try {
          file.writeContent(output);
        } finally {
          output.closeSync();
        }
      }
    } finally {
      input.closeSync();
    }
  }

  /// 保留旧目录，直到恢复检查点确认新库可用后统一清理。
  static Future<void> _replaceDirectory(
    Directory targetDir,
    Directory sourceDir, {
    bool keepBackup = false,
  }) async {
    final backupDir = Directory('${targetDir.path}.bak');
    if (await backupDir.exists()) {
      throw const StorageException(StorageFailure.pendingRestore);
    }

    final hadTarget = await targetDir.exists();
    if (hadTarget) {
      await targetDir.rename(backupDir.path);
    }

    try {
      await _copyDirectory(sourceDir, targetDir);
      if (!keepBackup && await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
    } catch (error) {
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      if (await backupDir.exists()) {
        await backupDir.rename(targetDir.path);
      }
      rethrow;
    }
  }

  /// 原子替换单个文件（otter.db）：旧文件先改名 .bak，复制新文件，失败回滚。
  static Future<void> _replaceFile(
    File source,
    File target, {
    bool keepBackup = false,
  }) async {
    final backup = File('${target.path}.bak');
    if (await backup.exists()) {
      throw const StorageException(StorageFailure.pendingRestore);
    }
    final hadTarget = await target.exists();
    if (hadTarget) await target.rename(backup.path);
    try {
      await Directory(p.dirname(target.path)).create(recursive: true);
      await source.copy(target.path);
      if (!keepBackup && await backup.exists()) await backup.delete();
    } catch (error) {
      if (await target.exists()) await target.delete();
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
  }

  static Future<void> _validateChecksums(
    String root,
    String databasePath,
    Directory library,
  ) async {
    final manifest =
        jsonDecode(await File(p.join(root, 'manifest.json')).readAsString())
            as Map<String, dynamic>;
    final databaseHash = manifest['databaseChecksum'];
    if (databaseHash != null) {
      if (!await File(databasePath).exists() ||
          (await sha256.bind(File(databasePath).openRead()).first).toString() !=
              databaseHash) {
        throw const StorageException(StorageFailure.invalidBackup);
      }
    }
    final expected = manifest['fileChecksums'];
    if (expected != null) {
      final actual = await compute(_fileChecksums, [
        library.path,
        BackupScope.full.name,
      ]);
      if (expected is! Map<String, dynamic> || !mapEquals(expected, actual)) {
        throw const StorageException(StorageFailure.invalidBackup);
      }
    }
  }

  static BackupScope _readManifestScope(String tempRootPath) {
    try {
      final raw = File(
        p.join(tempRootPath, 'manifest.json'),
      ).readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['app'] != 'OtterPad') {
        throw const StorageException(StorageFailure.invalidBackup);
      }
      if (json['formatVersion'] != _formatVersion) {
        throw const StorageException(StorageFailure.unsupportedBackup);
      }
      final scope = BackupScope.values.asNameMap()[json['scope']];
      if (scope == null) {
        throw const StorageException(StorageFailure.invalidBackup);
      }
      return scope;
    } on StorageException {
      rethrow;
    } catch (_) {
      throw const StorageException(StorageFailure.invalidBackup);
    }
  }

  /// dataOnly 备份做**覆盖恢复**时的防数据丢失：备份里没有 PDF / 提取
  /// 产物，直接整目录替换会清掉本地重文件。从 `.bak` 把被 dataOnly
  /// 排除的文件拷回**仍存在于备份中的**文献目录；备份里已不存在的文献
  /// 不拷回（尊重备份时刻的删除状态）。
  static Future<void> _restoreHeavyFilesFromBak(Directory docsDir) async {
    final bakDir = Directory('${docsDir.path}.bak');
    if (!await bakDir.exists()) return;
    final rows = await GStorage.db
        .customSelect('SELECT id, contentHash FROM documents')
        .get();
    final restoredIds = rows.map((row) => row.read<String>('id')).toSet();
    await for (final entity in bakDir.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: bakDir.path);
      if (includeInDataOnly(_toArchivePath(relative))) continue;
      final parts = p.split(relative);
      if (parts.isEmpty) continue;
      // 只有 PDF 的文献在 dataOnly ZIP 中没有目录，必须按恢复后的数据库判定。
      if (!restoredIds.contains(parts.first)) {
        continue;
      }
      final targetFile = File(p.join(docsDir.path, relative));
      if (await targetFile.exists()) continue;
      await Directory(p.dirname(targetFile.path)).create(recursive: true);
      await entity.copy(targetFile.path);
    }
    final missingIds = <String>[];
    for (final row in rows) {
      final id = row.read<String>('id');
      if (row.read<String?>('contentHash') != null &&
          !await File(p.join(docsDir.path, id, DocPaths.pdfName)).exists()) {
        missingIds.add(id);
      }
    }
    // 轻量备份没有带 PDF，且本地没有原文时，明确恢复为无文件条目。
    await GStorage.db.batch((batch) {
      for (final id in missingIds) {
        batch.update(
          GStorage.db.documents,
          const db.DocumentsCompanion(contentHash: Value(null)),
          where: (table) => table.id.equals(id),
        );
      }
    });
  }

  static Future<void> _copyDirectory(
    Directory sourceDir,
    Directory targetDir,
  ) async {
    await targetDir.create(recursive: true);
    await for (final entity in sourceDir.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: sourceDir.path);
      final targetPath = p.join(targetDir.path, relativePath);

      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(targetPath)).create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  static Future<Directory> _getBackupTempDir() async {
    final tempDir = await getTemporaryDirectory();
    final backupDir = Directory(p.join(tempDir.path, 'OtterPad', 'backup'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  static Future<Directory> _createRestoreTempRoot() async {
    final tempDir = await getTemporaryDirectory();
    final restoreDir = Directory(
      p.join(
        tempDir.path,
        'OtterPad',
        'restore_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (!await restoreDir.exists()) {
      await restoreDir.create(recursive: true);
    }
    return restoreDir;
  }

  static String _toArchivePath(String value) {
    return value.replaceAll('\\', '/');
  }
}
