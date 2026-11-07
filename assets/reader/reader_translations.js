(() => {
  const pending = new Map();
  const entries = new Map((window.readerEntries || []).map(e => [e.id, e]));
  let pairs;
  let scheduled = false;
  let held = false;

  function schedule() {
    if (scheduled || !pending.size) return;
    scheduled = true;
    requestAnimationFrame(flush);
  }

  function flush() {
    scheduled = false;
    if (held || _readerSearchActive) return;
    // 手指还在翻页时改 DOM 会打断 touch 流，_touchDragging 再也收不回来。
    // 这里只延期，不丢更新；松手或解锁后由 pointerup / readerScheduleTranslations 继续。
    if (_pointerIsDown || window.readerGestureActive?.()) {
      schedule();
      return;
    }
    pairs ||= new Map(Array.from(document.querySelectorAll('[data-reader-pair]'), p => [p.dataset.readerPair, p]));
    const selection = window.getSelection();
    const selected = selection?.rangeCount && !selection.isCollapsed ? selection.getRangeAt(0) : null;
    const content = document.getElementById('content');
    const block = content.children[_findAnchorBlockIndex()];
    const rect = content.getBoundingClientRect();
    const caret = document.caretRangeFromPoint?.(
      Math.max(8, Math.min((window.readerViewportWidth?.() ?? window.innerWidth) - 8, rect.left + 24)),
      Math.max(8, Math.min(window.innerHeight - 8, rect.top + 8)),
    );
    const caretElement = caret?.startContainer.nodeType === Node.ELEMENT_NODE
      ? caret.startContainer : caret?.startContainer.parentElement;
    const anchor = selected || caretElement?.closest('[data-reader-pair]') || block;
    const before = anchor?.getBoundingClientRect();
    let changed = false;
    let truncated = false;
    const started = performance.now();
    let processed = 0;
    for (const [id, entry] of pending) {
      // 一批译文可能上百段。单帧同步排公式会卡住 WebView，系统返回再去
      // 截图或销毁平台视图时主线程就会一直等。
      if (processed >= 4 || (processed > 0 && performance.now() - started > 8)) {
        truncated = true;
        break;
      }
      const pair = pairs.get(id);
      if (pair && selected?.intersectsNode(pair)) continue;
      pending.delete(id);
      processed++;
      const previous = entries.get(id);
      if (previous?.html === entry.html && previous?.language === entry.language &&
          !!previous?.rtl === !!entry.rtl &&
          previous?.showSource === entry.showSource && previous?.showTranslation === entry.showTranslation &&
          previous?.bilingual === entry.bilingual) continue;
      entries.set(id, entry);
      if (!pair) continue;
      const source = pair.querySelector('[data-language="source"]');
      const target = pair.querySelector('.reader-target');
      const hasTarget = !!entry.translated && entry.showTranslation !== false;
      if (previous?.html !== entry.html) {
        target.innerHTML = entry.html || '';
        target.classList.remove('revealed');
        _renderReaderMath(target);
      }
      target.dataset.language = entry.language;
      target.dir = entry.rtl ? 'rtl' : 'ltr';
      target.classList.toggle('translated', !!entry.bilingual);
      target.hidden = !hasTarget;
      source.hidden = entry.showSource === false && hasTarget;
      pair.dataset.bilingual = String(!!entry.bilingual);
      changed = true;
    }
    window.readerEntries = Array.from(entries.values());
    if (changed) {
      window.readerInvalidateBindings?.();
      // 一批写入后只测量一次；选区或视口文字仍使用原节点，保持其屏幕位置。
      const after = anchor?.getBoundingClientRect();
      if (before && after) {
        if (_isHorizontal()) content.scrollLeft += after.left - before.left;
        else window.scrollBy(0, after.top - before.top);
      }
      window._overlayer?.redraw();
      _reportScrollMetrics();
    }
    if (truncated) schedule();
  }

  window.applyReaderTranslations = payload => {
    const updates = JSON.parse(decodeURIComponent(escape(atob(payload))));
    for (const entry of updates) {
      pending.set(entry.id, entry);
    }
    schedule();
  };
  window.holdReaderTranslations = value => {
    held = value;
    if (!held) schedule();
  };
  window.readerScheduleTranslations = schedule;
  for (const event of ['pointerup', 'pointercancel', 'selectionchange']) {
    document.addEventListener(event, schedule);
  }
})();
