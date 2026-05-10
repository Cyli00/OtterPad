import 'dart:ui' show Color;

import 'package:markdown/markdown.dart' as md;

import '../../../providers/reader_settings_provider.dart';
import '../../../services/reader_localhost_server.dart';
import '../../../services/translation_style.dart';
import 'reader_background.dart';

// ─── Public API ───

/// 构建完整 HTML 文档。
///
/// [baseHref] 是 docDir 相对 server root 的子路径（如 `/docs/abc123/`），
/// 注入 `<base>` 标签后浏览器解析所有相对 URL 时都以此为基准——HTML 文件
/// 实际放在 `<dataDir>/_readers/<hash>.html` 仍能正确加载图片。
///
/// KaTeX 走本地打包，由 [ReaderLocalhostServer] 的 `/_assets/*` 路由从
/// `assets/katex/` rootBundle 服务，零网络依赖、彻底离线可用。
String buildReaderHtml({
  required String markdownContent,
  required ReaderPalette palette,
  required ReaderSettingsState settings,
  required String baseHref,
}) {
  final htmlBody = _markdownToHtml(markdownContent);
  final css = _buildCss(palette, settings);
  final js = _buildJs();

  final bgColor = _cssColor(palette.background);

  return '''
<!DOCTYPE html>
<html style="background-color:$bgColor;">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=no">
<base href="$baseHref">
<link rel="stylesheet" href="/_assets/katex/katex.min.css">
<style>$css</style>
</head>
<body>
<article id="content">$htmlBody</article>
<script src="/_assets/katex/katex.min.js"></script>
<script src="/_assets/katex/contrib/auto-render.min.js"></script>
<script>$js</script>
</body>
</html>''';
}

String buildThemeCssVars(ReaderPalette palette, ReaderSettingsState settings) {
  return '''
    document.documentElement.style.setProperty('--bg','${_cssColor(palette.background)}');
    document.documentElement.style.setProperty('--text','${_cssColor(palette.text)}');
    document.documentElement.style.setProperty('--secondary','${_cssColor(palette.secondaryText)}');
    document.documentElement.style.setProperty('--link','${_cssColor(palette.link)}');
    document.documentElement.style.setProperty('--divider','${_cssColor(palette.divider)}');
    document.documentElement.style.setProperty('--code-bg','${_cssColor(palette.codeBlock)}');
    document.documentElement.style.setProperty('--font-size','${settings.fontSize}px');
    document.documentElement.style.setProperty('--font-family','${_cssFontFamily(settings.font)}');
  ''';
}

// ─── Markdown → HTML ───

String _markdownToHtml(String markdown) {
  var html = md.markdownToHtml(
    markdown,
    extensionSet: md.ExtensionSet.gitHubWeb,
    inlineSyntaxes: [
      _LatexInlinePreserve(),
      _TranslationInlineSyntax(),
    ],
    blockSyntaxes: [
      _LatexBlockPreserve(),
    ],
  );

  html = _injectImageAttrs(html);
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
    final opening = parser.current.content.trimLeft();
    final isDoubleDollar = opening.startsWith(r'$$');
    final closer = isDoubleDollar ? r'$$' : r'\]';
    final lines = <String>[parser.current.content];
    parser.advance();

    while (!parser.isDone) {
      final line = parser.current.content;
      lines.add(line);
      if (line.trimRight().endsWith(closer)) {
        parser.advance();
        break;
      }
      parser.advance();
    }

    final tex = lines.join('\n');
    final el = md.Element.text('div', tex);
    el.attributes['class'] = 'math-display';
    return el;
  }
}

