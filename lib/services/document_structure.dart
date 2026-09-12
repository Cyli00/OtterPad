import 'dart:convert';
import 'dart:io';

/// extract.json（PaddleOCR 版面解析产物）的**唯一防腐层**。
///
/// 持久化的结构模型形状：每页一个对象，块列表在
/// `prunedResult.parsing_res_list`，页级 markdown 在 `markdown.text`。
/// 根既可能是页数组，也可能是带 `layoutParsingResults` 的对象（API 原始
/// 响应形状）——两种都在此消化，调用方（figure 提取 / markdown 替换 /
/// AI 排版修复 / 未来的翻译保护 span）不再各自 jsonDecode 直挖。

class LayoutTextRegion {
  final int pageIndex;
  final List<double> bbox;
  final int sourceLength;
  const LayoutTextRegion(this.pageIndex, this.bbox, this.sourceLength);
  Map<String, dynamic> toJson() => {
    'page_index': pageIndex,
    'bbox': bbox,
    'source_length': sourceLength,
  };
  factory LayoutTextRegion.fromJson(Map<String, dynamic> json) =>
      LayoutTextRegion(
        json['page_index'] as int,
        (json['bbox'] as List).map((v) => (v as num).toDouble()).toList(),
        json['source_length'] as int,
      );
}

/// 版面解析 API 返回的单个 block。
class LayoutBlock {
  final String blockId;
  final String blockLabel;

  /// [left, top, right, bottom]，坐标基于 API zoom = 2.0（144 DPI）。
  /// 缺失或不完整时为空列表，调用方按 length 判断。
  final List<double> blockBbox;

  /// bbox 的 JSON 原始数值（int 保持 int）——markdown 行内的 bbox 编码
  /// 图片名按字面拼接（`12` ≠ `12.0`），探针匹配必须用原始类型。
  final List<num> rawBbox;

  final String blockContent;

  /// PaddleOCR 页内逻辑分组 ID，同组 block 属于同一逻辑实体（如复合图的子图）。
  final int? groupId;

  /// PaddleOCR 跨页全局分组 ID。
  final int? globalGroupId;

  /// PaddleOCR 推断的阅读顺序（页内），null 表示未提供。
  final int? blockOrder;

  /// Explicit provider hierarchy; unlike groupId, this is a body/caption owner.
  final String? parentId;
  final String? sourceImage;
  final String? captionKind;
  final List<LayoutTextRegion> textRegions;

  LayoutBlock({
    required this.blockId,
    required this.blockLabel,
    required this.blockBbox,
    List<num>? rawBbox,
    required this.blockContent,
    this.groupId,
    this.globalGroupId,
    this.blockOrder,
    this.parentId,
    this.sourceImage,
    this.captionKind,
    this.textRegions = const [],
  }) : rawBbox = rawBbox ?? blockBbox;

