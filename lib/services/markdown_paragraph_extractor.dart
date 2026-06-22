/// 从 markdown 文档中抽出可翻译段落。
///
/// 跳过规则（这些内容不翻译）：
/// - 围栏代码块  ``` ... ```
/// - 数学公式块  $$ ... $$
/// - 图片独占段  `![alt](url)`
/// - 表格        含 `|---|` 分隔行
///
/// 可选跳过区域由 [ignoreSections] 控制，参见 [translation_skip_sections.dart]。
///
/// 其余段落按首字符归类为 [ParagraphKind]。段落彼此独立——上下文关联
/// 交给 LLM 在批内看到同批次其他段（`%%%%` 分隔）时自行处理。
library;

import 'translation_skip_sections.dart';

enum ParagraphKind {
  /// 普通文本段
  text,

  /// ATX 标题（# ~ ######）
  heading,

  /// 有序 / 无序列表
  list,

  /// blockquote
  blockquote,
}

class TranslatableParagraph {
  /// 在源 markdown 中的字符偏移（已剥离前后空白）
  final int offset;

  /// 段落字符长度（对应 [text] 在源中的长度——不包含前后空白）
  final int length;

  /// 段落原文（trim 后）
  final String text;

  /// 缓存 / 去重用的稳定 hash
  final String hash;

  final ParagraphKind kind;

  const TranslatableParagraph({
    required this.offset,
    required this.length,
    required this.text,
    required this.hash,
    required this.kind,
  });
}

class MarkdownParagraphExtractor {
  MarkdownParagraphExtractor._();

  /// [ignoreSections] 中的区域 ID 会被整段跳过；
  /// 未列入的已知区域则合并为单个段落送入翻译。
  static List<TranslatableParagraph> extract(
    String markdown, {
    List<String> ignoreSections = const [],
  }) {
    final skipRanges = _collectSkipRanges(markdown);

    // ── 可跳过区域检测 ──
    final detected = detectSkipSections(markdown);
    final mergedParagraphs = <TranslatableParagraph>[];
    for (final section in detected) {
      skipRanges.add(_Range(section.contentStart, section.contentEnd));
      if (!ignoreSections.contains(section.id)) {
        final text =
            markdown.substring(section.contentStart, section.contentEnd);
        mergedParagraphs.add(TranslatableParagraph(
          offset: section.contentStart,
          length: section.contentEnd - section.contentStart,
          text: text,
          hash: computeHash(text),
          kind: ParagraphKind.text,
        ));
      }
    }

    final paragraphs = <TranslatableParagraph>[];

    final separator = RegExp(r'\n[ \t]*\n');
    int cursor = 0;
    for (final match in separator.allMatches(markdown)) {
      _maybeAdd(markdown, cursor, match.start, skipRanges, paragraphs);
      cursor = match.end;
    }
    _maybeAdd(markdown, cursor, markdown.length, skipRanges, paragraphs);

    paragraphs.addAll(mergedParagraphs);
    return paragraphs;
  }

  /// 预扫描代码块与公式块，返回它们在源 md 中的 [start, end) 区间。
  /// 段落若与任何 skip 区间相交即整段跳过。
  static List<_Range> _collectSkipRanges(String md) {
    final ranges = <_Range>[];

    final code = RegExp(r'^[ \t]*(```|~~~).*?\n[\s\S]*?\n[ \t]*\1\s*$',
        multiLine: true);
    for (final m in code.allMatches(md)) {
      ranges.add(_Range(m.start, m.end));
    }

    final math = RegExp(r'\$\$[\s\S]*?\$\$');
    for (final m in math.allMatches(md)) {
      ranges.add(_Range(m.start, m.end));
    }

    return ranges;
  }

  static void _maybeAdd(
    String md,
    int start,
    int end,
    List<_Range> skipRanges,
    List<TranslatableParagraph> out,
  ) {
    if (start >= end) return;

    for (final r in skipRanges) {
      if (start < r.end && end > r.start) return;
    }

    int tStart = start;
    while (tStart < end && _isBlank(md.codeUnitAt(tStart))) {
      tStart++;
    }
    int tEnd = end;
    while (tEnd > tStart && _isBlank(md.codeUnitAt(tEnd - 1))) {
      tEnd--;
    }
    if (tStart >= tEnd) return;

    final text = md.substring(tStart, tEnd);

    if (_imageOnlyPattern.hasMatch(text)) return;
    if (_tablePattern.hasMatch(text)) return;

    out.add(TranslatableParagraph(
      offset: tStart,
      length: tEnd - tStart,
      text: text,
      hash: computeHash(text),
      kind: _classify(text),
    ));
  }

  static ParagraphKind _classify(String text) {
    if (_headingPattern.hasMatch(text)) return ParagraphKind.heading;
    if (_blockquotePattern.hasMatch(text)) return ParagraphKind.blockquote;
    if (_listPattern.hasMatch(text)) return ParagraphKind.list;
    return ParagraphKind.text;
  }

  /// 缓存 / 去重用的稳定 hash——供 figure title 等外部来源复用同一键。
  static String computeHash(String text) {
    final trimmed = text.trim();
    final h = trimmed.hashCode.toUnsigned(32).toRadixString(16);
    return '${trimmed.length}_$h';
  }

  static bool _isBlank(int cu) =>
      cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;

  static final _imageOnlyPattern =
      RegExp(r'^!\[[^\]]*\]\([^)]*\)[ \t]*$');
  static final _tablePattern =
      RegExp(r'^\s*\|[- :|]+\|\s*$', multiLine: true);
  static final _headingPattern = RegExp(r'^#{1,6}\s');
  static final _blockquotePattern = RegExp(r'^>\s');
  static final _listPattern = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s');
}

class _Range {
  final int start;
  final int end;
  const _Range(this.start, this.end);
}
