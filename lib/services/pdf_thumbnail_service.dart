import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_process_lock.dart';
import '../core/app_logger.dart';

/// PDF 缩略图服务：首次渲染 PDF 首页为 PNG 存入磁盘，后续直接返回文件路径。
///
/// 核心策略：
/// - 首次导入时提取 PDF 第一页，按高分辨率渲染为 PNG
/// - 后续只加载磁盘上的 PNG 文件，不再加载整个 PDF，保证丝滑滚动
/// - 使用全局 [PdfProcessLock] 彻底解决 OOM 问题
class PdfThumbnailService {
  PdfThumbnailService._();
  static final PdfThumbnailService instance = PdfThumbnailService._();

  // 防止同一文件的重复并发请求（如快速滚动时多次请求同一本书）
  final Map<String, Future<String?>> _cachingTasks = {};

  /// 单次渲染超时时间
  static const _renderTimeout = Duration(seconds: 30);

  Future<String> get _cacheDir async {
    final appDir = await getApplicationCacheDirectory();
    final dir = Directory(p.join(appDir.path, 'pdf_thumbnails'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  String _cacheKey(String filePath) {
    return '${md5.convert(filePath.codeUnits)}.png';
  }

  /// 获取缩略图文件路径，无缓存则触发后台渲染并返回。
  Future<String?> getThumbnailPath(String filePath) async {
    final cachePath = p.join(await _cacheDir, _cacheKey(filePath));
    if (await File(cachePath).exists()) return cachePath;

    // 调用方等待超时不代表原生渲染已结束，必须等真实任务结束后才能移除去重记录。
    final task = _cachingTasks.putIfAbsent(
      filePath,
      () => _renderAndSave(
        filePath,
        cachePath,
      ).whenComplete(() => _cachingTasks.remove(filePath)),
    );
    return task.timeout(
      _renderTimeout,
      onTimeout: () {
        log.d('渲染 PDF 首页超时 ($filePath)');
        return null;
      },
    );
  }

  /// 通过全局锁串行渲染 PDF 首页（带超时保护）
  Future<String?> _renderAndSave(String filePath, String cachePath) async {
    return PdfProcessLock.instance.run(() async {
      PdfDocument? document;
      PdfImage? rendered;
      ui.Image? image;
      try {
        document = await PdfDocument.openFile(
          filePath,
          passwordProvider: () => '',
        );
        if (document.pages.isEmpty) return null;

        final page = document.pages.first;

        // 2.5 倍分辨率保证高分屏清晰，但增加最大限制防止崩溃
        const scale = 2.5;
        double renderWidth = page.width * scale;
        double renderHeight = page.height * scale;

        const double maxDimension = 3000.0;
        if (renderWidth > maxDimension || renderHeight > maxDimension) {
          final aspect = page.width / page.height;
          if (renderWidth > renderHeight) {
            renderWidth = maxDimension;
            renderHeight = maxDimension / aspect;
          } else {
            renderHeight = maxDimension;
            renderWidth = maxDimension * aspect;
          }
        }

        rendered = await page.render(
          fullWidth: renderWidth,
          fullHeight: renderHeight,
        );

        if (rendered == null) return null;

        image = await rendered.createImage();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

        if (byteData == null) return null;

        await File(cachePath).writeAsBytes(byteData.buffer.asUint8List());
        return cachePath;
      } catch (e) {
        log.d('渲染 PDF 首页失败 ($filePath): $e');
        return null;
      } finally {
        image?.dispose();
        rendered?.dispose();
        await document?.dispose();
      }
    });
  }

  /// 删除指定文件的缩略图缓存
  Future<void> deleteCacheEntry(String filePath) async {
    try {
      final cache = File(p.join(await _cacheDir, _cacheKey(filePath)));
      if (await cache.exists()) await cache.delete();
    } catch (e) {
      log.d('删除缩略图缓存失败: $e');
    }
  }

  /// 文件重命名后迁移缩略图缓存，避免重新渲染
  Future<void> migrateCacheEntry(String oldPath, String newPath) async {
    if (oldPath == newPath) return;
    try {
      final dir = await _cacheDir;
      final oldCache = File(p.join(dir, _cacheKey(oldPath)));
      if (await oldCache.exists()) {
        final newCache = p.join(dir, _cacheKey(newPath));
        await oldCache.rename(newCache);
      }
    } catch (e) {
      log.d('迁移缩略图缓存失败: $e');
    }
  }

  /// 清除所有缓存
  Future<void> clearCache() async {
    try {
      final dir = Directory(await _cacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      log.d('清除缓存失败: $e');
    }
  }
}
