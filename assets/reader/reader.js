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

  // 从 Range 计算 content-relative 矩形（不含 scrollX/Y，差值即 content 坐标）。
  //
  // **关键**：`position: absolute` 的 SVG 起点是包含块的 **padding-box**，
  // 但 `getBoundingClientRect()` 返回的是 **border-box** 视口坐标。当
  // container（#content）自身有 padding 时（横向翻页模式 padding: 24px 32px），
  // 直接用 `r.top - cRect.top` 算出的坐标基于 border-box 起点，比 SVG 实际
  // 起点多偏移一个 padding 量——高亮整体向下/向右偏移 padding，文字行底。
  // 减去 container padding 把坐标系对齐到 padding-box 起点（即 SVG 起点）。
  //
  // Vertical 模式下 container 无 padding，减 0 不变，保持兼容。
  _getContentRects(range) {
    const cRect = this.container.getBoundingClientRect();
    const cs = getComputedStyle(this.container);
    const padLeft = parseFloat(cs.paddingLeft) || 0;
    const padTop = parseFloat(cs.paddingTop) || 0;
    let rects = [];
    for (const pr of this._splitRangeByParagraph(range)) {
      for (const r of pr.getClientRects()) {
        rects.push({
          left: r.left - cRect.left - padLeft,
          top: r.top - cRect.top - padTop,
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

  // 核心：从存储的 Range 重新计算所有高亮位置——解决 KaTeX/图片 reflow 漂移。
  // 读写分离：先批量读取所有 getClientRects（1 次强制 layout），
  // 再批量写 SVG（1 次 DOM 更新），避免 N 次 layout thrashing。
  redraw() {
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
  _handleSelection();
});
document.addEventListener('selectionchange', () => {
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
    window.flutter_inappwebview.callHandler('onScrollProgress', { progress: ratio });
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

window._restoreProgress = function(ratio) {
  requestAnimationFrame(() => {
    const r = Math.max(0, Math.min(1, ratio));
    if (document.body.dataset.pagination === 'horizontal') {
      const max = _maxPage();
      if (max > 0) {
        const idx = Math.max(0, Math.min(max, Math.round(r * max)));
        _targetPage = idx;
        document.getElementById('content')
          .scrollTo({ left: idx * window.innerWidth, behavior: 'auto' });
      }
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
  if (x < 0.3) {
    _flipPage(-1);
  } else if (x > 0.7) {
    _flipPage(1);
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
  document.body.dataset.pagination = mode;
  _syncPaginationVars();
  if (window._overlayer) window._overlayer.redraw();
  window.dispatchEvent(new Event('scroll'));
  if (mode === 'horizontal') _targetPage = _currentPage();
};

// ─── 横向翻页"页号状态机"（参考 Flutter PageController）───
// 不依赖 scrollLeft 当前值翻页——smooth scroll 在动画中会让 scrollLeft
// 处于"非整页"状态，多次相对 scrollBy 累加会停在中间。改成：
//   _targetPage 是真实意图位置，scrollBy 永远基于它的整页边界，
//   连续翻页累加到 _targetPage，最终一次性 scrollTo 到对齐位置。
let _targetPage = 0;

function _currentPage() {
  return Math.round(
    document.getElementById('content').scrollLeft / window.innerWidth);
}

function _maxPage() {
  const c = document.getElementById('content');
  return Math.max(0, Math.round(c.scrollWidth / window.innerWidth) - 1);
}

function _goToPage(idx) {
  const c = document.getElementById('content');
  idx = Math.max(0, Math.min(_maxPage(), idx));
  _targetPage = idx;
  c.scrollTo({ left: idx * window.innerWidth, behavior: 'smooth' });
}

function _flipPage(delta) {
  _goToPage(_targetPage + delta);
}

// ─── --page-width 同步 + resize 响应 ───
// vw 在某些 WebView 实现里不触发 column reflow，必须用 JS 主动 setProperty。
// resize 时记录视觉锚点（视口左侧最近的可见 block），重排后 scrollIntoView
// 推回左缘——避免内容重排后 scrollLeft 数值含义失效导致页码错乱。
function _syncPaginationVars() {
  document.documentElement.style.setProperty(
    '--page-width', window.innerWidth + 'px');
}
_syncPaginationVars();

let _paginationResizeTimer = null;
window.addEventListener('resize', () => {
  // vertical 模式不需要锚点保持——浏览器原生处理纵向 reflow，scrollY 保持
  // 段落相对位置足够。仅刷新 var 以便切回 horizontal 时是最新值。
  if (document.body.dataset.pagination !== 'horizontal') {
    _syncPaginationVars();
    return;
  }

  // 重排前抓"当前视口左侧最近的 #content 子元素"作为锚点
  const c = document.getElementById('content');
  const cRect = c.getBoundingClientRect();
  let anchor = null;
  for (const el of c.children) {
    if (el.tagName === 'svg' || el.tagName === 'SVG') continue;
    const r = el.getBoundingClientRect();
    if (r.right > cRect.left + 8) { anchor = el; break; }
  }

  clearTimeout(_paginationResizeTimer);
  _paginationResizeTimer = setTimeout(() => {
    _syncPaginationVars();
    // 等下一帧 layout 完成再恢复锚点位置 + redraw 高亮
    requestAnimationFrame(() => {
      const c = document.getElementById('content');
      if (anchor) {
        anchor.scrollIntoView({ block: 'nearest', inline: 'start' });
      }
      // scrollIntoView 的锚点元素可能不在新 layout 的整页边界——
      // 比如锚点段落被分到第 3 页中部。强制把 scrollLeft 落到最近整页
      // 边界，避免视口里同时露出两半页内容。
      const snapped =
          Math.round(c.scrollLeft / window.innerWidth) * window.innerWidth;
      if (Math.abs(c.scrollLeft - snapped) > 1) {
        c.scrollTo({ left: snapped, behavior: 'auto' });
      }
      _targetPage = Math.round(c.scrollLeft / window.innerWidth);

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
  if (document.body.dataset.pagination !== 'horizontal') return;
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
  if (document.body.dataset.pagination !== 'horizontal') return;
  if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
  if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') {
    e.preventDefault();
    _flipPage(1);
  } else if (e.key === 'ArrowLeft' || e.key === 'PageUp') {
    e.preventDefault();
    _flipPage(-1);
  }
});
