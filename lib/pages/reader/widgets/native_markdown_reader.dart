import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../data/models/book/highlight.dart';
import '../../../data/models/book/reader_anchor.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../utils/desktop.dart';
import 'native_reader/native_reader_document.dart';
import 'native_reader/native_reader_scrollbar.dart';
import 'native_reader/native_reader_text.dart';
import 'reader_background.dart';
import 'reader_content_handle.dart';
import 'reader_js_bridge.dart' show ReaderScrollMetrics, SearchHit;
import 'reader_typography.dart';

/// 用 Flutter 组件渲染提取结果的阅读器，接口与 `WebViewMarkdownReader` 对齐。
///
/// 正文按段落切成懒加载列表项；每个段落的每种语言是一个语言单元
/// （[NativeReaderCell]），选区、标注、搜索都落在它的纯文本坐标上，
/// 与 WebView 版共用同一份 `ReaderAnchor` 数据。
///
/// 仅支持连续纵向滚动；横向翻页仍由 WebView 版承担。
class NativeMarkdownReader extends StatefulWidget {
  const NativeMarkdownReader({
    super.key,
    required this.markdownData,
    this.readerEntries = const [],
    this.translatedMarkdown = const {},
    this.contentRevision = 0,
    required this.settings,
    required this.palette,
    this.bilingualColumns = false,
    this.highlights = const [],
    this.translationStyleId = 'themed',
    this.initialScrollProgress = 0,
    this.initialParagraphId,
    this.topInset = 0,
    this.bottomInset = 0,
    this.highlightQuery,
    this.onSelectionAnchor,
    this.onSelectionEnd,
    this.onSelectionCleared,
    this.onHighlightClick,
    this.onImageClick,
    this.onScrollDirection,
    this.onScrollProgress,
    this.onReadingParagraphChanged,
    this.onToggleToolbar,
  });

  /// `ReaderMarkdownPresentation` 产出的带段落标记 Markdown。
  final String markdownData;
  final List<Map<String, dynamic>> readerEntries;

  /// 段落 id → 译文 Markdown。
  final Map<String, String> translatedMarkdown;
  final int contentRevision;
  final ReaderSettingsState settings;
  final ReaderPalette palette;
  final bool bilingualColumns;
  final List<Highlight> highlights;
  final String translationStyleId;
  final double initialScrollProgress;
  final String? initialParagraphId;
  final double topInset;
  final double bottomInset;
  final String? highlightQuery;

  final ValueChanged<ReaderAnchor?>? onSelectionAnchor;
  final void Function(String text, Rect selectionRect, int lineCount)?
  onSelectionEnd;
  final VoidCallback? onSelectionCleared;
  final void Function(Highlight highlight, Rect rect)? onHighlightClick;
  final void Function(String imageSource)? onImageClick;
  final void Function(ScrollDirection direction)? onScrollDirection;

  /// 进度按列表项计（第几项 + 项内比例），不是像素比例；锚点块恒为 null。
  final void Function(double progress, int? anchorBlock)? onScrollProgress;
  final ValueChanged<String?>? onReadingParagraphChanged;

  /// 桌面端单击正文留白。
  final VoidCallback? onToggleToolbar;

  @override
  NativeMarkdownReaderState createState() => NativeMarkdownReaderState();
}

typedef _Located = ({String cellKey, int start, int end});

