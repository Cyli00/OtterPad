import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/storage.dart';
import 'backup_merge_service.dart';

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

class BackupRestoreService {
  static const _archiveRoot = 'otter_pad_backup';
  static const _manifestPath = '$_archiveRoot/manifest.json';
  static const _libraryDir = '$_archiveRoot/library';
  static const _dbDir = '$_archiveRoot/db';
  static const _formatVersion = 2;

  static const _settingsBoxNames = {'settings'};
  static const _libraryBoxNames = {'favorites', 'documents', 'highlights'};

  static String buildBackupFileName([DateTime? time]) {
    final value = time ?? DateTime.now();
    String two(int input) => input.toString().padLeft(2, '0');
    return 'otter_pad_backup_'
        '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}.zip';
  }

  static Future<String> createBackupArchive() async {
    final createdAt = DateTime.now();

    await GStorage.flush();

    final manifest = <String, dynamic>{
      'app': 'OtterPad',
      'formatVersion': _formatVersion,
      'createdAt': createdAt.toIso8601String(),
      'libraryRoot': GStorage.libraryDirPath,
      'dbRoot': GStorage.dbDirPath,
    };

    final tempDir = await _getBackupTempDir();
    final outputPath = p.join(tempDir.path, buildBackupFileName(createdAt));

    // 打包在后台 isolate 流式进行：旧实现把整库 readAsBytes 进 Archive、
    // encodeBytes 再生成第二份完整字节（1GB 库瞬时内存 2GB+），且同步压缩
    // 期间 UI 完全冻结。ZipFileEncoder 逐文件流式读写，内存 O(单文件)；
    // 解压方向（_extractInIsolate）早已用 compute，此处对齐。
    await compute(_createArchiveInIsolate, <String>[
      outputPath,
      GStorage.libraryDirPath,
      GStorage.dbDirPath,
      const JsonEncoder.withIndent('  ').convert(manifest),
    ]);
    return outputPath;
  }

  static Future<void> _createArchiveInIsolate(List<String> args) async {
    final outputPath = args[0];
    final libraryDir = Directory(args[1]);
    final dbDir = Directory(args[2]);
    final manifestJson = args[3];

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

      await _addDirectoryStreamed(encoder, libraryDir, _libraryDir);
      await _addDirectoryStreamed(encoder, dbDir, _dbDir);
    } finally {
      await encoder.close();
    }
  }

  /// 逐文件流式加入 zip。空目录条目不再写入——恢复侧写文件时
  /// `create(recursive: true)` 会按需重建目录。
  static Future<void> _addDirectoryStreamed(
    ZipFileEncoder encoder,
    Directory sourceDir,
    String archiveRoot,
  ) async {
    if (!await sourceDir.exists()) return;
    await for (final entity in sourceDir.list(recursive: true)) {
      if (entity is! File) continue;
      final relativePath = _toArchivePath(
        p.relative(entity.path, from: sourceDir.path),
      );
      await encoder.addFile(entity, '$archiveRoot/$relativePath');
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
    final extractedDocsDir = Directory(p.join(tempRoot.path, 'library'));
    final extractedDataDir = Directory(p.join(tempRoot.path, 'db'));

    try {
      await _extractArchiveToDirectory(archivePath, tempRoot.path);

      if (mode == RestoreMode.merge) {
        return await BackupMergeService.merge(
          extractedDataDir: extractedDataDir,
          extractedDocsDir: scope.restoreLibrary ? extractedDocsDir : null,
          scope: scope,
          onProgress: onProgress,
        );
      }

      // ── Overwrite 原逻辑 ────────────────────────────────────────────
      final docsDir = Directory(GStorage.libraryDirPath);
      final dataDir = Directory(GStorage.dbDirPath);

      await GStorage.close();

      // 两步替换的跨步骤回滚：第一步（library）成功后保留 .bak，第二步
      // （db/box）失败时连第一步一起恢复——否则会留下「文献=备份版、
      // 数据库=旧版」的错位状态（_replaceDirectory 自身的回滚只覆盖单步）。
      if (scope == BackupRestoreScope.full) {
        await _replaceDirectory(docsDir, extractedDocsDir, keepBackup: true);
        try {
          await _replaceDirectory(dataDir, extractedDataDir);
        } catch (_) {
          await _rollbackFromBackup(docsDir);
          rethrow;
        }
        await _deleteBackupOf(docsDir);
      } else if (scope == BackupRestoreScope.libraryOnly) {
        await _replaceDirectory(docsDir, extractedDocsDir, keepBackup: true);
        try {
          await _replaceBoxFiles(
            fromDir: extractedDataDir,
            toDir: dataDir,
            boxNames: _libraryBoxNames,
          );
        } catch (_) {
          await _rollbackFromBackup(docsDir);
          rethrow;
        }
        await _deleteBackupOf(docsDir);
      } else if (scope == BackupRestoreScope.settingsOnly) {
        await _replaceBoxFiles(
          fromDir: extractedDataDir,
          toDir: dataDir,
          boxNames: _settingsBoxNames,
        );
      }
      return null;
    } finally {
      await GStorage.reopen();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
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
  /// 回滚（见 restoreBackupArchive），用完须调 [_deleteBackupOf] 清理。
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

  /// 用 `.bak` 把 [targetDir] 恢复到替换前状态（跨步骤回滚用）。
  /// `.bak` 不存在时为 no-op（替换前目标目录本就不存在的情况）。
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

  static Future<void> _replaceBoxFiles({
    required Directory fromDir,
    required Directory toDir,
    required Set<String> boxNames,
  }) async {
    if (!await toDir.exists()) {
      await toDir.create(recursive: true);
    }

    final backups = <String, String>{};
    try {
      for (final boxName in boxNames) {
        for (final fileName in _boxRelatedFileNames(boxName)) {
          final sourceFile = File(p.join(fromDir.path, fileName));
          final targetFile = File(p.join(toDir.path, fileName));
          final backupFile = File('${targetFile.path}.bak');

          if (await backupFile.exists()) {
            await backupFile.delete();
          }
          if (await targetFile.exists()) {
            await targetFile.rename(backupFile.path);
            backups[targetFile.path] = backupFile.path;
          }

          if (await sourceFile.exists()) {
            await File(sourceFile.path).copy(targetFile.path);
          } else if (await backupFile.exists()) {
            await backupFile.rename(targetFile.path);
            backups.remove(targetFile.path);
          }
        }
      }

      for (final backupPath in backups.values) {
        final file = File(backupPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
      for (final entry in backups.entries) {
        final targetFile = File(entry.key);
        final backupFile = File(entry.value);
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        if (await backupFile.exists()) {
          await backupFile.rename(targetFile.path);
        }
      }
      rethrow;
    }
  }

  static List<String> _boxRelatedFileNames(String boxName) {
    return ['$boxName.hive', '$boxName.lock'];
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
