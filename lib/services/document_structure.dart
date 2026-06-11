import 'dart:convert';
import 'dart:io';

/// extract.json（PaddleOCR 版面解析产物）的**唯一防腐层**。
///
/// 持久化的结构模型形状：每页一个对象，块列表在
/// `prunedResult.parsing_res_list`，页级 markdown 在 `markdown.text`。
/// 根既可能是页数组，也可能是带 `layoutParsingResults` 的对象（API 原始
/// 响应形状）——两种都在此消化，调用方（figure 提取 / markdown 替换 /
/// AI 排版修复 / 未来的翻译保护 span）不再各自 jsonDecode 直挖。

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

  LayoutBlock({
    required this.blockId,
    required this.blockLabel,
    required this.blockBbox,
    List<num>? rawBbox,
    required this.blockContent,
  }) : rawBbox = rawBbox ?? blockBbox;

  factory LayoutBlock.fromJson(Map<String, dynamic> json) {
    final rawBbox =
        (json['block_bbox'] as List<dynamic>? ?? const []).whereType<num>();
    return LayoutBlock(
      blockId: json['block_id']?.toString() ?? '',
      blockLabel: json['block_label'] as String? ?? '',
      blockBbox: [for (final v in rawBbox) v.toDouble()],
      rawBbox: List.unmodifiable(rawBbox),
      blockContent: json['block_content'] as String? ?? '',
    );
  }
}

/// 结构模型中的一页：页号 + 块列表 + 该页的 raw markdown。
class StructurePage {
  final int pageIndex;
  final List<LayoutBlock> blocks;
  final String markdown;

  const StructurePage({
    required this.pageIndex,
    required this.blocks,
    required this.markdown,
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

  static StructurePage _parsePage(Map<String, dynamic> page, int index) {
    final blockList =
        ((page['prunedResult'] as Map<String, dynamic>?)?['parsing_res_list']
                as List<dynamic>?) ??
            const [];
    return StructurePage(
      pageIndex: (page['page_index'] as int?) ?? index,
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