  factory LayoutBlock.fromJson(Map<String, dynamic> json) {
    final box = json['block_bbox'];
    final rawBbox =
        box is List &&
            box.length == 4 &&
            box.every((v) => v is num && v.isFinite) &&
            (box[2] as num) > (box[0] as num) &&
            (box[3] as num) > (box[1] as num)
        ? box.cast<num>()
        : const <num>[];
    return LayoutBlock(
      blockId: json['block_id']?.toString() ?? '',
      blockLabel: json['block_label'] as String? ?? '',
      blockBbox: [for (final v in rawBbox) v.toDouble()],
      rawBbox: List.unmodifiable(rawBbox),
      blockContent: json['block_content'] as String? ?? '',
      groupId: json['group_id'] as int?,
      globalGroupId: json['global_group_id'] as int?,
      blockOrder: json['block_order'] as int?,
      parentId: json['parent_id'] as String?,
      sourceImage: json['source_image'] as String?,
      captionKind: json['caption_kind'] as String?,
      textRegions: (json['text_regions'] as List? ?? [])
          .map(
            (r) =>
                LayoutTextRegion.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'block_id': blockId,
    'block_label': blockLabel,
    'block_bbox': rawBbox,
    'block_content': blockContent,
    if (groupId != null) 'group_id': groupId,
    if (globalGroupId != null) 'global_group_id': globalGroupId,
    if (blockOrder != null) 'block_order': blockOrder,
    if (parentId != null) 'parent_id': parentId,
    if (sourceImage != null) 'source_image': sourceImage,
    if (captionKind != null) 'caption_kind': captionKind,
    if (textRegions.isNotEmpty)
      'text_regions': textRegions.map((r) => r.toJson()).toList(),
  };
}

/// 结构模型中的一页：页号 + 块列表 + 该页的 raw markdown。
class StructurePage {
  final int pageIndex;
  final List<LayoutBlock> blocks;
  final String markdown;

  /// Width and height in the same 144 DPI space as blockBbox.
  final List<double>? pageSize;
  final Map<String, String> images;

  const StructurePage({
    required this.pageIndex,
    required this.blocks,
    required this.markdown,
    this.pageSize,
    this.images = const {},
  });
}

/// 一篇文献的版面结构模型（extract.json 的类型化视图）。
class DocumentStructure {
  final List<StructurePage> pages;

  const DocumentStructure(this.pages);

  static const empty = DocumentStructure([]);

  bool get isEmpty => pages.isEmpty;

  /// 解析 extract.json 内容。容忍两种根形状；解析失败返回 [empty]。
  static DocumentStructure parse(String jsonContent) {
    try {
      final decoded = jsonDecode(jsonContent);
      final List<dynamic> rawPages;
      if (decoded is Map<String, dynamic>) {
        if (decoded['pdf_info'] is List) {
          return fromMinerULayout(decoded);
        }
        rawPages = decoded['layoutParsingResults'] as List<dynamic>? ?? [];
      } else if (decoded is List<dynamic>) {
        rawPages = decoded;
      } else {
        return empty;
      }
      return DocumentStructure([
        for (var i = 0; i < rawPages.length; i++)
          _parsePage(rawPages[i] as Map<String, dynamic>, i),
      ]);
    } catch (_) {
      return empty;
    }
  }

  /// MinerU layout.json / middle.json: page points and nested body/caption
  /// blocks. Preserve explicit ownership instead of synthesizing caption boxes.
  static DocumentStructure fromMinerULayout(Map<String, dynamic> layout) {
    final pages = <StructurePage>[];
    for (final raw in (layout['pdf_info'] as List? ?? const [])) {
      if (raw is! Map<String, dynamic>) continue;
      final pi = (raw['page_idx'] as num?)?.toInt() ?? pages.length;
      final size = _bboxValues(raw['page_size'], 2);
      final blocks = <LayoutBlock>[];
      var order = 0;
      void append(Map<String, dynamic> block, String? parent, String? kind) {
        final type = block['type'] as String? ?? '';
        final box = _bboxValues(block['bbox'], 4);
        final text = <String>[];
        final regions = <LayoutTextRegion>[];
        String? source;
        for (final line in (block['lines'] as List? ?? const [])) {
          if (line is! Map) continue;
          final parts = <String>[];
          for (final span in (line['spans'] as List? ?? const [])) {
            if (span is! Map) continue;
            final value = span['content'];
            if (value is String && value.isNotEmpty) {
              parts.add(
                span['type'] == 'inline_equation' && !value.startsWith(r'$')
                    ? '\$$value\$'
                    : value,
              );
            }
            final html = span['html'];
            if (html is String && html.isNotEmpty) parts.add(html);
            source ??= span['image_path'] as String?;
          }
          if (parts.isNotEmpty) {
            final lineText = parts.join(' ');
            text.add(lineText);
            final lineBox = _bboxValues(line['bbox'], 4);
            if (size != null && lineBox != null) {
              final crossPage = (line['spans'] as List? ?? []).any(
                (s) => s is Map && s['cross_page'] == true,
              );
              final regionPage = crossPage ? pi + 1 : pi;
              final b = [for (final v in lineBox) v * 2];
              final previous = regions.lastOrNull;
              if (previous != null &&
                  previous.pageIndex == regionPage &&
                  b[1] >= previous.bbox[1] &&
                  b[0] < previous.bbox[2] &&
                  b[2] > previous.bbox[0] &&
                  b[1] - previous.bbox[3] < (b[3] - b[1]) * 3) {
                final a = previous.bbox;
                regions[regions.length - 1] = LayoutTextRegion(regionPage, [
                  a[0] < b[0] ? a[0] : b[0],
                  a[1],
                  a[2] > b[2] ? a[2] : b[2],
                  b[3],
                ], previous.sourceLength + lineText.length);
              } else {
                regions.add(LayoutTextRegion(regionPage, b, lineText.length));
              }
            }
          }
        }
        final label = switch (type) {
          'image_body' => 'image',
          'chart_body' => 'chart',
          'table_body' => 'table',
          'image_caption' ||
          'chart_caption' ||
          'table_caption' => 'figure_title',
          'image_footnote' ||
          'chart_footnote' ||
          'table_footnote' => 'vision_footnote',
          'title' =>
            pi == 0 && blocks.isEmpty ? 'doc_title' : 'paragraph_title',
          _ => type,
        };
        blocks.add(
          LayoutBlock(
            blockId: 'mu_p${pi}_b${order++}',
            blockLabel: label,
            blockBbox: size == null || box == null
                ? const []
                : [for (final v in box) v * 2],
            blockContent: text.join(' '),
            textRegions: regions,
            parentId: parent,
            sourceImage: source,
            captionKind: label == 'figure_title' ? kind : null,
            blockOrder: order,
          ),
        );
      }

      for (final block in (raw['para_blocks'] as List? ?? const [])) {
        if (block is! Map<String, dynamic>) continue;
        final children = block['blocks'];
        if (children is List && children.isNotEmpty) {
          final parent = 'mu_p${pi}_owner$order';
          final kind = block['type'] == 'table'
              ? 'table'
              : block['type'] == 'chart'
              ? 'chart'
              : 'figure';
          for (final child in children.whereType<Map<String, dynamic>>()) {
            append(child, parent, kind);
          }
        } else {
          append(block, null, null);
        }
      }
      pages.add(
        StructurePage(
          pageIndex: pi,
          blocks: blocks,
          markdown: '',
          pageSize: size == null ? null : [for (final v in size) v * 2],
        ),
      );
    }
    return DocumentStructure(pages);
  }

  Map<String, dynamic> toJson({String? source}) => {
    '_source': ?source,
    'structure_version': 2,
    'layoutParsingResults': [
      for (final page in pages)
        {
          'page_index': page.pageIndex,
          if (page.pageSize != null) 'page_size': page.pageSize,
          'prunedResult': {
            'parsing_res_list': [for (final b in page.blocks) b.toJson()],
          },
          'markdown': {'text': page.markdown, 'images': page.images},
        },
    ],
  };

  /// v2 lacks separate caption boxes. Keep ownership but never invent one.
  /// [pageSizes] are PDF points; absent sizes disable geometric inference.
  static DocumentStructure fromMinerUV2(
    List<dynamic> rawPages, {
    List<List<double>> pageSizes = const [],
  }) {
    final pages = <StructurePage>[];
    String text(Object? items) => items is List
        ? items
              .whereType<Map>()
              .map((v) => v['content'])
              .whereType<String>()
              .join(' ')
        : '';
    for (var pi = 0; pi < rawPages.length; pi++) {
      final size = pi < pageSizes.length ? pageSizes[pi] : null;
      final blocks = <LayoutBlock>[];
      var order = 0;
      for (final raw in (rawPages[pi] as List).whereType<Map>()) {
        final type = raw['type'] as String? ?? '';
        final content = raw['content'] as Map? ?? const {};
        final visual = const ['image', 'table', 'chart'].contains(type);
        final parent = 'mu_p${pi}_v${order++}';
        final bbox = _bboxValues(raw['bbox'], 4);
        final converted = size == null || bbox == null
            ? <double>[]
            : [
                bbox[0] * size[0] / 500,
                bbox[1] * size[1] / 500,
                bbox[2] * size[0] / 500,
                bbox[3] * size[1] / 500,
              ];
        final kind = type == 'image' ? 'figure' : type;
        final source = (content['image_source'] as Map?)?['path'] as String?;
        blocks.add(
          LayoutBlock(
            blockId: parent,
            blockLabel: visual
                ? type
                : type == 'title'
                ? (pi == 0 && content['level'] == 1
                      ? 'doc_title'
                      : 'paragraph_title')
                : type == 'paragraph' || type == 'list'
                ? 'text'
                : type,
            blockBbox: converted,
            parentId: visual ? parent : null,
            sourceImage: source,
            blockOrder: blocks.length,
            blockContent: type == 'table'
                ? content['html'] as String? ?? ''
                : text(content['${type}_content']),
          ),
        );
        if (visual) {
          final caption = text(content['${type}_caption']);
          if (caption.trim().isNotEmpty) {
            blocks.add(
              LayoutBlock(
                blockId: '${parent}_cap',
                blockLabel: 'figure_title',
                blockBbox: const [],
                blockContent: caption,
                parentId: parent,
                captionKind: kind,
                blockOrder: blocks.length,
              ),
            );
          }
        }
      }
      pages.add(
        StructurePage(
          pageIndex: pi,
          blocks: blocks,
          markdown: '',
          pageSize: size == null ? null : [size[0] * 2, size[1] * 2],
        ),
      );
    }
    return DocumentStructure(pages);
  }

  static List<double>? _bboxValues(Object? raw, int length) {
    if (raw is! List ||
        raw.length != length ||
        raw.any((v) => v is! num || !v.isFinite)) {
      return null;
    }
    final values = [for (final v in raw) (v as num).toDouble()];
    if (length == 2 && values.any((v) => v <= 0)) return null;
    if (length == 4 && (values[2] <= values[0] || values[3] <= values[1])) {
      return null;
    }
    return values;
  }

  /// 从磁盘读取并解析；文件不存在或损坏返回 [empty]。
  static Future<DocumentStructure> load(String jsonPath) async {
    final file = File(jsonPath);
    if (!file.existsSync()) return empty;
    try {
      return parse(await file.readAsString());
    } catch (_) {
      return empty;
    }
  }

  static List<LayoutBlock> _paddleTextRegions(
    List<LayoutBlock> blocks,
    int pageIndex,
  ) {
    return blocks.map((block) {
      if (block.groupId == null ||
          block.textRegions.isNotEmpty ||
          block.blockContent.trim().isEmpty ||
          !const {
            'text',
            'paragraph',
            'abstract',
            'list',
          }.contains(block.blockLabel)) {
        return block;
      }
      final group = blocks
          .where(
            (other) =>
                other.groupId == block.groupId &&
                other.blockLabel == block.blockLabel &&
                other.blockBbox.length == 4 &&
                other.blockBbox[2] > other.blockBbox[0] &&
                other.blockBbox[3] > other.blockBbox[1],
          )
          .toList();
      if (group.length < 2 ||
          group.where((b) => b.blockContent.trim().isNotEmpty).length != 1) {
        return block;
      }
      group.sort(
        (a, b) => (a.blockOrder ?? blocks.indexOf(a)).compareTo(
          b.blockOrder ?? blocks.indexOf(b),
        ),
      );
      final areas = group
          .map(
            (b) =>
                (b.blockBbox[2] - b.blockBbox[0]) *
                (b.blockBbox[3] - b.blockBbox[1]),
          )
          .toList();
      final total = areas.fold<double>(0, (sum, area) => sum + area);
      // Paddle 将合并后的全文放在组首，续栏留下空文本框；保留框的顺序，
      // 不改变段落内容和哈希，已有译文与标注可直接复用。
      return LayoutBlock.fromJson({
        ...block.toJson(),
        'text_regions': [
          for (var i = 0; i < group.length; i++)
            LayoutTextRegion(
              pageIndex,
              group[i].blockBbox,
              (block.blockContent.length * areas[i] / total).round().clamp(
                1,
                1 << 30,
              ),
            ).toJson(),
        ],
      });
    }).toList();
  }

  static StructurePage _parsePage(Map<String, dynamic> page, int index) {
    final blockList =
        ((page['prunedResult'] as Map<String, dynamic>?)?['parsing_res_list']
            as List<dynamic>?) ??
        const [];
    return StructurePage(
      pageIndex: (page['page_index'] as int?) ?? index,
      pageSize:
          _bboxValues(page['page_size'], 2) ??
          _bboxValues([
            (page['prunedResult'] as Map?)?['width'],
            (page['prunedResult'] as Map?)?['height'],
          ], 2),
      images: ((page['markdown'] as Map?)?['images'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      blocks: _paddleTextRegions([
        for (final b in blockList)
          LayoutBlock.fromJson(b as Map<String, dynamic>),
      ], (page['page_index'] as int?) ?? index),
      markdown:
          ((page['markdown'] as Map<String, dynamic>?)?['text'] as String?) ??
          '',
    );
  }
}
