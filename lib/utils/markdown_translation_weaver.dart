import 'dart:convert';
import '../services/markdown_paragraph_extractor.dart';

/// 文档翻译显示模式。
enum DocTranslationMode {
  /// 关闭——显示原文（未翻译或用户主动切回）
  off,

  /// 双语对照：原段落后接译文段
  bilingual,

  /// 仅译文：段落替换为译文
  translated,
}

String markReaderParagraphs({
  required String markdown,
  required List<TranslatableParagraph> paragraphs,
  required Map<int, String> paragraphIds,
}) {
  final output = StringBuffer();
  var cursor = 0;
  for (final paragraph in paragraphs) {
    final start = paragraph.offset;
    final end = start + paragraph.length;
    final id = paragraphIds[start];
    if (id == null ||
        start < cursor ||
        paragraph.length <= 0 ||
        end > markdown.length ||
        markdown.substring(start, end) != paragraph.text) {
      continue;
    }
    final key = base64Url.encode(utf8.encode(id));
    output.write(markdown.substring(cursor, start));
    output.write(
      '\n\n<!-- reader-pair:$key -->\n\n${paragraph.text}\n\n<!-- reader-end -->\n\n',
    );
    cursor = end;
  }
  output.write(markdown.substring(cursor));
  return output.toString();
}
