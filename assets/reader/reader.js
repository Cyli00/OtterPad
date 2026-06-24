// ─── 初始化 ───
// Overlayer 在 DOMContentLoaded 创建，但 onContentReady 延迟到
// window.onload（KaTeX 渲染完、图片加载完后），确保高亮恢复时 DOM 已稳定。
document.addEventListener('DOMContentLoaded', function() {
  window._overlayer = new Overlayer(document.getElementById('content'));
});

window.addEventListener('load', function() { _initLazyMath(); });

function _onInitialRenderDone() {
  if (window._overlayer) window._overlayer.redraw();
  window.dispatchEvent(new Event('scroll'));
  if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('onContentReady');
  }
}

function _initLazyMath() {
  const content = document.getElementById('content');
  if (typeof renderMathInElement !== 'function') {
    _onInitialRenderDone();
    return;
  }

  const opts = {
    delimiters: [
      {left: '$$', right: '$$', display: true},
      {left: '\\[', right: '\\]', display: true},
      {left: '$', right: '$', display: false},
      {left: '\\(', right: '\\)', display: false},
    ],
    throwOnError: false,
  };
  const mathRe = /\$|\\\[|\\\(/;
  const vh = window.innerHeight;
  const deferred = [];

  for (const el of content.children) {
    if (el.tagName === 'svg' || el.tagName === 'SVG') continue;
    if (!el.classList.contains('math-display') && !mathRe.test(el.textContent)) continue;
    if (el.getBoundingClientRect().top < vh + 300) {
      renderMathInElement(el, opts);
    } else {
      deferred.push(el);
    }
  }

  _onInitialRenderDone();
  if (!deferred.length) return;

  const queue = [];
  let scheduled = false;
  const rIC = window.requestIdleCallback || function(cb) {
    setTimeout(() => cb({ didTimeout: true, timeRemaining: () => 8 }), 16);
  };

  function scheduleFlush() {
    if (scheduled || !queue.length) return;
    scheduled = true;
    // timeout 收窄到 150ms：快速 fling 时主线程持续繁忙、rIC 一直拿不到 idle，
    // 旧的 500ms 会让公式停在未渲染态约半秒（明显露白）。150ms 上限把最坏空窗
    // 压到约一帧多，didTimeout 分支会照常渲染。
    rIC(flushQueue, { timeout: 150 });
  }

  function flushQueue(deadline) {
    scheduled = false;
    while (queue.length && (deadline.timeRemaining() > 3 || deadline.didTimeout)) {
      renderMathInElement(queue.shift(), opts);
    }
    if (window._overlayer) window._overlayer.redraw();
    window.dispatchEvent(new Event('scroll'));
    if (queue.length) scheduleFlush();
  }

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      queue.push(entry.target);
    }
    scheduleFlush();
    // rootMargin 800px（约一屏）给 rIC 更多提前量：公式还在屏外一屏时就入队，
    // 多数滚动下渲染能赶在它真正可见之前完成。
  }, { rootMargin: '800px' });

  for (const block of deferred) {
    observer.observe(block);
  }
}

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

  // 同步 SVG 尺寸到内容坐标系。横向翻页时 #content 横向溢出（scrollWidth >>
  // clientWidth），width:100% 只覆盖一个视口宽，必须撑到 scrollWidth 才能容纳
  // 所有列的高亮 rect（配合 _getContentRects 的绝对坐标）；纵向恢复 100%。
  _syncSvgSize() {
    if (document.body.dataset.pagination === 'horizontal') {
      this.svg.style.width = this.container.scrollWidth + 'px';
      this.svg.style.height = this.container.clientHeight + 'px';
    } else {
      this.svg.style.width = '100%';
      this.svg.style.height = '100%';
    }
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

  // 从 Range 计算 SVG-relative 矩形（scroll-content 坐标系）。
  //
  // SVG 是 position:absolute;top:0;left:0 在 position:relative 的 #content
  // 内——containing block = #content 的 padding box，SVG 原点 = padding-box
  // 顶端 = border-box 顶端（无 border）= cRect.top/left。
  // getBoundingClientRect() 返回 viewport 坐标，减去 cRect 得 border-box 内坐标。
  //
  // 横向翻页时 #content 自身是横向滚动容器（overflow-x:auto），SVG 作为它的
  // abspos 子元素随内容一起平移、原点钉在 scroll-content 左缘（page 0）。故须
  // 再加 scrollLeft/scrollTop，把「当前视口相对」换算成「整篇 scroll-content
  // 绝对坐标」，否则非首屏列的高亮会落到 page 0 区被 SVG viewport 裁掉而消失。
  // 纵向模式滚的是 window、#content 自身不滚，scrollLeft/Top 恒为 0，无影响。
  _getContentRects(range) {
    const cRect = this.container.getBoundingClientRect();
    const sx = this.container.scrollLeft;
    const sy = this.container.scrollTop;
    let rects = [];
    for (const pr of this._splitRangeByParagraph(range)) {
      for (const r of pr.getClientRects()) {
        rects.push({
          left: r.left - cRect.left + sx,
          top: r.top - cRect.top + sy,
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
    this._syncSvgSize();
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

  // 核心：从存储的 Range 重新计算所有高亮位置——解决 KaTeX/图片 reflow 漂移。
  // 读写分离：先批量读取所有 getClientRects（1 次强制 layout），
  // 再批量写 SVG（1 次 DOM 更新），避免 N 次 layout thrashing。
  redraw() {
    this._syncSvgSize();
    const updates = [];
    for (const [id, obj] of this.map) {
      updates.push({ id, obj, rects: this._getContentRects(obj.range) });
    }
    for (const { id, obj, rects } of updates) {
      obj.element.remove();
      const g = this._drawGroup(id, rects, obj.color);
      this.svg.appendChild(g);
      obj.element = g;
      obj.rects = rects;
    }
  }

  // 注：当前无调用者（高亮点击走各 <g> 自带的 click 监听）。坐标换算与
  // _getContentRects 对齐（scroll-content 绝对坐标），以便复活时仍正确。
  hitTest(x, y) {
    const cRect = this.container.getBoundingClientRect();
    const cx = x - cRect.left + this.container.scrollLeft;
    const cy = y - cRect.top + this.container.scrollTop;
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
let _pointerIsDown = false;
let _pointerDownTimer = null;

document.addEventListener('pointerdown', () => {
  _pointerIsDown = true;
  // Android WebView 吞掉 pointerup——800ms 无 pointerup 自动解锁 selectionchange
  clearTimeout(_pointerDownTimer);
  _pointerDownTimer = setTimeout(() => { _pointerIsDown = false; }, 800);
});

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

// 三路"选择变化"信号：
// - pointerup：鼠标/触控笔/桌面端拖选的标准终止信号（毫秒级响应）；
//   selection 从有→无时也由它驱动 onSelectionCleared 让工具栏 dismiss。
// - keyup：键盘选择（Shift+Arrow / Ctrl+A 等）的终止信号。
// - selectionchange (debounced)：兜底 Android touch 场景。Android WebView
//   在 native TextSelection 激活期间会**吞掉 pointer 事件**，pointerup 不到
//   DOM——必须依赖 selectionchange 感知"选区出现"。
//
// **关键约束**：selectionchange listener 只在当前**有非空选区**时 schedule
// _handleSelection。Selection 从有→无（被系统/SVG handler 清空）**不**调
// _handleSelection，否则会和 _suppressNextClear 的"消耗一次"模式冲突——
// 点击已有高亮时 SVG g handler 同步清 selection，触发 selectionchange，
// 若让它驱动 _handleSelection，第一次能被 _suppressNextClear 拦住，但后续
// 任何 selection 状态扰动（Overlay 让 WebView 失焦等）就会裸奔 emit clear，
// 工具栏 500ms 后被错误 dismiss。
// "用户主动点空白"清工具栏的需求由 pointerup（桌面）和 Flutter 端
// Overlay 的 outside-tap dismiss（Android）承担。
let _selectionChangeTimer = null;
document.addEventListener('pointerup', (e) => {
  _pointerIsDown = false;
  clearTimeout(_pointerDownTimer);
  _handleSelection();
});
document.addEventListener('selectionchange', () => {
  if (_pointerIsDown) return;
  const sel = window.getSelection();
  if (!sel || sel.isCollapsed || !sel.toString().trim()) return;
  clearTimeout(_selectionChangeTimer);
  _selectionChangeTimer = setTimeout(_handleSelection, 350);
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

// ─── 阅读进度上报（500ms 节流 + 双滚动源）───
// vertical 模式滚 window，horizontal 模式滚 #content；两边事件互不冒泡，所以
// 必须给两个目标各挂一次。Flutter 端的 HistoryNotifier.setProgress 还有 2s
// 防抖 Hive 写盘，这里只负责把 0–1 的比例丢过去——多上报几次代价是 IPC，不写盘。
let _progressThrottleTimer = null;
function _reportScrollProgress() {
  if (_progressThrottleTimer) return;
  _progressThrottleTimer = setTimeout(() => {
    _progressThrottleTimer = null;
    if (!window.flutter_inappwebview) return;
    let ratio = 0;
    if (document.body.dataset.pagination === 'horizontal') {
      const max = _maxPage();
      ratio = max > 0 ? _currentPage() / max : 0;
    } else {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      ratio = max > 0 ? window.scrollY / max : 0;
    }
    if (ratio < 0) ratio = 0;
    if (ratio > 1) ratio = 1;
    // anchorBlock 是位置的内容引用（视口起始处第一个可见块索引）——
    // 比率在字号/窗口尺寸变化后会失真，恢复时横向模式优先用锚点。
    window.flutter_inappwebview.callHandler('onScrollProgress', {
      progress: ratio,
      anchorBlock: _findAnchorBlockIndex(),
    });
  }, 500);
}
window.addEventListener('scroll', _reportScrollProgress, { passive: true });
const _scrollProgressContent = document.getElementById('content');
if (_scrollProgressContent) {
  _scrollProgressContent.addEventListener('scroll', _reportScrollProgress, { passive: true });
}

// ─── 高频滚动度量上报（rAF，~60Hz）+ scrollTo 反向接口 ───
// 给 Flutter 侧覆盖滚动条用的实时位置 + 视口比例。
// 区别于上面的 onScrollProgress：
//   - 频率：rAF（合并到现有 _scrollRAF）vs 500ms timer
//   - payload：progress + viewportRatio vs 仅 progress
//   - 用途：覆盖滚动条 thumb 位置/高度 vs Hive 写盘
// horizontal 模式不上报——那边有自己的页号翻页 UI。
function _reportScrollMetrics() {
  if (!window.flutter_inappwebview) return;
  if (document.body.dataset.pagination === 'horizontal') return;
  const scrollHeight = document.documentElement.scrollHeight;
  const viewHeight = window.innerHeight;
  const max = scrollHeight - viewHeight;
  let progress = max > 0 ? window.scrollY / max : 0;
  if (progress < 0) progress = 0;
  if (progress > 1) progress = 1;
  let viewportRatio = scrollHeight > 0 ? viewHeight / scrollHeight : 1;
  if (viewportRatio < 0.05) viewportRatio = 0.05;
  if (viewportRatio > 1) viewportRatio = 1;
  window.flutter_inappwebview.callHandler('onScrollMetrics', {
    progress: progress,
    viewportRatio: viewportRatio,
  });
}
let _metricsTimer = null;
let _metricsLastTime = 0;
function _scheduleMetricsReport() {
  const now = performance.now();
  if (now - _metricsLastTime >= 50) {
    _metricsLastTime = now;
    clearTimeout(_metricsTimer);
    _metricsTimer = null;
    _reportScrollMetrics();
  } else if (!_metricsTimer) {
    _metricsTimer = setTimeout(() => {
      _metricsTimer = null;
      _metricsLastTime = performance.now();
      _reportScrollMetrics();
    }, 50 - (now - _metricsLastTime));
  }
}
window.addEventListener('scroll', _scheduleMetricsReport, { passive: true });
window.addEventListener('resize', _scheduleMetricsReport, { passive: true });
window.addEventListener('load', () => setTimeout(_reportScrollMetrics, 100));

// Flutter 拖动覆盖滚动条时调这个：ratio ∈ [0,1] → window.scrollY 绝对像素值。
window._scrollToRatio = function(ratio) {
  const max = document.documentElement.scrollHeight - window.innerHeight;
  if (max <= 0) return;
  const r = Math.max(0, Math.min(1, ratio));
  window.scrollTo({ top: r * max, behavior: 'auto' });
};

window._restoreProgress = function(ratio, anchorBlock) {
  requestAnimationFrame(() => {
    const r = Math.max(0, Math.min(1, ratio));
    if (_isHorizontal()) {
      // 锚点优先：比率在布局参数（字号/窗口尺寸）变化后会落错页，
      // 内容块引用不会。老数据无锚点 → 退回比率反算。
      if (_restoreToAnchor(anchorBlock)) { _updateFooter(); return; }
      const max = _maxPage();
      if (max > 0) {
        const idx = Math.max(0, Math.min(max, Math.round(r * max)));
        _targetPage = idx;
        _content().scrollTo({ left: idx * window.innerWidth, behavior: 'auto' });
      }
      _updateFooter();
    } else {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      if (max > 0) window.scrollTo({ top: r * max, behavior: 'auto' });
    }
  });
};

// ─── 图片点击 + 横向翻页点击区 ───
// 单一 click listener：图片点击优先短路；其次横向模式下按 X 分三段——
// 左 30% 上一页 / 右 30% 下一页 / 中央 toggle 工具栏。
// 高亮点击不走这里——SVG <g data-hl-id> 自带 click 已 stopPropagation。
document.addEventListener('click', (e) => {
  // 触摸拖动刚结束时部分 WebView 会补发合成 click——窗口期内一律忽略
  // （_suppressClickUntil 由触摸手势层维护，见横向翻页触摸区段）。
  if (performance.now() < _suppressClickUntil) return;
  if (document.body.dataset.translationStyle === 'blur') {
    const span = e.target.closest('.translated');
    if (span) { span.classList.toggle('revealed'); return; }
  }

  const img = e.target.closest('img');
  if (img && window.flutter_inappwebview) {
    e.preventDefault();
    window.flutter_inappwebview.callHandler('onImageClick', { src: img.src });
    return;
  }

  if (document.body.dataset.pagination !== 'horizontal') return;

  // 不抢可交互元素：链接、KaTeX 公式、搜索高亮 mark、SVG 高亮组
  if (e.target.closest('a, .katex, mark, g[data-hl-id]')) return;
  // 有未坍塌选区时不响应翻页/工具栏——避免误触打断拖选
  const sel = window.getSelection();
  if (sel && !sel.isCollapsed) return;

  const x = e.clientX / window.innerWidth;
  if (x < 0.3 || x > 0.7) {
    const dir = x < 0.3 ? -1 : 1;
    const before = _targetPage;
    _flipPage(dir);
    if (_targetPage !== before) {
      // 点击翻页成功 → Flutter 侧 Haptics.light()。
      // 滑动翻页不通知——页面跟手本身已是足够的确认反馈。
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('onPageFlip');
      }
    } else {
      _nudgeEdge(dir);
    }
  } else if (window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler('onToggleToolbar');
  }
});

// ─── Bridge 函数（Flutter → JS）───
window.setTranslationStyle = function(id) {
  document.body.dataset.translationStyle = id;
  if (id !== 'blur') {
    document.querySelectorAll('.translated.revealed').forEach(
      el => el.classList.remove('revealed'));
  }
};

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

// 批量同步高亮差异——payload 是 base64(utf8(JSON({remove, add, updateColor})))。
// Dart 侧 syncHighlights 一次 IPC 发送完整 diff，替代逐条 evaluateJavascript。
window.syncHighlightsBatch = function(b64Payload) {
  if (!window._overlayer) return;
  try {
    const json = decodeURIComponent(escape(atob(b64Payload)));
    const diff = JSON.parse(json);
    if (diff.remove) for (const id of diff.remove) window._overlayer.remove(id);
    if (diff.add) for (const h of diff.add) window._overlayer.addByText(h.id, h.text, h.color);
    if (diff.updateColor) for (const u of diff.updateColor) window._overlayer.updateColor(u.id, u.color);
  } catch(e) {
    console.error('syncHighlightsBatch failed', e);
  }
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

// ─── 翻页模式切换（Flutter 调用）───
// 由 Flutter 在 onContentReady 与 settings.paginationMode 变化时触发。
// 模式变化导致容器尺寸/坐标系变化：
//   1) sync --page-width 让 column 按当前 viewport 重排；
//   2) Overlayer.redraw() 重算所有高亮 rect；
//   3) dispatchEvent('scroll') 让 lazy 图片在新视口下重新评估。
window.setPaginationMode = function(mode) {
  if (mode !== 'vertical' && mode !== 'horizontal') return;
  // 切换前抓当前锚点——用旧模式的坐标系找到视口起始块
  const anchorIdx = _findAnchorBlockIndex();

  document.body.dataset.pagination = mode;
  _syncPaginationVars();
  _setTouchTakeover(mode === 'horizontal');
  if (mode !== 'horizontal') {
    _cancelFlipAnim();
    _content().style.transform = '';
  }

  // 等布局重排完成后恢复锚点 + 重绘高亮（与 resize handler 同模式）
  requestAnimationFrame(() => {
    _restoreToAnchor(anchorIdx);
    if (window._overlayer) window._overlayer.redraw();
    _updateFooter();
    window.dispatchEvent(new Event('scroll'));
  });
};

// ─── 横向翻页引擎 ───
// _targetPage 是页号唯一真值源：点击/触摸/滚轮/键盘/恢复/resize 全部汇到
// _animateToPage，原生横向滚动已被 touch-action: none 禁用（见 reader.css）。
// 旧实现的 scrollTo({behavior:'smooth'}) 时长曲线由 UA 决定（Android WebView
// 上明显偏慢），且原生手势滑动绕过状态机导致 _targetPage 失步——滑几页后
// 点击边缘会跳回滑动前的位置。统一成自驱 rAF 动画后两个问题一起消失。
let _targetPage = 0;
let _flipRAF = null;        // settle / nudge 动画句柄
let _touchDragging = false;

// 240ms + easeOutCubic 对齐 Flutter 侧 AnimationConstants.kAnim / kAnimCurve。
const _PAGE_ANIM_MS = 240;
function _easeOutCubic(t) { return 1 - Math.pow(1 - t, 3); }

function _content() { return document.getElementById('content'); }
function _isHorizontal() {
  return document.body.dataset.pagination === 'horizontal';
}

function _currentPage() {
  return Math.round(_content().scrollLeft / window.innerWidth);
}

function _maxPage() {
  return Math.max(0,
      Math.round(_content().scrollWidth / window.innerWidth) - 1);
}

function _cancelFlipAnim() {
  if (_flipRAF) { cancelAnimationFrame(_flipRAF); _flipRAF = null; }
}

// 所有程序化翻页的唯一出口：把 scrollLeft 动画到 idx 整页边界。
// fromOvershoot 是橡皮筋拖动留下的视觉过冲（transform px），随动画衰减归零
// ——scrollLeft 会被 DOM clamp 到 [0, max]，边界外的位移只能用 transform 表达。
function _animateToPage(idx, fromOvershoot) {
  const c = _content();
  idx = Math.max(0, Math.min(_maxPage(), idx));
  _targetPage = idx;
  _cancelFlipAnim();
  const from = c.scrollLeft;
  const to = idx * window.innerWidth;
  const over0 = fromOvershoot || 0;
  if (Math.abs(to - from) < 0.5 && Math.abs(over0) < 0.5) {
    c.scrollLeft = to;
    c.style.transform = '';
    return;
  }
  const t0 = performance.now();
  function step(now) {
    const t = Math.min(1, (now - t0) / _PAGE_ANIM_MS);
    const k = _easeOutCubic(t);
    c.scrollLeft = from + (to - from) * k;
    if (over0) {
      const over = over0 * (1 - k);
      c.style.transform =
          Math.abs(over) > 0.5 ? 'translateX(' + over + 'px)' : '';
    }
    if (t < 1) {
      _flipRAF = requestAnimationFrame(step);
    } else {
      _flipRAF = null;
      c.style.transform = '';
    }
  }
  _flipRAF = requestAnimationFrame(step);
}

function _flipPage(delta) {
  _animateToPage(_targetPage + delta);
}

// 边界反馈：已在首/末页时朝 dir 方向拉出 18px 再弹回（sin 半波），
// 不改 _targetPage——给"翻不动"一个视觉语义，代替点了没反应的死寂。
function _nudgeEdge(dir) {
  const c = _content();
  _cancelFlipAnim();
  const t0 = performance.now();
  function step(now) {
    const t = Math.min(1, (now - t0) / _PAGE_ANIM_MS);
    const off = -dir * 18 * Math.sin(Math.PI * t);
    c.style.transform = t < 1 ? 'translateX(' + off + 'px)' : '';
    if (t < 1) { _flipRAF = requestAnimationFrame(step); }
    else { _flipRAF = null; }
  }
  _flipRAF = requestAnimationFrame(step);
}

// ─── --page-width 同步 + resize 响应 ───
// vw 在某些 WebView 实现里不触发 column reflow，必须用 JS 主动 setProperty。
// resize 时记录视觉锚点（视口起始侧第一个可见 block 的索引），重排后恢复——
// 避免内容重排后 scrollLeft 数值含义失效导致页码错乱。
function _syncPaginationVars() {
  document.documentElement.style.setProperty(
    '--page-width', window.innerWidth + 'px');
}
_syncPaginationVars();

// 视口起始侧（横向=左缘 / 纵向=顶缘）第一个可见内容块的索引。
// resize 锚点保持和进度持久化共用：布局参数（字号/窗口尺寸）变化后,
// 比率反算会落错页，内容块引用不会。
function _findAnchorBlockIndex() {
  const c = _content();
  const cRect = c.getBoundingClientRect();
  const horizontal = _isHorizontal();
  const children = c.children;
  for (let i = 0; i < children.length; i++) {
    const el = children[i];
    if (el.tagName === 'svg' || el.tagName === 'SVG') continue;
    const r = el.getBoundingClientRect();
    if (horizontal ? r.right > cRect.left + 8 : r.bottom > 8) return i;
  }
  return -1;
}

// 把第 idx 个内容块对齐到视口起始。两种模式滚动容器不同，必须分流：
//   vertical 滚 window——块顶对齐视口（scroll-margin-top:60px 自动让出工具栏）；
//   horizontal 滚 #content——scrollIntoView 后还要吸附整页边界，锚点块可能起始
//   于页中部，否则视口会同时露出两半页内容。
// 旧实现只有 horizontal 分支（末尾 scrollLeft 吸附对 window.scrollY 无效），
// 导致 horizontal→vertical 切换后停在残留 scrollY（通常文档顶部）。
function _restoreToAnchor(idx) {
  const c = _content();
  if (idx == null || idx < 0 || idx >= c.children.length) return false;
  const el = c.children[idx];
  if (!_isHorizontal()) {
    el.scrollIntoView({ block: 'start', inline: 'nearest' });
    return true;
  }
  el.scrollIntoView({ block: 'nearest', inline: 'start' });
  const page = Math.max(0, Math.min(_maxPage(),
      Math.round(c.scrollLeft / window.innerWidth)));
  c.scrollTo({ left: page * window.innerWidth, behavior: 'auto' });
  _targetPage = page;
  return true;
}

let _paginationResizeTimer = null;
window.addEventListener('resize', () => {
  // vertical 模式不需要锚点保持——浏览器原生处理纵向 reflow，scrollY 保持
  // 段落相对位置足够。仅刷新 var 以便切回 horizontal 时是最新值。
  if (!_isHorizontal()) {
    _syncPaginationVars();
    return;
  }

  // 重排前抓当前锚点索引
  const anchorIdx = _findAnchorBlockIndex();

  clearTimeout(_paginationResizeTimer);
  _paginationResizeTimer = setTimeout(() => {
    _syncPaginationVars();
    // 等下一帧 layout 完成再恢复锚点位置 + redraw 高亮
    requestAnimationFrame(() => {
      _restoreToAnchor(anchorIdx);
      _updateFooter();
      if (window._overlayer) window._overlayer.redraw();
      window.dispatchEvent(new Event('scroll'));
    });
  }, 120);
});

// ─── 横向翻页：滚轮 + 键盘 ───
// 仅 horizontal 模式生效；vertical 模式提前 return 不影响原生上下滚动。

// 滚轮 → 一次一页。
// 节流：触控板 / 精密滚轮一次手势会喷出多个 wheel 事件，全响应就是"飞过头"。
// 同向 280ms 内只翻一次；方向反转时立即响应（用户改主意翻回去不该被卡住）。
let _wheelCooldownUntil = 0;
let _wheelLastDir = 0;
window.addEventListener('wheel', (e) => {
  if (!_isHorizontal()) return;
  e.preventDefault();
  const dir = Math.sign(e.deltaY);
  if (!dir) return;
  const now = performance.now();
  if (dir === _wheelLastDir && now < _wheelCooldownUntil) return;
  _wheelCooldownUntil = now + 280;
  _wheelLastDir = dir;
  _flipPage(dir);
}, { passive: false });

// 键盘 → ArrowLeft/PageUp 上一页；ArrowRight/PageDown/Space 下一页
window.addEventListener('keydown', (e) => {
  if (!_isHorizontal()) return;
  if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
  if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') {
    e.preventDefault();
    _flipPage(1);
  } else if (e.key === 'ArrowLeft' || e.key === 'PageUp') {
    e.preventDefault();
    _flipPage(-1);
  }
});

// ─── 横向翻页：触摸手势（书页模型，参照 Flutter PageView 物理）───
// touch-action: none 已禁用 #content 的原生横向滚动（reader.css），这里完整接管：
//   认领：位移出 8px slop 且 |dx|>|dy|，且无活动选区、触点不在可横滚内层
//     （pre / 公式块）——手指不动 = 让位给原生长按选择；纵向意图 = 放行。
//   跟手：scrollLeft 1:1 跟随；边界外 0.3 阻尼且改用 transform 表达
//     （scrollLeft 会被 DOM clamp 到 [0,max]，表达不了过冲）。
//   松手：|速度|>0.3px/ms 沿速度方向翻一页（与位移矛盾时速度优先=反悔手势）；
//     否则位移过半翻页、不足回弹。单次手势最多翻一页。
let _touch = null;
let _suppressClickUntil = 0;

// 触点到 #content 之间存在还能朝手指反方向滚的元素 → 让位给内层原生滚动
function _innerHScrollable(target, dx) {
  const c = _content();
  for (let el = target; el && el !== c; el = el.parentElement) {
    if (el.scrollWidth > el.clientWidth + 1) {
      const ox = getComputedStyle(el).overflowX;
      if ((ox === 'auto' || ox === 'scroll') &&
          (dx < 0 ? el.scrollLeft + el.clientWidth < el.scrollWidth - 1
                  : el.scrollLeft > 1)) {
        return true;
      }
    }
  }
  return false;
}

document.addEventListener('touchstart', (e) => {
  if (!_isHorizontal() || e.touches.length !== 1) {
    // 多指介入：若正在拖动，按当前位置就近收尾——否则 _touchDragging
    // 卡 true，snap 兜底永久失效、橡皮筋 transform 残留在屏上。
    if (_touchDragging) {
      _touchDragging = false;
      _animateToPage(
          Math.round(_content().scrollLeft / window.innerWidth),
          _touch ? _touch.overVisual : 0);
    }
    _touch = null;
    return;
  }
  const t = e.touches[0];
  // 不在此处打断动画：纯点击（中央 toggle 工具栏）不该把翻页动画停在半路，
  // 真正认领拖动时（touchmove 出 slop）才接管。
  _touch = {
    id: t.identifier, x0: t.clientX, y0: t.clientY,
    base: 0, basePage: 0, claimed: false, refused: false,
    lastX: t.clientX, lastT: e.timeStamp, vx: 0, overVisual: 0,
    target: e.target,
  };
}, { passive: true });

function _onTouchMove(e) {
  if (!_touch || !_isHorizontal() || _touch.refused) return;
  const t = Array.from(e.touches).find(x => x.identifier === _touch.id);
  if (!t) return;
  if (!_touch.claimed) {
    const dx = t.clientX - _touch.x0;
    const dy = t.clientY - _touch.y0;
    if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
    const sel = window.getSelection();
    if ((sel && !sel.isCollapsed) ||
        Math.abs(dx) <= Math.abs(dy) ||
        _innerHScrollable(_touch.target, dx)) {
      _touch.refused = true;
      return;
    }
    _touch.claimed = true;
    _touchDragging = true;
    _cancelFlipAnim();
    const c = _content();
    c.style.transform = '';
    _touch.base = c.scrollLeft;
    _touch.basePage = Math.max(0, Math.min(_maxPage(),
        Math.round(_touch.base / window.innerWidth)));
    _touch.x0 = t.clientX;  // 认领点重置基准：从这里开始 1:1，避免 slop 跳变
  }
  e.preventDefault();
  const c = _content();
  const raw = _touch.base - (t.clientX - _touch.x0);
  const maxLeft = _maxPage() * window.innerWidth;
  const clamped = Math.max(0, Math.min(maxLeft, raw));
  const over = raw - clamped;   // <0 = 首页再往前拖；>0 = 末页再往后拖
  c.scrollLeft = clamped;
  _touch.overVisual = -over * 0.3;
  c.style.transform = over ? 'translateX(' + _touch.overVisual + 'px)' : '';
  const dt = e.timeStamp - _touch.lastT;
  if (dt > 0) {
    _touch.vx = (t.clientX - _touch.lastX) / dt;
    _touch.lastX = t.clientX;
    _touch.lastT = e.timeStamp;
  }
}

function _onTouchEnd(e) {
  const st = _touch;
  _touch = null;
  if (!st || !st.claimed) return;
  _touchDragging = false;
  // preventDefault(touchmove) 后浏览器不应再派发合成 click，但部分 WebView
  // 实现仍会补发——400ms 窗口内的 click 一律忽略（见 click handler 头部）。
  _suppressClickUntil = performance.now() + 400;
  const c = _content();
  if (!_isHorizontal()) { c.style.transform = ''; return; }
  // 手指停顿 >100ms 再松开，最后一次采样速度已过期，视为静止松手
  const vx = (e.timeStamp - st.lastT > 100) ? 0 : st.vx;
  let delta = 0;
  if (Math.abs(vx) > 0.3) {
    delta = vx < 0 ? 1 : -1;
  } else {
    const moved = (c.scrollLeft - st.base) / window.innerWidth;
    if (moved > 0.5) delta = 1;
    else if (moved < -0.5) delta = -1;
  }
  _animateToPage(st.basePage + delta, st.overVisual);
}

// touchmove 必须 passive:false 才能 preventDefault，但非 passive listener 会
// 拖累 vertical 模式的原生滚动合成——所以随模式动态挂/卸，仅横向模式存在。
let _touchMoveAttached = false;
function _setTouchTakeover(on) {
  if (on === _touchMoveAttached) return;
  _touchMoveAttached = on;
  if (on) {
    document.addEventListener('touchmove', _onTouchMove, { passive: false });
  } else {
    document.removeEventListener('touchmove', _onTouchMove);
    _touch = null;
    _touchDragging = false;
  }
}

document.addEventListener('touchend', _onTouchEnd, { passive: true });
document.addEventListener('touchcancel', _onTouchEnd, { passive: true });

// ─── 整页对齐兜底 ───
// scrollToBlock / scrollToSearchResult / flashImage 这类 scrollIntoView 滚动源
// 不经过 _animateToPage，会停在任意 scrollLeft。观察 #content 滚动，idle 150ms
// 后吸附最近整页并同步 _targetPage——保证页号对任何滚动源都不失步。
let _snapTimer = null;
_content().addEventListener('scroll', () => {
  if (!_isHorizontal() || _touchDragging || _flipRAF) return;
  clearTimeout(_snapTimer);
  _snapTimer = setTimeout(() => {
    if (!_isHorizontal() || _touchDragging || _flipRAF) return;
    const page = Math.max(0, Math.min(_maxPage(),
        Math.round(_content().scrollLeft / window.innerWidth)));
    if (Math.abs(_content().scrollLeft - page * window.innerWidth) > 1) {
      _animateToPage(page);
    } else {
      _targetPage = page;
    }
  }, 150);
}, { passive: true });

// ─── 进度页脚 ───
// 横向 "12 / 45"，纵向 "37%"。页内渲染而非 Flutter overlay：页码要和翻页
// 动画同帧更新，走 bridge 有 500ms 节流 + IPC 延迟；主题色直接引用 :root
// CSS 变量（样式见 reader.css #page-footer），换主题自动跟随。
const _footerEl = document.createElement('div');
_footerEl.id = 'page-footer';
document.body.appendChild(_footerEl);

let _footerRAF = null;
function _updateFooter() {
  if (_footerRAF) return;
  _footerRAF = requestAnimationFrame(() => {
    _footerRAF = null;
    if (_isHorizontal()) {
      const page = Math.max(0, Math.min(_maxPage(), _currentPage()));
      _footerEl.textContent = (page + 1) + ' / ' + (_maxPage() + 1);
    } else {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const r = max > 0 ? Math.max(0, Math.min(1, window.scrollY / max)) : 0;
      _footerEl.textContent = Math.round(r * 100) + '%';
    }
  });
}
window.addEventListener('scroll', _updateFooter, { passive: true });
_content().addEventListener('scroll', _updateFooter, { passive: true });
_updateFooter();
