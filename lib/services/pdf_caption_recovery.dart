import 'dart:io';
import 'dart:math' as math;

import 'package:pdfrx/pdfrx.dart';

import 'document_structure.dart';
import 'figure_extract_service.dart';
import 'pdf_process_lock.dart';

class PdfCaptionRecovery {
  static Future<DocumentStructure> recover(
    DocumentStructure structure,
    String pdfPath,
  ) async {
    final file = File(pdfPath);
    if (!await file.exists() || await file.length() < 5) return structure;
    await FigureExtractService.instance.init();
    return PdfProcessLock.instance.run(() async {
      final pdf = await PdfDocument.openFile(
        pdfPath,
        passwordProvider: () => '',
      );
      try {
        final pages = <StructurePage>[];
        for (final page in structure.pages) {
          final nearbyVisuals = structure.pages.any(
            (p) =>
                (p.pageIndex - page.pageIndex).abs() <= 1 &&
                p.blocks.any(
                  (b) =>
                      const ['image', 'chart', 'table'].contains(b.blockLabel),
                ),
          );
          if (!nearbyVisuals ||
              page.pageIndex < 0 ||
              page.pageIndex >= pdf.pages.length) {
            pages.add(page);
            continue;
          }
          final pdfPage = pdf.pages[page.pageIndex];
          final text = await pdfPage.loadText();
          pages.add(
            text == null ? page : recoverPage(page, text, pdfPage.height),
          );
        }
        return DocumentStructure(pages);
      } finally {
        pdf.dispose();
      }
    });
  }

  static StructurePage recoverPage(
    StructurePage page,
    PdfPageRawText text,
    double pageHeight,
  ) {
    final service = FigureExtractService.instance;
    final lines = <({String text, List<double> box})>[];
    for (final match in RegExp(r'[^\r\n]+').allMatches(text.fullText)) {
      final value = String.fromCharCodes(
        match[0]!.runes.where((c) => c >= 32 || c == 9),
      ).trim();
      if (value.isEmpty) continue;
      final rects = text.charRects
          .sublist(match.start, match.end)
          .where((r) => r.isNotEmpty);
      if (rects.isEmpty) continue;
      // PDF 原点在左下角，布局统一使用左上角原点、144 DPI；只合并有墨迹的字符框。
      final rect = rects.reduce((a, b) => a.merge(b));
      lines.add((
        text: value,
        box: [
          rect.left * 2,
          (pageHeight - rect.top) * 2,
          rect.right * 2,
          (pageHeight - rect.bottom) * 2,
        ],
      ));
    }
    final recovered = <LayoutBlock>[];
    final replaced = <LayoutBlock>{};
    for (var i = 0; i < lines.length; i++) {
      final anchor = lines[i];
      if (!service.isMainCaption(anchor.text)) continue;
      final name = service.extractCaptionName(anchor.text);
      final existing = page.blocks
          .where(
            (b) =>
                service.isMainCaption(b.blockContent) &&
                service.extractCaptionName(b.blockContent) == name,
          )
          .firstOrNull;
      if (existing != null && existing.blockBbox.length == 4) continue;
      final parts = [anchor.text];
      final box = [...anchor.box];
      var previous = anchor.box;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j];
        final b = next.box;
        final height = previous[3] - previous[1];
        if (service.isMainCaption(next.text) ||
            b[1] < previous[1] ||
            b[1] - previous[3] > math.max(6, height * 1.2) ||
            b[2] <= anchor.box[0] ||
            b[0] >= math.max(anchor.box[2], box[2]) ||
            page.blocks.any(
              (block) =>
                  const [
                    'text',
                    'paragraph_title',
                    'header',
                    'footer',
                  ].contains(block.blockLabel) &&
                  block.blockBbox.length == 4 &&
                  b[0] >= block.blockBbox[0] - 4 &&
                  b[2] <= block.blockBbox[2] + 4 &&
                  b[1] >= block.blockBbox[1] - 4 &&
                  b[3] <= block.blockBbox[3] + 4 &&
                  !service.isMainCaption(block.blockContent),
            )) {
          break;
        }
        parts.add(next.text);
        box[0] = math.min(box[0], b[0]);
        box[2] = math.max(box[2], b[2]);
        box[3] = math.max(box[3], b[3]);
        previous = b;
        i = j;
      }
      final content = parts.join(' ');
      recovered.add(
        LayoutBlock(
          blockId:
              existing?.blockId ??
              'pdf_caption_p${page.pageIndex}_${recovered.length}',
          blockLabel: 'figure_title',
          blockBbox: box,
          blockContent: content,
          parentId: existing?.parentId,
          groupId: existing?.groupId,
          globalGroupId: existing?.globalGroupId,
          captionKind: service.classifyKind(content),
          textRegions: [LayoutTextRegion(page.pageIndex, box, content.length)],
          blockOrder:
              existing?.blockOrder ?? page.blocks.length + recovered.length,
        ),
      );
      if (existing != null) replaced.add(existing);
    }
    if (recovered.isEmpty) return page;
    return StructurePage(
      pageIndex: page.pageIndex,
      blocks: [
        ...page.blocks.where((b) => !replaced.contains(b)),
        ...recovered,
      ],
      markdown: page.markdown,
      pageSize: page.pageSize,
      images: page.images,
    );
  }
}
