import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/storage.dart';

/// 可清理的缓存条目。
///
/// 新增缓存路径时只需在 [cacheEntries] 中追加一条。
class CacheEntry {
  final String label;
  final Future<Directory> Function() resolver;

  const CacheEntry({required this.label, required this.resolver});
}

/// 存储清理服务——集中管理缓存清除和数据清除。
///
/// **扩展约定**：新增缓存路径时在 [cacheEntries] 追加 [CacheEntry]；
/// 新增数据路径时在 [dataEntries] 追加。
class StorageCleanupService {
  StorageCleanupService._();

  static final cacheEntries = <CacheEntry>[
    CacheEntry(
      label: 'PDF 缩略图',
      resolver: () async {
        final appDir = await getApplicationCacheDirectory();
        return Directory(p.join(appDir.path, 'pdf_thumbnails'));
      },
    ),
    CacheEntry(
      label: '临时文件',
      resolver: () async {
        final tempDir = await getTemporaryDirectory();
        return Directory(p.join(tempDir.path, 'OtterPad'));
      },
    ),
  ];

  static final dataEntries = <CacheEntry>[
    CacheEntry(
      label: '文献库文件',
      resolver: () async {
        final appDir = await getApplicationDocumentsDirectory();
        return Directory(p.join(appDir.path, 'OtterPad', 'docs'));
      },
    ),
    CacheEntry(
      label: '数据库',
      resolver: () async {
        final appDir = await getApplicationDocumentsDirectory();
        return Directory(p.join(appDir.path, 'OtterPad', 'data'));
      },
    ),
  ];

  /// 计算一组目录的总磁盘占用。
  static Future<int> _sizeOf(List<CacheEntry> entries) async {
    var total = 0;
    for (final entry in entries) {
      final dir = await entry.resolver();
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    }
    return total;
  }

  static Future<int> cacheSize() => _sizeOf(cacheEntries);
  static Future<int> dataSize() => _sizeOf(dataEntries);

  /// 清除所有缓存目录（保留目录本身）。
  static Future<void> clearCache() async {
    for (final entry in cacheEntries) {
      final dir = await entry.resolver();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }

  /// 清除所有数据（文献 + 数据库），完成后重新初始化 Hive。
  static Future<void> clearData() async {
    await GStorage.close();
    for (final entry in dataEntries) {
      final dir = await entry.resolver();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    await GStorage.init();
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
