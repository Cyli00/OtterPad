import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/app_database.dart' as db;
import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
import '../data/models/collection/favorite.dart';
import 'backup_merge_service.dart';

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
  full('完整恢复', '恢复 data 与 docs 目录'),
  libraryOnly('仅恢复文库数据', '恢复文献库、收藏、标注和文档文件'),
  settingsOnly('仅恢复设置', '恢复设置类数据');

  const BackupRestoreScope(this.label, this.description);

  final String label;
  final String description;

  bool get restoreLibrary => this != BackupRestoreScope.settingsOnly;
  bool get restoreSettings => this != BackupRestoreScope.libraryOnly;
}

enum RestoreMode {
  overwrite('覆盖恢复', '清除本地数据后用备份替换'),
  merge('合并恢复', '保留本地数据，仅添加备份中不存在的内容');

  const RestoreMode(this.label, this.description);

  final String label;
  final String description;
}

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
  }) async {
    final createdAt = DateTime.now();
    await GStorage.flush();

    final manifest = <String, dynamic>{
      'app': 'OtterPad',
      'formatVersion': _formatVersion,
      'createdAt': createdAt.toIso8601String(),
      'scope': scope.name,
      'libraryRoot': GStorage.libraryDirPath,
      'dbRoot': GStorage.dbDirPath,
      'dbFile': _dbFileName,
      ...?manifestExtra,
    };

    final tempDir = await _getBackupTempDir();
    final outputPath = p.join(tempDir.path, buildBackupFileName(createdAt));
    // VACUUM INTO 生成一致快照（不阻塞写、不撕裂 WAL）。
    final snapshotPath = p.join(tempDir.path, 'snapshot_$_dbFileName');
    await GStorage.db.customStatement("VACUUM INTO '$snapshotPath'");

    // 打包在后台 isolate 流式进行（只 zip 文件，不碰 DB 连接）。
    await compute(_createArchiveInIsolate, <String>[
      outputPath,
      GStorage.libraryDirPath,
      snapshotPath,
      const JsonEncoder.withIndent('  ').convert(manifest),
      scope.name,
    ]);

    // 清理临时快照
    try {
      await File(snapshotPath).delete();
    } catch (_) {}
    return outputPath;
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
    await for (final entity in sourceDir.list(recursive: true)) {
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
  }) async {
    onProgress?.call('正在解压备份文件...');
    final tempRoot = await _createRestoreTempRoot();
    final extractedDbPath = p.join(tempRoot.path, 'db', _dbFileName);
    final extractedDocsDir = Directory(p.join(tempRoot.path, 'library'));

    try {
      await _extractArchiveToDirectory(archivePath, tempRoot.path);
      final backupScope = _readManifestScope(tempRoot.path);

      if (mode == RestoreMode.merge) {
        return await BackupMergeService.merge(
          backupDbPath: extractedDbPath,
          extractedDocsDir: scope.restoreLibrary ? extractedDocsDir : null,
          scope: scope,
          onProgress: onProgress,
        );
      }

      // ── Overwrite ───────────────────────────────────────────────────
      if (scope == BackupRestoreScope.full) {
        await _overwriteFull(extractedDbPath, extractedDocsDir, backupScope);
      } else if (scope == BackupRestoreScope.libraryOnly) {
        await _overwriteLibraryTables(extractedDbPath, extractedDocsDir);
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

    await GStorage.close();

    // 两步替换的跨步骤回滚：第一步（library）成功后保留 .bak，第二步
    // （db）失败时连第一步一起恢复。
    await _replaceDirectory(docsDir, extractedDocsDir, keepBackup: true);
    try {
      await _replaceFile(File(extractedDbPath), dbFile);
    } catch (_) {
      await _rollbackFromBackup(docsDir);
      await GStorage.reopen();
      rethrow;
    }
    if (backupScope == BackupScope.dataOnly) {
      await _restoreHeavyFilesFromBak(docsDir);
    }
    await _deleteBackupOf(docsDir);
    await GStorage.reopen();
  }

  /// libraryOnly 覆盖：表级替换 library 表（保留 settings/meta）+ library/ 目录。
  static Future<void> _overwriteLibraryTables(
    String extractedDbPath,
    Directory extractedDocsDir,
  ) async {
    final docsDir = Directory(GStorage.libraryDirPath);
    await _replaceDirectory(docsDir, extractedDocsDir, keepBackup: true);
    try {
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
        });
      } finally {
        await backupDb.close();
      }
      await _deleteBackupOf(docsDir);
    } catch (_) {
      await _rollbackFromBackup(docsDir);
      rethrow;
    }
    await GStorage.refreshCache();
  }

  /// settingsOnly 覆盖：表级替换 settings 表（保留其余）。
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
              settingCompanion(r.settingKey, _decode(r.value)),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      });
    } finally {
      await backupDb.close();
    }
    await GStorage.refreshCache();
  }

  /// 把备份表的全部行批量插入活库（已先清空活库对应表）。
  static Future<void> _copyTable(
    db.AppDatabase backupDb,
    dynamic backupTable,
    dynamic liveTable,
    dynamic Function(dynamic row) toCompanion,
  ) async {
    final rows = await backupDb.select(backupTable).get();
    if (rows.isEmpty) return;
    await GStorage.db.batch((b) {
      for (final r in rows) {
        b.insert(liveTable, toCompanion(r), mode: InsertMode.insertOrReplace);
      }
    });
  }

  static Object? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
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
    final archiveBytes = File(archivePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(archiveBytes);

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

      final targetFile = File(targetPath);
      Directory(p.dirname(targetFile.path)).createSync(recursive: true);
      targetFile.writeAsBytesSync(file.readBytes() ?? const <int>[]);
    }
  }

  /// [keepBackup] 为 true 时成功后保留 `.bak` 目录——供调用方做跨步骤
  /// 回滚（见 _overwriteFull），用完须调 [_deleteBackupOf] 清理。
  static Future<void> _replaceDirectory(
    Directory targetDir,
    Directory sourceDir, {
    bool keepBackup = false,
  }) async {
    final backupDir = Directory('${targetDir.path}.bak');
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
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
  static Future<void> _replaceFile(File source, File target) async {
    final backup = File('${target.path}.bak');
    if (await backup.exists()) await backup.delete();
    final hadTarget = await target.exists();
    if (hadTarget) await target.rename(backup.path);
    try {
      await Directory(p.dirname(target.path)).create(recursive: true);
      await source.copy(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (error) {
      if (await target.exists()) await target.delete();
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
  }

  /// 解压根的 manifest.json 里记录的备份范围；缺失或解析失败按 full 处理。
  static BackupScope _readManifestScope(String tempRootPath) {
    try {
      final raw = File(p.join(tempRootPath, 'manifest.json')).readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return BackupScope.values.asNameMap()[json['scope']] ?? BackupScope.full;
    } catch (_) {
      return BackupScope.full;
    }
  }

  /// dataOnly 备份做**覆盖恢复**时的防数据丢失：备份里没有 PDF / 提取
  /// 产物，直接整目录替换会清掉本地重文件。从 `.bak` 把被 dataOnly
  /// 排除的文件拷回**仍存在于备份中的**文献目录；备份里已不存在的文献
  /// 不拷回（尊重备份时刻的删除状态）。
  static Future<void> _restoreHeavyFilesFromBak(Directory docsDir) async {
    final bakDir = Directory('${docsDir.path}.bak');
    if (!await bakDir.exists()) return;
    await for (final entity in bakDir.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: bakDir.path);
      if (includeInDataOnly(_toArchivePath(relative))) continue;
      final parts = p.split(relative);
      if (parts.isEmpty) continue;
      // 文献目录在恢复后的库里不存在 = 备份时已删除，不拷回
      if (!await Directory(p.join(docsDir.path, parts.first)).exists()) {
        continue;
      }
      final targetFile = File(p.join(docsDir.path, relative));
      if (await targetFile.exists()) continue;
      await Directory(p.dirname(targetFile.path)).create(recursive: true);
      await entity.copy(targetFile.path);
    }
  }

  /// 用 `.bak` 把 [targetDir] 恢复到替换前状态（跨步骤回滚用）。
  static Future<void> _rollbackFromBackup(Directory targetDir) async {
    final backupDir = Directory('${targetDir.path}.bak');
    if (!await backupDir.exists()) return;
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await backupDir.rename(targetDir.path);
  }

  static Future<void> _deleteBackupOf(Directory targetDir) async {
    final backupDir = Directory('${targetDir.path}.bak');
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }
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