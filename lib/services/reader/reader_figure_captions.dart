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
  // 混合正文只能按已记录的字符范围拆分，不能把整个 OCR 块改成图注。
  final ranges = <(int, String), List<FigureCaptionRef>>{};
  for (final figure in figures.where((f) => f.isDisplayFigure)) {
    for (final ref in figure.captionRefs) {
      if (ref.blockId != null && ref.start != null && ref.end != null) {
        ranges.putIfAbsent((ref.pageIndex, ref.blockId!), () => []).add(ref);
      }
    }
  }
  final remapped = <(int, String, int), String>{};
  final split = <LayoutBlock, List<LayoutBlock>>{};
  for (final page in structure.pages) {
    for (final block in page.blocks) {
      final refs = ranges[(page.pageIndex, block.blockId)];
      if (refs == null) continue;
      final valid =
          refs
              .where(
                (r) =>
                    r.start! >= 0 &&
                    r.end! <= block.blockContent.length &&
                    r.end! > r.start! &&
                    block.blockContent.substring(r.start!, r.end!) == r.text,
              )
              .toList()
            ..sort((a, b) => a.start!.compareTo(b.start!));
      if (!valid.any(
        (r) =>
            block.blockContent.substring(0, r.start!).trim().isNotEmpty ||
            block.blockContent.substring(r.end!).trim().isNotEmpty,
      )) {
        continue;
      }
      final parts = <LayoutBlock>[];
      void append(int start, int end, String label) {
        final text = block.blockContent.substring(start, end).trim();
        if (text.isEmpty) return;
        parts.add(
          LayoutBlock(
            blockId: '${block.blockId}:$start',
            blockLabel: label,
            blockBbox: const [],
            blockContent: text,
            parentId: block.parentId,
            sourceData: block.sourceData,
          ),
        );
      }

      var cursor = 0;
      for (final ref in valid) {
        if (ref.start! < cursor) continue;
        append(cursor, ref.start!, block.blockLabel);
        append(ref.start!, ref.end!, 'figure_title');
        remapped[(page.pageIndex, block.blockId, ref.start!)] =
            '${block.blockId}:${ref.start}';
        cursor = ref.end!;
      }
      append(cursor, block.blockContent.length, block.blockLabel);
      split[block] = parts;
    }
  }
  if (split.isNotEmpty) {
    structure = DocumentStructure([
      for (final page in structure.pages)
        StructurePage(
          pageIndex: page.pageIndex,
          pageSize: page.pageSize,
          markdown: page.markdown,
          images: page.images,
          blocks: [
            for (final block in page.blocks) ...split[block] ?? [block],
          ],
        ),
    ]);
    figures = [
      for (final figure in figures)
        FigureManifestEntry.fromJson({
          ...figure.toJson(),
          'caption_refs': [
            for (final ref in figure.captionRefs)
              {
                ...ref.toJson(),
                if (remapped[(ref.pageIndex, ref.blockId, ref.start)]
                    case final String id)
                  'block_id': id,
              },
          ],
        }),
    ];
  }
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
        final referenced = refs.any(
          (r) => r.pageIndex == pageIndex && r.blockId == block.blockId,
        );
        if (consumed.contains(block) ||
            !(referenced ||
                readerCaptionLabels.contains(block.blockLabel) ||
                const {'text', 'paragraph'}.contains(block.blockLabel))) {
          continue;
        }
        final text = _captionKey(block.blockContent);
        if (text.isEmpty || !key.contains(text)) continue;
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
