import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;

import '../../../../data/models/book/reader_anchor.dart';
import '../../../../services/reader/reader_document_index.dart'
    show readerPlainText;

// ─── 列表项 ───

/// 原生阅读器的一个列表项。[sourceOffset] 是原始 Markdown（未插入段落标记）
/// 中的偏移，供大纲跳转定位。
sealed class NativeReaderSegment {
  NativeReaderSegment(this.sourceOffset);
  final int sourceOffset;
}

/// 带段落身份的正文，原文与译文成对显示。
class NativePairSegment extends NativeReaderSegment {
  NativePairSegment(super.sourceOffset, this.id, this.markdown);
  final String id;
  final String markdown;
}

/// 独占一段的图片及其题注。
class NativeFigureSegment extends NativeReaderSegment {
  NativeFigureSegment(
    super.sourceOffset, {
    required this.url,
    required this.caption,
    this.figureId,
  });
  final String url;
  final String caption;
  final String? figureId;

  /// 与 `readerEntries` 里题注条目的 `source` 同一口径，用于配对。
  late final String captionText = readerPlainText(caption);

  late final String fileName = () {
    try {
      final segments = Uri.parse(url).pathSegments;
      return segments.isEmpty ? '' : segments.last;
    } catch (_) {
      return url.split(RegExp(r'[/\\]')).last.split('?').first;
    }
  }();
}

/// 其余内容：未进入段落索引的标题、公式块、表格、代码等。
class NativeBlockSegment extends NativeReaderSegment {
  NativeBlockSegment(super.sourceOffset, this.markdown, {this.figureId});
  final String markdown;
  final String? figureId;

  late final bool isTable = _tableStart.hasMatch(markdown);
}

final _tableStart = RegExp(r'^<table[\s>]', caseSensitive: false);
final _headingStart = RegExp(r'^(#{1,6})\s');

/// ATX 标题级别；非标题返回 0。
int nativeHeadingLevel(String markdown) =>
    _headingStart.firstMatch(markdown)?[1]?.length ?? 0;

final _pairPattern = RegExp(
  r'\n\n<!-- reader-pair:([A-Za-z0-9_=-]+) -->\n\n([\s\S]*?)\n\n<!-- reader-end -->\n\n',
);
final _commentPattern = RegExp(r'^<!--([\s\S]*?)-->');
final _figureMarker = RegExp(r'^\s*otter-figure:([a-zA-Z0-9_-]+)\s*$');
final _imagePattern = RegExp(r'^!\[([^\]]*)\]\(([^)\s]+)\)$');

/// 把 `markReaderParagraphs` 产出的带标记 Markdown 拆成列表项。
List<NativeReaderSegment> parseNativeReaderSegments(String marked) {
  final segments = <NativeReaderSegment>[];
  var cursor = 0;
  var source = 0;
  String? figureId;

  void addGap(String gap) {
    for (final block in _splitBlocks(gap)) {
      var text = block.text.trim();
      // 定位标记只用来认图，不进入正文。
      for (
        var comment = _commentPattern.firstMatch(text);
        comment != null;
        comment = _commentPattern.firstMatch(text)
      ) {
        figureId = _figureMarker.firstMatch(comment[1]!)?[1] ?? figureId;
        text = text.substring(comment.end).trim();
      }
      if (text.isEmpty) continue;
      final offset = source + block.offset;
      final image = _imagePattern.firstMatch(text);
      if (image != null) {
        final alt = image[1]!;
        segments.add(
          NativeFigureSegment(
            offset,
            url: image[2]!,
            caption: alt.startsWith('fig:') ? alt.substring(4) : '',
            figureId: figureId,
          ),
        );
      } else {
        segments.add(NativeBlockSegment(offset, text, figureId: figureId));
      }
      figureId = null;
    }
  }

  for (final match in _pairPattern.allMatches(marked)) {
    final gap = marked.substring(cursor, match.start);
    addGap(gap);
    source += gap.length;
    final body = match[2]!;
    String? id;
    try {
      id = utf8.decode(base64Url.decode(match[1]!));
    } catch (_) {
      id = null;
    }
    segments.add(
      id == null
          ? NativeBlockSegment(source, body)
          : NativePairSegment(source, id, body),
    );
    source += body.length;
    cursor = match.end;
    figureId = null;
  }
  addGap(marked.substring(cursor));
  return segments;
}