/// 给 `<img>` 注入 `loading="lazy"` + `decoding="async"` 并把 `file://`
/// 绝对 URL 重写为 server URL：
/// - lazy：屏外图片**不发起下载**，配合 CSS 的 `content-visibility: auto`
///   实现真正的延迟加载（CSS 那个只跳过 layout/paint，不阻止下载）；
/// - async：图片解码不阻塞主线程，避免大图加载瞬间冻屏；
/// - **file:// 转换**：figure 提取管线写入 markdown 的 src 是绝对 file:// URL
///   （`doc_extract_service.dart` 里 `Uri.file(fig.imagePath)`），在 localhost
///   HTTP origin 下浏览器拒绝跨协议加载。把 `file:///<dataDir>/docs/<hash>/...`
///   转成 server URL `http://localhost:PORT/docs/<hash>/...` 后同 origin 加载
///   正常。相对路径与 http(s)/data URI 保留原样。
String _injectImageAttrs(String html) {
  const lazyAttrs = 'loading="lazy" decoding="async" ';
  return html.replaceAllMapped(
    RegExp(r'<img\s+([^>]*?)src="([^"]*?)"', caseSensitive: false),
    (match) {
      final attrs = match[1]!;
      final src = match[2]!;
      String resolved = src;
      if (src.startsWith('file://')) {
        try {
          final filePath = Uri.parse(src).toFilePath();
          final mapped =
              ReaderLocalhostServer.instance.urlForPath(filePath);
          if (mapped != null) resolved = mapped;
        } catch (_) {
          // Uri.parse / toFilePath 失败 → 保留原 src，浏览器按原状处理
        }
      }
      return '<img $lazyAttrs${attrs}src="$resolved"';
    },
  );
}

// ─── CSS ───

