import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/storage/storage.dart';
import '../core/app_logger.dart';

/// 阅读器本地静态文件服务（单例，跨平台一致）。
///
/// **背景**：原本 WebView 用 `file://` 协议加载 HTML 并引用图片，但各平台对
/// `file://` 跨目录引用的策略差异极大（iOS WKWebView 默认拒绝、macOS 沙箱
/// 需 security-scoped bookmark、Android 11+ Scoped Storage 限制）。改用本地
/// HTTP 服务后，HTML 和图片同处一个 `http://localhost:PORT` origin，浏览器
/// 不再有跨目录/跨协议限制，**iOS/Android/macOS/Windows 行为完全一致**。
///
/// 选用 raw [HttpServer] 而非 `flutter_inappwebview` 自带的 `InAppLocalhostServer`：
/// - 后者不暴露 `port` getter，无法用 `port: 0` 让系统自动分配空闲端口；
/// - 自己实现可加细粒度的路径穿越防护（`..` 序列拒绝）；
/// - 仅依赖 `dart:io`，零新包。
///
/// **生命周期**：app 启动时 [start] 一次（main.dart），整个进程共享；
/// reader 切换文档时**不重启 server**，因 root 是 `<AppSupport>/OtterPad/`
/// （所有文献子目录 + hive 数据库的共同祖先目录，由 `GStorage.appRootPath`
/// 提供）。
///
/// **平台配置注意（用户级）**：
/// - **iOS Info.plist**：iOS 14+ 默认 ATS 阻塞明文 HTTP，但 `localhost`
///   通常作为例外。如果 WebView 加载失败，需要在 `ios/Runner/Info.plist`
///   的 `NSAppTransportSecurity` 下加 `NSAllowsLocalNetworking = true`。
/// - **Android Manifest**：Android 9+ 默认禁 cleartext。如 WebView 拒绝
///   `http://localhost`，需在 `AndroidManifest.xml` 的 `<application>`
///   加 `android:usesCleartextTraffic="true"` 或配置 network_security_config
///   给 localhost 单独开例外。
class ReaderLocalhostServer {
  ReaderLocalhostServer._();
  static final ReaderLocalhostServer instance = ReaderLocalhostServer._();

  HttpServer? _server;
  String _root = '';

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  String get root => _root;

  /// 启动服务。多次调用幂等——已运行直接返回。
  ///
  /// [documentRoot] 不传时默认用 [GStorage.appRootPath]。
  /// 绑定 127.0.0.1 + port 0（系统自动分配空闲端口），仅 loopback 可访问。
  Future<void> start({String? documentRoot}) async {
    if (_server != null) return;
    _root = p.normalize(documentRoot ?? GStorage.appRootPath);
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server = server;
    server.listen(
      _handleRequest,
      onError: (Object e) {
        log.d('[ReaderLocalhostServer] connection error: $e');
      },
    );
    log.d(
      '[ReaderLocalhostServer] started on http://127.0.0.1:${server.port} '
      '(root=$_root)',
    );
  }

  Future<void> close() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  /// 把绝对文件路径转成 `http://localhost:PORT/<rel>` URL。
  /// 路径不在 root 下时返回 null（防越界引用）。
  String? urlForPath(String absPath) {
    if (!isRunning) return null;
    final normAbs = p.normalize(absPath);
    final rel = p.relative(normAbs, from: _root);
    // p.relative 在路径不在 _root 下时会返回 `..` 开头的相对路径
    if (rel.startsWith('..') || p.isAbsolute(rel)) {
      log.d(
        '[ReaderLocalhostServer] urlForPath rejected (out of root): $absPath',
      );
      return null;
    }
    // Windows 路径用反斜杠，URL 必须用正斜杠
    final urlPath =
        rel.split(RegExp(r'[/\\]')).map(Uri.encodeComponent).join('/');
    return 'http://localhost:$port/$urlPath';
  }

  // ── 请求处理 ────────────────────────────────────────────────────────────

  /// 路由前缀：URL 命中后从 Flutter rootBundle 服务 asset，而非文件系统。
  /// 用于打包资源（KaTeX 等）：`/_assets/katex/katex.min.css` →
  /// `assets/katex/katex.min.css` in rootBundle。
  static const _assetPrefix = '/_assets/';

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      // 仅允许 GET / HEAD（静态文件服务）
      if (req.method != 'GET' && req.method != 'HEAD') {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
      }

      final urlPath = Uri.decodeComponent(req.uri.path);

