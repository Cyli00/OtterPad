import 'dart:convert';
import 'package:markdown/markdown.dart' as md;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:path/path.dart' as p;

import '../../../providers/reader_settings_provider.dart';
import '../../../services/translation_style.dart';
import '../../../utils/markdown_preprocessor.dart';
import 'reader_background.dart';
import 'reader_typography.dart';

const readerAssetVersion = 'reader-stable-viewport-6';

// ─── Public API ───

/// 构建完整 HTML 文档。
///
/// [baseHref] 是 docDir 相对 server root 的子路径（如 `/library/<documentId>/`），
/// 注入 `<base>` 标签后浏览器解析所有相对 URL 时都以此为基准——HTML 文件
/// 放在文献目录内也能正确加载同目录下的图片。
///
/// KaTeX 走本地打包，由 [ReaderLocalhostServer] 的 `/_assets/*` 路由从
/// `assets/katex/` rootBundle 服务，零网络依赖、彻底离线可用。
String buildReaderHtml({
  required String markdownContent,
  required ReaderPalette palette,
  required ReaderSettingsState settings,
  required String baseHref,
  // localhost server 的 root 必须由调用方（主 isolate）传入：
  // buildReaderHtml 可能在后台 isolate 执行，那里 ReaderLocalhostServer
  // 单例是未初始化的新实例，直接访问会让 file:// 重写失效、图片裂掉。
  required String serverRoot,
  String translationStyleId = 'themed',
  String imageCacheBuster = '',
  bool desktop = false,
  bool bilingualColumns = false,
  double topInset = 0,
  double bottomInset = 0,
  List<Map<String, dynamic>> readerEntries = const [],
}) {
  var htmlBody = _markdownToHtml(markdownContent, serverRoot, imageCacheBuster);
  if (readerEntries.isNotEmpty) {
    final fragment = html.parseFragment(htmlBody);
    _pairTranslations(fragment, readerEntries);
    final captions = fragment.querySelectorAll('figcaption');
    final pairedIds = fragment
        .querySelectorAll('[data-reader-pair]')
        .map((element) => element.attributes['data-reader-pair'])
        .toSet();
    final byText = <String, List<Map<String, dynamic>>>{};
    for (final entry in readerEntries) {
      if (entry['caption'] == false || pairedIds.contains(entry['id'])) {
        continue;
      }
      byText.putIfAbsent(entry['source'] as String, () => []).add(entry);
    }
    for (final group in byText.entries) {
      final matches = captions
          .where(
            (c) => c.text.replaceAll(RegExp(r'\s+'), ' ').trim() == group.key,
          )
          .toList();
      if (matches.length != group.value.length) continue;
      for (var i = 0; i < matches.length; i++) {
        final caption = matches[i];
        final original = caption.nodes.toList();
        caption.nodes.clear();
        _fillPair(caption, group.value[i], original);
      }
    }
    htmlBody = fragment.outerHtml;
  }
  // CSS 变量块按文档注入 :root：palette/字体可热更新，排版 token 静态注入
  // 一次（reader.css 的数字全部来自 ReaderTypography，不在 CSS 里硬编码）。
  // 静态 CSS 在 assets/reader/reader.css、JS 在 assets/reader/reader.js，
  // 均经 localhost /_assets/* 路由提供（见 ReaderLocalhostServer）。
  // --top-inset：顶部工具栏高度，让正文 padding-top 把首行（标题）顶到工具栏
  // 之下，否则半透明工具栏会压住标题最上沿。
  final rootVars = _cssVarsToCssBlock({
    ...palette.toCssVars(),
    ...settings.toCssVars(),
    ...ReaderTypography.cssVars(),
    '--top-inset': '${topInset}px',
    '--bottom-inset': '${bottomInset}px',
  });

  final bgColor = cssColor(palette.background);

  return '''
<!DOCTYPE html>
<html style="background-color:$bgColor;">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=no">
<base href="$baseHref">
<link rel="stylesheet" href="/_assets/katex/katex.min.css">
<link rel="stylesheet" href="/_assets/reader/reader.css?v=$readerAssetVersion">
<style>:root {
$rootVars
}</style>
</head>
<body data-bilingual-columns="$bilingualColumns" data-desktop="$desktop" data-translation-style="$translationStyleId">
<article id="content">$htmlBody</article>
<script src="/_assets/katex/katex.min.js"></script>
<script src="/_assets/katex/contrib/auto-render.min.js"></script>
<script>window.readerEntries = JSON.parse(decodeURIComponent(escape(atob('${base64Encode(utf8.encode(jsonEncode(readerEntries)))}'))));</script>
<script src="/_assets/reader/reader_anchors.js?v=$readerAssetVersion"></script>
<script src="/_assets/reader/reader.js?v=$readerAssetVersion"></script>
<script src="/_assets/reader/reader_translations.js?v=$readerAssetVersion"></script>
</body>
</html>''';
}

