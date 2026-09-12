import '../data/models/book/document.dart';
import 'identifier_parser.dart';

class ZoteroPdfAttachment {
  const ZoteroPdfAttachment(this.key, this.title);
  final String key;
  final String title;
}

class ZoteroImportCandidate {
  const ZoteroImportCandidate(this.key, this.document, this.attachments);
  final String key;
  final Document document;
  final List<ZoteroPdfAttachment> attachments;
}

/// Zotero item JSON ↔ [Document] 的转换层（防腐层）。
///
/// 这是整个 Zotero 同步里**唯一**触碰格式差异的地方：Zotero 有 ~35 种 itemType、
/// creators 拆分 first/last、publicationTitle 与 publisher 分离等，全部在此消化，
/// 不让这些细节渗透进 [Document] 或 `IdentifierResolver`。
///
/// 当前只实现单向 `Zotero → Document`，反向 `toZoteroItem` 留待双向同步时补。
class ZoteroItemMapper {
  ZoteroItemMapper._();

  /// 不导入的非文献条目类型（附件 / 笔记 / 标注）。
  static const _skippedItemTypes = {'attachment', 'note', 'annotation'};

  static List<ZoteroImportCandidate> localCandidates(
    List<Map<String, dynamic>> items,
  ) {
    final attachments = <String, List<ZoteroPdfAttachment>>{};
    for (final item in items) {
      final data = item['data'];
      if (data is! Map ||
          data['deleted'] == true ||
          data['itemType'] != 'attachment' ||
          data['contentType'] != 'application/pdf' ||
          !const {
            'imported_file',
            'imported_url',
            'linked_file',
          }.contains(data['linkMode'])) {
        continue;
      }
      final parent = data['parentItem'];
      final key = item['key'];
      if (parent is! String || key is! String) continue;
      attachments
          .putIfAbsent(parent, () => [])
          .add(
            ZoteroPdfAttachment(
              key,
              (data['filename'] ?? data['title'] ?? key).toString(),
            ),
          );
    }
    final result = <ZoteroImportCandidate>[];
    for (final item in items) {
      final data = item['data'];
      if (data is! Map || data['deleted'] == true) continue;
      final document = toDocument(item);
      final key = item['key'];
      if (document == null || key is! String) continue;
      final pdfs = attachments[key] ?? <ZoteroPdfAttachment>[];
      pdfs.sort((a, b) => a.key.compareTo(b.key));
      result.add(ZoteroImportCandidate(key, document, pdfs));
    }
    return result;
  }

  /// 把单个 Zotero item（含顶层 `key`/`version` 与 `data` 字段）映射为 [Document]。
  ///
  /// 返回的 [Document] `id` 为空串、`contentHash` 为 null——真正的 id 由
  /// `DocumentsNotifier.importDocuments` 在落盘时分配。无法构成文献（缺标题、
  /// 非文献类型）时返回 null。
  static Document? toDocument(Map<String, dynamic> item) {
    final data = item['data'];
    if (data is! Map) return null;

    final itemType = data['itemType'] as String?;
    if (itemType == null || _skippedItemTypes.contains(itemType)) return null;

    final title = (data['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    return Document(
      id: '',
      title: title,
      authors: _authors(data['creators']),
      journal: _container(itemType, data),
      year: _year(data['date'] as String?),
      doi: IdentifierParser.normalizeDoi(data['DOI'] as String?)?.toLowerCase(),
      keywords: _tags(data['tags']),
      contentHash: null,
      addedAt: DateTime.now(),
    );
  }

  /// creators → authors：优先 `author`，没有作者时退回全部 creators。
  /// 单条目支持 firstName+lastName 与单字段 `name` 两种结构。
  static List<String> _authors(dynamic creators) {
    if (creators is! List) return const [];

    String? nameOf(Map creator) {
      final single = (creator['name'] as String?)?.trim();
      if (single != null && single.isNotEmpty) return single;
      final first = (creator['firstName'] as String?)?.trim() ?? '';
      final last = (creator['lastName'] as String?)?.trim() ?? '';
      final joined = '$first $last'.trim();
      return joined.isEmpty ? null : joined;
    }

    final authors = <String>[];
    final fallback = <String>[];
    for (final creator in creators) {
      if (creator is! Map) continue;
      final name = nameOf(creator);
      if (name == null) continue;
      if (creator['creatorType'] == 'author') {
        authors.add(name);
      } else {
        fallback.add(name);
      }
    }
    return authors.isNotEmpty ? authors : fallback;
  }

  /// 按 itemType 把"刊名/出版商"归一到 [Document.journal] 单字段。
  static String? _container(String itemType, Map data) {
    String? pick(String key) {
      final value = (data[key] as String?)?.trim();
      return (value != null && value.isNotEmpty) ? value : null;
    }

    return switch (itemType) {
      'journalArticle' => pick('publicationTitle'),
      'conferencePaper' => pick('proceedingsTitle') ?? pick('publicationTitle'),
      'bookSection' => pick('bookTitle') ?? pick('publisher'),
      'book' => pick('publisher'),
      'preprint' => pick('repository') ?? pick('publicationTitle'),
      _ => pick('publicationTitle') ?? pick('publisher'),
    };
  }

  /// Zotero `date` 为自由文本，抽取首个 4 位年份。
  static String? _year(String? date) {
    if (date == null) return null;
    return RegExp(r'\d{4}').firstMatch(date)?.group(0);
  }

  /// tags → keywords，去重保序。
  static List<String> _tags(dynamic tags) {
    if (tags is! List) return const [];
    final result = <String>[];
    final seen = <String>{};
    for (final entry in tags) {
      if (entry is! Map) continue;
      final tag = (entry['tag'] as String?)?.trim();
      if (tag == null || tag.isEmpty) continue;
      if (seen.add(tag.toLowerCase())) result.add(tag);
    }
    return result;
  }
}
