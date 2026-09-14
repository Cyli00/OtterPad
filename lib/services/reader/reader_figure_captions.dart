import '../document_structure.dart';
import '../figure_extract_service.dart';

const readerCaptionLabels = {
  'figure_title',
  'chart_title',
  'table_title',
  'image_title',
  'figure_caption',
  'image_caption',
  'table_caption',
  'chart_caption',
  'caption',
};

final _captionFormatting = RegExp(r'[\s*_$`\\]');
String _captionKey(String value) => value.replaceAll(_captionFormatting, '');

// 只使用题注引用和题注框，绝不把图片裁剪框或图表内文字当作替换区域。
DocumentStructure readerFigureCaptionStructure(
  DocumentStructure structure,
  List<FigureManifestEntry> figures,
) {
  final replacements = <LayoutBlock, LayoutBlock>{};
  final consumed = <LayoutBlock>{};
  final additions = <int, List<LayoutBlock>>{};
  final seen = <(int, String)>{};
  final pages = {for (final page in structure.pages) page.pageIndex: page};
  for (final figure in figures.where((f) => f.isDisplayFigure)) {
    final caption = figure.captionText.trim();
    final key = _captionKey(caption);
    if (key.isEmpty || !seen.add((figure.pageIndex, key))) continue;
    final parts = <({StructurePage page, LayoutBlock block})>[];
    final refs = figure.captionRefs;
    final candidatePages = refs.isEmpty
        ? {figure.pageIndex}
        : refs.map((r) => r.pageIndex).toSet();
    for (final pageIndex in candidatePages) {
      final page = pages[pageIndex];
      if (page == null) continue;
      for (final block in page.blocks) {
        if (consumed.contains(block) ||
            !(readerCaptionLabels.contains(block.blockLabel) ||
                const {'text', 'paragraph'}.contains(block.blockLabel))) {
          continue;
        }
        final text = _captionKey(block.blockContent);
        if (text.isEmpty || !key.contains(text)) continue;
        final referenced = refs.any(
          (r) => r.pageIndex == pageIndex && r.blockId == block.blockId,
        );
        if (referenced ||
            figure.blockIds.contains(block.blockId) ||
            readerCaptionLabels.contains(block.blockLabel) ||
            text == key) {
          parts.add((page: page, block: block));
        }
      }
    }
    // 清单可能附带 vision_footnote；不能把它挤进主图注或重复覆盖到 PDF。
    // 只有完整题注能由这些文字块解释时才合并，否则保留 OCR 的独立段落。
    parts.sort(
      (a, b) => key
          .indexOf(_captionKey(a.block.blockContent))
          .compareTo(key.indexOf(_captionKey(b.block.blockContent))),
    );
    if (parts.isNotEmpty &&
        parts.map((p) => _captionKey(p.block.blockContent)).join() != key) {
      continue;
    }
    final pageIndex = parts.isNotEmpty
        ? parts.first.page.pageIndex
        : refs.firstOrNull?.pageIndex ?? figure.pageIndex;
    if (!pages.containsKey(pageIndex)) continue;
    if (parts.isEmpty &&
        candidatePages.any(
          (i) =>
              pages[i]?.blocks.any(
                (b) =>
                    const {
                      'vision_footer',
                      'vision_footnote',
                      'header',
                      'footer',
                      'footnote',
                    }.contains(b.blockLabel) &&
                    _captionKey(b.blockContent) == key,
              ) ==
              true,
        )) {
      continue;
    }
    final first = parts.firstOrNull?.block;
    final block = LayoutBlock(
      blockId: first?.blockId ?? 'caption:${figure.id ?? figure.imagePath}',
      blockLabel: switch (figure.kind) {
        'table' => 'table_title',
        'chart' => 'chart_title',
        _ => 'figure_title',
      },
      blockBbox: first?.blockBbox ?? figure.captionBbox ?? const [],
      blockContent: caption,
      parentId: first?.parentId,
      textRegions: parts.length > 1
          ? [
              for (final part in parts)
                if (part.block.textRegions.isNotEmpty)
                  ...part.block.textRegions
                else
                  LayoutTextRegion(
                    part.page.pageIndex,
                    part.block.blockBbox,
                    part.block.blockContent.trim().length,
                  ),
            ]
          : first?.textRegions ?? const [],
    );
    if (first == null) {
      additions.putIfAbsent(pageIndex, () => []).add(block);
    } else {
      replacements[first] = block;
      consumed.addAll(parts.map((p) => p.block));
    }
  }
  return DocumentStructure([
    for (final page in structure.pages)
      StructurePage(
        pageIndex: page.pageIndex,
        pageSize: page.pageSize,
        markdown: page.markdown,
        images: page.images,
        blocks: [
          for (final block in page.blocks)
            if (replacements.containsKey(block))
              replacements[block]!
            else if (!consumed.contains(block))
              block,
          ...?additions[page.pageIndex],
        ],
      ),
  ]);
}