dom.Element _languageCell(String id, String language) => dom.Element.tag('div')
  ..classes.add('reader-language')
  ..attributes['data-paragraph-id'] = id
  ..attributes['data-language'] = language;

void _pairTranslations(dom.Node parent, List<Map<String, dynamic>> entries) {
  final byId = {for (final entry in entries) entry['id']: entry};
  void visit(dom.Node parent) {
    final nodes = parent.nodes.toList();
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is! dom.Comment ||
          !(node.data?.startsWith(' reader-pair:') ?? false)) {
        if (node is dom.Element) visit(node);
        continue;
      }
      final key = (node.data ?? '').trim().substring('reader-pair:'.length);
      final id = utf8.decode(base64Url.decode(key));
      var end = -1;
      for (var j = i + 1; j < nodes.length; j++) {
        final next = nodes[j];
        if (next is! dom.Comment) continue;
        if (next.data?.trim() == 'reader-end') {
          end = j;
          break;
        }
      }
      final entry = byId[id];
      if (end < 0 || entry == null) continue;
      final pair = dom.Element.tag('div')..classes.add('reader-pair');
      parent.insertBefore(pair, node);
      _fillPair(pair, entry, nodes.sublist(i + 1, end));
      node.remove();
      nodes[end].remove();
      i = end;
    }
  }

  visit(parent);
}

String buildReaderTranslationHtml(String translation) =>
    _markdownToHtml(MarkdownPreprocessor.processTranslation(translation), '');

void _fillPair(
  dom.Element pair,
  Map<String, dynamic> entry,
  List<dom.Node> original,
) {
  final id = entry['id'] as String;
  final translated = entry['translated'] as String? ?? '';
  final showTarget = entry['showTranslation'] != false && translated.isNotEmpty;
  pair.classes.add('reader-pair');
  pair.attributes['data-reader-pair'] = id;
  pair.attributes['data-bilingual'] =
      (entry['bilingual'] ??
              (entry['showSource'] != false &&
                  entry['showTranslation'] != false))
          .toString();
  final source = _languageCell(id, 'source')..nodes.addAll(original);
  if (entry['showSource'] == false && showTarget) {
    source.attributes['hidden'] = '';
  }
  final target = _languageCell(id, entry['language'] as String? ?? 'translated')
    ..classes.add('reader-target')
    ..nodes.addAll(
      html
          .parseFragment(
            _sanitizeReaderHtml(
              entry['html'] as String? ??
                  buildReaderTranslationHtml(translated),
            ),
          )
          .nodes
          .toList(),
    );
  if (!showTarget) target.attributes['hidden'] = '';
  if (pair.attributes['data-bilingual'] == 'true') {
    target.classes.add('translated');
  }
  pair
    ..append(source)
    ..append(target);
}

String buildThemeCssVars(ReaderPalette palette, ReaderSettingsState settings) {
  return _cssVarsToJsSetProperty({
    ...palette.toCssVars(),
    ...settings.toCssVars(),
  });
}

/// `Map<varName, value>` → CSS 变量声明块（用于 `:root { ... }` 注入）。
///
/// 输出形如 `  --bg: rgba(...);\n  --text: rgba(...);`，可直接拼进 CSS 字符串。
String _cssVarsToCssBlock(Map<String, String> vars) {
  return vars.entries.map((e) => '  ${e.key}: ${e.value};').join('\n');
}