/// 按空行切块；代码围栏、`$$`/`\[` 公式块和 HTML 表格内部的空行不切。
Iterable<({String text, int offset})> _splitBlocks(String source) sync* {
  var start = -1;
  var end = 0;
  var fence = false;
  var dollarMath = false;
  var bracketMath = false;
  var table = 0;
  var position = 0;
  while (position <= source.length) {
    var newline = source.indexOf('\n', position);
    if (newline < 0) newline = source.length;
    final line = source.substring(position, newline).trim();
    final open = fence || dollarMath || bracketMath || table > 0;
    if (line.isEmpty && !open) {
      if (start >= 0) {
        yield (text: source.substring(start, end), offset: start);
        start = -1;
      }
    } else {
      if (start < 0) start = position;
      end = newline;
      if (!dollarMath &&
          !bracketMath &&
          (line.startsWith('```') || line.startsWith('~~~'))) {
        fence = !fence;
      } else if (!fence) {
        if (r'$$'.allMatches(line).length.isOdd) dollarMath = !dollarMath;
        if (bracketMath) {
          if (line.contains(r'\]')) bracketMath = false;
        } else if (line.startsWith(r'\[') && !line.contains(r'\]')) {
          bracketMath = true;
        }
        final lower = line.toLowerCase();
        table = math.max(
          0,
          table +
              '<table'.allMatches(lower).length -
              '</table>'.allMatches(lower).length,
        );
      }
    }
    if (newline >= source.length) break;
    position = newline + 1;
  }
  if (start >= 0) yield (text: source.substring(start, end), offset: start);
}

// ─── 文字对齐 ───

/// 去掉空白、`$` 和 `\( \) \[ \]` 后的文字，附带到原文的偏移表。
///
/// 口径与 `assets/reader/reader_anchors.js` 的 `compact` 一致：显示文字与
/// 段落纯文本只在这些字符上有出入，两边各算一份后逐字对应。
class CompactText {
  CompactText._(this.text, this.offsets);

  factory CompactText(String source) {
    final buffer = StringBuffer();
    final offsets = <int>[];
    for (var i = 0; i < source.length; i++) {
      final unit = source.codeUnitAt(i);
      if (unit == 0x5C &&
          i + 1 < source.length &&
          _isMathBracket(source.codeUnitAt(i + 1))) {
        i++;
        continue;
      }
      if (unit == 0x24 || unit == 0xFFFC || _isWhitespace(unit)) continue;
      buffer.writeCharCode(unit);
      offsets.add(i);
    }
    return CompactText._(buffer.toString(), offsets);
  }

  final String text;

  /// 第 k 个保留字符在原文中的偏移。
  final List<int> offsets;

  int get length => offsets.length;

