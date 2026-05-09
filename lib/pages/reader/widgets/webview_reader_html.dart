import 'dart:ui' show Color;

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../../providers/reader_settings_provider.dart';
import '../../../services/translation_style.dart';
import 'reader_background.dart';

// ─── Public API ───

String buildReaderHtml({
  required String markdownContent,
  required ReaderPalette palette,
  required ReaderSettingsState settings,
  required String documentDir,
}) {
  final htmlBody = _markdownToHtml(markdownContent, documentDir);
  final css = _buildCss(palette, settings);
  final js = _buildJs();

  final bgColor = _cssColor(palette.background);

  return '''
<!DOCTYPE html>
<html style="background-color:$bgColor;">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=no">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css"
      crossorigin="anonymous">
<style>$css</style>
</head>
<body>
<article id="content">$htmlBody</article>
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"
        crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"
        crossorigin="anonymous"></script>
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

String _markdownToHtml(String markdown, String documentDir) {
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

  html = _resolveImagePaths(html, documentDir);
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

String _resolveImagePaths(String html, String documentDir) {
  return html.replaceAllMapped(
    RegExp(r'<img\s+([^>]*?)src="([^"]*?)"', caseSensitive: false),
    (match) {
      final attrs = match[1]!;
      final src = match[2]!;
      if (src.startsWith('http://') ||
          src.startsWith('https://') ||
          src.startsWith('file://') ||
          src.startsWith('data:')) {
        return match[0]!;
      }
      final abs = p.join(documentDir, src);
      final uri = Uri.file(abs).toString();
      return '<img ${attrs}src="$uri"';
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

/// 阅读器三套字体族的 CSS 表达。
///
/// 首选 思源宋体 / 思源黑体 / Ubuntu Mono（与 [ReaderFont.fontFamily] 对齐）。
/// 这些字体在 Windows/macOS 默认不预装，通过 Adobe `Source Han ...`、
/// Google `Noto ... CJK SC` 等发行别名和平台原生 CJK 字体兜底，
/// 未安装首选字体时仍能正确渲染中文。
String _cssFontFamily(ReaderFont font) {
  return switch (font) {
    ReaderFont.serif =>
      "'Source Han Serif', 'Source Han Serif SC', 'Noto Serif CJK SC', "
          "'Songti SC', STSong, SimSun, Georgia, 'Times New Roman', serif",
    ReaderFont.sans =>
      "'Source Han Sans', 'Source Han Sans SC', 'Noto Sans CJK SC', "
          "'PingFang SC', 'Microsoft YaHei', system-ui, -apple-system, "
          "'Segoe UI', sans-serif",
    ReaderFont.mono =>
      "'Ubuntu Mono', 'UbuntuMono Nerd Font', 'Cascadia Mono', Consolas, "
          "Menlo, 'Courier New', 'Noto Sans Mono', monospace",
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
    const content = this.container;
    const normalized = searchText.replace(/\s+/g, ' ').trim();
    if (!normalized) return null;

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

    const normFull = fullText.replace(/\s+/g, ' ');
    const idx = normFull.indexOf(normalized);
    if (idx < 0) return null;

    let origIdx = 0;
    const normToOrig = [];
    while (origIdx < fullText.length) {
      if (/\s/.test(fullText[origIdx])) {
        while (origIdx < fullText.length && /\s/.test(fullText[origIdx])) origIdx++;
        normToOrig.push(origIdx > 0 ? origIdx - 1 : 0);
      } else {
        normToOrig.push(origIdx);
        origIdx++;
      }
    }

    const origStart = normToOrig[idx] || 0;
    const origEnd = (normToOrig[idx + normalized.length - 1] || origStart) + 1;

    let startNode = null, startOffset = 0;
    let endNode = null, endOffset = 0;

    for (const entry of nodes) {
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

function _handleSelection() {
  clearTimeout(_selectionTimeout);
  _selectionTimeout = setTimeout(() => {
    if (_isScrolling) return;
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.toString().trim()) {
      _currentSelectionRange = null;
      if (_suppressNextClear) {
        _suppressNextClear = false;
        return;
      }
      if (window.flutter_inappwebview)
        window.flutter_inappwebview.callHandler('onSelectionCleared');
      return;
    }
    const text = sel.toString();
    _currentSelectionRange = sel.getRangeAt(0).cloneRange();
    const rect = sel.getRangeAt(0).getBoundingClientRect();
    const vw = window.innerWidth, vh = window.innerHeight;
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

document.addEventListener('pointerup', (e) => {
  if (e.pointerType !== 'touch') _handleSelection();
});
document.addEventListener('selectionchange', () => {
  if (!_isScrolling) _handleSelection();
});

// ─── 滚动方向检测（passive + rAF，不阻塞滚动线程）───
let _lastScrollY = 0;
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
    const dir = y > _lastScrollY ? 'down' : 'up';
    if (Math.abs(y - _lastScrollY) > 8 && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('onScrollDirection', { direction: dir });
    }
    _lastScrollY = y;
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
