import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
// pdfrx 的页替换要求代理类型；当前版本尚未从公开入口导出此类型。
// ignore: implementation_imports
import 'package:pdfrx_engine/src/pdf_page_proxies.dart';

import '../../../data/models/book/highlight.dart';
import '../../../data/models/book/reader_anchor.dart';
import '../../../services/reader/reader_document_index.dart';
import '../../../services/document_structure.dart';
import 'reader_layout_geometry.dart';
import 'reader_pdf_annotation_geometry.dart';
import 'reader_pdf_typesetting.dart';

/// PDF 展示层：原文 / 译文 / 同页左右双语。
enum ReaderPdfLayerMode {
  /// 只显示原文（翻译关闭）。
  source,

  /// 译文替换原文文字层。
  translated,

  /// 同一源页两个显示槽位：左原文、右译文。
  bilingual,
}

class ReaderPdfDocumentRef extends PdfDocumentRefFile {
  ReaderPdfDocumentRef(super.path, {this.onPagesChanged})
    : super(
        useProgressiveLoading: false,
        key: PdfDocumentRefKey(path, [Object()]),
      );

  final VoidCallback? onPagesChanged;
  PdfDocument? _document;

  /// 原始页（未经代理包装）：双语槽位与源页映射的唯一依据。
  List<PdfPage> _basePages = const [];
  ReaderDocumentIndex _index = ReaderDocumentIndex.empty;
  Map<String, String> _translations = const {};
  String _language = 'source';
  TextStyle _style = const TextStyle();
  ReaderPdfLayerMode _layer = ReaderPdfLayerMode.source;
  final _retired = <ReaderPdfPage>[];
  final _pages = <(int, bool), ReaderPdfPage>{};
  final _sourceTexts = <int, Future<PdfPageRawText?>>{};
  final _paragraphsByPage = <int, List<ReaderParagraph>>{};
  final _structureByPage = <int, StructurePage>{};

  /// 源页总数：双语不会把界面总页数变成两倍。
  int get sourcePageCount => _basePages.length;

  /// 当前展示层：调用方在切换前后对比，用于按源页恢复位置。
  ReaderPdfLayerMode get layer => _layer;

  /// 源页号 → 显示槽位号；双语取原文一侧。
  int slotForSourcePage(int sourcePageNumber) {
    final page = sourcePageNumber < 1 ? 1 : sourcePageNumber;
    return _layer == ReaderPdfLayerMode.bilingual ? (page - 1) * 2 + 1 : page;
  }

  /// 显示槽位号 → 源页号。
  int sourcePageForSlot(int slotNumber) =>
      _layer == ReaderPdfLayerMode.bilingual
      ? ((slotNumber - 1) ~/ 2) + 1
      : slotNumber;