class NativeMarkdownReaderState extends State<NativeMarkdownReader>
    implements ReaderContentHandle, NativeReaderTextHost {
  // 与 reader.css 的 ::selection / .search-hl / .search-hl-active 同色。
  static const _selectionColor = Color(0x4D6495ED);
  static const _searchColor = Color(0x40FFC107);
  static const _searchActiveColor = Color(0x99FF9800);

  final _selectionKey = GlobalKey<SelectionAreaState>();
  final _centerKey = GlobalKey();
  late final ScrollController _scroll;
  final _lock = ValueNotifier<NativeCellKind?>(null);
  final _metrics = ValueNotifier(
    const ReaderScrollMetrics(progress: 0, viewportRatio: 1),
  );

  /// 已挂载的列表项。
  final _items = <int, _SegmentItemState>{};

  // ── 内容 ──
  List<NativeReaderSegment> _segments = const [];
  final _pairIndex = <String, int>{};
  final _figureIndex = <String, int>{};
  final _imageIndex = <String, int>{};
  List<Map<String, dynamic>> _entries = const [];
  Map<String, String> _translated = const {};
  final _entryById = <String, Map<String, dynamic>>{};

  /// 题注与条目按文字配上对的图片项。
  final _figureEntries = <int, Map<String, dynamic>>{};
  final _cells = <int, List<NativeReaderCell>>{};
  final _cellEntry = <int, Map<String, dynamic>?>{};
  Map<String, List<ReaderMark>> _marks = const {};
  bool _hasBilingual = false;
  NativeReaderStyle? _style;

  /// 列表以该项顶端为滚动原点，向上、向下各自懒加载。
  int _anchor = 0;

  // ── 选区 ──
  final _selections = <String, NativeTextSelection>{};
  String _selectedContent = '';
  String _selectionSignature = '';
  bool _held = false;
  bool _lockedByCell = false;
  Offset? _pointerDown;
  Offset? _lastPointer;
  bool _pointerDragged = false;
  bool _primaryClick = false;

  // ── 搜索与定位 ──
  List<NativeSearchMatch> _hits = const [];
  int? _activeHit;
  _Located? _located;
  int? _flashSegment;
  Timer? _locateTimer;

  // ── 滚动上报 ──
  bool _measureScheduled = false;
  double _lastPixels = 0;
  ScrollDirection? _lastDirection;
  double _progress = 0;
  int _firstVisible = 0;
  Timer? _progressTimer;

  double get _lead =>
      widget.topInset +
      widget.settings.fontSize * ReaderTypography.blockMarginScale;

  @override
  void initState() {
    super.initState();
    _parse();
    _syncEntries();
    _applyQuery(widget.highlightQuery);
    _rebuildMarks();

    final count = _segments.length;
    var fraction = 0.0;
    final paragraph = widget.initialParagraphId;
    final start = paragraph == null ? null : _paragraphSegment(paragraph);
    if (start != null) {
      _anchor = start;
    } else if (count > 0) {
      final target = widget.initialScrollProgress.clamp(0.0, 1.0) * count;
      _anchor = math.min(target.floor(), count - 1);
      fraction = target - _anchor;
    }
    _lastPixels = -_lead;
    _scroll = ScrollController(initialScrollOffset: -_lead)
      ..addListener(_scheduleMeasure);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _items[_anchor]?.context.findRenderObject();
      if (fraction > 0 && box is RenderBox && _scroll.hasClients) {
        final pixels = _scroll.position.pixels + fraction * box.size.height;
        _lastPixels = pixels;
        _scroll.jumpTo(pixels);
      }
      _scheduleMeasure();
    });
  }

  @override
  void didUpdateWidget(covariant NativeMarkdownReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    var marks =
        !identical(widget.highlights, oldWidget.highlights) ||
        widget.palette != oldWidget.palette;
    if (widget.markdownData != oldWidget.markdownData ||
        widget.contentRevision != oldWidget.contentRevision) {
      _parse();
      _cells.clear();
      _cellEntry.clear();
      _selections.clear();
      _located = null;
      _flashSegment = null;
      _syncEntries();
      _applyQuery(widget.highlightQuery);
      marks = true;
    } else {
      if (!_deferEntries && !identical(widget.readerEntries, _entries)) {
        _syncEntries();
        marks = true;
      }
      if (widget.highlightQuery != oldWidget.highlightQuery) {
        _applyQuery(widget.highlightQuery);
        marks = true;
      }
    }
    if (marks) _rebuildMarks();
  }

  @override
  void dispose() {
    _locateTimer?.cancel();
    _progressTimer?.cancel();
    _scroll.dispose();
    _lock.dispose();
    _metrics.dispose();
    super.dispose();
  }

  // ─── 内容模型 ───

  void _parse() {
    _segments = parseNativeReaderSegments(widget.markdownData);
    _pairIndex.clear();
    _figureIndex.clear();
    _imageIndex.clear();
    for (var i = 0; i < _segments.length; i++) {
      switch (_segments[i]) {
        case NativePairSegment(:final id):
          _pairIndex[id] = i;
        case NativeFigureSegment(:final figureId, :final fileName):
          if (figureId != null) _figureIndex[figureId] = i;
          _imageIndex[fileName] = i;
        case NativeBlockSegment(:final figureId):
          if (figureId != null) _figureIndex[figureId] = i;
      }
    }
    if (_anchor >= _segments.length) {
      _anchor = math.max(0, _segments.length - 1);
    }
  }

  void _syncEntries() {
    _entries = widget.readerEntries;
    _translated = widget.translatedMarkdown;
    _entryById.clear();
    _figureEntries.clear();
    _hasBilingual = false;
    // 没有段落标记的题注条目，按文字与图片题注一一配对；数量对不上时
    // 保持未配对，不落到第一处。
    final loose = <String, List<Map<String, dynamic>>>{};
    for (final entry in _entries) {
      final id = entry['id'] as String;
      _entryById[id] = entry;
      if (entry['bilingual'] == true) _hasBilingual = true;
      if (entry['caption'] == true && !_pairIndex.containsKey(id)) {
        loose
            .putIfAbsent(entry['source'] as String? ?? '', () => [])
            .add(entry);
      }
    }
    if (loose.isNotEmpty) {
      final figures = <String, List<int>>{};
      for (var i = 0; i < _segments.length; i++) {
        final segment = _segments[i];
        if (segment is NativeFigureSegment && segment.caption.isNotEmpty) {
          figures.putIfAbsent(segment.captionText, () => []).add(i);
        }
      }
      for (final MapEntry(key: text, value: entries) in loose.entries) {
        final indexes = figures[text];
        if (indexes == null || indexes.length != entries.length) continue;
        for (var i = 0; i < indexes.length; i++) {
          _figureEntries[indexes[i]] = entries[i];
        }
      }
    }
    // 只丢弃条目变了的语言单元，其余保留身份，避免无谓重排。
    final stale = [
      for (final index in _cells.keys)
        if (!identical(_cellEntry[index], _entryOf(index))) index,
    ];
    for (final index in stale) {
      for (final cell in _cells.remove(index)!) {
        _selections.removeWhere((_, value) => identical(value.cell, cell));
      }
    }
  }

  Map<String, dynamic>? _entryOf(int index) => switch (_segments[index]) {
    NativePairSegment(:final id) => _entryById[id],
    NativeFigureSegment() => _figureEntries[index],
    NativeBlockSegment() => null,
  };

  String? _paragraphId(int index) => _entryOf(index)?['id'] as String?;

  int? _paragraphSegment(String id) {
    final index = _pairIndex[id];
    if (index != null) return index;
    for (final MapEntry(:key, :value) in _figureEntries.entries) {
      if (value['id'] == id) return key;
    }
    return null;
  }

  List<NativeReaderCell> _cellsOf(int index) =>
      _cells[index] ??= _buildCells(index);

  List<NativeReaderCell> _buildCells(int index) {
    final entry = _cellEntry[index] = _entryOf(index);
    switch (_segments[index]) {
      case NativePairSegment(:final id, :final markdown):
        if (entry == null) return [NativeReaderCell.block(index, markdown)];
        return nativeEntryCells(
          index,
          entry,
          sourceMarkdown: markdown,
          translatedMarkdown: _translated[id] ?? '',
        );
      case NativeFigureSegment(:final caption):
        if (caption.isEmpty) return const [];
        if (entry == null) {
          return [NativeReaderCell.block(index, caption, caption: true)];
        }
        return nativeEntryCells(
          index,
          entry,
          sourceMarkdown: caption,
          translatedMarkdown: _translated[entry['id']] ?? '',
        );
      case NativeBlockSegment(:final isTable, :final markdown):
        return isTable ? const [] : [NativeReaderCell.block(index, markdown)];
    }
  }

  /// 有段落身份的列表项（正文段落与配上对的图题）。
  Iterable<int> get _anchoredSegments =>
      _pairIndex.values.followedBy(_figureEntries.keys);

  void _rebuildMarks() {
    final marks = <String, List<ReaderMark>>{};
    void add(String key, ReaderMark mark) =>
        marks.putIfAbsent(key, () => []).add(mark);

    if (widget.highlights.isNotEmpty) {
      final byKey = <String, NativeReaderCell>{
        for (final index in _anchoredSegments)
          for (final cell in _cellsOf(index)) cell.key: cell,
      };
      for (final highlight in widget.highlights) {
        final color = Color(
          0xFF000000 | (int.tryParse(highlight.color, radix: 16) ?? 0xFFD54F),
        ).withValues(alpha: 0.3);
        final anchor = highlight.anchor;
        if (anchor != null) {
          for (final range in anchor.ranges) {
            // 隐藏的语言不画；语言换过的旧译文标注也不落到新译文上。
            final kind = range.language == 'source' ? 'source' : 'target';
            final cell = byKey['${range.paragraphId}/$kind'];
            if (cell == null || cell.language != range.language) continue;
            final hit = range.resolve(cell.text, cell.revision);
            if (hit == null) continue;
            add(
              cell.key,
              ReaderMark(hit.start, hit.end, color, highlightId: highlight.id),
            );
          }
          continue;
        }
        // 没有锚点的旧标注：全文只在一处出现时才画。
        final quote = CompactText(highlight.text).text;
        if (quote.isEmpty) continue;
        final found = <(NativeReaderCell, ({int start, int end}))>[];
        for (final cell in byKey.values) {
          final at = cell.compact.text.indexOf(quote);
          if (at < 0 || cell.compact.text.indexOf(quote, at + 1) >= 0) continue;
          final range = cell.compact.range(at, at + quote.length);
          if (range != null) found.add((cell, range));
        }
        if (found.length != 1) continue;
        final (cell, range) = found.single;
        add(
          cell.key,
          ReaderMark(range.start, range.end, color, highlightId: highlight.id),
        );
      }
    }
    for (var i = 0; i < _hits.length; i++) {
      final hit = _hits[i];
      add(
        hit.cellKey,
        ReaderMark(
          hit.start,
          hit.end,
          i == _activeHit ? _searchActiveColor : _searchColor,
        ),
      );
    }
    final located = _located;
    if (located != null) {
      add(
        located.cellKey,
        ReaderMark(
          located.start,
          located.end,
          widget.palette.link.withValues(alpha: 0.28),
        ),
      );
    }
    _marks = marks;
  }

  // ─── 搜索 ───

  List<NativeSearchMatch> _search(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
  }) {
    Iterable<({NativeReaderCell cell, bool heading})> cells() sync* {
      for (var i = 0; i < _segments.length; i++) {
        final heading = switch (_segments[i]) {
          NativePairSegment(:final markdown) ||
          NativeBlockSegment(:final markdown) =>
            nativeHeadingLevel(markdown) > 0,
          NativeFigureSegment() => false,
        };
        for (final cell in _cellsOf(i)) {
          yield (cell: cell, heading: heading);
        }
      }
    }

    return nativeSearch(
      cells(),
      query,
      caseSensitive: caseSensitive,
      wholeWord: wholeWord,
    );
  }

  void _applyQuery(String? query) {
    _hits = query == null || query.isEmpty ? const [] : _search(query);
    _activeHit = null;
  }

  @override
  Future<List<SearchHit>> searchContent(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
  }) async {
    final hits = query.isEmpty
        ? const <NativeSearchMatch>[]
        : _search(query, caseSensitive: caseSensitive, wholeWord: wholeWord);
    if (!mounted) return const [];
    setState(() {
      _hits = hits;
      _activeHit = null;
      _rebuildMarks();
    });
    return [
      for (var i = 0; i < hits.length; i++)
        SearchHit(
          heading: hits[i].heading,
          snippet: hits[i].snippet,
          matchStart: hits[i].matchStart,
          matchLength: hits[i].end - hits[i].start,
          hitIndex: i,
        ),
    ];
  }

  @override
  void scrollToSearchResult(int index) {
    if (index < 0 || index >= _hits.length) return;
    setState(() {
      _activeHit = index;
      _rebuildMarks();
    });
    _scrollToSegment(_hits[index].segment, alignment: 0.3);
  }

  // ─── 跳转与定位 ───

  /// 让列表项 [index] 的顶端停在视口上方 [alignment] 处（至少让出工具栏）。
  /// 目标已在缓存区内时平滑滚动，否则以它为新原点直接重排。
  void _scrollToSegment(
    int index, {
    double alignment = 0,
    bool animate = true,
  }) {
    if (_segments.isEmpty || !_scroll.hasClients) return;
    final target = index.clamp(0, _segments.length - 1);
    final position = _scroll.position;
    final lead = math.max(_lead, position.viewportDimension * alignment);
    final box = _items[target]?.context.findRenderObject();
    if (animate &&
        box is RenderBox &&
        box.attached &&
        !MediaQuery.disableAnimationsOf(context)) {
      final reveal = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0);
      position.animateTo(
        (reveal.offset - lead).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: kAnim,
        curve: kAnimCurve,
      );
      return;
    }
    // 滚动原点一换，框架按旧原点记下的选区端点就失效了。
    clearSelection();
    setState(() => _anchor = target);
    _lastPixels = -lead;
    position.jumpTo(-lead);
    _scheduleMeasure();
  }

  void _jumpToRatio(double ratio) {
    if (_segments.isEmpty) return;
    _scrollToSegment((ratio * _segments.length).floor(), animate: false);
  }

  /// 跳到原始 Markdown 偏移 [offset] 所在的列表项（大纲导航）。
  void scrollToSourceOffset(int offset) {
    var low = 0;
    var high = _segments.length - 1;
    var index = 0;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (_segments[middle].sourceOffset <= offset) {
        index = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    _scrollToSegment(index);
  }

  @override
  void scrollToFigure(String id) {
    final index = _figureIndex[id];
    if (index != null) _scrollToSegment(index, alignment: 0.3);
  }

  @override
  void flashImage(String filename) {
    final index = _imageIndex[filename];
    if (index == null) return;
    _showLocated(index, null, const Duration(seconds: 2));
  }

  @override
  Future<bool> locateQuote(
    String quote, {
    ReaderAnchor? anchor,
    String? figureName,
  }) async {
    final target = _resolveQuote(quote, anchor, figureName);
    if (target == null || !mounted) return false;
    _showLocated(target.segment, target.range, const Duration(seconds: 4));
    return true;
  }

  ({int segment, _Located? range})? _resolveQuote(
    String quote,
    ReaderAnchor? anchor,
    String? figureName,
  ) {
    final figure = figureName == null ? null : _imageIndex[figureName];
    if (figure != null) return (segment: figure, range: null);

    for (final part in anchor?.ranges ?? const <ReaderAnchorRange>[]) {
      final index = _paragraphSegment(part.paragraphId);
      if (index == null) continue;
      final cells = _cellsOf(index);
      if (cells.isEmpty) continue;
      final cell = cells.where((c) => c.language == part.language).firstOrNull;
      final hit = cell == null ? null : part.resolve(cell.text, cell.revision);
      // 该语言当前未显示或文字已变：退而标出整段。
      final shown = hit == null || cell == null ? cells.first : cell;
      return (
        segment: index,
        range: (
          cellKey: shown.key,
          start: hit?.start ?? 0,
          end: hit?.end ?? shown.text.length,
        ),
      );
    }

    final key = CompactText(quote).text;
    if (key.isEmpty) return null;
    final hits = [
      for (final index in _anchoredSegments)
        for (final cell in _cellsOf(index))
          if (cell.compact.text.contains(key)) cell,
    ];
    if ({for (final cell in hits) cell.paragraphId}.length != 1) return null;
    final cell =
        hits.where((c) => c.kind == NativeCellKind.source).firstOrNull ??
        hits.first;
    final at = cell.compact.text.indexOf(key);
    final range = cell.compact.text.indexOf(key, at + 1) >= 0
        ? null
        : cell.compact.range(at, at + key.length);
    return (
      segment: cell.segment,
      range: (
        cellKey: cell.key,
        start: range?.start ?? 0,
        end: range?.end ?? cell.text.length,
      ),
    );
  }

  /// 滚到 [segment] 并短暂标出：给了 [range] 标文字，否则给整项描边。
  void _showLocated(int segment, _Located? range, Duration duration) {
    setState(() {
      _located = range;
      _flashSegment = range == null ? segment : null;
      _rebuildMarks();
    });
    _scrollToSegment(segment, alignment: 0.3);
    _locateTimer?.cancel();
    _locateTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _located = null;
        _flashSegment = null;
        _rebuildMarks();
      });
    });
  }

  // ─── 滚动上报 ───

  // 位置换算要读布局结果，统一放到帧末；滚动监听可能在布局途中触发。
  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (mounted) _measure();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _measure() {
    if (!_scroll.hasClients || _segments.isEmpty) return;
    final position = _scroll.position;
    final delta = position.pixels - _lastPixels;
    if (delta.abs() > 8) {
      _lastPixels = position.pixels;
      // 同向连续滚动只上报一次，与 WebView 版一致。
      final direction = delta > 0
          ? ScrollDirection.reverse
          : ScrollDirection.forward;
      if (direction != _lastDirection) {
        _lastDirection = direction;
        widget.onScrollDirection?.call(direction);
      }
    }

    final root = context.findRenderObject();
    if (root is! RenderBox || !root.hasSize) return;
    final top = widget.topInset;
    final bottom = root.size.height - widget.bottomInset;
    int? first;
    var fraction = 0.0;
    var visible = 0;
    for (final MapEntry(key: index, value: item) in _items.entries) {
      final box = item.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero, ancestor: root).dy;
      final height = box.size.height;
      if (y + height <= top || y >= bottom) continue;
      visible++;
      if (first == null || index < first) {
        first = index;
        fraction = height <= 0 ? 0 : ((top - y) / height).clamp(0.0, 1.0);
      }
    }
    if (first == null) return;

    final count = _segments.length;
    final atEnd =
        _items.containsKey(count - 1) &&
        position.pixels >= position.maxScrollExtent - 1;
    _firstVisible = first;
    _progress = atEnd ? 1 : ((first + fraction) / count).clamp(0.0, 1.0);
    _metrics.value = ReaderScrollMetrics(
      progress: _progress,
      viewportRatio: (visible / count).clamp(0.05, 1.0),
    );
    _progressTimer ??= Timer(const Duration(milliseconds: 500), () {
      _progressTimer = null;
      if (!mounted) return;
      String? paragraph;
      final end = math.min(_segments.length, _firstVisible + 12);
      for (var i = _firstVisible; i < end && paragraph == null; i++) {
        paragraph = _paragraphId(i);
      }
      widget.onReadingParagraphChanged?.call(paragraph);
      widget.onScrollProgress?.call(_progress, null);
    });
  }

  // ─── 选区 ───

  @override
  ValueListenable<NativeCellKind?> get selectionLock => _lock;

  bool get _deferEntries => _held || _pointerDown != null;

  void _lockSelection(NativeCellKind kind) {
    _lockedByCell = true;
    _lock.value = kind;
  }

  void _onPointerDown(PointerDownEvent event) {
    // 语言单元的监听先于这里触发；没有落在任何单元上就解除限制。
    if (!_lockedByCell) _lock.value = null;
    _lockedByCell = false;
    _pointerDown = event.position;
    _pointerDragged = false;
    _primaryClick =
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final down = _pointerDown;
    if (down != null && (event.position - down).distance > 4) {
      _pointerDragged = true;
    }
  }

  void _onPointerEnd(PointerEvent event) {
    final clicked = _pointerDown != null && !_pointerDragged && _primaryClick;
    _pointerDown = null;
    _lastPointer = event.position;
    _applyDeferredEntries();
    if (!isDesktopOs || !clicked || event is! PointerUpEvent) return;
    // 桌面端单击留白切换工具栏；选区收尾在同一事件里完成，推迟一拍再判断。
    scheduleMicrotask(() {
      if (!mounted || _selections.isNotEmpty || _selectedContent.isNotEmpty) {
        return;
      }
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(
        result,
        event.position,
        event.viewId,
      );
      final onContent = result.path.any(
        (entry) =>
            entry.target is RenderParagraph || entry.target is RenderImage,
      );
      if (!onContent) widget.onToggleToolbar?.call();
    });
  }

  void _applyDeferredEntries() {
    if (!mounted ||
        _deferEntries ||
        identical(_entries, widget.readerEntries)) {
      return;
    }
    setState(() {
      _syncEntries();
      _rebuildMarks();
    });
  }

  @override
  void holdTranslations(bool value) {
    _held = value;
    _applyDeferredEntries();
  }

  @override
  void textSelectionChanged(NativeTextSelection selection) {
    final key = '${selection.cell.key}#${selection.order}';
    if (selection.text.isEmpty) {
      _selections.remove(key);
    } else {
      // 滚出缓存区的文字不再回报；它最后一次的范围留在这里，供收尾时拼出
      // 完整的跨屏选区。
      _selections[key] = selection;
    }
  }

  void _onSelectedContent(SelectedContent? content) {
    _selectedContent = content?.plainText ?? '';
    if (content == null) _selections.clear();
  }

  void _onSelectionFinalized() => scheduleMicrotask(_emitSelection);

  void _emitSelection() {
    if (!mounted) return;
    final selection = _composeSelection();
    if (selection == null) {
      _selectionSignature = '';
      widget.onSelectionCleared?.call();
      return;
    }
    // 同一选区的重复收尾信号不再打扰工具栏。
    final signature = '${selection.text}|${selection.rect}';
    if (signature == _selectionSignature) return;
    _selectionSignature = signature;
    widget.onSelectionAnchor?.call(selection.anchor);
    widget.onSelectionEnd?.call(
      selection.text,
      selection.rect,
      selection.lineCount,
    );
  }

  ({String text, ReaderAnchor? anchor, Rect rect, int lineCount})?
  _composeSelection() {
    final ordered = _selections.values.toList()
      ..sort((a, b) {
        final segment = a.cell.segment.compareTo(b.cell.segment);
        if (segment != 0) return segment;
        final kind = a.cell.kind.index.compareTo(b.cell.kind.index);
        return kind != 0 ? kind : a.order.compareTo(b.order);
      });
    final byCell = <NativeReaderCell, List<NativeTextSelection>>{};
    for (final selection in ordered) {
      byCell.putIfAbsent(selection.cell, () => []).add(selection);
    }

    final texts = <String>[];
    final ranges = <ReaderAnchorRange>[];
    final rects = <Rect>[];
    for (final MapEntry(key: cell, value: parts) in byCell.entries) {
      final mapped = [
        for (final part in parts)
          if (part.range case final range?) range,
      ];
      if (mapped.isEmpty) {
        texts.add(parts.map((part) => part.text).join('\n'));
      } else {
        final start = mapped.map((range) => range.start).reduce(math.min);
        final end = mapped.map((range) => range.end).reduce(math.max);
        texts.add(cell.text.substring(start, end));
        if (cell.anchored) ranges.add(nativeAnchorRange(cell, start, end));
      }
      for (final part in parts) {
        rects.addAll(part.rects());
      }
    }
    // 表格等不经过语言单元的内容，退回框架给出的选中文字。
    var text = texts.join('\n\n');
    if (text.trim().isEmpty) text = _selectedContent;
    if (text.trim().isEmpty) return null;

    final lines = rects.where((r) => r.width > 0.5 && r.height > 0.5).toList()
      ..sort((a, b) => a.top.compareTo(b.top));
    var lineCount = 0;
    var lineBottom = double.negativeInfinity;
    Rect? bounds;
    for (final rect in lines) {
      bounds = bounds?.expandToInclude(rect) ?? rect;
      if (rect.top >= lineBottom - 2) {
        lineCount++;
        lineBottom = rect.bottom;
      } else {
        lineBottom = math.max(lineBottom, rect.bottom);
      }
    }
    final root = context.findRenderObject();
    final viewport = root is RenderBox && root.hasSize
        ? root.localToGlobal(Offset.zero) & root.size
        : null;
    final pointer = _lastPointer ?? viewport?.center;
    if (bounds == null) {
      if (pointer == null) return null;
      bounds = Rect.fromCenter(center: pointer, width: 1, height: 1);
    }
    if (viewport != null) {
      bounds = bounds.overlaps(viewport)
          ? bounds.intersect(viewport)
          : Rect.fromCenter(center: viewport.center, width: 1, height: 1);
    }
    return (
      text: text,
      anchor: ranges.isEmpty ? null : ReaderAnchor(ranges),
      rect: bounds,
      lineCount: math.max(1, lineCount),
    );
  }

  Object? _copySelection() {
    final text = _composeSelection()?.text ?? _selectedContent;
    if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
    return null;
  }

  @override
  void clearSelection() {
    _selectionKey.currentState?.selectableRegion.clearSelection();
    _selections.clear();
    _selectedContent = '';
    _selectionSignature = '';
  }

  /// 标注由 `highlights` 重新着色画出，这里只需撤掉选区。
  @override
  void addHighlightFromSelection(String id, String color) => clearSelection();

  @override
  void highlightTapped(String highlightId, Rect globalRect) {
    final highlight = widget.highlights
        .where((h) => h.id == highlightId)
        .firstOrNull;
    if (highlight == null) return;
    clearSelection();
    widget.onHighlightClick?.call(highlight, globalRect);
  }

  // ─── UI ───

  NativeReaderStyle _resolveStyle() {
    final style = _style;
    if (style != null &&
        style.palette == widget.palette &&
        style.fontSize == widget.settings.fontSize &&
        style.font == widget.settings.font &&
        style.translationStyleId == widget.translationStyleId) {
      return style;
    }
    return _style = NativeReaderStyle(
      palette: widget.palette,
      fontSize: widget.settings.fontSize,
      font: widget.settings.font,
      translationStyleId: widget.translationStyleId,
      onImageTap: (url) => widget.onImageClick?.call(url),
    );
  }

  Widget _buildItem(NativeReaderStyle style, int index) {
    final cells = _cellsOf(index);
    return _SegmentItem(
      key: ValueKey<int>(index),
      host: this,
      index: index,
      segment: _segments[index],
      cells: cells,
      marks: [
        for (final cell in cells) _marks[cell.key] ?? const <ReaderMark>[],
      ],
      style: style,
      columns: widget.bilingualColumns,
      // 对应 reader.css：桌面正文限宽居中，并排双语时铺满。
      maxWidth: !isDesktopOs || (widget.bilingualColumns && _hasBilingual)
          ? double.infinity
          : style.fontSize * 44 + 40,
      flashing: index == _flashSegment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _resolveStyle();
    final count = _segments.length;
    final anchor = _anchor;
    return MediaQuery.withNoTextScaling(
      child: DefaultSelectionStyle(
        selectionColor: _selectionColor,
        child: DefaultTextStyle.merge(
          style: style.body,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerEnd,
                onPointerCancel: _onPointerEnd,
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.keyC, control: true):
                        _CopyIntent(),
                    SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                        _CopyIntent(),
                  },
                  child: Actions(
                    actions: {
                      _CopyIntent: CallbackAction<_CopyIntent>(
                        onInvoke: (_) => _copySelection(),
                      ),
                    },
                    child: SelectionArea(
                      key: _selectionKey,
                      // 操作栏由阅读页统一弹出。
                      contextMenuBuilder: null,
                      onSelectionChanged: _onSelectedContent,
                      child: _SelectionStatusListener(
                        onFinalized: _onSelectionFinalized,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: CustomScrollView(
                            controller: _scroll,
                            center: _centerKey,
                            slivers: [
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: widget.topInset + style.blockGap,
                                ),
                              ),
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) =>
                                      _buildItem(style, anchor - 1 - i),
                                  childCount: anchor,
                                ),
                              ),
                              SliverList(
                                key: _centerKey,
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) => _buildItem(style, anchor + i),
                                  childCount: count - anchor,
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: widget.bottomInset + style.blockGap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: widget.topInset,
                bottom: widget.bottomInset,
                right: 0,
                child: NativeReaderScrollbar(
                  metrics: _metrics,
                  onJumpTo: _jumpToRatio,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

/// 在选区收尾（松开鼠标、手柄拖动结束、双击选词等）时回调。
class _SelectionStatusListener extends StatefulWidget {
  const _SelectionStatusListener({
    required this.onFinalized,
    required this.child,
  });

  final VoidCallback onFinalized;
  final Widget child;

  @override
  State<_SelectionStatusListener> createState() =>
      _SelectionStatusListenerState();
}

class _SelectionStatusListenerState extends State<_SelectionStatusListener> {
  ValueListenable<SelectableRegionSelectionStatus>? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final status = SelectableRegionSelectionStatusScope.maybeOf(context);
    if (identical(status, _status)) return;
    _status?.removeListener(_onStatus);
    _status = status?..addListener(_onStatus);
  }

  @override
  void dispose() {
    _status?.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    if (_status?.value == SelectableRegionSelectionStatus.finalized) {
      widget.onFinalized();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─── 列表项 ───

class _SegmentItem extends StatefulWidget {
  const _SegmentItem({
    super.key,
    required this.host,
    required this.index,
    required this.segment,
    required this.cells,
    required this.marks,
    required this.style,
    required this.columns,
    required this.maxWidth,
    required this.flashing,
  });

  final NativeMarkdownReaderState host;
  final int index;
  final NativeReaderSegment segment;
  final List<NativeReaderCell> cells;

  /// 与 [cells] 一一对应。
  final List<List<ReaderMark>> marks;
  final NativeReaderStyle style;
  final bool columns;
  final double maxWidth;
  final bool flashing;

  @override
  State<_SegmentItem> createState() => _SegmentItemState();
}

class _SegmentItemState extends State<_SegmentItem> {
  @override
  void initState() {
    super.initState();
    widget.host._items[widget.index] = this;
  }

  @override
  void dispose() {
    // 换原点时同一项可能先在另一侧列表挂载，别把新登记的删掉。
    final items = widget.host._items;
    if (identical(items[widget.index], this)) items.remove(widget.index);
    super.dispose();
  }

  Widget _cell(int i) => _CellView(
    key: ValueKey(widget.cells[i].kind),
    cell: widget.cells[i],
    marks: widget.marks[i],
    style: widget.style,
    host: widget.host,
  );

  Widget _cellsLayout() {
    final cells = widget.cells;
    // 桌面并排双语：同一段落一行，长的一侧撑开行高。
    if (widget.columns && cells.length == 2 && cells[1].translatedStyle) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cell(0)),
          SizedBox(width: widget.style.fontSize * 3),
          Expanded(child: _cell(1)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < cells.length; i++) _cell(i)],
    );
  }

  Widget _table(String html) {
    final style = widget.style;
    final divider = style.palette.divider.toARGB32() & 0xffffff;
    final border = '0.5px solid #${divider.toRadixString(16).padLeft(6, '0')}';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: style.blockGap / 2),
      child: HtmlWidget(
        html,
        key: ObjectKey(style),
        textStyle: style.body,
        customStylesBuilder: (element) => switch (element.localName) {
          'table' => const {'border-collapse': 'collapse', 'width': '100%'},
          'td' || 'th' => {'border': border, 'padding': '8px 12px'},
          _ => null,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final segment = widget.segment;
    var top = 0.0;
    Widget content;
    switch (segment) {
      case NativeFigureSegment(:final url):
        content = Padding(
          padding: EdgeInsets.symmetric(vertical: style.blockGap / 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _FigureImage(url: url, onTap: style.onImageTap),
              if (widget.cells.isNotEmpty) _cellsLayout(),
            ],
          ),
        );
      case NativeBlockSegment(isTable: true, :final markdown):
        content = _table(markdown);
      case NativePairSegment(:final markdown) ||
          NativeBlockSegment(:final markdown):
        // 标题上方的额外留白，对应 reader.css 的 h1–h3 margin-top。
        top =
            style.fontSize *
            switch (nativeHeadingLevel(markdown)) {
              1 => 0.4,
              2 => 0.3,
              3 => 0.2,
              _ => 0.0,
            };
        content = _cellsLayout();
    }
    if (widget.flashing) {
      content = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: style.palette.link, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: content,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, top, 20, 0),
          child: content,
        ),
      ),
    );
  }
}

