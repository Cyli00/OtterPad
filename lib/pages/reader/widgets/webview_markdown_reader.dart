import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../../core/animation_constants.dart';
import '../../../data/models/book/highlight.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../services/haptics.dart';
import '../../../services/reader_localhost_server.dart';
import 'reader_background.dart';
import 'reader_js_bridge.dart';
import 'reader_update_plan.dart';
import 'webview_reader_html.dart';
import '../../../core/app_logger.dart';

class WebViewMarkdownReader extends StatefulWidget {
  final String markdownData;
  final ReaderSettingsState settings;
  final ReaderPalette palette;
  final List<Highlight> highlights;
  final String documentDir;
  final double topInset;
  final double bottomInset;

  final String translationStyleId;
  final double initialScrollProgress;

  /// 横向翻页的进度锚点（视口起始处内容块索引），优先于比率恢复。
  /// 来源是 HistoryEntry.anchorBlock；null = 老数据或纵向模式按比率。
  final int? initialAnchorBlock;
  final String? highlightQuery;

  final void Function(String text, Rect selectionRect, int lineCount)?
  onSelectionEnd;
  final VoidCallback? onSelectionCleared;
  final void Function(Highlight highlight, Rect rect)? onHighlightClick;
  final void Function(String imageSource)? onImageClick;
  final void Function(ScrollDirection direction)? onScrollDirection;

  /// 阅读进度上报（0.0–1.0 + 内容块锚点）。WebView JS 侧已做 500ms 节流。
  final void Function(double progress, int? anchorBlock)? onScrollProgress;

  /// 横向模式边缘点击成功翻页——view 层触发轻触觉反馈。
  final VoidCallback? onPageFlip;

  /// 显式重载纪元：md 内容未变但 figures/*.png 被原地覆盖（AI 排版修复）
  /// 时由 view 层递增，强制 WebView 整页重载以重新请求图片。
  final int reloadEpoch;

  /// 横向翻页模式下点击页面中央触发——view 层据此 toggle 沉浸式工具栏。
  /// vertical 模式下不会被调（JS 侧已 mode 短路）。
  final VoidCallback? onToggleToolbar;

  const WebViewMarkdownReader({
    super.key,
    required this.markdownData,
    required this.settings,
    required this.palette,
    this.highlights = const [],
    required this.documentDir,
    this.translationStyleId = 'themed',
    this.initialScrollProgress = 0,
    this.initialAnchorBlock,
    this.topInset = 0,
    this.bottomInset = 0,
    this.highlightQuery,
    this.onSelectionEnd,
    this.onSelectionCleared,
    this.onHighlightClick,
    this.onImageClick,
    this.onScrollDirection,
    this.onScrollProgress,
    this.onPageFlip,
    this.onToggleToolbar,
    this.reloadEpoch = 0,
  });

  @override
  WebViewMarkdownReaderState createState() => WebViewMarkdownReaderState();
}

