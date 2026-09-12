import '../data/models/book/document.dart';
import 'chinese_metadata_extractor.dart';
import 'document_metadata_parser.dart';

/// 文献元数据的"质量 / 判重"纯谓词集合。
///
/// 从 `DocumentsNotifier`（god notifier）抽出——这些判断不依赖 notifier 的
/// state / I/O，是对 [Document] 的纯函数，独立成可单测的工具，消除原先散落在
/// 851 行 notifier 里的判重 / 修复检测逻辑。
class DocumentMetadataChecks {
  DocumentMetadataChecks._();

  static Document mergeFromSource(
    Document current,
    Document incoming,
    Document? previous,
  ) {
    final values = current.toJson();
    final source = incoming.toJson();
    final baseline = previous?.toJson();
    for (final key in [
      'title',
      'authors',
      'journal',
      'year',
      'doi',
      'keywords',
    ]) {
      final value = values[key];
      final old = baseline?[key];
      final unchanged = value is List && old is List
          ? value.length == old.length &&
                List.generate(
                  value.length,
                  (i) => value[i] == old[i],
                ).every((v) => v)
          : value == old;
      // 已有内容只有仍等于上次导入值时才更新；首次关联只补空字段，保留用户编辑。
      if ((baseline != null && unchanged) ||
          (baseline == null &&
              (value == null ||
                  value == '' ||
                  value is List && value.isEmpty))) {
        values[key] = source[key];
      }
    }
    return Document.fromJson(values);
  }

  /// 文献是否需要元数据修复（已落盘但字段缺失 / 内容可疑）。
  static bool needsRepair(Document doc) {
    if (doc.contentHash == null) return false;
    // 字段缺失维度
    if (looksLikePlaceholderTitle(doc) ||
        doc.authors.isEmpty ||
        isBlank(doc.year) ||
        (isBlank(doc.journal) && isBlank(doc.doi))) {
      return true;
    }
    // 字段已填但内容可疑维度：字段填满≠正确，否则坏数据会骗过修复检测。
    // 1) 标题仍是未拆分的 CNKI 命名 "标题_作者"（历史数据）
    final titleSplit = DocumentMetadataParser.parseText(doc.title);
    if (titleSplit.title != null && titleSplit.authors.isNotEmpty) return true;
    // 2) 作者里混入「文章编号」等非人名词（此前正文误提取）
    if (doc.authors.any(ChineseMetadataExtractor.isNonPersonName)) return true;
    return false;
  }

  /// 文献核心元数据是否完整。
  static bool isComplete(Document doc) {
    return !looksLikePlaceholderTitle(doc) &&
        doc.authors.isNotEmpty &&
        !isBlank(doc.year) &&
        (!isBlank(doc.journal) || !isBlank(doc.doi));
  }

  /// 两篇文献的核心元数据（标题 / 期刊 / 年份 / DOI / 作者）是否等价。
  static bool sameCore(Document left, Document right) {
    if (normalizeMetadataValue(left.title) !=
        normalizeMetadataValue(right.title)) {
      return false;
    }
    if (normalizeMetadataValue(left.journal) !=
        normalizeMetadataValue(right.journal)) {
      return false;
    }
    if (normalizeMetadataValue(left.year) !=
        normalizeMetadataValue(right.year)) {
      return false;
    }
    if (normalizeMetadataValue(left.doi) != normalizeMetadataValue(right.doi)) {
      return false;
    }
    if (left.authors.length != right.authors.length) return false;
    for (var i = 0; i < left.authors.length; i++) {
      if (normalizeMetadataValue(left.authors[i]) !=
          normalizeMetadataValue(right.authors[i])) {
        return false;
      }
    }
    return true;
  }

  /// candidate 是否与 existing 重复：DOI 优先；否则标题一致 + 年份或首作者一致。
  static bool isDuplicate(Document existing, Document candidate) {
    if (!isBlank(existing.doi) && !isBlank(candidate.doi)) {
      return existing.doi!.toLowerCase() == candidate.doi!.toLowerCase();
    }

    final normalizedTitle = normalizeComparisonKey(existing.title);
    final candidateTitle = normalizeComparisonKey(candidate.title);
    if (normalizedTitle.isEmpty ||
        candidateTitle.isEmpty ||
        normalizedTitle != candidateTitle) {
      return false;
    }

    final existingYear = normalizeComparisonKey(existing.year);
    final candidateYear = normalizeComparisonKey(candidate.year);
    if (existingYear.isNotEmpty &&
        candidateYear.isNotEmpty &&
        existingYear == candidateYear) {
      return true;
    }

    final existingAuthor = existing.authors.isEmpty
        ? ''
        : normalizeComparisonKey(existing.authors.first);
    final candidateAuthor = candidate.authors.isEmpty
        ? ''
        : normalizeComparisonKey(candidate.authors.first);
    return existingAuthor.isNotEmpty && existingAuthor == candidateAuthor;
  }

  /// 标题是否为占位 / 可疑（空 / 等于文档 id / 非合理标题）。
  static bool looksLikePlaceholderTitle(Document doc) {
    final normalizedTitle = normalizeComparisonKey(doc.title);
    if (normalizedTitle.isEmpty) return true;
    if (normalizedTitle == normalizeComparisonKey(doc.id)) return true;
    // 文件路径 / LaTeX 中间产物 / Word 占位文本——也算 placeholder，让 rebuild
    // 能继续尝试修复（例如 PDF 正文里的 DOI / arXiv ID）。
    if (!DocumentMetadataParser.isPlausibleTitle(doc.title)) return true;
    return false;
  }

  static String normalizeComparisonKey(String? value) {
    return (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? normalizeMetadataValue(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static bool isBlank(String? value) {
    return value == null || value.trim().isEmpty;
  }
}
