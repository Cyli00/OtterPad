import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../../data/models/book/highlight.dart' show kDefaultHighlightColor;
import '../../providers/document_translation_provider.dart'
    show DocTranslationMode;
import '../../src/rust/api/document.dart';
import '../../src/rust/document.dart';
import '../../utils/uuid.dart';
import 'reader_layout.dart';

enum ReaderMode { scroll, paged }

/// 用户标注；一次跨块选择得到多段 [ranges]，作为一条标注整体增删。
@immutable
class ReaderHighlight {
  const ReaderHighlight({
    required this.id,
    required this.ranges,
    required this.createdAt,
    this.color = kDefaultHighlightColor,
    this.note,
  });

  final String id;
  final List<AnchorRange> ranges;

  /// 与 0.1.x `kHighlightColors` 相同的 6 位十六进制色值。
  final String color;
  final String? note;
  final DateTime createdAt;

  String get text => ranges.map((r) => r.quote).join('\n');

  ReaderHighlight copyWith({String? color, String? note}) => ReaderHighlight(
    id: id,
    ranges: ranges,
    createdAt: createdAt,
    color: color ?? this.color,
    note: note ?? this.note,
  );
}

@immutable
class SearchHit {
  const SearchHit(this.blockIndex, this.start, this.end);

  final int blockIndex;
  final int start;
  final int end;
}

/// 阅读器 UI 状态：模式、阅读位置、选区、标注、搜索。
///
/// 位置一律用 [ReaderLocation]（块序号 + [Block.text] 偏移），与排版无关；
/// 换模式、改字号或窗口尺寸后由视图按新排版换算回滚动偏移或页码。
class ReaderController extends ChangeNotifier {
  ReaderController(
    this.source, {
    List<ReaderHighlight> highlights = const [],
    this.onHighlightSaved,
    this.onHighlightRemoved,
  }) : _highlights = [...highlights],
       _model = source {
    _reindex();
  }

  /// Rust 的文档模型；[model] 是叠加译文后的展示模型。
  final ReaderDocument source;
  ReaderDocument _model;
  ReaderDocument get model => _model;

  /// 标注新增或修改、删除后调用，由页面写入 Rust。
  final void Function(ReaderHighlight)? onHighlightSaved;
  final void Function(String id)? onHighlightRemoved;

  // ── 译文 ──

  Map<String, String> _translations = const {};
  DocTranslationMode _translationMode = DocTranslationMode.off;
  String _language = '';
  bool _rtl = false;
  bool get rtlTranslations => _rtl;

  /// 按译文键叠加译文：双语时插在原文块之后，只看译文时替换原文块。
  /// 译文块 id 为原文块 id 加 `#t`，阅读位置按块 id 保持。
  void setTranslations(
    Map<String, String> translations,
    DocTranslationMode mode,
    String language, {
    bool rtl = false,
  }) {
    if (identical(translations, _translations) &&
        mode == _translationMode &&
        language == _language &&
        rtl == _rtl) {
      return;
    }
    final anchorId = _model.blocks.isEmpty
        ? null
        : _model
              .blocks[location.blockIndex.clamp(0, _model.blocks.length - 1)]
              .id;
    _translations = translations;
    _translationMode = mode;
    _language = language;
    _rtl = rtl;
    _model = _display();
    _base = null;
    _extent = null;
    _reindex();
    if (anchorId != null) {
      final base = anchorId.endsWith('#t')
          ? anchorId.substring(0, anchorId.length - 2)
          : anchorId;
      final index =
          _blockIndexById[anchorId] ??
          _blockIndexById[base] ??
          _blockIndexById['$base#t'];
      location = ReaderLocation(index ?? 0, 0);
    }
    if (_query.isNotEmpty) {
      search(_query);
    } else {
      notifyListeners();
    }
  }

  ReaderDocument _display() {
    if (_translationMode == DocTranslationMode.off || _translations.isEmpty) {
      return source;
    }
    final keys = source.translationKeys;
    final blocks = <Block>[];
    for (var i = 0; i < source.blocks.length; i++) {
      final block = source.blocks[i];
      final key = i < keys.length ? keys[i] : '';
      final text = key.isEmpty ? null : _translations[key];
      if (text == null || text.trim().isEmpty) {
        blocks.add(block);
        continue;
      }
      final translated = translatedBlock(source: block, markdown: text);
      if (_translationMode == DocTranslationMode.bilingual) blocks.add(block);
      blocks.add(translated);
    }
    return ReaderDocument(
      version: source.version,
      blocks: blocks,
      translationKeys: const [],
      figures: source.figures,
      figureAssets: source.figureAssets,
      figureImages: source.figureImages,
      assetDirectory: source.assetDirectory,
      references: source.references,
      blockRegions: const [],
    );
  }