class WebViewMarkdownReaderState extends State<WebViewMarkdownReader>
    implements ReaderJsBridgeListener {
  ReaderJsBridge? _bridge;
  final _webViewKey = GlobalKey();

  // 编辑笔记对话框期间，把 InAppWebView 从树中移除（keepAlive 保活原生实例，
  // 恢复时不重载内容），原生 View 脱离 ViewRoot，键盘 insets 动画不再遍历它。
  // 见 [freeze]/[unfreeze]。
  final InAppWebViewKeepAlive _keepAlive = InAppWebViewKeepAlive();
  bool _frozen = false;
  Uint8List? _snapshot;

  // 覆盖滚动条状态：JS rAF 通道更新 metrics；UI 在 1.5s idle 后淡出。
  // _scrollbarVisible 通过 setState 直接驱动 AnimatedOpacity，不放 ValueNotifier
  // 里——metrics 是高频更新（rAF），visible 是低频两态（show/hide），分开走避免
  // 把整个 thumb 重建塞进每帧。
  final ValueNotifier<ReaderScrollMetrics> _scrollMetrics = ValueNotifier(
    const ReaderScrollMetrics(progress: 0, viewportRatio: 1),
  );
  bool _scrollbarVisible = false;
  Timer? _scrollbarHideTimer;
  bool _scrollbarPointerActive = false;

  /// 用户在 WebView 内通过文本选择创建的高亮 id 集合——JS 已直接画 SVG，
  /// 下一次 syncHighlights 不应再添加，否则重复绘制。bridge.syncHighlights
  /// 接受 skipNewIds 参数，这里维护它的来源。
  final _selectionHighlightIds = <String>{};

  /// HTML 写到文献目录内 `<documentDir>/.reader.html`：
  /// - **自包含**：HTML 缓存随文献目录一起被备份/恢复/删除，无需单独清理；
  ///   旧方案放在 `<dataDir>/._readers/<docKey>.html` 时是孤立文件，删文献
  ///   时容易漏（DocCardActions.delete 没显式清理它）；
  /// - `.reader.html` 的 `.` 前缀让 macOS Finder / iOS Files App 默认隐藏；
  /// - server root 在 OtterPad/ 下，URL 形如
  ///   `http://localhost:PORT/library/<documentId>/.reader.html`，与同目录内的
  ///   `figures/Figure_*.png` 共 origin、共 base href，相对路径解析自然。
  String get _htmlFilePath => p.join(widget.documentDir, '.reader.html');

  /// docDir 相对 server root 的子路径（如 `library/<documentId>`），写入 HTML 的
  /// `base href` 标签后，相对图片路径仍能解析到 `library/<documentId>/figures/...`。
  /// 注：URL 用 forward slash，Windows 反斜杠路径需转换。
  String get _docBaseHref {
    final root = ReaderLocalhostServer.instance.root;
    final rel = p.relative(widget.documentDir, from: root);
    final segments = rel
        .split(RegExp(r'[/\\]'))
        .map(Uri.encodeComponent)
        .join('/');
    return '/$segments/';
  }

  /// 首次 HTML 是否已写好——写好前 WebView 不挂载（initialUrlRequest 会
  /// 立即加载，HTML 必须先落盘），build 用纸张底色占位。
  bool _htmlReady = false;

  /// 揭幕控制：纸色幕布盖在 WebView 上方，遮住原生实例创建 → HTML 首帧
  /// paint → 进度恢复的全过程（原生 WebView 在首帧 paint 前刷系统白底，
  /// 是「进入闪白」的来源）。[onContentReady] 恢复完进度后调 [_reveal] 淡出。
  /// [_curtainGone] 在淡出动画结束后把幕布整体出树——幕布上的 spinner 是
  /// 永久动画，不能留在 opacity:0 的层里空转。
  bool _revealed = false;
  bool _curtainGone = false;
  Timer? _revealFallbackTimer;

  @override
  void initState() {
    super.initState();
    _prepareInitialHtml();
  }

  Future<void> _prepareInitialHtml() async {
    await _writeHtmlFile();
    if (mounted) setState(() => _htmlReady = true);
    // 兜底：onContentReady 依赖 window.onload，首屏图片异常时可能迟迟不来。
    // 超时强制揭幕——transparentBackground 下未 paint 区域透出底层纸色，
    // 提前揭幕也不会闪白。
    _revealFallbackTimer = Timer(const Duration(seconds: 3), _reveal);
  }

  void _reveal() {
    _revealFallbackTimer?.cancel();
    if (!mounted || _revealed) return;
    setState(() => _revealed = true);
  }

  @override
  void dispose() {
    _revealFallbackTimer?.cancel();
    _scrollbarHideTimer?.cancel();
    _scrollMetrics.dispose();
    InAppWebViewController.disposeKeepAlive(_keepAlive);
    super.dispose();
  }

  // dispose 不再清理 HTML——`.reader.html` 在文献目录内，随文献删除一起走。
  // 留着的好处：重进同一文献时指纹命中（见 _writeHtmlFile）可跳过整篇
  // parse + 写盘，接近秒开；留下的代价仅几十 KB 磁盘占用，可忽略。

  /// 覆盖滚动条可见性：每次新事件重置 1.5s 淡出计时器。
  /// 用户在 thumb 上按住期间（[_scrollbarPointerActive]）也保持可见。
  void _showScrollbarTransiently() {
    if (!_scrollbarVisible) {
      setState(() => _scrollbarVisible = true);
    }
    _scrollbarHideTimer?.cancel();
    _scrollbarHideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (_scrollbarPointerActive) return;
      setState(() => _scrollbarVisible = false);
    });
  }

  /// Flutter 拖动覆盖条 → JS scrollTo。ratio ∈ [0,1]。
  void _scrollToRatio(double ratio) => _bridge?.scrollToRatio(ratio);

  /// app 版本+构建号——指纹的版本成分：升级后 markdown→HTML 生成逻辑或
  /// reader.css 的 var() 语义可能变化，旧缓存必须失效。进程内只过一次
  /// 平台通道。
  static String? _appVersionCache;

  static Future<String> _appVersion() async {
    if (_appVersionCache != null) return _appVersionCache!;
    final info = await PackageInfo.fromPlatform();
    return _appVersionCache = '${info.version}+${info.buildNumber}';
  }

  /// HTML 生成（整篇 markdown 解析 + 全文正则后处理）与写盘都在后台
  /// isolate 执行——大文献的同步转换此前直接跑在 initState 里，卡住打开
  /// 阅读器的首帧与路由转场（「打开就卡一下」的来源）。
  ///
  /// `.reader.html` 当缓存用：sidecar 指纹文件 `.reader.html.fp` 记录
  /// 内容 hash | 图片 cacheBuster | app 版本，三者都没变就跳过整篇
  /// parse + 写盘（大文献数百 ms~秒级），isolate 只做一次 hash（几十 ms）。
  /// 主题/字号/翻译样式/翻页/top-inset **不进指纹**——[onContentReady]
  /// 会用 widget 当前值无条件重放，缓存 HTML 里烤的旧值被覆写。
  /// debug 构建始终重新生成：开发期改生成器代码不用手动清缓存。
  ///
  /// Isolate 闭包不能捕获 `this`（State 持有 controller 等不可发送对象），
  /// 全部输入先提为局部变量。
  Future<void> _writeHtmlFile() async {
    final markdown = widget.markdownData;
    final palette = widget.palette;
    final settings = widget.settings;
    final styleId = widget.translationStyleId;
    final baseHref = _docBaseHref;
    final buster = _figuresCacheBuster();
    final inset = widget.topInset;
    final bottomInset = widget.bottomInset;
    final path = _htmlFilePath;
    // server root 在主 isolate 取出传入——isolate 内单例未初始化，
    // 否则 file:// 重写失效、图片裂成 alt 文本（见 _rootRelativeUrlForPath）。
    final serverRoot = ReaderLocalhostServer.instance.root;
    final appVersion = await _appVersion();
    final reused = await Isolate.run(() {
      final fingerprint =
          '${md5.convert(utf8.encode(markdown))}|$buster|$appVersion';
      final htmlFile = File(path);
      final fpFile = File('$path.fp');
      String? stored;
      try {
        if (fpFile.existsSync()) stored = fpFile.readAsStringSync();
      } catch (_) {
        // 指纹读不出来按不匹配处理，走重新生成
      }
      if (!kDebugMode && stored == fingerprint && htmlFile.existsSync()) {
        return true;
      }
      // 写入顺序「删 fp → 写 HTML → 写 fp」：中途被杀只会留下无指纹的
      // 半截 HTML，下次必然重新生成，不会把坏文件当缓存加载。
      if (fpFile.existsSync()) fpFile.deleteSync();
      final html = buildReaderHtml(
        markdownContent: markdown,
        palette: palette,
        settings: settings,
        baseHref: baseHref,
        serverRoot: serverRoot,
        translationStyleId: styleId,
        imageCacheBuster: buster,
        topInset: inset,
        bottomInset: bottomInset,
      );
      htmlFile.parent.createSync(recursive: true);
      htmlFile.writeAsStringSync(html);
      fpFile.writeAsStringSync(fingerprint);
      return false;
    });
    if (reused) {
      log.d('[WebViewMarkdownReader] .reader.html 指纹命中，跳过重新生成');
    }
  }

  @override
  void didUpdateWidget(covariant WebViewMarkdownReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // "什么变了 → 该做什么"由纯函数 planUpdates 决定（可无 mock 单测）；
    // 这里只负责把每个动作落到 bridge / 实例态上。
    for (final update in planUpdates(_propsOf(oldWidget), _propsOf(widget))) {
      _applyUpdate(update);
    }
  }

  ReaderProps _propsOf(WebViewMarkdownReader w) => ReaderProps(
    markdownData: w.markdownData,
    palette: w.palette,
    settings: w.settings,
    translationStyleId: w.translationStyleId,
    highlights: w.highlights,
    highlightQuery: w.highlightQuery,
    reloadEpoch: w.reloadEpoch,
  );

  void _applyUpdate(ReaderUpdate update) {
    switch (update) {
      case ReloadContent():
        _reloadContent();
      case ApplyTheme(:final palette, :final settings):
        _bridge?.applyTheme(palette, settings);
      case ApplyPagination(:final mode):
        _bridge?.applyPagination(mode);
      case ApplyTranslationStyle(:final styleId):
        _bridge?.applyTranslationStyle(styleId);
      case SyncHighlights(:final oldHighlights, :final newHighlights):
        _bridge?.syncHighlights(
          oldHighlights,
          newHighlights,
          skipNewIds: _selectionHighlightIds,
        );
        // syncHighlights 已消费过的 selection id 从集合里移除（避免无界增长）。
        _selectionHighlightIds.removeWhere(
          (id) => newHighlights.any((h) => h.id == id),
        );
      case ApplySearchQuery(:final query):
        _bridge?.applySearchQuery(query);
    }
  }

  void _reloadContent() {
    _writeHtmlFile().then((_) {
      if (!mounted) return;
      final url = _readerUrl(cacheBust: true);
      if (url == null) {
        log.d(
          '[WebViewMarkdownReader] localhost server not running or '
          'document outside server root: $_htmlFilePath',
        );
        return;
      }
      _bridge?.reloadUrl(url);
    });
  }

  /// HTML 文件经 localhost server 暴露的 URL：
  /// `http://localhost:PORT/data/._readers/<docHash>.html`
  /// 同 origin 内引用的图片自动走相对路径解析，不再有 file:// 跨域问题。
  ///
  /// [cacheBust]=true 时附加 `?v=<timestamp>` query，强制 WebView 不命中缓存。
  /// 初始加载（initialUrlRequest）不需要 bust——首次加载没有缓存可命中。
  String? _readerUrl({bool cacheBust = false}) {
    final base = ReaderLocalhostServer.instance.urlForPath(_htmlFilePath);
    if (base == null || !cacheBust) return base;
    return '$base?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  // ─── 对外暴露的方法（通过 GlobalKey 调用） ───
  // 都是单行转发到 bridge——bridge 字段未初始化时（WebView 未 ready）静默跳过。

  void scrollToBlockIndex(int index) => _bridge?.scrollToBlock(index);

  void scrollToSearchResult(int index) => _bridge?.scrollToSearchResult(index);

  Future<List<SearchHit>> searchContent(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
  }) async {
    return await _bridge?.searchContent(
          query,
          caseSensitive: caseSensitive,
          wholeWord: wholeWord,
        ) ??
        const [];
  }

  void clearSelection() => _bridge?.clearSelection();

  void flashImage(String filename) => _bridge?.flashImage(filename);

  void addHighlightFromSelection(String id, String color) {
    _selectionHighlightIds.add(id);
    _bridge?.addHighlightFromSelection(id, color);
  }

  /// 暂停背景 WebView——前景弹出 sheet/dialog 时调用，释放 CPU/GPU。
  /// 暂停背景 WebView 的 JS timer / 动画——主题/文本 sheet 弹出期间调用。
  /// 这两个 sheet 需要 WebView **保持可见做实时预览**，所以只能轻暂停（不能
  /// onPause/移除，否则改字号/主题看不到实时变化）。必须配对 [resumeWebView]。
  void pauseWebView() => _bridge?.pauseTimers();

  void resumeWebView() => _bridge?.resumeTimers();

  /// 彻底冻结 WebView——编辑笔记对话框期间调用。onPause 停 compositor →
  /// setState 把 InAppWebView 从树移除（keepAlive 保活），原生 View detach 出
  /// ViewRoot，键盘 insets 动画不再遍历它。
  /// [capture] 为 true 时先截当前帧做占位（sheet 半透出底层用）；对话框已盖满屏
  /// 可传 false 跳过、省去截图延迟让对话框跟手弹出。必须配对 [unfreeze]。
  Future<void> freeze({bool capture = true}) async {
    if (_frozen) return;
    Uint8List? shot;
    if (capture) {
      try {
        shot = await _bridge?.takeScreenshot();
      } catch (_) {}
      if (!mounted) return;
    }
    _bridge?.pauseRendering();
    setState(() {
      _snapshot = shot;
      _frozen = true;
    });
  }

  void unfreeze() {
    if (!_frozen) return;
    _bridge?.resumeRendering();
    if (mounted) {
      setState(() => _frozen = false);
    } else {
      _frozen = false;
    }
  }

  Widget _buildFrozenPlaceholder() {
    final shot = _snapshot;
    if (shot == null) return const SizedBox.expand();
    return SizedBox.expand(
      child: Image.memory(shot, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }

  // ─── 坐标转换 ───

  /// JS 端传来的是 getBoundingClientRect() 的绝对 CSS 像素值（viewport 坐标），
  /// viewport meta = device-width,initial-scale=1 → 1 CSS px = 1 Flutter 逻辑 px。
  /// 只需加上 Widget 在屏幕中的偏移即可转为全局坐标。
  Rect? _viewportToScreen(Map<String, dynamic> data) {
    final box = _webViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final offset = box.localToGlobal(Offset.zero);

    return Rect.fromLTRB(
      (data['left'] as num).toDouble() + offset.dx,
      (data['top'] as num).toDouble() + offset.dy,
      (data['right'] as num).toDouble() + offset.dx,
      (data['bottom'] as num).toDouble() + offset.dy,
    );
  }

  /// 用 figures.json 的 mtime 当 figure 路径的 cache buster.
  /// localhost server 给 PNG 设了 max-age=300,重新提取后同 URL 5 分钟内拿旧字节;
  /// mtime 变化时 URL 加的 `?v=` 也变,自然 cache miss → 新 PNG.
  String _figuresCacheBuster() {
    try {
      final manifest = File(
        p.join(widget.documentDir, 'figures', 'figures.json'),
      );
      if (manifest.existsSync()) {
        return manifest.lastModifiedSync().millisecondsSinceEpoch.toString();
      }
    } catch (_) {}
    return '';
  }

  /// 纸色 + 弱化 spinner——HTML 落盘前的占位和揭幕幕布共用，让「进入 →
  /// 内容就绪」全程背景色恒定、spinner 连续，不再出现多段视觉跳变。
  Widget _loadingCurtain() => ColoredBox(
    color: widget.palette.background,
    child: Center(
      child: CircularProgressIndicator(
        color: widget.palette.secondaryText,
        strokeWidth: 2,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // HTML 还在后台 isolate 生成——先铺纸张底色占位，避免 WebView 加载到
    // 半截文件，也避免占位闪白/闪黑。
    if (!_htmlReady) {
      return _loadingCurtain();
    }

    // 走 localhost server，所有平台同 origin 加载——
    // 不再需要 allowFileAccessFromFileURLs / allowUniversalAccessFromFileURLs。
    // server 未启动时退化到 about:blank（理论上不应发生：main.dart 启动时已 start）。
    final url = _readerUrl() ?? 'about:blank';
    final isHorizontal =
        widget.settings.paginationMode == ReaderPaginationMode.horizontal;

    // _webViewKey 挂在 SizedBox 而非 InAppWebView：PlatformView 的 RenderBox
    // 在 release 模式下 localToGlobal 可能返回 (0,0)，导致坐标转换偏移缺失。
    // SizedBox 是普通 Flutter Widget，localToGlobal 在所有构建模式下均可靠。
    final webView = SizedBox.expand(
      key: _webViewKey,
      child: InAppWebView(
        keepAlive: _keepAlive,
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          // 原生 WebView 从创建到 HTML 首帧 paint 之间默认刷系统白底，暗色/
          // 纸色主题下表现为进入时闪白。透明后这段空窗透出底层纸色背景
          // （view 层 contentBg），配合上方的揭幕幕布彻底消除闪白。
          transparentBackground: true,
          // 必须开 hybrid composition：VD 模式（false）下 WebView 的原生文本选择
          // 手柄与放大镜（PopupWindow）无法叠加到 Flutter 纹理上——表现为手柄消失、
          // 放大镜渲染成黑色圆角矩形。代价是键盘/对话框动画期间 WebView 会逐帧
          // 重合成（ART GC 抖动/掉帧），但阅读器的文本选择是核心交互，优先保证。
          useHybridComposition: true,
          disableContextMenu: true,
          supportZoom: false,
          // 必须允许 WebView 横向滚动：horizontal 模式下 #content 通过
          // scrollLeft 翻页；同时 vertical 模式下也让代码块/表格的
          // overflow-x: auto 能正常工作。
          disableHorizontalScroll: false,
          // 关掉原生滚动条——本组件用 Flutter 覆盖层 [_OverlayScrollbar]
          // 接管视觉 + 拖动交互。Android 原生条 OS 层绘制，CSS 无法接管，
          // 且不可触摸拖动（仅指示器）。
          verticalScrollBarEnabled: false,
          horizontalScrollBarEnabled: false,
        ),
        onWebViewCreated: (controller) {
          _bridge = ReaderJsBridge(controller, this)..attachHandlers();
        },
        onRenderProcessGone: (controller, detail) async {
          await controller.reload();
        },
      ),
    );

    // 冻结态：InAppWebView 不挂载（原生 View detach 出 ViewRoot），改用截图占位。
    Widget content = _frozen ? _buildFrozenPlaceholder() : webView;

    // 揭幕幕布：内容（含进度恢复）就绪前盖住 WebView，淡出后整体出树。
    if (!_curtainGone) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          content,
          IgnorePointer(
            child: AnimatedOpacity(
              duration: kAnim,
              opacity: _revealed ? 0 : 1,
              onEnd: () {
                if (_revealed && mounted) {
                  setState(() => _curtainGone = true);
                }
              },
              child: _loadingCurtain(),
            ),
          ),
        ],
      );
    }

    // horizontal 翻页模式不需要覆盖滚动条——页内有进度页脚（x/y 页码）
    // 和边缘点击翻页，纵向拖动滚动条的交互不存在。
    if (isHorizontal) return content;

    return Stack(
      children: [
        content,
        Positioned(
          top: widget.topInset,
          bottom: widget.bottomInset,
          right: 0,
          child: IgnorePointer(
            ignoring: !_scrollbarVisible,
            child: AnimatedOpacity(
              duration: kAnim,
              opacity: _scrollbarVisible ? 1 : 0,
              child: _OverlayScrollbar(
                metrics: _scrollMetrics,
                onJumpTo: _scrollToRatio,
                onInteractionStart: () {
                  _scrollbarPointerActive = true;
                  _showScrollbarTransiently();
                },
                onInteractionEnd: () {
                  _scrollbarPointerActive = false;
                  _showScrollbarTransiently();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── ReaderJsBridgeListener 实现 ───
  //
  // Bridge 把 JS 端的 9 路 handler 全部归一到这些方法。widget 自己实现，
  // 而不是再绕一层"listener 适配器"——本来 widget 就是回调的天然消费者。

  @override
  void onContentReady() {
    // 主题/翻译样式重放：加载期间到达的 ApplyTheme/ApplyTranslationStyle 被
    // bridge 的 !_contentReady 丢弃，而 planUpdates 是新旧 props 差分——丢弃
    // 后差异不再出现，永不重试。ready 时用 widget 当前值兜底（幂等：HTML
    // 生成时本就带这些值，重放只是覆写同名 CSS 变量/属性）。
    _bridge?.applyTheme(widget.palette, widget.settings);
    _bridge?.applyTranslationStyle(widget.translationStyleId);
    _bridge?.applyTopInset(widget.topInset);
    _bridge?.applyBottomInset(widget.bottomInset);
    // 翻页方式必须在首屏注入：JS 默认 body 没 data-pagination 属性，
    // 视为 vertical；horizontal 时若不注入会以 vertical 渲染首屏，
    // 直到第一次 didUpdateWidget 才切，造成"先看到 vertical 一闪"。
    _bridge?.applyPagination(widget.settings.paginationMode);
    _bridge?.restoreAllHighlights(widget.highlights);
    _bridge?.applySearchQuery(widget.highlightQuery);
    if (widget.initialScrollProgress > 0 || widget.initialAnchorBlock != null) {
      // 揭幕必须等进度恢复的 JS 执行完，否则会看到「先顶部、再跳到上次
      // 位置」的闪动；剩余的 paint 延迟由幕布 240ms 淡出动画掩盖。
      _bridge
          ?.restoreScrollProgress(
            widget.initialScrollProgress,
            anchorBlock: widget.initialAnchorBlock,
          )
          .whenComplete(_reveal);
    } else {
      _reveal();
    }
  }

  @override
  void onSelectionEnd(String text, Map<String, dynamic> rawRect) {
    final rect = _viewportToScreen(rawRect);
    if (rect == null) return;
    final lineCount = (rawRect['lineCount'] as num?)?.toInt() ?? 1;
    widget.onSelectionEnd?.call(text, rect, math.max(1, lineCount));
  }

  @override
  void onSelectionCleared() => widget.onSelectionCleared?.call();

  @override
  void onHighlightClick(String highlightId, Map<String, dynamic> rawPos) {
    final hl = widget.highlights.where((h) => h.id == highlightId).firstOrNull;
    if (hl == null) return;
    final rect = _viewportToScreen(rawPos);
    if (rect == null) return;
    widget.onHighlightClick?.call(hl, rect);
  }

  @override
  void onImageClick(String imageSource) =>
      widget.onImageClick?.call(imageSource);

  @override
  void onScrollDirection(ScrollDirection direction) =>
      widget.onScrollDirection?.call(direction);

  @override
  void onScrollProgress(double progress, int? anchorBlock) =>
      widget.onScrollProgress?.call(progress, anchorBlock);

  @override
  void onPageFlip() {
    // 系统返回手势确认同档的轻触感——仅点击翻页，滑动翻页 JS 侧不发此事件
    Haptics.light();
    widget.onPageFlip?.call();
  }

  @override
  void onScrollMetrics(ReaderScrollMetrics metrics) {
    _scrollMetrics.value = metrics;
    _showScrollbarTransiently();
  }

  @override
  void onToggleToolbar() => widget.onToggleToolbar?.call();
}

// ─── 覆盖滚动条 ─────────────────────────────────────────────────
//
// 12px 宽柱形布局：触摸热区 12px（手指友好），thumb 视觉 6px 居中（精致）。
// 拖动时按 localPosition.dy / trackHeight 反算 ratio，调 onJumpTo。
// thumb min-height 48 防止超长文档下 thumb 缩成针线。
class _OverlayScrollbar extends StatelessWidget {
  final ValueListenable<ReaderScrollMetrics> metrics;
  final ValueChanged<double> onJumpTo;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  const _OverlayScrollbar({
    required this.metrics,
    required this.onJumpTo,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  static const double _trackWidth = 12;
  static const double _thumbWidth = 6;
  static const double _minThumbHeight = 48;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            onInteractionStart();
            final ratio = (d.localPosition.dy / trackHeight).clamp(0.0, 1.0);
            onJumpTo(ratio);
          },
          onTapUp: (_) => onInteractionEnd(),
          onTapCancel: onInteractionEnd,
          onVerticalDragStart: (_) => onInteractionStart(),
          onVerticalDragUpdate: (d) {
            final ratio = (d.localPosition.dy / trackHeight).clamp(0.0, 1.0);
            onJumpTo(ratio);
          },
          onVerticalDragEnd: (_) => onInteractionEnd(),
          onVerticalDragCancel: onInteractionEnd,
          child: SizedBox(
            width: _trackWidth,
            child: ValueListenableBuilder<ReaderScrollMetrics>(
              valueListenable: metrics,
              builder: (context, m, _) {
                final thumbHeight = math.max(
                  _minThumbHeight,
                  trackHeight * m.viewportRatio,
                );
                final maxTop = math.max(0.0, trackHeight - thumbHeight);
                final thumbTop = m.progress * maxTop;
                return Stack(
                  children: [
                    Positioned(
                      top: thumbTop,
                      left: (_trackWidth - _thumbWidth) / 2,
                      width: _thumbWidth,
                      height: thumbHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withAlpha(140),
                          borderRadius: BorderRadius.circular(_thumbWidth / 2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
