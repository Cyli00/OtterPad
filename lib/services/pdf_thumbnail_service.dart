import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF 缩略图服务：首次渲染 PDF 首页为 PNG 存入磁盘，后续直接返回文件路径。
///
/// 核心策略：
/// - 首次导入时提取 PDF 第一页，按高分辨率渲染为 PNG
/// - 后续只加载磁盘上的 PNG 文件，不再加载整个 PDF，保证丝滑滚动
/// - 使用简单的异步 Future 队列（避免重入并发打开）彻底解决 OOM 问题
class PdfThumbnailService {
  PdfThumbnailService._();
  static final PdfThumbnailService instance = PdfThumbnailService._();

  // 防止同一文件的重复并发请求（如快速滚动时多次请求同一本书）
  final Map<String, Future<String?>> _cachingTasks = {};

  // 串行队列锁（Future chain），防止并发打开大量 PDF 导致内存暴胀
  Future<void> _processLock = Future.value();

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

    // 如果任务已经发起，直接复用其对应的 Future 等待结果
    if (_cachingTasks.containsKey(filePath)) {
      return _cachingTasks[filePath];
    }

    // 开启渲染提取任务
    final task = _renderAndSaveWithLock(filePath, cachePath);
    _cachingTasks[filePath] = task;

    try {
      return await task;
    } finally {
      // 提取成功或失败，都必须移除旧任务
      _cachingTasks.remove(filePath);
    }
  }

  /// 带有串行队列锁的渲染机制，保证同一时刻仅解析一份 PDF
  Future<String?> _renderAndSaveWithLock(
      String filePath, String cachePath) async {
    // 简单的 Future chain 机制：串并联锁
    final lock = _processLock;
    final completer = Completer<void>();
    _processLock = completer.future;

    // 等到上一个 PDF 处理结束
    await lock;

    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(
        filePath,
        passwordProvider: () => '',
      );
      if (document.pages.isEmpty) return null;

      final page = document.pages.first;

      // 2.5 倍分辨率保证高分屏清晰
      const scale = 2.5;
      final rendered = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );

      if (rendered == null) return null;

      final image = await rendered.createImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) return null;

      await File(cachePath).writeAsBytes(byteData.buffer.asUint8List());
      return cachePath;
    } catch (e) {
      debugPrint('渲染 PDF 首页失败 ($filePath): $e');
      return null;
    } finally {
      document?.dispose();
      completer.complete();
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
      debugPrint('清除缓存失败: $e');
    }
  }
}