  /// 展示块对应的原文块 id 与锚点语言。
  (String, String) _anchorTarget(Block block) => block.id.endsWith('#t')
      ? (block.id.substring(0, block.id.length - 2), _language)
      : (block.id, 'source');

  ReaderMode _mode = ReaderMode.scroll;
  ReaderMode get mode => _mode;
  set mode(ReaderMode value) {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
  }

  /// 视图滚动或翻页时持续更新，不通知监听者，避免每帧重建。
  ReaderLocation location = const ReaderLocation(0, 0);

  // ── 选区 ──

  ReaderLocation? _base;
  ReaderLocation? _extent;

  bool get hasSelection => _base != null && _extent != null && _base != _extent;

  (ReaderLocation, ReaderLocation)? get selection {
    if (!hasSelection) return null;
    final a = _base!;
    final b = _extent!;
    final forward =
        a.blockIndex < b.blockIndex ||
        (a.blockIndex == b.blockIndex && a.offset <= b.offset);
    return forward ? (a, b) : (b, a);
  }

  void select(ReaderLocation base, ReaderLocation extent) {
    if (base == _base && extent == _extent) return;
    _base = base;
    _extent = extent;
    notifyListeners();
  }

  void extendSelection(ReaderLocation extent) {
    if (_base == null || extent == _extent) return;
    _extent = extent;
    notifyListeners();
  }

  void clearSelection() {
    if (_base == null && _extent == null) return;
    _base = null;
    _extent = null;
    notifyListeners();
  }

  /// 选区在各块上的 `[start, end)`；空块、只有图片的块不产生区间。
  List<(int, int, int)> get selectedRanges {
    final range = selection;
    if (range == null) return const [];
    final (a, b) = range;
    return [
      for (var i = a.blockIndex; i <= b.blockIndex; i++)
        if (_rangeIn(i, a, b) case final r?) (i, r.$1, r.$2),
    ];
  }

  (int, int)? _rangeIn(int blockIndex, ReaderLocation a, ReaderLocation b) {
    final block = model.blocks[blockIndex];
    if (block.ownerId != null) return null;
    final start = blockIndex == a.blockIndex ? a.offset : 0;
    final end = blockIndex == b.blockIndex ? b.offset : block.text.length;
    return end > start ? (start, end) : null;
  }

  String get selectedText => [
    for (final (i, s, e) in selectedRanges)
      model.blocks[i].text.substring(s, e),
  ].join('\n\n');

  // ── 标注 ──

  final List<ReaderHighlight> _highlights;
  List<ReaderHighlight> get highlights => List.unmodifiable(_highlights);

  /// 每块上的标注区间，按创建顺序；绘制时后者覆盖前者。
  final _highlightMarks = <int, List<(int, int, ReaderHighlight)>>{};
  final _blockIndexById = <String, int>{};

  void _reindex() {
    _blockIndexById
      ..clear()
      ..addAll({
        for (var i = 0; i < model.blocks.length; i++) model.blocks[i].id: i,
      });
    _highlightMarks.clear();
    for (final h in _highlights) {
      for (final r in h.ranges) {
        final id = r.language == 'source' ? r.blockId : '${r.blockId}#t';
        if (r.language != 'source' && r.language != _language) continue;
        final index = _blockIndexById[id];
        if (index == null) continue;
        _highlightMarks.putIfAbsent(index, () => []).add((
          r.start.toInt(),
          r.end.toInt(),
          h,
        ));
      }
    }
  }

  /// 以当前选区创建标注并清除选区；与 Rust `DocumentModel::anchor` 同规则生成锚点。
  ReaderHighlight? highlightSelection(String color) {
    final ranges = [
      for (final (i, s, e) in selectedRanges) _anchor(model.blocks[i], s, e),
    ];
    if (ranges.isEmpty) return null;
    final highlight = ReaderHighlight(
      id: generateUuid(),
      ranges: ranges,
      color: color,
      createdAt: DateTime.now(),
    );
    _highlights.add(highlight);
    _reindex();
    _base = null;
    _extent = null;
    notifyListeners();
    onHighlightSaved?.call(highlight);
    return highlight;
  }