  @override
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
  ) async {
    final document = await super.loadDocument(progressCallback);
    disposeLayout();
    _document = document;
    _basePages = List<PdfPage>.of(document.pages);
    document.events.listen(
      (_) {},
      onDone: () {
        if (identical(_document, document)) {
          disposeLayout();
          _document = null;
        }
      },
    );
    _replacePages();
    return document;
  }

  void configure(
    ReaderDocumentIndex index,
    Map<String, String> translations,
    String language,
    TextStyle style,
    ReaderPdfLayerMode layer,
  ) {
    if (identical(_index, index) &&
        mapEquals(_translations, translations) &&
        _language == language &&
        _style == style &&
        _layer == layer) {
      return;
    }
    if (!identical(_index, index)) {
      _paragraphsByPage.clear();
      _structureByPage.clear();
      for (final paragraph in index.paragraphs) {
        for (final pageIndex
            in paragraph.regions.map((r) => r.pageIndex).toSet()) {
          (_paragraphsByPage[pageIndex + 1] ??= []).add(paragraph);
        }
      }
      for (final page in index.pages) {
        _structureByPage[page.pageIndex + 1] = page;
      }
    }
    _index = index;
    _translations = Map.unmodifiable(translations);
    _language = language;
    _style = style;
    _layer = layer;
    _replacePages();
  }

  void _replacePages() {
    final document = _document;
    if (document == null) return;
    final current = document.pages;
    final pages = <PdfPage>[];
    for (var i = 0; i < _basePages.length; i++) {
      final base = _basePages[i];
      final sourcePageNumber = i + 1;
      PdfPage slot(bool translated) => _slot(
        base,
        sourcePageNumber,
        slotNumber: pages.length + 1,
        translated: translated,
      );
      switch (_layer) {
        case ReaderPdfLayerMode.source:
          pages.add(slot(false));
        case ReaderPdfLayerMode.translated:
          pages.add(slot(true));
        case ReaderPdfLayerMode.bilingual:
          pages.add(slot(false));
          pages.add(slot(true));
      }
    }
    if (!listEquals(current, pages)) {
      document.pages = pages;
      onPagesChanged?.call();
    }
    // pdfrx 的页更新事件会清除文字缓存；旧帧绘制结束后再释放排版资源。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final retired = List<ReaderPdfPage>.of(_retired);
      _retired.clear();
      for (final page in retired) {
        page.disposeLayout();
      }
    });
  }

  ReaderPdfPage _slot(
    PdfPage base,
    int sourcePageNumber, {
    required int slotNumber,
    required bool translated,
  }) {
    final key = (sourcePageNumber, translated);
    final cached = _pages[key];
    final paragraphs =
        _paragraphsByPage[sourcePageNumber] ?? const <ReaderParagraph>[];
    final structure = _structureByPage[sourcePageNumber];
    final translations = translated ? _translations : const <String, String>{};
    final language = translated ? _language : 'source';
    final reusable =
        cached != null &&
        identical(cached.structurePage, structure) &&
        listEquals(cached.paragraphs, paragraphs) &&
        cached.style == _style &&
        cached.language == language &&
        paragraphs.every(
          (p) => cached.translations[p.hash] == translations[p.hash],
        );
    if (reusable && cached.pageNumber == slotNumber) return cached;
    final page = ReaderPdfPage(
      base,
      pageNumber: slotNumber,
      sourcePageNumber: sourcePageNumber,
      translated: translated,
      paragraphs: paragraphs,
      structurePage: structure,
      translations: translations,
      language: language,
      style: _style,
    );
    // 缓存按源页归属，显示槽位变化不会串页；两侧共用原生文字。
    page._sourceLoader = () =>
        _sourceTexts.putIfAbsent(sourcePageNumber, base.loadText);
    if (reusable) {
      page._readyLayout = cached._readyLayout;
      page._layout = cached._layout?.then((layout) {
        page._readyLayout = layout;
        return layout;
      });
      cached._ownsLayout = false;
    }
    if (cached != null) _retired.add(cached);
    _pages[key] = page;
    return page;
  }

  void disposeLayout() {
    for (final page in [..._pages.values, ..._retired]) {
      page.disposeLayout();
    }
    _pages.clear();
    _retired.clear();
    _sourceTexts.clear();
  }
}

class ReaderPdfBlock {
  final ReaderParagraph paragraph;
  final Rect rect;
  final String text;
  final String language;
  final List<Rect> charRects;

  /// 实际可见行（页坐标）：文字层与规范文本之间的索引映射，作为选区的首选依据。
  final List<ReaderTypesetLine> lines;
  final ReaderTypesetText? typeset;
  ReaderPdfBlock({
    required this.paragraph,
    required this.rect,
    required this.text,
    required this.language,
    required this.charRects,
    this.lines = const [],
    this.typeset,
  });
}

class ReaderPdfPageLayout {
  final PdfPageRawText text;
  final List<ReaderPdfBlock> blocks;
  ReaderPdfPageLayout(this.text, this.blocks);
  void dispose() {
    for (final block in blocks) {
      block.typeset?.dispose();
    }
  }
}

class ReaderPdfPage extends PdfPageRenumbered {
  final List<ReaderParagraph> paragraphs;
  final StructurePage? structurePage;
  final Map<String, String> translations;
  final String language;
  final TextStyle style;

  /// 原始页号：OCR 区域、structurePage、`pdf-page:N` 后备锚点唯一依据。
  final int sourcePageNumber;

  /// 本槽位是否使用译文文字层（双语模式右侧为 true）。
  final bool translated;

  Future<PdfPageRawText?>? _sourceText;
  Future<PdfPageRawText?> Function()? _sourceLoader;
  Future<PdfPageRawText?> get sourceText =>
      _sourceText ??= _sourceLoader?.call() ?? basePage.loadText();
  Future<ReaderPdfPageLayout>? _layout;
  ReaderPdfPageLayout? _readyLayout;
  ReaderPdfPageLayout? get readyLayout => _readyLayout;
  bool _ownsLayout = true;
  ReaderPdfAnnotationGeometry? _annotationGeometry;
  List<Highlight>? _annotationHighlights;
  bool _disposed = false;

