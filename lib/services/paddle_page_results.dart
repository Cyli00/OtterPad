import 'dart:convert';

import '../data/models/ocr/doc_extract_config.dart';
import 'doc_extract_service.dart';
import 'mineru_page_chunks.dart';

/// 把按阅读顺序排好的 Paddle 页合成一份结果。
///
/// 页序以列表顺序为准，并写成连续的 `page_index`。服务商若按 200 页一段
/// 把 `page_index` 从 0 重新开始，后一段会在阅读版里盖掉前一段：720 页时
/// 就只剩下约第 601 页以后的文字。同名图片也不许后页覆盖前页的 URL。
DocExtractResult assemblePaddlePages(List<Map<String, dynamic>> pagesInOrder) {
  final images = <String, String>{};
  final markdown = <String>[];
  final stored = <Map<String, dynamic>>[];
  for (var i = 0; i < pagesInOrder.length; i++) {
    final page = Map<String, dynamic>.from(pagesInOrder[i]);
    final section = page['markdown'];
    var text = '';
    if (section is Map) {
      final copy = Map<String, dynamic>.from(section);
      text = copy['text'] as String? ?? '';
      final rawImages = copy['images'];
      if (rawImages is Map) {
        final next = <String, String>{};
        for (final entry in rawImages.entries) {
          var key = entry.key.toString();
          final value = entry.value.toString();
          if (images.containsKey(key) && images[key] != value) {
            final renamed = 'p${i}_$key';
            text = text.replaceAll(key, renamed);
            key = renamed;
          }
          images[key] = value;
          next[key] = value;
        }
        copy['images'] = next;
      }
      copy['text'] = text;
      page['markdown'] = copy;
    }
    page['page_index'] = i;
    markdown.add(text);
    stored.add(page);
  }
  return DocExtractResult(
    rawMarkdown: markdown.join('\n\n'),
    images: images,
    jsonContent: jsonEncode(stored),
  );
}

/// 多个 `pageRanges` 任务按页段序号拼接。调用前必须收齐；缺一段就抛出，
/// 不能把已经成功的后段当成整篇文档。
DocExtractResult mergePaddleChunkResults(
  List<({ExtractPageChunk chunk, DocExtractResult result})> parts,
) {
  if (parts.isEmpty) {
    throw const FormatException('PaddleOCR 没有可合并的分片');
  }
  final ordered = [...parts]
    ..sort((a, b) => a.chunk.index.compareTo(b.chunk.index));
  final seen = <int>{};
  final pages = <Map<String, dynamic>>[];
  for (final part in ordered) {
    if (!seen.add(part.chunk.index)) {
      throw FormatException('PaddleOCR 分片序号重复: ${part.chunk.label}');
    }
    final raw = part.result.jsonContent;
    if (raw == null) {
      throw FormatException('PaddleOCR 分片 ${part.chunk.label} 缺少版面结果');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('PaddleOCR 分片 ${part.chunk.label} 缺少版面结果');
    }
    for (final item in decoded) {
      if (item is Map) pages.add(Map<String, dynamic>.from(item));
    }
  }
  return assemblePaddlePages(pages);
}

List<ExtractPageChunk> planPaddlePageChunks(int? pageCount) =>
    planExtractPageChunks(
      pageCount,
      maxPages: DocExtractProvider.paddle.maxPagesPerFile,
    );
