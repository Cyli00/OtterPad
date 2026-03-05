import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// 使用 pdfrx 渲染引擎，提供高效底层 API 读取 PDF 页面
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

  String _cacheKey(String assetPath) {
    return '${md5.convert(assetPath.codeUnits)}.png';
  }

  /// 获取缩略图文件路径，无缓存则触发后台渲染并返回。
  Future<String?> getThumbnailPath(String assetPath) async {
    final cachePath = p.join(await _cacheDir, _cacheKey(assetPath));
    if (await File(cachePath).exists()) return cachePath;

    // 如果任务已经发起，直接复用其对应的 Future 等待结果
    if (_cachingTasks.containsKey(assetPath)) {
      return _cachingTasks[assetPath];
    }

    // 开启渲染提取任务
    final task = _renderAndSaveWithLock(assetPath, cachePath);
    _cachingTasks[assetPath] = task;
    
    try {
      return await task;
    } finally {
      // 提取成功或失败，都必须移除旧任务
      _cachingTasks.remove(assetPath);
    }
  }

  /// 带有串行队列锁的渲染机制，保证同一时刻仅解析一份 PDF
  Future<String?> _renderAndSaveWithLock(String assetPath, String cachePath) async {
    // 简单的 Future chain 机制：串并联锁
    final lock = _processLock;
    final completer = Completer<void>();
    _processLock = completer.future;
    
    // 等到上一个 PDF 处理结束
    await lock;

    PdfDocument? document;
    try {
      // 提供一个空的 passwordProvider，防止因 PDF 包含加密标识（即使不需要真实密码）而抛出异常
      document = await PdfDocument.openAsset(
        assetPath,
        passwordProvider: () => '',
      );
      if (document.pages.isEmpty) return null;

      final page = document.pages.first;

      // 倍数放大分辨率：原先 `fullWidth: page.width` 倍率为 1.0 (等效 72 DPI)，模糊。
      // 这里提高到 2.5 倍以保证现代高分屏 (Retina/OLED) 上封面不会有锯齿
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

      // 保存为 PNG 图像供系统 UI 在内存无缝访问
      await File(cachePath).writeAsBytes(byteData.buffer.asUint8List());
      return cachePath;
    } catch (e) {
      debugPrint('渲染 PDF 首页失败 ($assetPath): $e');
      return null;
    } finally {
      document?.dispose();
      // 最后无论成功失败，当前任务从队列头部移出，释放锁让下个协程接手执行
      completer.complete(); 
    }
  }

  /// 清除所有缓存（如版本更新或手动清理时调用）
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
