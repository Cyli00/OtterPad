import 'package:markdown/markdown.dart' as md;

import '../../../providers/reader_settings_provider.dart';
import '../../../services/reader_localhost_server.dart';
import '../../../services/translation_style.dart';
import 'reader_background.dart';

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
  String translationStyleId = 'themed',
  String imageCacheBuster = '',
  double topInset = 0,
}) {
  final htmlBody = _markdownToHtml(markdownContent, imageCacheBuster);
  // 动态 CSS 变量块（palette/字体/行高）按文档注入 :root；静态 CSS 在
  // assets/reader/reader.css、JS 在 assets/reader/reader.js，均经 localhost
  // /_assets/* 路由提供（见 ReaderLocalhostServer）。
  // --top-inset：顶部工具栏高度，让正文 padding-top 把首行（标题）顶到工具栏
  // 之下，否则半透明工具栏会压住标题最上沿。
  final rootVars = _cssVarsToCssBlock({
    ...palette.toCssVars(),
    ...settings.toCssVars(),
    '--top-inset': '${topInset}px',
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
<link rel="stylesheet" href="/_assets/reader/reader.css">
<style>:root {
$rootVars
}</style>
</head>
<body data-translation-style="$translationStyleId">
<article id="content">$htmlBody</article>
<script src="/_assets/katex/katex.min.js"></script>
<script src="/_assets/katex/contrib/auto-render.min.js"></script>
<script src="/_assets/reader/reader.js"></script>
</body>
</html>''';
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

String _markdownToHtml(String markdown, [String imageCacheBuster = '']) {
  var html = md.markdownToHtml(
    markdown,
    extensionSet: md.ExtensionSet.gitHubWeb,
    inlineSyntaxes: [_LatexInlinePreserve(), _TranslationInlineSyntax()],
    blockSyntaxes: [_LatexBlockPreserve()],
  );

  html = _injectImageAttrs(html, imageCacheBuster);
  html = _convertFigCaptions(html);
  return html;
}

/// `<img alt="fig:Caption text" src="...">` → `<figure><img><figcaption>`
String _convertFigCaptions(String html) {
  return html.replaceAllMapped(
    RegExp(
      r'<p>\s*<img\s+([^>]*?)alt="fig:([^"]*?)"([^>]*?)/?\s*>\s*</p>',
      caseSensitive: false,
    ),
    (m) {
      final before = m[1]!;
      final caption = m[2]!;
      final after = m[3]!;
      return '<figure><img ${before}alt="$caption"$after />'
          '<figcaption>$caption</figcaption></figure>';
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
///   转成 server URL `http://localhost:PORT/library/<documentId>/...` 后同 origin 加载
///   正常。相对路径与 http(s)/data URI 保留原样。
String _injectImageAttrs(String html, [String cacheBuster = '']) {
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
          final mapped = ReaderLocalhostServer.instance.urlForPath(filePath);
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