class _FigureImage extends StatelessWidget {
  const _FigureImage({required this.url, required this.onTap});

  final String url;
  final void Function(String url) onTap;

  static Widget _broken(BuildContext _, Object _, StackTrace? _) =>
      const Icon(Symbols.broken_image_rounded, size: 48);

  @override
  Widget build(BuildContext context) {
    String? path;
    if (url.startsWith('file://')) {
      try {
        path = Uri.parse(url).toFilePath();
      } catch (_) {
        path = '';
      }
    } else if (url.startsWith('/')) {
      path = url;
    }
    final image = path == null
        ? Image.network(url, fit: BoxFit.contain, errorBuilder: _broken)
        : Image.file(File(path), fit: BoxFit.contain, errorBuilder: _broken);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onTap(url),
            child: ConstrainedBox(
              // 与 reader.css 的图片高度上限一致。
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    (isDesktopOs ? 0.7 : 0.33),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: image,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个语言单元：缓存 Markdown 生成的组件，并向其中的文字提供定位上下文。
class _CellView extends StatefulWidget {
  const _CellView({
    super.key,
    required this.cell,
    required this.marks,
    required this.style,
    required this.host,
  });

  final NativeReaderCell cell;
  final List<ReaderMark> marks;
  final NativeReaderStyle style;
  final NativeMarkdownReaderState host;

  @override
  State<_CellView> createState() => _CellViewState();
}

class _CellViewState extends State<_CellView> {
  NativeReaderCell? _cell;
  NativeReaderStyle? _style;
  List<Widget> _blocks = const [];
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final style = widget.style;
    if (!identical(cell, _cell) || !identical(style, _style)) {
      _cell = cell;
      _style = style;
      _blocks = style.generator.buildWidgets(
        cell.markdown,
        config: style.config(
          caption: cell.caption,
          translated: cell.translatedStyle,
        ),
      );
    }
    Widget child = NativeCellScope(
      cell: cell,
      marks: widget.marks,
      host: widget.host,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _blocks,
      ),
    );
    if (cell.translatedStyle) {
      switch (style.translationStyleId) {
        case 'quote':
          child = DecoratedBox(
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: style.palette.secondaryText, width: 3),
              ),
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: style.fontSize * 0.8),
              child: child,
            ),
          );
        case 'blur':
          child = GestureDetector(
            onTap: () => setState(() => _revealed = !_revealed),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              enabled: !_revealed,
              child: child,
            ),
          );
      }
    }
    if (isDesktopOs && cell.kind != NativeCellKind.block) {
      child = Listener(
        onPointerDown: (_) => widget.host._lockSelection(cell.kind),
        child: child,
      );
    }
    return child;
  }
}
