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

  /// PaddleOCR 页内分组提示，不作为不可拆分的实体身份。
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
  final Map<String, dynamic> sourceData;

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
    this.sourceData = const {},
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
      sourceData: Map<String, dynamic>.from(
        json['source_data'] as Map? ?? json,
      ),
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
    if (sourceData.isNotEmpty) 'source_data': sourceData,
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
      final pages = [
        for (var i = 0; i < rawPages.length; i++)
          _parsePage(rawPages[i] as Map<String, dynamic>, i),
      ];
      return DocumentStructure(
        decoded is Map && decoded['_source'] == 'mineru'
            ? _mineruTextRegions(pages)
            : _paddleTextRegions(pages),
      );
    } catch (_) {
      return empty;
    }
  }

  /// MinerU layout.json / middle.json: page points and nested body/caption
  /// blocks. Preserve explicit ownership instead of synthesizing caption boxes.
  static DocumentStructure fromMinerULayout(Map<String, dynamic> layout) {
    final pages = <StructurePage>[];
    final linePages = <String, Set<int>>{};
    String lineKey(Map line) => jsonEncode([
      _bboxValues(line['bbox'], 4),
      for (final span in (line['spans'] as List? ?? []).whereType<Map>())
        [span['type'], span['content'], span['html']],
    ]);
    void indexLines(Map block, int pageIndex) {
      for (final line in (block['lines'] as List? ?? []).whereType<Map>()) {
        (linePages[lineKey(line)] ??= {}).add(pageIndex);
      }
      for (final child in (block['blocks'] as List? ?? []).whereType<Map>()) {
        indexLines(child, pageIndex);
      }
    }

    final rawPages = layout['pdf_info'] as List? ?? const [];
    for (var i = 0; i < rawPages.length; i++) {
      final raw = rawPages[i];
      if (raw is! Map) continue;
      final pi = (raw['page_idx'] as num?)?.toInt() ?? i;
      for (final block
          in (raw['preproc_blocks'] as List? ?? []).whereType<Map>()) {
        indexLines(block, pi);
      }
    }
    for (final raw in rawPages) {
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
              // cross_page 表示来自后续正文页，中间可能隔着整页图表。
              final matches = linePages[lineKey(line)]
                  ?.where((pageIndex) => pageIndex > pi)
                  .toList();
              final regionPage = !crossPage
                  ? pi
                  : matches?.length == 1
                  ? matches!.single
                  : null;
              if (regionPage == null) continue;
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
            sourceData: {
              'provider': 'mineru',
              'page': pi,
              'order': order - 1,
              'native': block,
            },
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

      for (final block in [
        ...?raw['para_blocks'] as List?,
        ...?raw['discarded_blocks'] as List?,
      ]) {
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
    return DocumentStructure(_mineruTextRegions(pages));
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
    if (rawPages.any(
      (page) =>
          page is! List ||
          page.any(
            (block) =>
                block is! Map ||
                block['type'] is! String ||
                block['content'] is! Map,
          ),
    )) {
      throw const FormatException('unsupported_mineru_v2_schema');
    }
    final pages = <StructurePage>[];
    String text(Object? items) {
      if (items is String) return items;
      if (items is List) {
        return items.map(text).where((s) => s.isNotEmpty).join(' ');
      }
      if (items is Map) {
        return text(
          items['content'] ??
              items['item_content'] ??
              items['list_content'] ??
              items['list_items'] ??
              items['children'],
        );
      }
      return '';
    }

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
            sourceData: {
              'provider': 'mineru',
              'page': pi,
              'order': order - 1,
              'native': raw,
            },
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
                : text(
                    type == 'list'
                        ? content['list_items']
                        : content['${type}_content'],
                  ),
          ),
        );
        if (visual) {
          final footnote = text(content['${type}_footnote']);
          if (footnote.isNotEmpty) {
            blocks.add(
              LayoutBlock(
                blockId: '${parent}_note',
                blockLabel: 'vision_footnote',
                blockBbox: const [],
                blockContent: footnote,
                parentId: parent,
                sourceData: {
                  'provider': 'mineru',
                  'page': pi,
                  'native': content['${type}_footnote'],
                },
              ),
            );
          }
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
        // 非视觉容器也可能携带被误分类的题注，不把字段白名单当作召回边界。
        if (!visual) {
          for (final field in content.keys.where(
            (key) => key is String && key.endsWith('_caption'),
          )) {
            final caption = text(content[field]);
            if (caption.trim().isEmpty) continue;
            blocks.add(
              LayoutBlock(
                blockId: '${parent}_$field',
                blockLabel: field.toString(),
                blockBbox: const [],
                blockContent: caption,
                parentId: parent,
                sourceData: {'provider': 'mineru', 'native': content[field]},
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

  static List<StructurePage> _withTextRegions(
    List<StructurePage> pages,
    Map<LayoutBlock, List<LayoutTextRegion>> replacements,
  ) => [
    for (final page in pages)
      StructurePage(
        pageIndex: page.pageIndex,
        pageSize: page.pageSize,
        markdown: page.markdown,
        images: page.images,
        blocks: [
          for (final block in page.blocks)
            if (replacements[block] case final regions?)
              LayoutBlock.fromJson({
                ...block.toJson(),
                'text_regions': regions.map((r) => r.toJson()).toList(),
              })
            else
              block,
        ],
      ),
  ];

  static const _bodyLabels = {'text', 'paragraph', 'abstract', 'list'};

  static List<StructurePage> _paddleTextRegions(List<StructurePage> pages) {
    final entries = <({int page, LayoutBlock block})>[];
    final globalGroups = <(int, String), List<int>>{};
    final localGroups = <(int, int, String), List<int>>{};
    for (final page in pages) {
      final ordered = [...page.blocks];
      ordered.sort(
        (a, b) => (a.blockOrder ?? page.blocks.indexOf(a)).compareTo(
          b.blockOrder ?? page.blocks.indexOf(b),
        ),
      );
      for (final block in ordered) {
        if (!_bodyLabels.contains(block.blockLabel)) continue;
        final index = entries.length;
        entries.add((page: page.pageIndex, block: block));
        if (block.globalGroupId case final global? when global >= 0) {
          (globalGroups[(global, block.blockLabel)] ??= []).add(index);
        }
        if (block.groupId case final local? when local >= 0) {
          (localGroups[(page.pageIndex, local, block.blockLabel)] ??= []).add(
            index,
          );
        }
      }
    }

    // 全局分组用于跨页续文；同一页内 Paddle 有时会给续栏分配相邻但不同的
    // global_group_id，此时仅在页内分组恰好只有一个非空正文块、且补上这条关联
    // 后整个分区仍只有一个非空块时才建立关联。这样既能恢复左右栏，也不会把
    // 同号的两个独立正文块合并，或把两个已成形的全局分组串成一个双非空块。
    final parent = List<int>.generate(entries.length, (i) => i);
    int root(int value) {
      var current = value;
      while (parent[current] != current) {
        parent[current] = parent[parent[current]];
        current = parent[current];
      }
      return current;
    }

    void union(int a, int b) {
      final left = root(a);
      final right = root(b);
      if (left != right) parent[right] = left;
    }

    for (final group in globalGroups.values) {
      for (var i = 1; i < group.length; i++) {
        union(group.first, group[i]);
      }
    }
    for (final group in localGroups.values) {
      if (group.length < 2) continue;
      final owners = group
          .where((i) => entries[i].block.blockContent.trim().isNotEmpty)
          .toList();
      if (owners.length != 1) continue;
      // 合并后若出现第二个非空正文块，整组会在下方被跳过，连带丢掉全局续框；
      // 先按当前分区状态确认合并结果仍只有一个非空块。
      final roots = {for (final i in group) root(i)};
      final mergedOwners = [
        for (var i = 0; i < entries.length; i++)
          if (roots.contains(root(i)) &&
              entries[i].block.blockContent.trim().isNotEmpty)
            i,
      ];
      if (mergedOwners.length != 1) continue;
      for (var i = 1; i < group.length; i++) {
        union(group.first, group[i]);
      }
    }

    final groups = <int, List<({int page, LayoutBlock block})>>{};
    for (var i = 0; i < entries.length; i++) {
      (groups[root(i)] ??= []).add(entries[i]);
    }
    final replacements = <LayoutBlock, List<LayoutTextRegion>>{};
    for (final group in groups.values) {
      final owners = group.where((e) => e.block.blockContent.trim().isNotEmpty);
      if (group.length < 2 ||
          owners.length != 1 ||
          group.any((e) => e.block.blockBbox.length != 4)) {
        continue;
      }
      final owner = owners.single.block;
      if (owner.textRegions.isNotEmpty &&
          (owner.textRegions.length >= group.length ||
              owner.textRegions.any(
                (r) => !group.any(
                  (e) =>
                      e.page == r.pageIndex &&
                      e.block.blockBbox.length == r.bbox.length &&
                      r.bbox.indexed.every(
                        (v) => e.block.blockBbox[v.$1] == v.$2,
                      ),
                ),
              ))) {
        continue;
      }
      final areas = group.map((e) {
        final b = e.block.blockBbox;
        return (b[2] - b[0]) * (b[3] - b[1]);
      }).toList();
      final total = areas.fold<double>(0, (sum, area) => sum + area);
      // 全文只在一个块中，其余空框仍占据排版容量；保持正文与缓存哈希不变。
      replacements[owner] = [
        for (var i = 0; i < group.length; i++)
          LayoutTextRegion(
            group[i].page,
            group[i].block.blockBbox,
            (owner.blockContent.length * areas[i] / total).round().clamp(
              1,
              1 << 30,
            ),
          ),
      ];
    }
    return _withTextRegions(pages, replacements);
  }

  static List<StructurePage> _mineruTextRegions(List<StructurePage> pages) {
    final entries = [
      for (final page in pages)
        for (final block in page.blocks) (page: page.pageIndex, block: block),
    ];
    final replacements = <LayoutBlock, List<LayoutTextRegion>>{};
    for (var i = 0; i < entries.length; i++) {
      final owner = entries[i];
      if (!_bodyLabels.contains(owner.block.blockLabel)) continue;
      final regions = [...owner.block.textRegions];
      for (var ri = 0; ri < regions.length; ri++) {
        final region = regions[ri];
        if (region.pageIndex <= owner.page || region.bbox.length != 4) continue;
        // 旧缓存没有原始行来源；仅在下一段正文前寻找唯一且紧密包围行组的空续框。
        // 图表和题注不终止查找，也不参与坐标匹配。
        final candidates = <int>[];
        for (final next in entries.skip(i + 1)) {
          if (!_bodyLabels.contains(next.block.blockLabel)) continue;
          if (next.block.blockContent.trim().isNotEmpty) break;
          final b = next.block.blockBbox;
          final a = region.bbox;
          if (next.page <= owner.page ||
              b.length != 4 ||
              next.block.blockLabel != owner.block.blockLabel) {
            continue;
          }
          if (a[0] >= b[0] - 4 &&
              a[1] >= b[1] - 4 &&
              a[2] <= b[2] + 4 &&
              a[3] <= b[3] + 4 &&
              (a[2] - a[0]) * (a[3] - a[1]) >=
                  (b[2] - b[0]) * (b[3] - b[1]) * .7) {
            candidates.add(next.page);
          }
        }
        if (candidates.length == 1 && candidates.single != region.pageIndex) {
          regions[ri] = LayoutTextRegion(
            candidates.single,
            region.bbox,
            region.sourceLength,
          );
          replacements[owner.block] = regions;
        }
      }
    }
    return _withTextRegions(pages, replacements);
  }

  static StructurePage _parsePage(Map<String, dynamic> page, int index) {
    if ((page['prunedResult'] is! Map ||
            (page['prunedResult'] as Map)['parsing_res_list'] is! List) &&
        (page['markdown'] is! Map ||
            (page['markdown'] as Map)['text'] is! String)) {
      throw const FormatException('unsupported_paddle_page');
    }
    final preprocessor =
        (page['prunedResult'] as Map?)?['doc_preprocessor_res'] as Map?;
    final transformed =
        preprocessor != null &&
        (((preprocessor['angle'] as num?) ?? 0) != 0 ||
            (preprocessor['model_settings'] as Map?)?['use_doc_unwarping'] ==
                true);
    final blockList =
        ((page['prunedResult'] as Map<String, dynamic>?)?['parsing_res_list']
            as List<dynamic>?) ??
        const [];
    return StructurePage(
      pageIndex: (page['page_index'] as int?) ?? index,
      pageSize: transformed
          ? null
          : _bboxValues(page['page_size'], 2) ??
                _bboxValues([
                  (page['prunedResult'] as Map?)?['width'],
                  (page['prunedResult'] as Map?)?['height'],
                ], 2),
      images: ((page['markdown'] as Map?)?['images'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      blocks: [
        for (final b in blockList)
          LayoutBlock.fromJson(b as Map<String, dynamic>),
      ],
      markdown:
          ((page['markdown'] as Map<String, dynamic>?)?['text'] as String?) ??
          '',
    );
  }
}