  /// 原文 [offset] 之前保留了多少个字符。
  int indexOf(int offset) {
    var low = 0;
    var high = offsets.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (offsets[middle] < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// 保留字符区间 → 原文区间；区间为空或越界返回 null。
  ({int start, int end})? range(int start, int end) =>
      start < 0 || end > offsets.length || start >= end
      ? null
      : (start: offsets[start], end: offsets[end - 1] + 1);

  /// [part] 在本文字中唯一出现的位置；没有或有歧义返回 -1。
  int locate(CompactText part) {
    if (part.text.isEmpty) return -1;
    final at = text.indexOf(part.text);
    if (at < 0 || text.indexOf(part.text, at + 1) >= 0) return -1;
    return at;
  }
}

bool _isMathBracket(int unit) =>
    unit == 0x28 || unit == 0x29 || unit == 0x5B || unit == 0x5D;

// 与 JS `\s` 同集合。
bool _isWhitespace(int unit) =>
    unit == 0x20 ||
    (unit >= 0x09 && unit <= 0x0D) ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

// ─── 语言单元 ───

enum NativeCellKind { source, target, block }

/// 一个段落的一种语言。锚点、高亮和搜索都以 [text] 的 UTF-16 偏移为坐标。
class NativeReaderCell {
  NativeReaderCell({
    required this.segment,
    required this.key,
    required this.kind,
    required this.markdown,
    String? text,
    this.paragraphId = '',
    this.language = '',
    this.revision = '',
    this.caption = false,
    this.translatedStyle = false,
  }) : _text = text;

  NativeReaderCell.block(this.segment, this.markdown, {this.caption = false})
    : key = 'block:$segment',
      kind = NativeCellKind.block,
      paragraphId = '',
      language = '',
      revision = '',
      translatedStyle = false,
      _text = null;

  final int segment;
  final String key;
  final NativeCellKind kind;
  final String markdown;
  final String paragraphId;
  final String language;
  final String revision;
  final bool caption;

  /// 双语对照时译文套用「译文样式」。
  final bool translatedStyle;

  final String? _text;
  late final String text = _text ?? readerPlainText(markdown);
  late final CompactText compact = CompactText(text);

  bool get anchored => kind != NativeCellKind.block;
}

bool _showsTarget(Map<String, dynamic> entry) =>
    (entry['translated'] as String? ?? '').isNotEmpty &&
    entry['showTranslation'] != false;

/// 按 `readerEntries` 一项当前的显示状态生成语言单元。
List<NativeReaderCell> nativeEntryCells(
  int segment,
  Map<String, dynamic> entry, {
  required String sourceMarkdown,
  required String translatedMarkdown,
}) {
  final id = entry['id'] as String;
  final caption = entry['caption'] == true;
  final target = _showsTarget(entry);
  final translated = entry['translated'] as String? ?? '';
  return [
    if (!(entry['showSource'] == false && target))
      NativeReaderCell(
        segment: segment,
        key: '$id/source',
        kind: NativeCellKind.source,
        markdown: sourceMarkdown,
        text: entry['source'] as String? ?? '',
        paragraphId: id,
        language: 'source',
        revision: entry['sourceRevision'] as String? ?? '',
        caption: caption,
      ),
    if (target)
      NativeReaderCell(
        segment: segment,
        key: '$id/target',
        kind: NativeCellKind.target,
        markdown: translatedMarkdown.isEmpty ? translated : translatedMarkdown,
        text: translated,
        paragraphId: id,
        language: entry['language'] as String? ?? 'translated',
        revision: entry['translatedRevision'] as String? ?? '',
        caption: caption,
        translatedStyle: entry['bilingual'] == true,
      ),
  ];
}

ReaderAnchorRange nativeAnchorRange(NativeReaderCell cell, int start, int end) {
  final text = cell.text;
  return ReaderAnchorRange(
    paragraphId: cell.paragraphId,
    language: cell.language,
    revision: cell.revision,
    start: start,
    end: end,
    quote: text.substring(start, end),
    prefix: text.substring(math.max(0, start - 32), start),
    suffix: text.substring(end, math.min(text.length, end + 32)),
  );
}

// ─── 着色标记 ───

/// 语言单元内需要加底色的一段（[NativeReaderCell.text] 坐标）。
class ReaderMark {
  const ReaderMark(this.start, this.end, this.color, {this.highlightId});
  final int start;
  final int end;
  final Color color;

  /// 非空表示用户标注，点击可唤起标注工具栏。
  final String? highlightId;

  @override
  bool operator ==(Object other) =>
      other is ReaderMark &&
      start == other.start &&
      end == other.end &&
      color == other.color &&
      highlightId == other.highlightId;

  @override
  int get hashCode => Object.hash(start, end, color, highlightId);
}

// ─── 搜索 ───

typedef NativeSearchMatch = ({
  int segment,
  String cellKey,
  int start,
  int end,
  String heading,
  String snippet,
  int matchStart,
});

final _inlineMath = RegExp(r'\$[^$\n]+\$');

/// 在按文档顺序给出的语言单元里查找 [query]，公式源码内的命中不计。
List<NativeSearchMatch> nativeSearch(
  Iterable<({NativeReaderCell cell, bool heading})> cells,
  String query, {
  bool caseSensitive = false,
  bool wholeWord = false,
}) {
  var pattern = RegExp.escape(query);
  if (wholeWord) pattern = '(?<![A-Za-z0-9])$pattern(?![A-Za-z0-9])';
  final regex = RegExp(pattern, caseSensitive: caseSensitive, unicode: true);
  final matches = <NativeSearchMatch>[];
  var heading = '';
  for (final (:cell, heading: isHeading) in cells) {
    final text = cell.text;
    final formulas = _inlineMath.allMatches(text).toList();
    for (final match in regex.allMatches(text)) {
      if (match.end == match.start ||
          formulas.any((f) => f.start < match.end && match.start < f.end)) {
        continue;
      }
      final from = math.max(0, match.start - 60);
      matches.add((
        segment: cell.segment,
        cellKey: cell.key,
        start: match.start,
        end: match.end,
        heading: heading,
        snippet: text.substring(from, math.min(text.length, match.end + 160)),
        matchStart: match.start - from,
      ));
    }
    if (isHeading) heading = text;
  }
  return matches;
}