/// `Map<varName, value>` → JS `setProperty` 调用序列（用于 evaluateJavascript）。
///
/// setProperty 第二个参数必须用**双引号**字面量包裹——字体列表内含字面单引号
/// （如 'Times New Roman'），用单引号包会引发未 escape 的 JS 语法错误，导致
/// 整段 evaluateJavascript silent fail。Dart 三引号字符串里嵌字面双引号无需
/// escape，与 JS 双引号字符串嵌字面单引号无需 escape 刚好双向无冲突。
String _cssVarsToJsSetProperty(Map<String, String> vars) {
  return vars.entries
      .map(
        (e) =>
            'document.documentElement.style.setProperty(\'${e.key}\', "${e.value}");',
      )
      .join('\n');
}

// ─── Markdown → HTML ───

String _markdownToHtml(
  String markdown,
  String serverRoot, [
  String imageCacheBuster = '',
]) {
  var html = md.markdownToHtml(
    markdown,
    extensionSet: md.ExtensionSet.gitHubWeb,
    inlineSyntaxes: [_LatexInlinePreserve(), _TranslationInlineSyntax()],
    blockSyntaxes: [_LatexBlockPreserve()],
  );

  html = _injectImageAttrs(html, serverRoot, imageCacheBuster);
  html = _convertFigCaptions(html);
  html = html.replaceAllMapped(
    RegExp(r'<!-- otter-figure:([a-zA-Z0-9_-]+) -->\s*<figure>'),
    (m) => '<figure id="otter-figure-${m[1]}">',
  );
  html = html.replaceAllMapped(
    RegExp(r'<!-- otter-caption:([a-zA-Z0-9_-]+) -->\s*<p>([\s\S]*?)</p>'),
    (m) =>
        '<figcaption class="figure_title" data-caption-id="${m[1]}">${m[2]}</figcaption>',
  );
  final fragment = dom.DocumentFragment.html(html);
  for (final figure in fragment.querySelectorAll('figure[id]')) {
    final caption = figure.querySelector('figcaption');
    if (caption != null) {
      caption.attributes['data-caption-id'] = figure.id.replaceFirst(
        'otter-figure-',
        '',
      );
    }
  }
  html = fragment.outerHtml;
  return _sanitizeReaderHtml(html);
}

const _blockedReaderHtmlTags = <String>{
  'applet',
  'audio',
  'base',
  'body',
  'embed',
  'form',
  'frame',
  'frameset',
  'head',
  'html',
  'iframe',
  'input',
  'link',
  'math',
  'meta',
  'object',
  'option',
  'script',
  'select',
  'source',
  'style',
  'svg',
  'template',
  'textarea',
  'track',
  'video',
};

const _readerUrlAttributes = <String>{
  'action',
  'background',
  'cite',
  'data',
  'formaction',
  'href',
  'imagesrcset',
  'poster',
  'src',
  'srcset',
  'xlink:href',
};

final _unsafeReaderCss = RegExp(
  r'(?:url\s*\(|expression\s*\(|@import|behavior\s*:|-moz-binding\s*:|javascript\s*:)',
  caseSensitive: false,
);

String _sanitizeReaderHtml(String value) {
  final fragment = html.parseFragment(value);
  for (final node in fragment.nodes.toList()) {
    _sanitizeReaderNode(node);
  }
  return fragment.outerHtml;
}

void _sanitizeReaderNode(dom.Node node) {
  if (node is! dom.Element) return;
  final tag = node.localName?.toLowerCase();
  if (tag == null || _blockedReaderHtmlTags.contains(tag)) {
    node.remove();
    return;
  }

  for (final name in node.attributes.keys.toList()) {
    final lowerName = name.toString().toLowerCase();
    final value = node.attributes[name] ?? '';
    final hasUnsafeHandler = lowerName.startsWith('on');
    final hasUnsafeCss =
        lowerName == 'style' && _unsafeReaderCss.hasMatch(value);
    if (hasUnsafeHandler || lowerName == 'srcdoc' || hasUnsafeCss) {
      node.attributes.remove(name);
      continue;
    }
    if (_readerUrlAttributes.contains(lowerName) &&
        !_isSafeReaderUrl(
          value,
          allowDataImage: tag == 'img' && lowerName == 'src',
          allowNavigation: lowerName == 'href' || lowerName == 'cite',
        )) {
      node.attributes.remove(name);
    }
  }

  for (final child in node.nodes.toList()) {
    _sanitizeReaderNode(child);
  }
}

