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
  final String filePath;
  final DateTime addedAt;

  const Document({
    required this.id,
    required this.title,
    required this.authors,
    this.journal,
    this.year,
    this.doi,
    this.keywords = const [],
    required this.filePath,
    required this.addedAt,
  });

  Document copyWith({
    String? title,
    List<String>? authors,
    String? journal,
    String? year,
    String? doi,
    List<String>? keywords,
    String? filePath,
  }) {
    return Document(
      id: id,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      journal: journal ?? this.journal,
      year: year ?? this.year,
      doi: doi ?? this.doi,
      keywords: keywords ?? this.keywords,
      filePath: filePath ?? this.filePath,
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
    'filePath': filePath,
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
    final legacyPublisher = (json['publisher'] as String?)?.trim();
    final journal = (json['journal'] as String?)?.trim();

    return Document(
      id: json['id'] as String,
      title: (json['title'] as String? ?? '').trim(),
      authors: authors,
      journal: (journal != null && journal.isNotEmpty)
          ? journal
          : (legacyPublisher != null && legacyPublisher.isNotEmpty
                ? legacyPublisher
                : null),
      year: (json['year'] as String?)?.trim(),
      doi: (json['doi'] as String?)?.trim(),
      keywords: keywords,
      filePath: (json['filePath'] as String? ?? '').trim(),
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  /// 判断是否匹配搜索关键词。
  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    if (authors.any((a) => a.toLowerCase().contains(q))) return true;
    if (journal != null && journal!.toLowerCase().contains(q)) return true;
    if (year != null && year!.contains(q)) return true;
    if (doi != null && doi!.toLowerCase().contains(q)) return true;
    if (keywords.any((k) => k.toLowerCase().contains(q))) return true;
    return false;
  }
}
