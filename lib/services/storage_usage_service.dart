import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/storage.dart';

enum StorageGroupKey { papers, chat, cache, logs }

class StorageSubInfo {
  final String id;
  final int bytes;
  final int fileCount;

  const StorageSubInfo({
    required this.id,
    required this.bytes,
    required this.fileCount,
  });
}

class StorageGroupInfo {
  final StorageGroupKey key;
  final int bytes;
  final int fileCount;
  final List<StorageSubInfo> subcategories;

  const StorageGroupInfo({
    required this.key,
    required this.bytes,
    required this.fileCount,
    this.subcategories = const [],
  });
}

class StorageReport {
  final int totalBytes;
  final int totalFiles;
  final List<StorageGroupInfo> groups;

  const StorageReport({
    required this.totalBytes,
    required this.totalFiles,
    required this.groups,
  });
}

class StorageUsageService {
  StorageUsageService._();

  static const _imageExts = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.svg',
  };

  static bool _isImage(String name) =>
      _imageExts.contains(p.extension(name).toLowerCase());

  static Future<StorageReport> computeReport() async {
    final filesC = _Counter();
    final imagesC = _Counter();
    final notesC = _Counter();
    final chatC = _Counter();
    final cacheC = _Counter();
    final logsC = _Counter();

    final libraryDir = Directory(GStorage.libraryDirPath);
    if (await libraryDir.exists()) {
      await for (final entity in libraryDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        int bytes = 0;
        try {
          bytes = await entity.length();
        } catch (_) {}

        final rel = p.relative(entity.path, from: libraryDir.path);
        final parts = p.split(rel);
        if (parts.length < 2) continue;

        final fileName = parts.last;
        final subPath = parts.sublist(1).join('/');

        if (subPath.startsWith('chats/')) {
          chatC.add(bytes);
        } else if (subPath.startsWith('figures/')) {
          imagesC.add(bytes);
        } else if (subPath.startsWith('summary/') && _isImage(fileName)) {
          imagesC.add(bytes);
        } else if (fileName == '.reader.html') {
          cacheC.add(bytes);
        } else {
          filesC.add(bytes);
        }
      }
    }

    final dbDir = Directory(GStorage.dbDirPath);
    if (await dbDir.exists()) {
      await for (final entity in dbDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path).toLowerCase();
        if (!name.startsWith('highlights')) continue;
        int bytes = 0;
        try {
          bytes = await entity.length();
        } catch (_) {}
        notesC.add(bytes);
      }
    }

    await _countDir(await _thumbDir(), cacheC);
    await _countDir(await _tempDir(), cacheC);

    final papersBytes = filesC.bytes + imagesC.bytes + notesC.bytes;
    final papersFiles = filesC.fileCount + imagesC.fileCount + notesC.fileCount;

    final groups = [
      StorageGroupInfo(
        key: StorageGroupKey.papers,
        bytes: papersBytes,
        fileCount: papersFiles,
        subcategories: [
          StorageSubInfo(
            id: 'files',
            bytes: filesC.bytes,
            fileCount: filesC.fileCount,
          ),
          StorageSubInfo(
            id: 'images',
            bytes: imagesC.bytes,
            fileCount: imagesC.fileCount,
          ),
          StorageSubInfo(
            id: 'notes',
            bytes: notesC.bytes,
            fileCount: notesC.fileCount,
          ),
        ],
      ),
      StorageGroupInfo(
        key: StorageGroupKey.chat,
        bytes: chatC.bytes,
        fileCount: chatC.fileCount,
      ),
      StorageGroupInfo(
        key: StorageGroupKey.cache,
        bytes: cacheC.bytes,
        fileCount: cacheC.fileCount,
      ),
      StorageGroupInfo(
        key: StorageGroupKey.logs,
        bytes: logsC.bytes,
        fileCount: logsC.fileCount,
      ),
    ];

    final totalBytes = groups.fold(0, (sum, g) => sum + g.bytes);
    final totalFiles = groups.fold(0, (sum, g) => sum + g.fileCount);

    return StorageReport(
      totalBytes: totalBytes,
      totalFiles: totalFiles,
      groups: groups,
    );
  }

  static Future<void> clearGroups(Set<StorageGroupKey> keys) async {
    for (final key in keys) {
      switch (key) {
        case StorageGroupKey.papers:
          await _clearLibraryMatching(
            (sub, name) => !sub.startsWith('chats/') && name != '.reader.html',
          );
          await GStorage.highlights.clear();
        case StorageGroupKey.chat:
          await _clearLibraryMatching(
            (sub, name) => sub.startsWith('chats/'),
          );
        case StorageGroupKey.cache:
          await _deleteContents(await _thumbDir());
          await _deleteContents(await _tempDir());
          await _clearLibraryMatching((sub, name) => name == '.reader.html');
        case StorageGroupKey.logs:
          break;
      }
    }
  }

  // ── helpers ──

  static Future<void> _countDir(Directory dir, _Counter counter) async {
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        int bytes = 0;
        try {
          bytes = await entity.length();
        } catch (_) {}
        counter.add(bytes);
      }
    } catch (_) {}
  }

  static Future<Directory> _thumbDir() async {
    final cacheDir = await getApplicationCacheDirectory();
    return Directory(p.join(cacheDir.path, 'pdf_thumbnails'));
  }

  static Future<Directory> _tempDir() async {
    final tempDir = await getTemporaryDirectory();
    return Directory(p.join(tempDir.path, 'OtterPad'));
  }

  static Future<void> _clearLibraryMatching(
    bool Function(String subPath, String fileName) predicate,
  ) async {
    final libraryDir = Directory(GStorage.libraryDirPath);
    if (!await libraryDir.exists()) return;
    await for (final entity in libraryDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: libraryDir.path);
      final parts = p.split(rel);
      if (parts.length < 2) continue;
      final fileName = parts.last;
      final subPath = parts.sublist(1).join('/');
      if (predicate(subPath, fileName)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> _deleteContents(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _Counter {
  int bytes = 0;
  int fileCount = 0;
  void add(int b) {
    bytes += b;
    fileCount += 1;
  }
}
