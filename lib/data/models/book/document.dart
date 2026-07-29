/// 文献元数据模型，仅保留阅读与检索所需的核心字段。
class Document {
  final String id;
  final String title;
  final List<String> authors;
  final String? journal;
  final String? year;
  final String? doi;

  /// 关键词列表。PubMed 路径填充为 MeSH Descriptor + 作者 Keyword 合集，
  /// 其他路径暂时为空，后续可用快速模型基于 abstract 抽取填充。
  final List<String> keywords;

  /// 当前绑定 PDF 的内容指纹。为 null 时表示只有元数据、尚无本地 PDF。
  final String? contentHash;

  final DateTime addedAt;

  const Document({
    required this.id,
    required this.title,
    required this.authors,
    this.journal,
    this.year,
    this.doi,
    this.keywords = const [],
    this.contentHash,
    required this.addedAt,
  });

  Document copyWith({
    String? id,
    String? title,
    List<String>? authors,
    String? journal,
    String? year,
    String? doi,
    List<String>? keywords,
    Object? contentHash = _sentinel,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      journal: journal ?? this.journal,
      year: year ?? this.year,
      doi: doi ?? this.doi,
      keywords: keywords ?? this.keywords,
      contentHash: identical(contentHash, _sentinel)
          ? this.contentHash
          : contentHash as String?,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'authors': authors,
    'journal': journal,
    'year': year,
    'doi': doi,
    'keywords': keywords,
    'contentHash': contentHash,
    'addedAt': addedAt.toIso8601String(),
  };

  factory Document.fromJson(Map<String, dynamic> json) {
    final rawAuthors = json['authors'] as List<dynamic>?;
    final authors = rawAuthors == null
        ? <String>[]
        : rawAuthors
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
    final rawKeywords = json['keywords'] as List<dynamic>?;
    final keywords = rawKeywords == null
        ? <String>[]
        : rawKeywords
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
    final journal = (json['journal'] as String?)?.trim();
    final contentHash = (json['contentHash'] as String?)?.trim();

    return Document(
      id: json['id'] as String,
      title: (json['title'] as String? ?? '').trim(),
      authors: authors,
      journal: (journal != null && journal.isNotEmpty) ? journal : null,
      year: (json['year'] as String?)?.trim(),
      doi: (json['doi'] as String?)?.trim(),
      keywords: keywords,
      contentHash: contentHash == null || contentHash.isEmpty
          ? null
          : contentHash,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

}

const _sentinel = Object();
