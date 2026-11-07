import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/rust_backend.dart';
import '../src/rust/maintenance.dart';

enum StorageGroupKey { papers, chat, cache, logs, database }

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

  /// Rust 统计数据目录；缩略图与临时文件在 Flutter 缓存目录，计入缓存组。
  static Future<StorageReport> computeReport() async {
    final rust = await RustBackend.instance.storageReport(
      taskId: rustTaskId('storage-report'),
    );
    final counters = {
      for (final key in StorageGroupKey.values) key: _Counter(),
    };
    for (final usage in rust.groups) {
      final counter = counters[_key(usage.group)]!;
      counter.bytes += usage.bytes.toInt();
      counter.fileCount += usage.files.toInt();
    }
    await _countDir(await _thumbDir(), counters[StorageGroupKey.cache]!);
    await _countDir(await _tempDir(), counters[StorageGroupKey.cache]!);
    final groups = [
      for (final key in StorageGroupKey.values)
        StorageGroupInfo(
          key: key,
          bytes: counters[key]!.bytes,
          fileCount: counters[key]!.fileCount,
        ),
    ];
    return StorageReport(
      totalBytes: groups.fold(0, (sum, g) => sum + g.bytes),
      totalFiles: groups.fold(0, (sum, g) => sum + g.fileCount),
      groups: groups,
    );
  }

  static StorageGroupKey _key(StorageGroup group) => switch (group) {
    StorageGroup.papers => StorageGroupKey.papers,
    StorageGroup.chat => StorageGroupKey.chat,
    StorageGroup.cache || StorageGroup.recovery => StorageGroupKey.cache,
    StorageGroup.logs => StorageGroupKey.logs,
    StorageGroup.database => StorageGroupKey.database,
  };

  static Future<void> clearGroups(Set<StorageGroupKey> keys) async {
    await RustBackend.instance.clearStorage(
      groups: [
        for (final key in keys)
          switch (key) {
            StorageGroupKey.papers => StorageGroup.papers,
            StorageGroupKey.chat => StorageGroup.chat,
            StorageGroupKey.cache => StorageGroup.cache,
            StorageGroupKey.logs => StorageGroup.logs,
            StorageGroupKey.database => StorageGroup.database,
          },
        if (keys.contains(StorageGroupKey.cache)) StorageGroup.recovery,
      ],
      taskId: rustTaskId('storage-clear'),
    );
    if (keys.contains(StorageGroupKey.cache)) {
      await _deleteContents(await _thumbDir());
      await _deleteContents(await _tempDir());
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