bool _isSafeReaderUrl(
  String raw, {
  required bool allowDataImage,
  required bool allowNavigation,
}) {
  final value = raw.trim();
  if (value.isEmpty) return true;
  if (value.startsWith('//')) return false;
  final normalized = value.replaceAll(RegExp(r'[\u0000-\u0020]'), '');
  final uri = Uri.tryParse(normalized);
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme.isEmpty || scheme == 'http' || scheme == 'https') return true;
  if (allowNavigation && (scheme == 'mailto' || scheme == 'tel')) return true;
  if (!allowDataImage || scheme != 'data') return false;
  final comma = normalized.indexOf(',');
  final mediaType =
      (comma < 0 ? normalized.substring(5) : normalized.substring(5, comma))
          .toLowerCase();
  return mediaType.startsWith('image/png') ||
      mediaType.startsWith('image/jpeg') ||
      mediaType.startsWith('image/gif') ||
      mediaType.startsWith('image/webp') ||
      mediaType.startsWith('image/bmp');
}

/// `<img alt="fig:Caption text" src="...">` → `<figure><img><figcaption>`。
///
/// 无题注图表保留图像，只省略题注节点。
String _convertFigCaptions(String html) {
  return html.replaceAllMapped(
    RegExp(
      r'<p>\s*<img\s+([^>]*?)alt="fig:([^"]*?)"([^>]*?)/?\s*>\s*</p>',
      caseSensitive: false,
    ),
    (m) {
      final caption = m[2]!;
      final before = m[1]!;
      final after = m[3]!;
      if (caption.trim().isEmpty) {
        return '<figure><img ${before}alt=""$after /></figure>';
      }
      return '<figure><img ${before}alt="$caption"$after />'
          '<figcaption class="figure_title">$caption</figcaption></figure>';
    },
  );
}

class _LatexInlinePreserve extends md.InlineSyntax {
  _LatexInlinePreserve() : super(r'\$([^\$\n]+?)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(match[0]!));
    return true;
  }
}

class _TranslationInlineSyntax extends md.InlineSyntax {
  _TranslationInlineSyntax()
    : super(
        '${RegExp.escape(kTranslationMarkerOpen)}'
        r'([\s\S]*?)'
        '${RegExp.escape(kTranslationMarkerClose)}',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match[1] ?? '';
    if (content.isEmpty) return false;
    final el = md.Element.text('span', content);
    el.attributes['class'] = 'translated';
    parser.addNode(el);
    return true;
  }
}

class _LatexBlockPreserve extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^(\$\$|\\?\[)');

  @override
  bool canParse(md.BlockParser parser) {
    final line = parser.current.content.trimLeft();
    return line.startsWith(r'$$') || line.startsWith(r'\[');
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    final firstLine = parser.current.content.trimLeft();
    final isDoubleDollar = firstLine.startsWith(r'$$');
    final closer = isDoubleDollar ? r'$$' : r'\]';
    const openerLength = 2;
    final lines = <String>[];
    var isFirstLine = true;

    while (!parser.isDone) {
      final line = parser.current.content;
      final searchStart = isFirstLine ? openerLength : 0;
      final closeStart = line.indexOf(closer, searchStart);

      if (closeStart >= 0) {
        final closeEnd = closeStart + closer.length;
        lines.add(line.substring(0, closeEnd));
        final trailing = line.substring(closeEnd).trimLeft();
        parser.advance();
        if (trailing.isNotEmpty) {
          _insertLineBeforeCurrent(parser, trailing);
        }
        break;
      }

      lines.add(line);
      parser.advance();
      isFirstLine = false;
    }

    final tex = lines.join('\n');
    final el = md.Element.text('div', tex);
    el.attributes['class'] = 'math-display';
    return el;
  }

  void _insertLineBeforeCurrent(md.BlockParser parser, String content) {
    final line = md.Line(content);
    if (parser.isDone) {
      parser.lines.add(line);
      return;
    }

    final currentIndex = parser.lines.indexOf(parser.current);
    if (currentIndex >= 0) {
      parser.lines.insert(currentIndex, line);
    } else {
      parser.lines.add(line);
    }
  }
}

