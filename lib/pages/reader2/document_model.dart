// 对齐 rust/src/document 的 DocumentModel（serde JSON）。FRB 接入后由生成类型替换本文件。

enum BlockKind {
  heading,
  paragraph,
  list,
  quote,
  figure,
  table,
  equation,
  code,
}

class InlineRun {
  const InlineRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.strike = false,
    this.link,
    this.math,
  });

  /// 计入块 `text` 的原文；公式 run 含 `$` 定界符，UTF-16 偏移按它计算。
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strike;
  final String? link;
  final String? math;

  factory InlineRun.fromJson(Map<String, dynamic> json) => InlineRun(
    text: json['text'] as String,
    bold: json['bold'] as bool,
    italic: json['italic'] as bool,
    code: json['code'] as bool,
    strike: json['strike'] as bool,
    link: json['link'] as String?,
    math: json['math'] as String?,
  );
}

class TextRegion {
  const TextRegion({
    required this.pageIndex,
    required this.bbox,
    required this.sourceLength,
  });

  final int pageIndex;
  final List<double> bbox;
  final int sourceLength;

  factory TextRegion.fromJson(Map<String, dynamic> json) => TextRegion(
    pageIndex: json['page_index'] as int,
    bbox: [for (final v in json['bbox'] as List) (v as num).toDouble()],
    sourceLength: json['source_length'] as int,
  );
}

class TableCell {
  const TableCell({
    required this.text,
    required this.rowSpan,
    required this.colSpan,
    required this.header,
  });

  final String text;
  final int rowSpan;
  final int colSpan;
  final bool header;

  factory TableCell.fromJson(Map<String, dynamic> json) => TableCell(
    text: json['text'] as String,
    rowSpan: json['row_span'] as int,
    colSpan: json['col_span'] as int,
    header: json['header'] as bool,
  );
}

class Block {
  const Block({
    required this.id,
    required this.kind,
    required this.text,
    required this.runs,
    this.headingLevel,
    this.sourceBlockId,
    this.pageIndex,
    this.sourceRegions = const [],
    this.markdown = '',
    this.revision = '',
    this.image,
    this.ownerId,
    this.table,
  });

  final String id;
  final BlockKind kind;
  final int? headingLevel;
  final String? sourceBlockId;
  final int? pageIndex;
  final List<TextRegion> sourceRegions;
  final String markdown;

  /// 锚点、选区、搜索的 UTF-16 偏移基准，等于各 run `text` 依次拼接。
  final String text;
  final String revision;
  final List<InlineRun> runs;
  final String? image;

  /// 非空时本块是 [ownerId] 图表的组成部分（子图），不单独成段显示。
  final String? ownerId;
  final List<List<TableCell>>? table;

  factory Block.fromJson(Map<String, dynamic> json) => Block(
    id: json['id'] as String,
    kind: BlockKind.values.byName(json['kind'] as String),
    headingLevel: json['heading_level'] as int?,
    sourceBlockId: json['source_block_id'] as String?,
    pageIndex: json['page_index'] as int?,
    sourceRegions: [
      for (final r in json['source_regions'] as List)
        TextRegion.fromJson(r as Map<String, dynamic>),
    ],
    markdown: json['markdown'] as String,
    text: json['text'] as String,
    revision: json['revision'] as String,
    runs: [
      for (final r in json['runs'] as List)
        InlineRun.fromJson(r as Map<String, dynamic>),
    ],
    image: json['image'] as String?,
    ownerId: json['owner_id'] as String?,
    table: switch (json['table']) {
      null => null,
      final Map<String, dynamic> t => [
        for (final row in t['rows'] as List)
          [
            for (final c in row as List)
              TableCell.fromJson(c as Map<String, dynamic>),
          ],
      ],
      final other => throw FormatException('table: $other'),
    },
  );
}

class DocumentModel {
  const DocumentModel({required this.version, required this.blocks});

  final int version;
  final List<Block> blocks;

  factory DocumentModel.fromJson(Map<String, dynamic> json) => DocumentModel(
    version: json['version'] as int,
    blocks: [
      for (final b in json['blocks'] as List)
        Block.fromJson(b as Map<String, dynamic>),
    ],
  );
}

/// Rust `AnchorRange`：偏移是 [Block.text] 上的 UTF-16 下标，end 不含。
class AnchorRange {
  const AnchorRange({
    required this.blockId,
    required this.language,
    required this.revision,
    required this.start,
    required this.end,
    required this.quote,
    this.prefix = '',
    this.suffix = '',
  });

  final String blockId;
  final String language;
  final String revision;
  final int start;
  final int end;
  final String quote;
  final String prefix;
  final String suffix;
}
