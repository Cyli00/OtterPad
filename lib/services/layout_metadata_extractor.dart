import 'document_metadata_parser.dart';
import 'document_structure.dart';
import 'chinese_text_detector.dart';

/// 从 OCR 版面解析结构（extract.json 首页）提取书籍元数据。
///
/// 适用于中文教材、专著等 PaddleOCR 能识别出 `doc_title` 标签的文档。
/// 期刊论文通常无 `doc_title`，该提取器返回空元数据，不干扰现有管线。
class LayoutMetadataExtractor {
  LayoutMetadataExtractor._();

  static final _authorRoleSuffixRe = RegExp(
    r'(?:编著|主编|编|著|译|改编)\s*$',
  );

  static final _excludedRoleRe = RegExp(
    r'(?:主审|审校|审|校)\s*$',
  );

  static final _chineseNameRe = RegExp(r'[一-鿿]{2,4}');

  /// 从首页 block 列表提取元数据。
  static DocumentMetadata extractFromFirstPage(List<LayoutBlock> blocks) {
    final title = _extractTitle(blocks);
    if (title == null) return const DocumentMetadata();

    final authors = _extractAuthors(blocks);
    return DocumentMetadata(title: title, authors: authors);
  }

  static String? _extractTitle(List<LayoutBlock> blocks) {
    for (final b in blocks) {
      if (b.blockLabel != 'doc_title') continue;
      final content = b.blockContent.trim();
      if (content.isEmpty) continue;
      return _pickBestTitleLine(content);
    }
    return null;
  }

  static String? _pickBestTitleLine(String content) {
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    if (lines.length == 1) return lines.first;

    final chineseLines = lines.where(ChineseTextDetector.isChinese).toList();
    if (chineseLines.isNotEmpty) {
      chineseLines.sort((a, b) => b.length.compareTo(a.length));
      return chineseLines.first;
    }
    return lines.first;
  }

  static List<String> _extractAuthors(List<LayoutBlock> blocks) {
    for (final b in blocks) {
      if (b.blockLabel != 'text') continue;
      final lines = b.blockContent.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (_excludedRoleRe.hasMatch(trimmed)) continue;
        if (!_authorRoleSuffixRe.hasMatch(trimmed)) continue;
        final namesPart = trimmed.replaceAll(_authorRoleSuffixRe, '').trim();
        final names = _chineseNameRe
            .allMatches(namesPart)
            .map((m) => m.group(0)!)
            .toList();
        if (names.isNotEmpty) return names;
      }
    }
    return const [];
  }
}
