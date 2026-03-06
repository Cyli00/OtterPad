/// 文献元数据模型（对标 Zotero Info 面板）
class Document {
  final String id;

  // ── 基本信息 ──
  final String itemType; // journalArticle / book / preprint / bookSection
  final String title;
  final List<String> authors;

  // ── 期刊/出版信息 ──
  final String? journal; // Publication（期刊名）
  final String? journalAbbr; // Journal Abbr（期刊缩写）
  final String? publisher;
  final String? volume;
  final String? issue;
  final String? pages;

  // ── 日期 ──
  final String? year;
  final String? date; // 完整日期，如 "2002-04-30"

  // ── 标识符 ──
  final String? doi;
  final String? pmid;
  final String? pmcid;
  final String? arxivId;
  final String? isbn;
  final String? issn;
  final String? url;

  // ── 附加信息 ──
  final String? abstractText; // 摘要
  final String? language;

  // ── 系统字段 ──
  final String filePath;
  final DateTime addedAt;

  const Document({
    required this.id,
    this.itemType = 'journalArticle',
    required this.title,
    required this.authors,
    this.journal,
    this.journalAbbr,
    this.publisher,
    this.volume,
    this.issue,
    this.pages,
    this.year,
    this.date,
    this.doi,
    this.pmid,
    this.pmcid,
    this.arxivId,
    this.isbn,
    this.issn,
    this.url,
    this.abstractText,
    this.language,
    required this.filePath,
    required this.addedAt,
  });

  Document copyWith({
    String? itemType,
    String? title,
    List<String>? authors,
    String? journal,
    String? journalAbbr,
    String? publisher,
    String? volume,
    String? issue,
    String? pages,
    String? year,
    String? date,
    String? doi,
    String? pmid,
    String? pmcid,
    String? arxivId,
    String? isbn,
    String? issn,
    String? url,
    String? abstractText,
    String? language,
    String? filePath,
  }) {
    return Document(
      id: id,
      itemType: itemType ?? this.itemType,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      journal: journal ?? this.journal,
      journalAbbr: journalAbbr ?? this.journalAbbr,
      publisher: publisher ?? this.publisher,
      volume: volume ?? this.volume,
      issue: issue ?? this.issue,
      pages: pages ?? this.pages,
      year: year ?? this.year,
      date: date ?? this.date,
      doi: doi ?? this.doi,
      pmid: pmid ?? this.pmid,
      pmcid: pmcid ?? this.pmcid,
      arxivId: arxivId ?? this.arxivId,
      isbn: isbn ?? this.isbn,
      issn: issn ?? this.issn,
      url: url ?? this.url,
      abstractText: abstractText ?? this.abstractText,
      language: language ?? this.language,
      filePath: filePath ?? this.filePath,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemType': itemType,
        'title': title,
        'authors': authors,
        'journal': journal,
        'journalAbbr': journalAbbr,
        'publisher': publisher,
        'volume': volume,
        'issue': issue,
        'pages': pages,
        'year': year,
        'date': date,
        'doi': doi,
        'pmid': pmid,
        'pmcid': pmcid,
        'arxivId': arxivId,
        'isbn': isbn,
        'issn': issn,
        'url': url,
        'abstractText': abstractText,
        'language': language,
        'filePath': filePath,
        'addedAt': addedAt.toIso8601String(),
      };

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        id: json['id'] as String,
        itemType: json['itemType'] as String? ?? 'journalArticle',
        title: json['title'] as String,
        authors: (json['authors'] as List<dynamic>).cast<String>(),
        journal: json['journal'] as String?,
        journalAbbr: json['journalAbbr'] as String?,
        publisher: json['publisher'] as String?,
        volume: json['volume'] as String?,
        issue: json['issue'] as String?,
        pages: json['pages'] as String?,
        year: json['year'] as String?,
        date: json['date'] as String?,
        doi: json['doi'] as String?,
        pmid: json['pmid'] as String?,
        pmcid: json['pmcid'] as String?,
        arxivId: json['arxivId'] as String?,
        isbn: json['isbn'] as String?,
        issn: json['issn'] as String?,
        url: json['url'] as String?,
        abstractText: json['abstractText'] as String?,
        language: json['language'] as String?,
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
    if (pmid != null && pmid!.contains(q)) return true;
    if (arxivId != null && arxivId!.toLowerCase().contains(q)) return true;
    if (isbn != null && isbn!.contains(q)) return true;
    if (publisher != null && publisher!.toLowerCase().contains(q)) return true;
    if (abstractText != null && abstractText!.toLowerCase().contains(q)) {
      return true;
    }
    return false;
  }
}