      // 优先匹配 asset 路由——asset 不在文件系统，从 rootBundle 读
      if (urlPath.startsWith(_assetPrefix)) {
        await _serveAsset(req, urlPath.substring(_assetPrefix.length));
        return;
      }

      await _serveFile(req, urlPath);
    } catch (e) {
      log.d('[ReaderLocalhostServer] handler error: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// 文件系统静态文件服务（用户文献、图片等）。
  ///
  /// **关键修复**：URL path 是 HTTP 标准 `/` 分隔，且总以 `/` 开头。
  /// 直接 `p.join(_root, urlPath)` 在 Windows / Unix 都会把前导 `/` 解读为
  /// "root-relative"（Win）或 "absolute"（Unix），把 `_root` 整个丢弃 →
  /// fullPath 跑到根目录 → `isWithin` false → 403。
  /// 修法：拿 `/` split urlPath 得到段列表，用 `p.joinAll` 按 platform
  /// 偏好的 separator 重组——天然跨平台正确，URL 的 `/` 永远不进 path 包。
  Future<void> _serveFile(HttpRequest req, String urlPath) async {
    final segments =
        urlPath.split('/').where((s) => s.isNotEmpty).toList();
    final fullPath = p.normalize(p.joinAll([_root, ...segments]));

    // 路径穿越防护：normalize 后必须仍在 root 下。
    // p.isWithin 不接受相等情况，单独判等。
    if (fullPath != _root && !p.isWithin(_root, fullPath)) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }

    final file = File(fullPath);
    if (!await file.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    final stat = await file.stat();
    req.response.headers
      ..contentType = ContentType.parse(_mimeType(fullPath))
      ..contentLength = stat.size
      // 缓存按资源类型分流：
      // - HTML：reader HTML 内容随翻译/笔记/markdown 重写频繁变化，且
      //   reload 时 URL 不变，必须 `no-store` 强制 WebView 每次重新拉取，
      //   否则翻译完成后 loadUrl 同 URL 命中旧缓存 → 译文看不见（这正是
      //   引入 cache-control 后踩到的坑：原本 max-age=300 让翻译失效）。
      // - 图片/字体/CSS/JS：内容随磁盘文件变化但写入频率低（figure 提取
      //   后通常不再改），5 分钟缓存加速重复访问、降低 server 压力。
      ..set(
        HttpHeaders.cacheControlHeader,
        _isHtmlPath(fullPath) ? 'no-store' : 'public, max-age=300',
      );

    if (req.method == 'HEAD') {
      await req.response.close();
      return;
    }

    // 流式发送（大图片不一次性读入内存）
    await req.response.addStream(file.openRead());
    await req.response.close();
  }

  /// 从 Flutter asset bundle 服务静态资源（KaTeX、字体等）。
  /// 优势：无需启动时解包到磁盘、版本随 app 升级。
  ///
  /// `assetRelPath` 不允许包含 `..` 序列——asset bundle 没有路径穿越风险，
  /// 但保险起见仍校验。Asset 不存在时 `rootBundle.load` 抛异常，统一 404。
  Future<void> _serveAsset(HttpRequest req, String assetRelPath) async {
    if (assetRelPath.contains('..') || assetRelPath.startsWith('/')) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }

    final assetKey = 'assets/$assetRelPath';
    try {
      final data = await rootBundle.load(assetKey);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      req.response.headers
        ..contentType = ContentType.parse(_mimeType('/$assetRelPath'))
        ..contentLength = bytes.length
        // asset 内容随 app 版本一起更新，可以放心长缓存（1 天）
        ..set(HttpHeaders.cacheControlHeader, 'public, max-age=86400');

      if (req.method == 'HEAD') {
        await req.response.close();
        return;
      }
      req.response.add(bytes);
      await req.response.close();
    } catch (e) {
      log.d('[ReaderLocalhostServer] asset not found: $assetKey ($e)');
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    }
  }

  bool _isHtmlPath(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.html' || ext == '.htm';
  }

  String _mimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.html' || '.htm' => 'text/html; charset=utf-8',
      '.css' => 'text/css; charset=utf-8',
      '.js' || '.mjs' => 'application/javascript; charset=utf-8',
      '.json' => 'application/json; charset=utf-8',
      '.svg' => 'image/svg+xml',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.bmp' => 'image/bmp',
      '.ico' => 'image/x-icon',
      '.woff' => 'font/woff',
      '.woff2' => 'font/woff2',
      '.ttf' => 'font/ttf',
      '.otf' => 'font/otf',
      '.txt' || '.md' => 'text/plain; charset=utf-8',
      '.pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }
}