String _buildCss(ReaderPalette palette, ReaderSettingsState settings) {
  return '''
:root {
  --bg: ${_cssColor(palette.background)};
  --text: ${_cssColor(palette.text)};
  --secondary: ${_cssColor(palette.secondaryText)};
  --link: ${_cssColor(palette.link)};
  --divider: ${_cssColor(palette.divider)};
  --code-bg: ${_cssColor(palette.codeBlock)};
  --font-size: ${settings.fontSize}px;
  --font-family: ${_cssFontFamily(settings.font)};
  --line-height: 1.7;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: var(--font-family);
  font-size: var(--font-size);
  line-height: var(--line-height);
  color: var(--text);
  background-color: var(--bg);
  padding: 20px;
  padding-top: ${settings.fontSize * 0.4 + 20}px;
  padding-bottom: 40px;
  -webkit-user-select: text;
  user-select: text;
  word-wrap: break-word;
  overflow-wrap: break-word;
}

#content { position: relative; max-width: 100%; contain: content; }
#content > * { scroll-margin-top: 60px; }

p, li, blockquote, pre, table, .math-display {
  margin-top: ${settings.fontSize * 0.4}px;
  margin-bottom: ${settings.fontSize * 0.4}px;
}

h1 {
  font-size: calc(var(--font-size) * 1.6);
  font-weight: 700; line-height: 1.3;
  margin-top: ${settings.fontSize * 0.8}px;
  margin-bottom: ${settings.fontSize * 0.4}px;
}
h2 {
  font-size: calc(var(--font-size) * 1.35);
  font-weight: 700; line-height: 1.35;
  margin-top: ${settings.fontSize * 0.7}px;
  margin-bottom: ${settings.fontSize * 0.4}px;
}
h3 {
  font-size: calc(var(--font-size) * 1.15);
  font-weight: 600; line-height: 1.4;
  margin-top: ${settings.fontSize * 0.6}px;
  margin-bottom: ${settings.fontSize * 0.4}px;
}
h4 {
  font-size: calc(var(--font-size) * 1.05);
  font-weight: 600; line-height: 1.4;
}
h5 { font-weight: 600; line-height: 1.4; }
h6 { font-weight: 500; line-height: 1.4; color: var(--secondary); }

a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }

hr { border: none; border-top: 1px solid var(--divider); margin: 1em 0; }

blockquote {
  border-left: 3px solid var(--divider);
  padding-left: 12px;
  color: var(--secondary);
}

pre {
  font-family: Consolas, 'Cascadia Mono', 'Courier New', Menlo, 'Noto Sans Mono', monospace;
  font-size: calc(var(--font-size) * 0.88);
  background: var(--code-bg);
  border-radius: 8px;
  padding: 12px;
  overflow-x: auto;
}

code {
  font-family: Consolas, 'Cascadia Mono', 'Courier New', Menlo, 'Noto Sans Mono', monospace;
  font-size: calc(var(--font-size) * 0.88);
  background: var(--code-bg);
  padding: 1px 4px;
  border-radius: 4px;
}
pre code { background: transparent; padding: 0; }

table {
  border-collapse: collapse;
  width: 100%;
}
th, td {
  border: 0.5px solid var(--divider);
  padding: 8px 12px;
  text-align: left;
}
th { font-weight: 600; }

img {
  max-width: 100%;
  max-height: 33vh;
  display: block;
  margin: 8px auto;
  cursor: pointer;
  scroll-margin-top: 60px;
  scroll-margin-bottom: 60px;
  content-visibility: auto;
}

figure {
  margin: ${settings.fontSize * 0.4}px 0;
  text-align: center;
  scroll-margin-top: 60px;
  scroll-margin-bottom: 60px;
}
figure img { margin: 4px auto; }

figcaption {
  font-size: calc(var(--font-size) * 0.85);
  color: var(--secondary);
  line-height: 1.5;
  padding: 4px 8px 0;
}

.translated { color: var(--link); }

/* KaTeX 默认行内公式 1.21em，在 OtterPad 长文献正文里偏大——撑大行高、
   破坏段落节奏。压回 1.0em 让公式与正文同字号；display 数学维持稍大
   1.1em 强调块级。如果觉得仍偏大可以再降到 0.95em。 */
.katex { font-size: 1.0em; }
.katex-display > .katex { font-size: 1.1em; }

.math-display {
  text-align: center;
  overflow-x: auto;
  padding: 4px 0;
}

.katex-display { overflow-x: auto; overflow-y: hidden; }

::selection { background: rgba(100, 149, 237, 0.3); }

.search-hl {
  background-color: rgba(255, 193, 7, 0.25);
  border-radius: 2px;
  color: inherit;
}
.search-hl-active {
  background-color: rgba(255, 152, 0, 0.6);
  outline: 2px solid rgba(255, 152, 0, 0.8);
  outline-offset: 1px;
  border-radius: 2px;
}

@keyframes img-pulse {
  0%   { box-shadow: 0 0 0 0 rgba(100, 149, 237, 0.6); }
  50%  { box-shadow: 0 0 0 6px rgba(100, 149, 237, 0.25); }
  100% { box-shadow: 0 0 0 0 rgba(100, 149, 237, 0); }
}
.img-flash {
  animation: img-pulse 1s ease-in-out 2;
  border-radius: 4px;
}
''';
}

String _cssColor(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  final a = c.a;
  return 'rgba($r,$g,$b,${a.toStringAsFixed(2)})';
}

/// 阅读器两套字体族的 CSS 表达（与 [ReaderFont.fontFamily] 对齐）。
///
/// `serif` 首选 Times New Roman；`sans` 完全交给浏览器/系统默认
/// （`system-ui`、`-apple-system`、`Segoe UI`），CJK 通过列表里
/// `Noto Serif CJK SC` / `PingFang SC` / `Microsoft YaHei` 等兜底。
String _cssFontFamily(ReaderFont font) {
  return switch (font) {
    ReaderFont.serif =>
      "'Times New Roman', 'Songti SC', STSong, SimSun, "
          "'Noto Serif CJK SC', Georgia, 'Noto Serif', serif",
    ReaderFont.sans =>
      "system-ui, -apple-system, 'Segoe UI', 'PingFang SC', "
          "'Microsoft YaHei', 'Noto Sans CJK SC', sans-serif",
  };
}