  ReaderPdfPage(
    super.source, {
    int? pageNumber,
    int? sourcePageNumber,
    required this.paragraphs,
    this.structurePage,
    required this.translations,
    required this.language,
    required this.style,
    this.translated = false,
  }) : sourcePageNumber = sourcePageNumber ?? source.pageNumber,
       super(pageNumber: pageNumber ?? source.pageNumber);

  Future<ReaderPdfPageLayout> get layout =>
      _layout ??= _buildLayout().then((value) {
        _readyLayout = value;
        return value;
      });
  @override
  Future<PdfPageRawText?> loadText() async => (await layout).text;

  /// 行级标注几何：绘制层与单击命中共用。页几何不变且标注列表实例不变时复用。
  ReaderPdfAnnotationGeometry annotationGeometry(
    ReaderPdfPageLayout layout,
    List<Highlight> highlights,
  ) {
    if (_annotationGeometry != null &&
        identical(highlights, _annotationHighlights)) {
      return _annotationGeometry!;
    }
    _annotationHighlights = highlights;
    return _annotationGeometry = ReaderPdfAnnotationGeometry.build(
      page: this,
      layout: layout,
      highlights: highlights,
    );
  }

  void disposeLayout() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsLayout) _layout?.then((value) => value.dispose());
  }

  Future<ReaderPdfPageLayout> _buildLayout() async {
    final native = await sourceText;
    final geometry = ReaderLayoutGeometry(native);
    final pageSize = Size(width, height);
    final nativeRects = [
      for (final box in native?.charRects ?? const <PdfRect>[])
        box.toRect(page: this),
    ];
    final located = <({ReaderParagraph p, Rect rect, int regionIndex})>[];
    for (final p in paragraphs) {
      for (var regionIndex = 0; regionIndex < p.regions.length; regionIndex++) {
        final region = p.regions[regionIndex];
        if (region.pageIndex != sourcePageNumber - 1) continue;
        final bbox = region.bbox;
        final sourceSize = _sourceSize(p);
        final rect = bbox.length == 4
            ? readerBoxRect(bbox, sourceSize, pageSize, rotation.index)
            : geometry.paragraphRect(p, this, pageSize);
        if (rect == null || rect.isEmpty || !rect.isFinite) continue;
        var clipped = rect.intersect(Offset.zero & pageSize);
        for (final glyph in nativeRects) {
          if (!glyph.isEmpty && rect.inflate(1).contains(glyph.center)) {
            clipped = clipped.expandToInclude(glyph);
          }
        }
        clipped = clipped.intersect(Offset.zero & pageSize);
        if (clipped.isEmpty) continue;
        if (_visualBboxes(p).any(
          (b) => clipped.overlaps(
            readerBoxRect(b, sourceSize, pageSize, rotation.index),
          ),
        )) {
          continue;
        }
        located.add((p: p, rect: clipped, regionIndex: regionIndex));
      }
    }
    final blocks = <ReaderPdfBlock>[];
    final replaced = <Rect>[];
    final addedText = StringBuffer();
    final addedRects = <PdfRect>[];
    final sourceMappings = <String, List<Rect>>{};
    for (final item in located) {
      final p = item.p;
      final translated = translations[p.hash];
      final text = translated == null
          ? p.plainText
          : readerTranslatedText(translated);
      if (text.isEmpty) continue;
      final slice = readerPdfRegionRanges(p, text)[item.regionIndex];
      final display = text.substring(slice.start, slice.end);
      final sourceSlice = readerPdfRegionRanges(
        p,
        p.plainText,
      )[item.regionIndex];
      final sourceDisplay = p.plainText.substring(
        sourceSlice.start,
        sourceSlice.end,
      );
      if (display.isEmpty) continue;
      var rect = item.rect;
      ReaderTypesetText? typeset;
      var lines = const <ReaderTypesetLine>[];
      List<Rect> charRects;
      if (translated != null) {
        // 只借用当前栏内的留白，下一段、公式、图表和页眉页脚均为硬边界。
        var bottom = rect.bottom;
        var limit = math.min(height * .95, rect.bottom + rect.height * .35);
        for (final other in located) {
          if (other == item) continue;
          if (other.rect.left < rect.right &&
              other.rect.right > rect.left &&
              other.rect.top >= rect.bottom) {
            limit = math.min(limit, other.rect.top - 1);
          }
        }
        final sourceSize = _sourceSize(p);
        for (final box in _protectedBboxes(p)) {
          final obstacle = readerBoxRect(
            box,
            sourceSize,
            pageSize,
            rotation.index,
          );
          if (obstacle.left < rect.right &&
              obstacle.right > rect.left &&
              obstacle.top >= rect.bottom) {
            limit = math.min(limit, obstacle.top - 1);
          }
        }
        // PDF 文字层中的非正文也阻止扩张，包括 OCR 没有返回的公式编号。
        for (final r in nativeRects) {
          if (r.left < rect.right &&
              r.right > rect.left &&
              r.top >= rect.bottom + 1) {
            limit = math.min(limit, r.top - 1);
          }
        }
        bottom = math.max(bottom, limit);
        final available = Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          bottom,
        );
        final heights =
            nativeRects
                .where((r) => !r.isEmpty && item.rect.contains(r.center))
                .map((r) => r.height)
                .toList()
              ..sort();
        final fontSize = heights.isEmpty
            ? null
            : heights[heights.length ~/ 2] * 1.7;
        typeset = await ReaderTypesetText.fit(
          text: display,
          source: sourceDisplay,
          rect: available,
          preferredFontSize: fontSize,
          centered: p.isHeading && rect.width > width * .6,
          heading: p.isHeading,
          style: style,
        );
        lines = [
          for (final line in typeset.lines)
            ReaderTypesetLine(
              TextRange(
                start: slice.start + line.range.start,
                end: slice.start + line.range.end,
              ),
              line.rect.shift(rect.topLeft),
            ),
        ];
        rect = Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          math.max(item.rect.bottom, rect.top + typeset.height),
        );
        charRects = List<Rect>.filled(text.length, Rect.zero);
        charRects.setRange(
          slice.start,
          slice.end,
          typeset.charRects.map((r) => r.shift(rect.topLeft)),
        );
        replaced.add(item.rect);
      } else {
        final mapped = sourceMappings.putIfAbsent(
          p.id,
          () => geometry.alignedCharRects(
            text,
            this,
            pageSize,
            within: rect,
            regions: located
                .where((r) => r.p.id == p.id)
                .map((r) => r.rect)
                .toList(),
          ),
        );
        charRects = mapped
            .map((r) => rect.inflate(1).contains(r.center) ? r : Rect.zero)
            .toList();
        if (charRects.isEmpty && (native?.fullText.trim().isEmpty ?? true)) {
          // 扫描件没有原生字符坐标，按 OCR 段落框生成可拖选的透明文字层。
          final fallback = await ReaderTypesetText.fit(
            text: display,
            source: sourceDisplay,
            rect: rect,
            heading: p.isHeading,
            style: style,
          );
          charRects = List<Rect>.filled(text.length, Rect.zero);
          charRects.setRange(
            slice.start,
            slice.end,
            fallback.charRects.map((r) => r.shift(rect.topLeft)),
          );
          lines = [
            for (final line in fallback.lines)
              ReaderTypesetLine(
                TextRange(
                  start: slice.start + line.range.start,
                  end: slice.start + line.range.end,
                ),
                line.rect.shift(rect.topLeft),
              ),
          ];
          fallback.dispose();
        }
      }
      blocks.add(
        ReaderPdfBlock(
          paragraph: p,
          rect: rect,
          text: text,
          language: translated == null ? 'source' : language,
          charRects: charRects,
          lines: lines,
          typeset: typeset,
        ),
      );
      if (lines.isNotEmpty) {
        // 文字层按实际可见行组织：行末换行只属于显示层，
        // 规范引用与翻译哈希保持不变。
        for (final line in lines) {
          final start = math.max(line.range.start, slice.start);
          final end = math.min(line.range.end, slice.end);
          if (end <= start) continue;
          for (var i = start; i < end; i++) {
            addedText.write(text[i]);
            addedRects.add(
              charRects[i].isEmpty
                  ? const PdfRect(0, 0, 0, 0)
                  : readerRectToPdf(charRects[i], this),
            );
          }
          addedText.write('\n');
          addedRects.add(const PdfRect(0, 0, 0, 0));
        }
      } else if (translated != null ||
          (native?.fullText.trim().isEmpty ?? true)) {
        addedText.write(display);
        addedRects.addAll(
          charRects
              .sublist(slice.start, slice.end)
              .map((r) => readerRectToPdf(r, this)),
        );
        addedText.write('\n');
        addedRects.add(const PdfRect(0, 0, 0, 0));
      }
    }
    final text = StringBuffer();
    final rects = <PdfRect>[];
    if (native != null) {
      for (
        var i = 0;
        i < native.fullText.length && i < native.charRects.length;
        i++
      ) {
        final rect = native.charRects[i].toRect(page: this);
        if (replaced.any((r) => r.contains(rect.center))) continue;
        text.write(native.fullText[i]);
        rects.add(native.charRects[i]);
      }
    }
    text.write(addedText);
    rects.addAll(addedRects);
    return ReaderPdfPageLayout(PdfPageRawText(text.toString(), rects), blocks);
  }

  Size _sourceSize(ReaderParagraph p) {
    final source =
        structurePage?.pageSize ??
        (p.pageIndex == sourcePageNumber - 1 ? p.pageSize : null);
    return source == null
        ? Size(width * 2, height * 2)
        : Size(source[0], source[1]);
  }

  Iterable<List<double>> _visualBboxes(ReaderParagraph p) =>
      structurePage == null
      ? p.visualBboxes
      : structurePage!.blocks
            .where(
              (b) => const {'image', 'chart', 'table'}.contains(b.blockLabel),
            )
            .map((b) => b.blockBbox)
            .where((b) => b.length == 4);
  Iterable<List<double>> _protectedBboxes(ReaderParagraph p) =>
      structurePage == null
      ? p.protectedBboxes
      : structurePage!.blocks
            .where((b) => !ReaderDocumentIndex.canTranslate(b, structurePage!))
            .map((b) => b.blockBbox)
            .where((b) => b.length == 4);

  Future<ReaderAnchor?> anchorForSelection(PdfPageTextRange selection) async {
    final pageLayout = await layout;
    // 页面版本已替换或释放时拒绝过期选区，不把旧索引交给新页。
    if (_disposed) return null;
    final result = <ReaderAnchorRange>[];
    final selectedLines = mergeLineRects(
      selection.pageText.charRects
          .sublist(selection.start, selection.end)
          .map((r) => r.toRect(page: this)),
    );
    for (final block in pageLayout.blocks) {
      final selected = selectedLines
          .where((r) => r.overlaps(block.rect))
          .toList();
      if (selected.isEmpty) continue;
      final indexes = _matchCharIndexes(block.charRects, selected);
      if (indexes.isEmpty) continue;
      result.addAll(
        block.paragraph
            .anchor(
              language: block.language,
              displayText: block.text,
              start: indexes.first,
              end: indexes.last + 1,
            )
            .ranges,
      );
    }
    if (result.isNotEmpty) return ReaderAnchor(result);
    final raw = pageLayout.text;
    final indexes = _matchCharIndexes(
      raw.charRects.map((r) => r.toRect(page: this)).toList(),
      selectedLines,
    );
    if (indexes.isEmpty) return null;
    final start = indexes.first;
    final end = indexes.last + 1;
    return ReaderAnchor([
      ReaderAnchorRange(
        paragraphId: 'pdf-page:$sourcePageNumber',
        language: 'source',
        revision: readerTextRevision(raw.fullText),
        start: start,
        end: end,
        quote: raw.fullText.substring(start, end),
      ),
    ]);
  }

  // 选区先合并成行，匹配复杂度从“每字 × 每选中字”降为“每字 × 选中行”。
  List<int> _matchCharIndexes(List<Rect> chars, List<Rect> selected) {
    final lines = selected.map((r) => r.inflate(.2)).toList();
    return [
      for (var i = 0; i < chars.length; i++)
        if (!chars[i].isEmpty &&
            lines.any((line) => line.contains(chars[i].center)))
          i,
    ];
  }
}

PdfRect readerRectToPdf(Rect r, PdfPage page) => r.toPdfRect(page: page);

List<TextRange> readerPdfRegionRanges(ReaderParagraph p, String text) {
  final weights = p.regions
      .map((r) => r.sourceLength.clamp(1, 1 << 30))
      .toList();
  final total = weights.fold<int>(0, (a, b) => a + b);
  final formulas = RegExp(
    r'\$[^$\n]+\$|\\\([\s\S]*?\\\)',
  ).allMatches(text).toList();
  final result = <TextRange>[];
  var start = 0;
  var weight = 0;
  for (var i = 0; i < weights.length; i++) {
    weight += weights[i];
    var end = i == weights.length - 1
        ? text.length
        : (text.length * weight / total).round().clamp(start, text.length);
    for (final f in formulas) {
      if (end > f.start && end < f.end) end = f.end;
    }
    if (end > 0 &&
        end < text.length &&
        text.codeUnitAt(end) >= 0xDC00 &&
        text.codeUnitAt(end) <= 0xDFFF) {
      end++;
    }
    result.add(TextRange(start: start, end: end));
    start = end;
  }
  return result;
}
