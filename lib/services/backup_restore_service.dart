import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/storage.dart';

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

class BackupRestoreService {
  static const _archiveRoot = 'otter_pad_backup';
  static const _manifestPath = '$_archiveRoot/manifest.json';
  static const _docsDir = '$_archiveRoot/docs';
  static const _dataDir = '$_archiveRoot/data';
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
    final archive = Archive();
    final createdAt = DateTime.now();
    final appRoot = await _getAppRootDir();
    final docsDir = Directory(p.join(appRoot.path, 'docs'));
    final dataDir = Directory(p.join(appRoot.path, 'data'));

    await GStorage.flush();

    final manifest = <String, dynamic>{
      'app': 'OtterPad',
      'formatVersion': _formatVersion,
      'createdAt': createdAt.toIso8601String(),
      'docsRoot': docsDir.path,
      'dataRoot': dataDir.path,
    };

    archive.add(
      ArchiveFile.string(
        _manifestPath,
        const JsonEncoder.withIndent('  ').convert(manifest),
      ),
    );

    await _addDirectoryToArchive(
      archive,
      sourceDir: docsDir,
      archiveRoot: _docsDir,
    );
    await _addDirectoryToArchive(
      archive,
      sourceDir: dataDir,
      archiveRoot: _dataDir,
    );