  void updateHighlight(ReaderHighlight highlight) {
    final i = _highlights.indexWhere((h) => h.id == highlight.id);
    if (i < 0) return;
    _highlights[i] = highlight;
    _reindex();
    notifyListeners();
    onHighlightSaved?.call(highlight);
  }

  void removeHighlight(String id) {
    _highlights.removeWhere((h) => h.id == id);
    _reindex();
    notifyListeners();
    onHighlightRemoved?.call(id);
  }

  /// 用存储中的最新标注替换（不触发保存回调）。
  void replaceHighlights(List<ReaderHighlight> highlights) {
    _highlights
      ..clear()
      ..addAll(highlights);
    _reindex();
    notifyListeners();
  }

  /// 块 id（含译文块）对应的展示序号。
  int? indexOfBlock(String id) => _blockIndexById[id];

  ReaderHighlight? highlightAt(ReaderLocation location) {
    ReaderHighlight? hit;
    for (final (s, e, h)
        in _highlightMarks[location.blockIndex] ??
            const <(int, int, ReaderHighlight)>[]) {
      if (s <= location.offset && location.offset < e) hit = h;
    }
    return hit;
  }

  AnchorRange _anchor(Block block, int start, int end) {
    const context = 32;
    final text = block.text;
    final (blockId, language) = _anchorTarget(block);
    return AnchorRange(
      blockId: blockId,
      language: language,
      revision: block.revision,
      start: BigInt.from(start),
      end: BigInt.from(end),
      quote: text.substring(start, end),
      prefix: text.substring(start < context ? 0 : start - context, start),
      suffix: text.substring(
        end,
        end + context > text.length ? text.length : end + context,
      ),
    );
  }

  // ── 搜索 ──

  String _query = '';
  String get query => _query;
  List<SearchHit> _hits = const [];
  List<SearchHit> get hits => _hits;
  int _current = -1;
  int get currentHit => _current;

  /// 在块文本上做大小写不敏感的子串匹配；从当前阅读位置之后的第一个命中开始。
  void search(String query) {
    _query = query;
    final needle = query.trim().toLowerCase();
    final hits = <SearchHit>[];
    if (needle.isNotEmpty) {
      for (var i = 0; i < model.blocks.length; i++) {
        final block = model.blocks[i];
        if (block.ownerId != null) continue;
        final hay = block.text.toLowerCase();
        // toLowerCase 可能改变长度（如土耳其语 İ），此时不能复用偏移。
        if (hay.length != block.text.length) continue;
        for (
          var at = hay.indexOf(needle);
          at >= 0;
          at = hay.indexOf(needle, at + needle.length)
        ) {
          hits.add(SearchHit(i, at, at + needle.length));
        }
      }
    }
    _hits = hits;
    _current = hits.isEmpty
        ? -1
        : hits
              .indexWhere(
                (h) =>
                    h.blockIndex > location.blockIndex ||
                    (h.blockIndex == location.blockIndex &&
                        h.start >= location.offset),
              )
              .clamp(0, hits.length - 1);
    notifyListeners();
  }

  void stepHit(int delta) {
    if (_hits.isEmpty) return;
    _current = (_current + delta) % _hits.length;
    notifyListeners();
  }

  void clearSearch() {
    if (_query.isEmpty && _hits.isEmpty) return;
    _query = '';
    _hits = const [];
    _current = -1;
    notifyListeners();
  }

  SearchHit? get activeHit => _current < 0 ? null : _hits[_current];

  /// 块 [blockIndex] 的着色区间：标注 < 搜索命中 < 当前命中 < 选区。
  List<TextMark> marksFor(
    int blockIndex, {
    required Color Function(String hex) highlight,
    required Color hit,
    required Color activeHit,
    required Color selection,
  }) {
    final marks = <TextMark>[
      for (final (s, e, h)
          in _highlightMarks[blockIndex] ??
              const <(int, int, ReaderHighlight)>[])
        TextMark(s, e, highlight(h.color)),
    ];
    for (var i = 0; i < _hits.length; i++) {
      final h = _hits[i];
      if (h.blockIndex == blockIndex) {
        marks.add(TextMark(h.start, h.end, i == _current ? activeHit : hit));
      }
    }
    for (final (i, s, e) in selectedRanges) {
      if (i == blockIndex) marks.add(TextMark(s, e, selection));
    }
    return marks;
  }
}
