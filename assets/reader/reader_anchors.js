(() => {
  const compact = text => text.replace(/\\[()[\]]/g, '').replace(/[\s$]/g, '');
  let cached;
  window.readerInvalidateBindings = () => { cached = null; };
  function index() {
    if (cached) return cached;
    const content = document.getElementById('content');
    const points = [];
    let text = '';
    const tagged = new Map();
    function visit(node) {
      if (node.nodeType === Node.ELEMENT_NODE) {
        if (node.matches('svg, table, script, [hidden]')) return;
        if (node.matches('.katex')) {
          const source = compact(node.querySelector('annotation')?.textContent || '');
          const offset = Array.prototype.indexOf.call(node.parentNode.childNodes, node);
          for (const character of source.split('')) {
            text += character; points.push({ node: node.parentNode, offset, end: offset + 1 });
          }
          return;
        }
        const start = text.length;
        for (const child of node.childNodes) visit(child);
        if (node.dataset.paragraphId && node.dataset.language) {
          tagged.set(node.dataset.paragraphId + '/' + node.dataset.language, {start, end: text.length});
        }
      } else if (node.nodeType === Node.TEXT_NODE) {
        for (let i = 0; i < node.textContent.length; i++) {
          if (node.textContent[i] === '\\' && /[()[\]]/.test(node.textContent[i + 1] || '')) { i++; continue; }
          if (/[\s$]/.test(node.textContent[i])) continue;
          text += node.textContent[i]; points.push({ node, offset: i, end: i + 1 });
        }
      }
    }
    visit(content);
    const entries = [];
    for (const p of window.readerEntries || []) {
      if (p.showSource !== false || tagged.has(p.id + '/source')) entries.push({ id: p.id, text: p.source, language: 'source', revision: p.sourceRevision });
      if (p.translated && p.showTranslation !== false) entries.push({ id: p.id, text: p.translated, language: p.language, revision: p.translatedRevision });
    }
    const groups = new Map();
    const bindings = [];
    for (const entry of entries) {
      const key = compact(entry.text);
      if (!key) continue;
      const region = tagged.get(entry.id + '/' + entry.language);
      if (region) {
        const local = text.slice(region.start, region.end);
        const at = local.indexOf(key);
        if (at >= 0 && local.indexOf(key, at + 1) < 0) {
          bindings.push({...entry, start: region.start + at, end: region.start + at + key.length});
          continue;
        }
      }
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(entry);
    }
    for (const [key, group] of groups) {
      const hits = [];
      let from = 0;
      while (from < text.length) {
        const at = text.indexOf(key, from);
        if (at < 0) break;
        if (!bindings.some(b => at >= b.start && at < b.end)) hits.push(at);
        from = at + key.length;
      }
      // 重复文本数量不一致时保持未定位，不落到第一处。
      if (hits.length !== group.length) continue;
      group.forEach((entry, i) => bindings.push({ ...entry, start: hits[i], end: hits[i] + key.length }));
    }
    bindings.sort((a, b) => a.start - b.start);
    cached = { points, bindings, text };
    return cached;
  }
  function rangeAt(start, end) {
    const points = index().points;
    if (!points[start] || !points[end - 1] || start >= end) return null;
    const range = document.createRange();
    range.setStart(points[start].node, points[start].offset);
    range.setEnd(points[end - 1].node, points[end - 1].end);
    return range;
  }
  function textOffset(text, count) {
    if (count <= 0) return 0;
    let seen = 0;
    for (let i = 0; i < text.length; i++) {
      if (text[i] === '\\' && /[()[\]]/.test(text[i + 1] || '')) { i++; continue; }
      if (!/[\s$]/.test(text[i]) && ++seen === count) return i + 1;
    }
    return text.length;
  }
  window.readerSelectionAnchor = selection => {
    const ranges = [];
    for (const b of index().bindings) {
      if (document.body.classList.contains('reader-select-source') && b.language !== 'source') continue;
      if (document.body.classList.contains('reader-select-target') && b.language === 'source') continue;
      const full = rangeAt(b.start, b.end);
      if (!full || selection.compareBoundaryPoints(Range.END_TO_START, full) >= 0 ||
          selection.compareBoundaryPoints(Range.START_TO_END, full) <= 0) continue;
      const selected = full.cloneRange();
      if (selection.compareBoundaryPoints(Range.START_TO_START, full) > 0)
        selected.setStart(selection.startContainer, selection.startOffset);
      if (selection.compareBoundaryPoints(Range.END_TO_END, full) < 0)
        selected.setEnd(selection.endContainer, selection.endOffset);
      const points = index().points;
      const included = [];
      for (let i = b.start; i < b.end; i++) {
        const point = points[i];
        if (selected.comparePoint(point.node, point.offset) === 0 && selected.comparePoint(point.node, point.end) === 0) included.push(i);
      }
      if (!included.length) continue;
      let start = textOffset(b.text, included[0] - b.start);
      const end = textOffset(b.text, included[included.length - 1] - b.start + 1);
      while (start < end) {
        if (/[\s$]/.test(b.text[start])) { start++; continue; }
        if (b.text[start] === '\\' && /[()[\]]/.test(b.text[start + 1] || '')) { start += 2; continue; }
        break;
      }
      if (start >= end) continue;
      ranges.push({ paragraphId: b.id, language: b.language, revision: b.revision,
        start, end, quote: b.text.slice(start, end), prefix: b.text.slice(Math.max(0, start - 32), start), suffix: b.text.slice(end, end + 32) });
    }
    return ranges.length ? { version: 1, ranges } : null;
  };
  window.readerHighlightRanges = highlight => {
    if (highlight.anchor && highlight.anchor.version !== 1) return [];
    if (!highlight.anchor) {
      const hits = [];
      for (const b of index().bindings) {
        const quote = compact(highlight.text);
        const at = compact(b.text).indexOf(quote);
        if (quote && at >= 0 && compact(b.text).indexOf(quote, at + 1) < 0)
          hits.push(rangeAt(b.start + at, b.start + at + quote.length));
      }
      return hits.length === 1 ? hits : [];
    }
    const ranges = [];
    for (const anchor of highlight.anchor.ranges || []) {
      for (const b of index().bindings.filter(b => b.id === anchor.paragraphId)) {
        if (b.language !== anchor.language) {
          ranges.push(rangeAt(b.start, b.start + 1)); continue;
        }
        let start = anchor.start;
        let end = anchor.end;
        if (anchor.revision !== b.revision || b.text.slice(start, end) !== anchor.quote) {
          const at = b.text.indexOf(anchor.quote);
          if (at < 0 || b.text.indexOf(anchor.quote, at + 1) >= 0 ||
              !b.text.slice(0, at).endsWith(anchor.prefix || '') ||
              !b.text.slice(at + anchor.quote.length).startsWith(anchor.suffix || '')) continue;
          start = at; end = at + anchor.quote.length;
        }
        ranges.push(rangeAt(b.start + compact(b.text.slice(0, start)).length,
          b.start + compact(b.text.slice(0, end)).length));
      }
    }
    return ranges.filter(Boolean);
  };
  let locateTimer;
  function originalRange(binding) {
    const source = Array.from(document.querySelectorAll('[data-paragraph-id][data-language="source"]'))
      .find(el => el.dataset.paragraphId === binding.id);
    if (source?.hidden) {
      source.hidden = false;
      window.readerInvalidateBindings();
    }
    const original = index().bindings.find(b => b.id === binding.id && b.language === 'source') || binding;
    return rangeAt(original.start, original.end);
  }
  window.readerLocateQuote = ({quote, anchor, figureName} = {}) => {
    let range;
    let target;
    if (figureName) {
      const image = Array.from(document.querySelectorAll('#content img')).find(img => {
        try { return decodeURIComponent(new URL(img.src).pathname.split('/').pop()) === figureName; }
        catch (_) { return false; }
      });
      target = image?.closest('figure') || image;
    }
    if (!target && anchor?.version === 1) {
      for (const part of anchor.ranges || []) {
        let binding = index().bindings.find(b => b.id === part.paragraphId);
        if (!binding) continue;
        const entry = (window.readerEntries || []).find(p => p.id === part.paragraphId);
        const text = part.language === 'source' ? entry?.source : entry?.translated;
        let start = part.start;
        if (text && text.slice(start, part.end) !== part.quote) {
          start = text.indexOf(part.quote);
          if (start < 0 || text.indexOf(part.quote, start + 1) >= 0 ||
              !text.slice(0, start).endsWith(part.prefix || '') ||
              !text.slice(start + part.quote.length).startsWith(part.suffix || '')) continue;
        }
        range = originalRange(binding);
        binding = index().bindings.find(b => b.id === part.paragraphId && b.language === 'source');
        if (binding && text && part.language === 'source') {
          const at = compact(text.slice(0, start)).length;
          range = rangeAt(binding.start + at, binding.start + at + compact(part.quote).length);
        }
        if (range) break;
      }
    }
    if (!target && !range) {
      const key = compact(quote || '');
      if (!key) return false;
      const hits = index().bindings.filter(b => compact(b.text).includes(key));
      const ids = new Set(hits.map(b => b.id));
      if (ids.size === 1) {
        const hit = hits.find(b => b.language === 'source') || hits[0];
        range = originalRange(hit);
        if (hit.language === 'source') {
          const at = compact(hit.text).indexOf(key);
          if (compact(hit.text).indexOf(key, at + 1) >= 0) return false;
          range = rangeAt(hit.start + at, hit.start + at + key.length);
        }
      } else if (ids.size > 1) {
        return false;
      } else {
        const at = index().text.indexOf(key);
        if (at < 0 || index().text.indexOf(key, at + 1) >= 0) return false;
        range = rangeAt(at, at + key.length);
      }
    }
    if (!target && !range) return false;
    window.readerStopWheel?.();
    const rect = target?.getBoundingClientRect() || Array.from(range.getClientRects()).find(r => r.height > 0);
    if (!rect) return false;
    const behavior = matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth';
    if (document.body.dataset.pagination === 'horizontal') {
      const content = document.getElementById('content');
      const page = Math.floor((content.scrollLeft + rect.left) / window.innerWidth);
      content.scrollTo({left: Math.max(0, page) * window.innerWidth, behavior});
    } else {
      window.scrollBy({top: rect.top - Math.max(80, window.innerHeight * .3), behavior});
    }
    document.querySelectorAll('.reader-locate-target').forEach(el => el.classList.remove('reader-locate-target'));
    CSS.highlights?.delete('reader-locate');
    if (target) target.classList.add('reader-locate-target');
    else if (CSS.highlights) CSS.highlights.set('reader-locate', new Highlight(range));
    clearTimeout(locateTimer);
    locateTimer = setTimeout(() => {
      target?.classList.remove('reader-locate-target');
      CSS.highlights?.delete('reader-locate');
    }, 4000);
    return true;
  };
  window.readerScrollToParagraph = id => {
    const binding = index().bindings.find(b => b.id === id);
    const range = binding && rangeAt(binding.start, binding.end);
    range?.startContainer.parentElement.scrollIntoView({ block: 'center' });
    return !!range;
  };
  window.readerVisibleParagraph = () => {
    for (const b of index().bindings) {
      const rect = rangeAt(b.start, b.end)?.getBoundingClientRect();
      if (rect && rect.bottom > 0 && rect.top < window.innerHeight && rect.right > 0 && rect.left < window.innerWidth) return b.id;
    }
    return null;
  };
})();
