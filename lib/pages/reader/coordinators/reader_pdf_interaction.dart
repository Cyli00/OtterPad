import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/highlight.dart';
import '../../../data/models/book/reader_anchor.dart';
import '../../../services/reader/reader_document_index.dart';
import '../widgets/reader_pdf_document.dart';
import '../widgets/reader_layout_geometry.dart';

typedef ReaderPdfSelectionResult = ({
  String text,
  Rect? rect,
  ReaderAnchor? anchor,
});

/// 统一 PDF 的拖选、单击与工具栏时序，业务操作仍由阅读器处理。
class ReaderPdfInteraction {
  ReaderPdfInteraction({
    required this.controller,
    required this.enabled,
    required this.index,
    required this.translations,
    required this.highlights,
    required this.onSelection,
    required this.onHighlight,
    required this.onDismiss,
    required this.onToggleToolbar,
  });

  final PdfViewerController controller;
  final bool Function() enabled;
  final ReaderDocumentIndex Function() index;
  final Map<String, String> Function() translations;
  final List<Highlight> Function() highlights;
  final ValueChanged<ReaderPdfSelectionResult> onSelection;
  final void Function(Highlight, Rect) onHighlight;
  final VoidCallback onDismiss;
  final VoidCallback onToggleToolbar;
  final ranges = ValueNotifier<List<PdfPageTextRange>>(const []);

  PointerDownEvent? _down;
  bool _moved = false;
  bool? _side;
  bool _disposed = false;
  bool _scheduled = false;
  bool _reading = false;
  bool _dirty = false;
  bool _showToolbar = false;
  bool _annotationOpen = false;
  int _epoch = 0;
  String? _shownSignature;
  Offset? _lastTap;
  Duration? _lastTapTime;

  bool get pointerDown => _down != null;
  bool get _active => !_disposed && enabled() && controller.isReady;
  bool _valid(int epoch) => _active && epoch == _epoch;

  void clear() {
    _epoch++;
    _down = null;
    _dirty = false;
    _shownSignature = null;
    _showToolbar = false;
    _annotationOpen = false;
    _side = null;
    ranges.value = const [];
    onDismiss();
  }

  void onPointerDown(PointerDownEvent event) {
    if (!_active) return;
    clear();
    _down = event;
    _moved = false;
    final point = controller.globalToDocument(event.position);
    final page = point == null
        ? null
        : controller
              .getPdfPageHitTestResult(
                point,
                useDocumentLayoutCoordinates: true,
              )
              ?.page;
    _side = page is ReaderPdfPage ? page.translated : null;
  }

  void onPointerMove(PointerMoveEvent event) {
    final down = _down;
    if (!_active || down == null) return;
    final slop = down.kind == PointerDeviceKind.mouse
        ? kPrecisePointerHitSlop
        : kTouchSlop;
    _moved |= (event.position - down.position).distance > slop;
    refresh();
  }

  void onPointerUp(PointerUpEvent event) {
    final down = _down;
    _down = null;
    if (!_active || down == null) return;
    final tap =
        !_moved &&
        (down.buttons & kPrimaryButton) != 0 &&
        event.timeStamp - down.timeStamp < kLongPressTimeout;
    if (tap) {
      final doubleTap =
          _lastTap != null &&
          _lastTapTime != null &&
          (event.position - _lastTap!).distance < kDoubleTapSlop &&
          event.timeStamp - _lastTapTime! < kDoubleTapTimeout;
      _lastTap = event.position;
      _lastTapTime = event.timeStamp;
      if (!doubleTap) {
        unawaited(_tap(event.position, _epoch));
        return;
      }
    }
    refresh(showToolbar: true);
  }

  void onPointerCancel(PointerCancelEvent event) {
    _down = null;
    clear();
  }

  void onSelectionChanged(PdfTextSelection selection) {
    if (!_active || _annotationOpen) return;
    refresh(showToolbar: !pointerDown);
  }

  // pdfrx 延迟回调不再重复命中；双击和右键仍走其原生选词/菜单路径。
  bool onGeneralTap(PdfViewerGeneralTapHandlerDetails details) =>
      _active &&
      details.type == PdfViewerGeneralTapType.tap &&
      _lastTap != null;

  void refresh({bool showToolbar = false}) {
    if (!_active || _annotationOpen) return;
    _dirty = true;
    _showToolbar |= showToolbar;
    if (_scheduled || _reading) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_active && _dirty) unawaited(_read());
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  Future<void> _read() async {
    final epoch = _epoch;
    _reading = true;
    _dirty = false;
    final show = _showToolbar;
    _showToolbar = false;
    try {
      final delegate = controller.textSelectionDelegate;
      final selected = delegate.hasSelectedText && delegate.isCopyAllowed
          ? await delegate.getSelectedTextRanges()
          : <PdfPageTextRange>[];
      if (!_valid(epoch) || _annotationOpen) return;
      final scoped = _scope(selected);
      if (!listEquals(ranges.value, scoped)) ranges.value = scoped;
      if (pointerDown || !show) return;
      if (scoped.isEmpty) {
        _shownSignature = null;
        onDismiss();
        return;
      }
      final signature = scoped
          .map((r) => '${r.pageNumber}:${r.start}:${r.end}')
          .join(',');
      if (signature == _shownSignature) return;
      final result = await _resolve(scoped, epoch);
      if (!_valid(epoch) ||
          pointerDown ||
          result == null ||
          result.rect == null) {
        return;
      }
      _shownSignature = signature;
      onSelection(result);
    } finally {
      _reading = false;
      if (_dirty && _active) refresh();
    }
  }