// ─── JavaScript ───

String _buildJs() {
  return r'''
// ─── 初始化 ───
// Overlayer 在 DOMContentLoaded 创建，但 onContentReady 延迟到
// window.onload（KaTeX 渲染完、图片加载完后），确保高亮恢复时 DOM 已稳定。
document.addEventListener('DOMContentLoaded', function() {
  window._overlayer = new Overlayer(document.getElementById('content'));
});

window.addEventListener('load', function() {
  if (typeof renderMathInElement === 'function') {
    renderMathInElement(document.body, {
      delimiters: [
        {left: '$$', right: '$$', display: true},
        {left: '\\[', right: '\\]', display: true},
        {left: '$', right: '$', display: false},
        {left: '\\(', right: '\\)', display: false},
      ],
      throwOnError: false,
    });
  }
  // KaTeX 渲染完后重绘已有高亮（如果有的话），再通知 Flutter 可以恢复高亮
  if (window._overlayer) window._overlayer.redraw();

  // **关键**：触发一次 scroll 事件让浏览器重新评估所有 loading="lazy"
  // 图片的可见性。HTML 解析时 KaTeX 还没渲染，浏览器评估视口时 layout
  // 还很短（公式区都是 raw `$x$` 字面量），把首屏外图片误标记为屏外
  // 永不加载；KaTeX 渲染完后 layout 大幅变长，但浏览器**不会自动**
  // 重新评估 lazy 状态——必须人工触发 scroll 事件让 IntersectionObserver
  // 重新跑一遍。否则用户看到的现象是"首次打开图片不显示，切换字号/字体
  // 触发 layout 变化才出现"。
  window.dispatchEvent(new Event('scroll'));

  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('onContentReady');
  }
});

// ─── SVG Overlayer（参照 anx-reader foliate-js/src/overlayer.js）───
class Overlayer {
  constructor(container) {
    this.container = container;
    this.svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    this.svg.style.cssText = 'position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:10;';
    container.style.position = 'relative';
    container.appendChild(this.svg);
    this.map = new Map();

    // ResizeObserver + 防抖：避免连续 reflow 时高频重绘
    this._redrawTimer = null;
    this._observer = new ResizeObserver(() => {
      clearTimeout(this._redrawTimer);
      this._redrawTimer = setTimeout(() => this.redraw(), 150);
    });
    this._observer.observe(container);
  }

  // 按段落拆分 Range，保证跨段落高亮的 getClientRects 精确
  _splitRangeByParagraph(range) {
    const ancestor = range.commonAncestorContainer;
    const pars = ancestor.querySelectorAll
        ? Array.from(ancestor.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote'))
        : [];
    const result = [];
    for (const p of pars) {
      if (!range.intersectsNode(p)) continue;
      const pr = document.createRange();
      pr.selectNodeContents(p);
      if (pr.compareBoundaryPoints(Range.START_TO_START, range) < 0)
        pr.setStart(range.startContainer, range.startOffset);
      if (pr.compareBoundaryPoints(Range.END_TO_END, range) > 0)
        pr.setEnd(range.endContainer, range.endOffset);
      result.push(pr);
    }
    return result.length ? result : [range];
  }

  // 从 Range 计算 content-relative 矩形（不含 scrollX/Y，差值即 content 坐标）
  _getContentRects(range) {
    const cRect = this.container.getBoundingClientRect();
    let rects = [];
    for (const pr of this._splitRangeByParagraph(range)) {
      for (const r of pr.getClientRects()) {
        rects.push({
          left: r.left - cRect.left,
          top: r.top - cRect.top,
          width: r.width,
          height: r.height,
        });
      }
    }
    return this._mergeRects(rects);
  }

  // 绘制一组矩形为 SVG <g>
  _drawGroup(id, rects, color) {
    const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.setAttribute('data-hl-id', id);
    g.style.pointerEvents = 'all';
    g.style.cursor = 'pointer';
    for (const r of rects) {
      const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      rect.setAttribute('x', r.left);
      rect.setAttribute('y', r.top);
      rect.setAttribute('width', r.width);
      rect.setAttribute('height', r.height);
      rect.setAttribute('fill', '#' + color);
      rect.setAttribute('fill-opacity', '0.3');
      rect.setAttribute('rx', '2');
      g.appendChild(rect);
    }
    g.addEventListener('click', (e) => {
      e.stopPropagation();
      e.preventDefault();
      _suppressNextClear = true;
      window.getSelection()?.removeAllRanges();
      if (!window.flutter_inappwebview) return;
      window.flutter_inappwebview.callHandler('onHighlightClick', {
        id: id,
        x: e.clientX / window.innerWidth,
        y: e.clientY / window.innerHeight,
      });
    });
    return g;
  }

  add(id, range, color) {
    this.remove(id);
    const rects = this._getContentRects(range);
    if (!rects.length) return;
    const g = this._drawGroup(id, rects, color);
    this.svg.appendChild(g);
    // 关键：存储 Range 对象，redraw 时重新 getClientRects
    this.map.set(id, { range, color, element: g, rects });
  }

  addByText(id, text, color) {
    const range = this._findTextRange(text);
    if (!range) return false;
    this.add(id, range, color);
    return true;
  }

  // 批量从文本添加多个高亮——共享一次 TreeWalker 扫描 + fullText 索引，
  // 避免每条 highlight 都从头遍历整个 DOM。N=50 高亮在长文献上 N 倍提速。
  addByTextBatch(items) {
    if (!items || !items.length) return;
    const idx = this._buildTextIndex();
    for (const item of items) {
      const range = this._findTextRangeWithIndex(idx, item.text);
      if (range) this.add(item.id, range, item.color);
    }
  }

  remove(id) {
    const obj = this.map.get(id);
    if (!obj) return;
    obj.element.remove();
    this.map.delete(id);
  }

  updateColor(id, color) {
    const obj = this.map.get(id);
    if (!obj) return;
    obj.color = color;
    obj.element.querySelectorAll('rect').forEach(r => r.setAttribute('fill', '#' + color));
  }

  // 核心：从存储的 Range 重新计算所有高亮位置——解决 KaTeX/图片 reflow 漂移
  redraw() {
    for (const [id, obj] of this.map) {
      obj.element.remove();
      const rects = this._getContentRects(obj.range);
      const g = this._drawGroup(id, rects, obj.color);
      this.svg.appendChild(g);
      obj.element = g;
      obj.rects = rects;
    }
  }

  hitTest(x, y) {
    const cRect = this.container.getBoundingClientRect();
    const cx = x - cRect.left, cy = y - cRect.top;
    const arr = Array.from(this.map.entries());
    for (let i = arr.length - 1; i >= 0; i--) {
      const [key, obj] = arr[i];
      for (const r of obj.rects) {
        if (r.left <= cx && cx <= r.left + r.width && r.top <= cy && cy <= r.top + r.height)
          return [key, obj.range];
      }
    }
    return [];
  }

  _mergeRects(rects) {
    if (rects.length <= 1) return rects;
    const sorted = [...rects].sort((a, b) => a.top - b.top || a.left - b.left);
    const merged = [sorted[0]];
    for (let i = 1; i < sorted.length; i++) {
      const prev = merged[merged.length - 1];
      const curr = sorted[i];
      if (Math.abs(curr.top - prev.top) < 3 && Math.abs(curr.left - (prev.left + prev.width)) < 2) {
        merged[merged.length - 1] = {
          left: prev.left, top: prev.top,
          width: curr.left + curr.width - prev.left,
          height: Math.max(prev.height, curr.height),
        };
      } else {
        merged.push(curr);
      }
    }
    return merged;
  }

  _findTextRange(searchText) {
    return this._findTextRangeWithIndex(this._buildTextIndex(), searchText);
  }

  // 一次性扫描 DOM，构建 {nodes, fullText, normFull, normToOrig} 索引。
  // 重型操作 (~O(总文本字符数))；批量定位时调一次后多次复用。
  _buildTextIndex() {
    const content = this.container;
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => {
        let el = node.parentElement;
        while (el && el !== content) {
          if (el.classList.contains('katex-mathml')) return NodeFilter.FILTER_REJECT;
          el = el.parentElement;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    const nodes = [];
    let fullText = '';
    while (walker.nextNode()) {
      nodes.push({ node: walker.currentNode, start: fullText.length });
      fullText += walker.currentNode.textContent;
    }
    // normalized → orig 映射：把多空白合并后的 normFull 反查回 fullText 偏移
    const normToOrig = [];
    let origIdx = 0;
    while (origIdx < fullText.length) {
      if (/\s/.test(fullText[origIdx])) {
        while (origIdx < fullText.length && /\s/.test(fullText[origIdx])) origIdx++;
        normToOrig.push(origIdx > 0 ? origIdx - 1 : 0);
      } else {
        normToOrig.push(origIdx);
        origIdx++;
      }
    }
    const normFull = fullText.replace(/\s+/g, ' ');
    return { nodes, fullText, normFull, normToOrig };
  }

  // 用预建索引定位 searchText 对应的 Range——轻量操作 (indexOf + 偏移映射)。
  _findTextRangeWithIndex(idx, searchText) {
    const normalized = searchText.replace(/\s+/g, ' ').trim();
    if (!normalized) return null;
    const findIdx = idx.normFull.indexOf(normalized);
    if (findIdx < 0) return null;

    const origStart = idx.normToOrig[findIdx] || 0;
    const origEnd =
        (idx.normToOrig[findIdx + normalized.length - 1] || origStart) + 1;

    let startNode = null, startOffset = 0;
    let endNode = null, endOffset = 0;

    for (const entry of idx.nodes) {
      const entryEnd = entry.start + entry.node.textContent.length;
      if (!startNode && origStart < entryEnd) {
        startNode = entry.node;
        startOffset = origStart - entry.start;
      }
      if (origEnd <= entryEnd) {
        endNode = entry.node;
        endOffset = origEnd - entry.start;
        break;
      }
    }

    if (!startNode || !endNode) return null;
    const range = document.createRange();
    try {
      range.setStart(startNode, Math.min(startOffset, startNode.textContent.length));
      range.setEnd(endNode, Math.min(endOffset, endNode.textContent.length));
    } catch(e) { return null; }
    return range;
  }
}

// ─── 选择处理 ───
let _selectionTimeout = null;
let _currentSelectionRange = null;
let _suppressNextClear = false;
let _isScrolling = false;
let _scrollIdleTimer = null;

// 上次上报给 Flutter 的 selection 签名 (text|left|top|right|bottom)，
// 用于跨"终止信号"去重——防止"鼠标抬起 + 键盘 keyup + 后续微调"
// 触发的多次 emit 都让 Flutter 端 dismiss/insert 工具栏导致闪烁。
let _lastEmittedSig = '';

function _handleSelection() {
  clearTimeout(_selectionTimeout);
  _selectionTimeout = setTimeout(() => {
    if (_isScrolling) return;
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.toString().trim()) {
      _currentSelectionRange = null;
      _lastEmittedSig = '';
      if (_suppressNextClear) {
        _suppressNextClear = false;
        return;
      }
      if (window.flutter_inappwebview)
        window.flutter_inappwebview.callHandler('onSelectionCleared');
      return;
    }
    const text = sel.toString();
    const rect = sel.getRangeAt(0).getBoundingClientRect();
    const vw = window.innerWidth, vh = window.innerHeight;

    // 签名相同 → 同一选区被多次终止信号触发，已经显示过工具栏，跳过 IPC
    // 节省 Flutter 端 OverlayEntry remove/insert 的开销与视觉闪烁。
    const sig = text + '|' +
        rect.left.toFixed(1) + '|' + rect.top.toFixed(1) + '|' +
        rect.right.toFixed(1) + '|' + rect.bottom.toFixed(1);
    if (sig === _lastEmittedSig) return;
    _lastEmittedSig = sig;

    _currentSelectionRange = sel.getRangeAt(0).cloneRange();
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('onSelectionEnd', {
        text: text,
        left: rect.left / vw,
        top: rect.top / vh,
        right: rect.right / vw,
        bottom: rect.bottom / vh,
      });
    }
  }, 200);
}

// **只听"选择终止"事件**，不再听 selectionchange——后者拖选过程中
// 每像素都 fire，与 pointerup 终止信号双触发是闪烁根因。
// - pointerup：鼠标/触控笔抬起，桌面端拖选的标准终止信号
// - keyup：键盘选择（Shift+Arrow / Ctrl+A 等）的终止信号，覆盖原来
//   依赖 selectionchange 的键盘场景
// 触摸端的选择仍走系统原生 UI，OtterPad 不拦截（disableContextMenu=true
// 仅拦右键菜单，系统选择 handle 不受影响）。
document.addEventListener('pointerup', (e) => {
  if (e.pointerType !== 'touch') _handleSelection();
});
document.addEventListener('keyup', (e) => {
  // 仅在"可能改变选区的键"上响应，避免输入框/快捷键噪音
  if (e.shiftKey || e.key === 'Shift' ||
      e.key === 'ArrowLeft' || e.key === 'ArrowRight' ||
      e.key === 'ArrowUp' || e.key === 'ArrowDown' ||
      e.key === 'Home' || e.key === 'End' ||
      (e.ctrlKey && (e.key === 'a' || e.key === 'A'))) {
    _handleSelection();
  }
});

// ─── 滚动方向检测（passive + rAF + 方向去重，不阻塞滚动线程）───
let _lastScrollY = 0;
let _lastScrollDir = '';
let _scrollRAF = null;
window.addEventListener('scroll', () => {
  // 标记滚动状态，抑制 selectionchange 噪音
  _isScrolling = true;
  clearTimeout(_scrollIdleTimer);
  _scrollIdleTimer = setTimeout(() => { _isScrolling = false; }, 200);

  if (_scrollRAF) return;
  _scrollRAF = requestAnimationFrame(() => {
    _scrollRAF = null;
    const y = window.scrollY;
    const delta = y - _lastScrollY;
    if (Math.abs(delta) <= 8) return;
    const dir = delta > 0 ? 'down' : 'up';
    _lastScrollY = y;
    // 方向真实变化才上报——同向连续滚动只上报第一次。
    // Flutter 端 AnimatedSlide 是状态机（down=隐藏/up=显示），同向重复事件
    // 只浪费 IPC + 触发无意义 setState。
    if (dir === _lastScrollDir) return;
    _lastScrollDir = dir;
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('onScrollDirection', { direction: dir });
    }
  });
}, { passive: true });

// ─── 图片点击 ───
document.addEventListener('click', (e) => {
  const img = e.target.closest('img');
  if (img && window.flutter_inappwebview) {
    e.preventDefault();
    window.flutter_inappwebview.callHandler('onImageClick', { src: img.src });
  }
});

// ─── Bridge 函数（Flutter → JS）───
window.addHighlight = function(id, text, color) {
  if (!window._overlayer) return false;
  return window._overlayer.addByText(id, text, color);
};

// 批量恢复高亮——payload 是 base64(utf8(JSON([{id, text, color}, ...])))。
// base64 是 [A-Za-z0-9+/=] 子集，能安全嵌入 JS 单引号字符串字面量，
// 不需要逐字符 escape highlight.text 中的换行/反斜杠/引号。
window.addHighlightsBatch = function(b64Payload) {
  if (!window._overlayer) return;
  try {
    const json = decodeURIComponent(escape(atob(b64Payload)));
    const items = JSON.parse(json);
    window._overlayer.addByTextBatch(items);
  } catch(e) {
    console.error('addHighlightsBatch failed', e);
  }
};

window.addHighlightFromSelection = function(id, color) {
  if (!window._overlayer || !_currentSelectionRange) return false;
  window._overlayer.add(id, _currentSelectionRange, color);
  window.getSelection()?.removeAllRanges();
  _currentSelectionRange = null;
  return true;
};

window.removeHighlight = function(id) {
  if (window._overlayer) window._overlayer.remove(id);
};

window.updateHighlightColor = function(id, color) {
  if (window._overlayer) window._overlayer.updateColor(id, color);
};

window.clearSelection = function() {
  window.getSelection()?.removeAllRanges();
  _currentSelectionRange = null;
};

// ─── 滚动导航 ───
window.scrollToBlock = function(index) {
  const blocks = document.querySelectorAll('#content > *');
  if (index >= 0 && index < blocks.length) {
    blocks[index].scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
};

// ─── 搜索高亮 ───
window.highlightSearch = function(query) {
  window.clearSearchHighlight();
  if (!query) return 0;

  const content = document.getElementById('content');
  const lowerQuery = query.toLowerCase();
  const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => {
      let el = node.parentElement;
      while (el && el !== content) {
        if (el.classList.contains('katex') || el.tagName === 'MARK')
          return NodeFilter.FILTER_REJECT;
        el = el.parentElement;
      }
      return NodeFilter.FILTER_ACCEPT;
    }
  });

  const hits = [];
  while (walker.nextNode()) {
    const node = walker.currentNode;
    const text = node.textContent;
    const lower = text.toLowerCase();
    let pos = 0;
    while ((pos = lower.indexOf(lowerQuery, pos)) >= 0) {
      hits.push({ node, offset: pos, length: query.length });
      pos += query.length;
    }
  }

  for (let i = hits.length - 1; i >= 0; i--) {
    const { node, offset, length } = hits[i];
    try {
      const range = document.createRange();
      range.setStart(node, offset);
      range.setEnd(node, offset + length);
      const mark = document.createElement('mark');
      mark.className = 'search-hl';
      mark.id = 'sh' + i;
      range.surroundContents(mark);
    } catch(e) {}
  }

  return hits.length;
};

window.clearSearchHighlight = function() {
  document.querySelectorAll('.search-hl').forEach(mark => {
    const parent = mark.parentNode;
    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parent.normalize();
  });
};

window.scrollToSearchResult = function(index) {
  document.querySelectorAll('.search-hl-active').forEach(e =>
    e.classList.remove('search-hl-active'));
  const el = document.getElementById('sh' + index);
  if (el) {
    el.classList.add('search-hl-active');
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
};

// ─── 图片定位闪烁 ───
window.flashImage = function(filename) {
  const imgs = document.querySelectorAll('#content img');
  for (const img of imgs) {
    if (img.src.includes(filename)) {
      img.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'center' });
      img.classList.add('img-flash');
      setTimeout(() => img.classList.remove('img-flash'), 2000);
      return true;
    }
  }
  return false;
};

window.activateNearestSearchResult = function() {
  const marks = document.querySelectorAll('.search-hl');
  if (!marks.length) return;
  document.querySelectorAll('.search-hl-active').forEach(e =>
    e.classList.remove('search-hl-active'));
  const viewTop = window.scrollY;
  const viewBottom = viewTop + window.innerHeight;
  for (const mark of marks) {
    const absTop = mark.getBoundingClientRect().top + window.scrollY;
    if (absTop >= viewTop - 50 && absTop <= viewBottom) {
      mark.classList.add('search-hl-active');
      return;
    }
  }
};
''';
}
