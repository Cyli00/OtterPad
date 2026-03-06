/// 文献元数据模型
class Document {
  final String id;
  final String title;
  final List<String> authors;
  final String? journal;
  final String? year;
  final String? doi;
  final String filePath;
  final DateTime addedAt;

  const Document({
    required this.id,
    required this.title,
    required this.authors,
    this.journal,
    this.year,
    this.doi,
    required this.filePath,
    required this.addedAt,
  });

  Document copyWith({
    String? title,
    List<String>? authors,
    String? journal,
    String? year,
    String? doi,
    String? filePath,
  }) {
    return Document(
      id: id,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      journal: journal ?? this.journal,
      year: year ?? this.year,
      doi: doi ?? this.doi,
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
        'filePath': filePath,
        'addedAt': addedAt.toIso8601String(),
      };

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        id: json['id'] as String,
        title: json['title'] as String,
        authors: (json['authors'] as List<dynamic>).cast<String>(),
        journal: json['journal'] as String?,
        year: json['year'] as String?,
        doi: json['doi'] as String?,
        filePath: json['filePath'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );

  /// 判断是否匹配搜索关键词
  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    if (authors.any((a) => a.toLowerCase().contains(q))) return true;
    if (journal != null && journal!.toLowerCase().contains(q)) return true;
    if (doi != null && doi!.toLowerCase().contains(q)) return true;
    return false;
  }
}