  List<PdfPageTextRange> _scope(List<PdfPageTextRange> selected) {
    bool? side = _side;
    return [
      for (final range in selected)
        if (range.pageNumber > 0 && range.pageNumber <= controller.pages.length)
          if (controller.pages[range.pageNumber - 1] is! ReaderPdfPage ||
              (controller.pages[range.pageNumber - 1] as ReaderPdfPage)
                      .translated ==
                  (side ??=
                      (controller.pages[range.pageNumber - 1] as ReaderPdfPage)
                          .translated))
            range,
    ];
  }

  Future<void> copy() async {
    if (!_active) return;
    final epoch = _epoch;
    final delegate = controller.textSelectionDelegate;
    if (!delegate.hasSelectedText || !delegate.isCopyAllowed) return;
    final selected = await delegate.getSelectedTextRanges();
    if (!_valid(epoch)) return;
    final result = await _resolve(_scope(selected), epoch);
    if (_valid(epoch) && result != null) {
      await Clipboard.setData(ClipboardData(text: result.text));
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
    ranges.dispose();
  }

  Future<ReaderPdfSelectionResult?> _resolve(
    List<PdfPageTextRange> ranges,
    int epoch,
  ) async {
    final anchors = <ReaderAnchorRange>[];
    Rect? rect;
    for (final range in ranges) {
      if (!_valid(epoch)) {
        return null;
      }
      final page = controller.pages[range.pageNumber - 1];
      if (page is ReaderPdfPage) {
        final anchor = await page.anchorForSelection(range);
        anchors.addAll(anchor?.ranges ?? []);
      }
      final documentRect = controller.calcRectForRectInsidePage(
        pageNumber: range.pageNumber,
        rect: range.bounds,
      );
      final a = controller.documentToGlobal(documentRect.topLeft);
      final b = controller.documentToGlobal(documentRect.bottomRight);
      if (a != null && b != null) {
        final r = Rect.fromPoints(a, b);
        rect = rect == null ? r : rect.expandToInclude(r);
      }
    }
    final merged = <ReaderAnchorRange>[];
    for (final anchor in anchors) {
      final at = merged.indexWhere(
        (r) =>
            r.paragraphId == anchor.paragraphId &&
            r.language == anchor.language,
      );
      final paragraph = index().byId(anchor.paragraphId);
      if (at < 0 || paragraph == null) {
        merged.add(anchor);
        continue;
      }
      final previous = merged[at];
      final value = anchor.language == 'source'
          ? paragraph.plainText
          : readerTranslatedText(translations()[paragraph.hash] ?? '');
      final start = previous.start < anchor.start
          ? previous.start
          : anchor.start;
      final end = previous.end > anchor.end ? previous.end : anchor.end;
      if (end <= value.length) {
        merged[at] = paragraph
            .anchor(
              language: anchor.language,
              displayText: value,
              start: start,
              end: end,
            )
            .ranges
            .single;
      }
    }
    final raw = ranges
        .map((r) => r.pageText.fullText.substring(r.start, r.end))
        .join('\n\n');
    if (!_valid(epoch)) return null;
    final text = merged.isEmpty
        ? readerCopyText(raw)
        : merged
              .map(
                (r) => r.paragraphId.startsWith('pdf-page:')
                    ? readerCopyText(r.quote)
                    : r.quote,
              )
              .join('\n\n')
              .trim();
    if (text.isEmpty) return null;
    return (
      text: text,
      rect: rect,
      anchor: merged.isEmpty ? null : ReaderAnchor(merged),
    );
  }

  Future<void> _tap(Offset global, int epoch) async {
    final position = controller.globalToDocument(global);
    if (position == null) return;
    unawaited(controller.textSelectionDelegate.clearTextSelection());
    final hit = controller.getPdfPageHitTestResult(
      position,
      useDocumentLayoutCoordinates: true,
    );
    final page = hit?.page;
    if (hit == null || page is! ReaderPdfPage) {
      onToggleToolbar();
      return;
    }
    final point = hit.offset.toOffset(page: page);
    final structure = page.structurePage;
    final size = structure?.pageSize;
    if (size != null &&
        size.length >= 2 &&
        size[0] > 0 &&
        size[1] > 0 &&
        structure!.blocks.any(
          (b) =>
              const {'image', 'chart', 'table'}.contains(b.blockLabel) &&
              b.blockBbox.length == 4 &&
              readerBoxRect(
                b.blockBbox,
                Size(size[0], size[1]),
                Size(page.width, page.height),
                page.rotation.index,
              ).contains(point),
        )) {
      return;
    }
    final layout = page.readyLayout ?? await page.layout;
    if (!_valid(epoch) ||
        pointerDown ||
        page.pageNumber > controller.pages.length ||
        !identical(page, controller.pages[page.pageNumber - 1])) {
      return;
    }
    final mark = page
        .annotationGeometry(layout, highlights())
        .hitTest(point, tolerance: 6 / math.max(controller.currentZoom, .01));
    if (mark != null) {
      final origin = position - point;
      final a = controller.documentToGlobal(origin + mark.line.topLeft);
      final b = controller.documentToGlobal(origin + mark.line.bottomRight);
      if (a == null || b == null) return;
      _annotationOpen = true;
      onHighlight(mark.mark.highlight, Rect.fromPoints(a, b));
      return;
    }
    if (layout.blocks.any((block) => block.rect.contains(point))) return;
    if (layout.text.charRects.any(
      (box) => box.isNotEmpty && box.toRect(page: page).contains(point),
    )) {
      return;
    }
    onToggleToolbar();
  }
}