/// 给 `<img>` 注入 `loading="lazy"` + `decoding="async"` 并把 `file://`
/// 绝对 URL 重写为 server URL：
/// - lazy：屏外图片**不发起下载**，配合 CSS 的 `content-visibility: auto`
///   实现真正的延迟加载（CSS 那个只跳过 layout/paint，不阻止下载）；
/// - async：图片解码不阻塞主线程，避免大图加载瞬间冻屏；
/// - **file:// 转换**：figure 提取管线写入 markdown 的 src 是绝对 file:// URL
///   （`doc_extract_service.dart` 里 `Uri.file(fig.imagePath)`），在 localhost
///   HTTP origin 下浏览器拒绝跨协议加载。把 `file:///<root>/library/<documentId>/...`
///   转成**根相对** URL `/library/<documentId>/...`——HTML 本身经
///   `http://localhost:PORT/...` 加载，根相对路径解析到当前 origin，同 origin
///   加载正常；且 HTML 与端口解耦（端口每次 app 启动随机分配，缓存的
///   `.reader.html` 跨启动复用时若烤死绝对 URL 图片会全裂）。
///   相对路径与 http(s)/data URI 保留原样。
String _injectImageAttrs(
  String html,
  String serverRoot, [
  String cacheBuster = '',
]) {
  const lazyAttrs = 'loading="lazy" decoding="async" ';
  return html.replaceAllMapped(
    RegExp(r'<img\s+([^>]*?)src="([^"]*?)"', caseSensitive: false),
    (match) {
      final attrs = match[1]!;
      final src = match[2]!;
      String resolved = src;
      var fromFileScheme = false;
      if (src.startsWith('file://')) {
        try {
          final filePath = Uri.parse(src).toFilePath();
          final mapped = _rootRelativeUrlForPath(filePath, serverRoot);
          if (mapped != null) {
            resolved = mapped;
            fromFileScheme = true;
          }
        } catch (_) {
          // Uri.parse / toFilePath 失败 → 保留原 src，浏览器按原状处理
        }
      }
      // 给 figure 路径附 `?v=<cacheBuster>` 强制 WebView 不命中旧缓存:
      // localhost server 给非 HTML 资源设了 max-age=300,重新提取后 5 分钟内
      // 同 URL 会拿到旧 PNG. cacheBuster 通常是 figures.json 的 mtime,变化时
      // URL 自然变,等价于 invalidation 信号.
      if (fromFileScheme && cacheBuster.isNotEmpty) {
        final sep = resolved.contains('?') ? '&' : '?';
        resolved = '$resolved${sep}v=$cacheBuster';
      }
      return '<img $lazyAttrs${attrs}src="$resolved"';
    },
  );
}

/// 绝对文件路径 → 根相对 URL（`/library/<documentId>/figures/x.png`）。
///
/// 不带 host:port——HTML 经 localhost 加载后由当前 origin 解析；端口
/// 每次 app 启动随机分配，烤死绝对 URL 会让跨启动复用的缓存 HTML 图片
/// 全裂。只依赖传入的 root，可在后台 isolate 安全运行（不触碰单例状态）。
/// 越界（不在 root 下）返回 null，Windows 反斜杠归一为正斜杠并逐段编码。
String? _rootRelativeUrlForPath(String absPath, String serverRoot) {
  if (serverRoot.isEmpty) return null;
  final rel = p.relative(p.normalize(absPath), from: serverRoot);
  if (rel.startsWith('..') || p.isAbsolute(rel)) return null;
  final urlPath = rel
      .split(RegExp(r'[/\\]'))
      .map(Uri.encodeComponent)
      .join('/');
  return '/$urlPath';
}