    final tempDir = await _getBackupTempDir();
    final outputPath = p.join(tempDir.path, buildBackupFileName(createdAt));
    final bytes = ZipEncoder().encodeBytes(archive);
    await File(outputPath).writeAsBytes(bytes, flush: true);
    return outputPath;
  }

  static Future<void> restoreBackupArchive({
    required String archivePath,
    required BackupRestoreScope scope,
  }) async {
    final archiveBytes = await File(archivePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    final manifest = _readJsonMap(
      archive,
      _manifestPath,
      fallback: const <String, dynamic>{},
    );
    final sourceDocsRoot = manifest['docsRoot']?.toString() ?? '';

    final appRoot = await _getAppRootDir();
    final docsDir = Directory(p.join(appRoot.path, 'docs'));
    final dataDir = Directory(p.join(appRoot.path, 'data'));
    final tempRoot = await _createRestoreTempRoot();
    final extractedDocsDir = Directory(p.join(tempRoot.path, 'docs'));
    final extractedDataDir = Directory(p.join(tempRoot.path, 'data'));
    var libraryRestored = false;

    try {
      await _extractArchiveSection(archive, _docsDir, extractedDocsDir);
      await _extractArchiveSection(archive, _dataDir, extractedDataDir);

      await GStorage.close();

      if (scope == BackupRestoreScope.full) {
        await _replaceDirectory(docsDir, extractedDocsDir);
        await _replaceDirectory(dataDir, extractedDataDir);
        libraryRestored = true;
      } else if (scope == BackupRestoreScope.libraryOnly) {
        await _replaceDirectory(docsDir, extractedDocsDir);
        await _replaceBoxFiles(
          fromDir: extractedDataDir,
          toDir: dataDir,
          boxNames: _libraryBoxNames,
        );
        libraryRestored = true;
      } else if (scope == BackupRestoreScope.settingsOnly) {
        await _replaceBoxFiles(
          fromDir: extractedDataDir,
          toDir: dataDir,
          boxNames: _settingsBoxNames,
        );
      }
    } finally {
      await GStorage.reopen();
      if (libraryRestored) {
        await _rewriteRestoredPaths(
          sourceDocsRoot: sourceDocsRoot,
          currentDocsRoot: docsDir.path,
        );
      }
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    }
  }

  static Future<void> _addDirectoryToArchive(
    Archive archive, {
    required Directory sourceDir,
    required String archiveRoot,
  }) async {
    archive.add(ArchiveFile.directory('$archiveRoot/'));
    if (!await sourceDir.exists()) return;

    await for (final entity in sourceDir.list(recursive: true)) {
      final relativePath = _toArchivePath(
        p.relative(entity.path, from: sourceDir.path),
      );

      if (entity is Directory) {
        archive.add(ArchiveFile.directory('$archiveRoot/$relativePath/'));
        continue;
      }
      if (entity is! File) continue;

      archive.add(
        ArchiveFile.bytes(
          '$archiveRoot/$relativePath',
          await entity.readAsBytes(),
        )..lastModTime = entity.lastModifiedSync().millisecondsSinceEpoch ~/ 1000,
      );
    }
  }

  static Future<void> _extractArchiveSection(
    Archive archive,
    String archiveRoot,
    Directory outputDir,
  ) async {
    if (await outputDir.exists()) {
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

    for (final file in archive) {
      if (!file.name.startsWith('$archiveRoot/')) continue;
      final relativePath = file.name.substring('$archiveRoot/'.length);
      if (relativePath.isEmpty) continue;

      final targetPath = p.normalize(
        p.joinAll([outputDir.path, ...relativePath.split('/')]),
      );
      if (!p.isWithin(outputDir.path, targetPath) &&
          targetPath != outputDir.path) {
        throw StateError('备份包中包含非法路径：$relativePath');
      }

      if (!file.isFile) {
        await Directory(targetPath).create(recursive: true);
        continue;
      }

      final targetFile = File(targetPath);
      await Directory(p.dirname(targetFile.path)).create(recursive: true);
      await targetFile.writeAsBytes(file.readBytes() ?? const <int>[]);
    }
  }

  static Future<void> _replaceDirectory(
    Directory targetDir,
    Directory sourceDir,
  ) async {
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
      if (await backupDir.exists()) {
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

  static Future<void> _rewriteRestoredPaths({
    required String sourceDocsRoot,
    required String currentDocsRoot,
  }) async {
    final documentsBox = GStorage.documents;
    final favoritesBox = GStorage.favorites;

    final rawDocuments = documentsBox.get('documents') as List<dynamic>?;
    if (rawDocuments != null) {
      final normalized = rawDocuments.map((item) {
        if (item is! String) return item;
        try {
          final json = Map<String, dynamic>.from(jsonDecode(item) as Map);
          final filePath = json['filePath']?.toString() ?? '';
          json['filePath'] = _remapDocsPath(
            filePath,
            sourceDocsRoot: sourceDocsRoot,
            currentDocsRoot: currentDocsRoot,
          );
          return jsonEncode(json);
        } catch (_) {
          return item;
        }
      }).toList();
      await documentsBox.put('documents', normalized);
    }

    final rawFavorites = favoritesBox.get('favorites') as List<dynamic>?;
    if (rawFavorites != null) {
      final normalized = rawFavorites.map((item) {
        if (item is! String) return item;
        try {
          final json = Map<String, dynamic>.from(jsonDecode(item) as Map);
          final docPaths = (json['docPaths'] as List<dynamic>? ?? const [])
              .map(
                (path) => _remapDocsPath(
                  path.toString(),
                  sourceDocsRoot: sourceDocsRoot,
                  currentDocsRoot: currentDocsRoot,
                ),
              )
              .toList();
          json['docPaths'] = docPaths;
          return jsonEncode(json);
        } catch (_) {
          return item;
        }
      }).toList();
      await favoritesBox.put('favorites', normalized);
    }

    await GStorage.flush();
  }

  static String _remapDocsPath(
    String value, {
    required String sourceDocsRoot,
    required String currentDocsRoot,
  }) {
    final filePath = value.trim();
    if (filePath.isEmpty) return filePath;

    final relative = _extractDocsRelativePath(
      filePath,
      sourceDocsRoot: sourceDocsRoot,
    );
    if (relative == null || relative.isEmpty) {
      return filePath;
    }

    return p.normalize(
      p.joinAll([
        currentDocsRoot,
        ...relative.split('/').where((item) => item.isNotEmpty),
      ]),
    );
  }

  static String? _extractDocsRelativePath(
    String fullPath, {
    required String sourceDocsRoot,
  }) {
    final normalizedPath = _normalizePath(fullPath);
    final normalizedRoot = _normalizePath(sourceDocsRoot);

    if (normalizedRoot.isNotEmpty) {
      final lowerPath = normalizedPath.toLowerCase();
      final lowerRoot = normalizedRoot.toLowerCase();
      if (lowerPath == lowerRoot) {
        return '';
      }
      final prefix = '$lowerRoot/';
      if (lowerPath.startsWith(prefix)) {
        return normalizedPath.substring(normalizedRoot.length + 1);
      }
    }

    final marker = '/otterpad/docs/';
    final index = normalizedPath.toLowerCase().indexOf(marker);
    if (index >= 0) {
      return normalizedPath.substring(index + marker.length);
    }

    return null;
  }

  static List<String> _boxRelatedFileNames(String boxName) {
    return ['$boxName.hive', '$boxName.lock'];
  }

  static Map<String, dynamic> _readJsonMap(
    Archive archive,
    String path, {
    required Map<String, dynamic> fallback,
  }) {
    final file = archive.find(path);
    if (file == null) return fallback;
    final bytes = file.readBytes();
    if (bytes == null) return fallback;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return fallback;
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

  static Future<Directory> _getAppRootDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(appDir.path, 'OtterPad'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
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

  static String _normalizePath(String value) {
    return value.replaceAll('\\', '/').replaceAll(RegExp('/+'), '/').trim();
  }

  static String _toArchivePath(String value) {
    return value.replaceAll('\\', '/');
  }
}
