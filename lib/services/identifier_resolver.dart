import 'package:dio/dio.dart';
import 'proxy_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../data/models/book/document.dart';
import 'identifier_parser.dart';
import 'metadata_names.dart';
import '../core/app_logger.dart';

/// 标识符解析过程中抛出的异常。
class IdentifierResolveException implements Exception {
  final String message;
  const IdentifierResolveException(this.message);

  @override
  String toString() => message;
}

/// 标识符解析器，通过公开 API 将 DOI/PMID/arXiv/ISBN 解析为 Document。
class IdentifierResolver {
  IdentifierResolver._();
  static final IdentifierResolver instance = IdentifierResolver._();

  static final RegExp _elifeDoiRegExp = RegExp(
    r'^10\.7554/elife\.(\d+)(?:\.\d+)?$',
    caseSensitive: false,
  );

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'OtterPad/0.1 (Flutter; mailto:dev@otterpad.app)',
      },
    ),
  );

  /// 更新代理配置，后续 Dio 发出的 HTTP 请求会走该代理。
  ///
  /// [mode] 接受 ProxyMode 枚举的任意子类，通过 name 属性匹配模式（便于跨包传递）。
  void applyProxy(Enum mode, String host, int port) {
    _dio.httpClientAdapter = buildProxyAdapter(
      mode.name,
      host,
      port,
    );
  }

  /// 测试网络连通性，返回请求耗时（毫秒）。
  Future<int> testConnectivity(String url, {CancelToken? cancelToken}) async {
    final sw = Stopwatch()..start();
    await _dio.head(url, cancelToken: cancelToken);
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  /// 解析标识符字符串，返回填充了元数据的 Document。
  ///
  /// 只负责元数据；PDF 获取见 [PdfFetchService]。
  Future<Document> resolve(String rawInput, {CancelToken? cancelToken}) async {
    final parsed = IdentifierParser.parse(rawInput);

    switch (parsed.type) {
      case IdentifierType.doi:
        // arXiv 规范 DataCite DOI（10.48550/arxiv.*）CrossRef/Unpaywall 均未
        // 收录，路由到 arXiv API；旧式 ID 的规范 DOI 不含子类别，须经 doi.org
        // 重定向拿回完整 ID。
        if (_isArxivCanonicalDoi(parsed.value)) {
          final arxivId = await _arxivIdFromDoiRedirect(
            parsed.value,
            cancelToken: cancelToken,
          );
          if (arxivId == null) {
            throw const IdentifierResolveException('未找到该标识符对应的文献');
          }
          return _resolveArxiv(arxivId, cancelToken: cancelToken);
        }
        return _resolveDoi(parsed.value, cancelToken: cancelToken);
      case IdentifierType.pmid:
        return _resolvePmid(parsed.value, cancelToken: cancelToken);
      case IdentifierType.arxiv:
        return _resolveArxiv(parsed.value, cancelToken: cancelToken);
      case IdentifierType.isbn:
        return _resolveIsbn(parsed.value, cancelToken: cancelToken);
      case IdentifierType.unknown:
        throw const IdentifierResolveException('未找到该标识符对应的文献');
    }
  }

  // ─── DOI → CrossRef REST API ─────────────────────────────────────────────

  Future<Document> _resolveDoi(
    String doi, {
    CancelToken? cancelToken,
  }) async {
    final normalizedDoiForMetadata = normalizeElifeDoiForMetadata(doi);
    final elifeArticleId = _extractElifeArticleId(normalizedDoiForMetadata);
    if (elifeArticleId != null) {
      try {
        return await _resolveElifeArticle(
          articleId: elifeArticleId,
          doi: normalizedDoiForMetadata,
          cancelToken: cancelToken,
        );
      } catch (e) {
        log.d('eLife API 解析失败，回退 Crossref: $e');
      }
    }

    try {
      final resp = await _dio.get(
        'https://api.crossref.org/works/${_encodeDoiPathSegment(normalizedDoiForMetadata)}',
        queryParameters: {'mailto': 'dev@otterpad.app'},
        cancelToken: cancelToken,
      );
      final msg = resp.data['message'] as Map<String, dynamic>;

      final title = _extractFirst(msg['title']) ?? normalizedDoiForMetadata;
      final authors = _extractCrossRefAuthors(msg['author']);
      final journal =
          _extractFirst(msg['container-title']) ??
          _extractFirst(msg['short-container-title']);
      final year = _extractCrossRefYear(msg);
      final resolvedDoi = (msg['DOI'] as String? ?? normalizedDoiForMetadata)
          .toLowerCase();

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        authors: authors,
        journal: journal,
        year: year,
        doi: resolvedDoi,
        addedAt: DateTime.now(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      log.e('DOI 解析失败', error: e, stackTrace: st);
      throw IdentifierResolveException('解析 DOI 时发生错误: $e');
    }
  }

  Future<Document> _resolveElifeArticle({
    required String articleId,
    required String doi,
    CancelToken? cancelToken,
  }) async {
    final resp = await _dio.get(
      'https://api.elifesciences.org/articles/$articleId',
      cancelToken: cancelToken,
    );
    final data = resp.data as Map<String, dynamic>;

    final title = (data['title'] as String?)?.trim();
    final resolvedTitle = title == null || title.isEmpty ? doi : title;
    final authors = _extractElifeAuthors(data['authors'], data['authorLine']);
    final year = _extractYearFromString(data['published'] as String?);
    final resolvedDoi =
        IdentifierParser.normalizeDoi(data['doi'] as String?)?.toLowerCase() ??
        doi.toLowerCase();
    final keywords = _extractElifeKeywords(data['keywords'], data['subjects']);

    return Document(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: resolvedTitle,
      authors: authors,
      journal: 'eLife',
      year: year,
      doi: resolvedDoi,
      keywords: keywords,
      addedAt: DateTime.now(),
    );
  }

  Future<Document> _resolvePmid(
    String pmid, {
    CancelToken? cancelToken,
  }) async {
    try {
      // 切换到 efetch XML 接口：esummary 不返回 MeSH / KeywordList，
      // 只有 efetch 能拿到受控主题词，用于后续的推荐算法。
      final resp = await _dio.get(
        'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi',
        queryParameters: {'db': 'pubmed', 'id': pmid, 'retmode': 'xml'},
        options: Options(responseType: ResponseType.plain),
        cancelToken: cancelToken,
      );

      final xmlDoc = XmlDocument.parse(resp.data as String);
      final articleNode = xmlDoc.findAllElements('PubmedArticle').firstOrNull;
      if (articleNode == null) {
        throw const IdentifierResolveException('未找到该标识符对应的文献');
      }
      final medline = articleNode.findElements('MedlineCitation').firstOrNull;
      final articleEl = medline?.findElements('Article').firstOrNull;
      if (articleEl == null) {
        throw const IdentifierResolveException('未找到该标识符对应的文献');
      }

      final title =
          articleEl
              .findElements('ArticleTitle')
              .firstOrNull
              ?.innerText
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim()
              .replaceFirst(RegExp(r'\.$'), '') ??
          pmid;

      // 作者：优先 ForeName + LastName，否则 Initials + LastName，兜底 CollectiveName
      final authors = <String>[];
      final authorList = articleEl.findElements('AuthorList').firstOrNull;
      if (authorList != null) {
        for (final author in authorList.findElements('Author')) {
          final lastName = author
              .findElements('LastName')
              .firstOrNull
              ?.innerText
              .trim();
          final foreName = author
              .findElements('ForeName')
              .firstOrNull
              ?.innerText
              .trim();
          final initials = author
              .findElements('Initials')
              .firstOrNull
              ?.innerText
              .trim();
          final collective = author
              .findElements('CollectiveName')
              .firstOrNull
              ?.innerText
              .trim();
          if (lastName != null && lastName.isNotEmpty) {
            final given = (foreName != null && foreName.isNotEmpty)
                ? foreName
                : initials;
            authors.add(MetadataNames.formatPersonName(given, lastName));
          } else if (collective != null && collective.isNotEmpty) {
            authors.add(collective);
          }
        }
      }

      final journalEl = articleEl.findElements('Journal').firstOrNull;
      final journal =
          journalEl?.findElements('Title').firstOrNull?.innerText.trim() ??
          journalEl
              ?.findElements('ISOAbbreviation')
              .firstOrNull
              ?.innerText
              .trim();

      // 年份：优先 <Year>，否则从 <MedlineDate> 文本里抓 4 位数字
      final pubDate = journalEl
          ?.findElements('JournalIssue')
          .firstOrNull
          ?.findElements('PubDate')
          .firstOrNull;
      String? year = pubDate
          ?.findElements('Year')
          .firstOrNull
          ?.innerText
          .trim();
      if ((year == null || year.isEmpty) && pubDate != null) {
        final medlineDate = pubDate
            .findElements('MedlineDate')
            .firstOrNull
            ?.innerText;
        year = _extractYearFromString(medlineDate);
      }

      // DOI 在 PubmedData/ArticleIdList 下
      String? doi;
      final articleIds = articleNode
          .findElements('PubmedData')
          .firstOrNull
          ?.findElements('ArticleIdList')
          .firstOrNull;
      if (articleIds != null) {
        for (final aid in articleIds.findElements('ArticleId')) {
          if (aid.getAttribute('IdType') != 'doi') continue;
          final value = aid.innerText.trim();
          if (value.isNotEmpty) doi = value;
        }
      }
      final normalizedDoi = doi?.toLowerCase();

      // MeSH Descriptor + 作者 KeywordList，合并去重保留顺序
      final keywords = <String>[];
      final seenKeywords = <String>{};
      void addKeyword(String? value) {
        if (value == null) return;
        final trimmed = value.trim();
        if (trimmed.isEmpty) return;
        final lower = trimmed.toLowerCase();
        if (seenKeywords.add(lower)) keywords.add(trimmed);
      }

      final meshList = medline?.findElements('MeshHeadingList').firstOrNull;
      if (meshList != null) {
        for (final heading in meshList.findElements('MeshHeading')) {
          addKeyword(
            heading.findElements('DescriptorName').firstOrNull?.innerText,
          );
        }
      }
      final kwLists =
          medline?.findElements('KeywordList') ?? const <XmlElement>[];
      for (final kwList in kwLists) {
        for (final kw in kwList.findElements('Keyword')) {
          addKeyword(kw.innerText);
        }
      }

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        authors: authors,
        journal: journal,
        year: year,
        doi: normalizedDoi,
        keywords: keywords,
        addedAt: DateTime.now(),
      );
    } on IdentifierResolveException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      log.e('PMID 解析失败', error: e, stackTrace: st);
      throw IdentifierResolveException('解析 PMID 时发生错误: $e');
    }
  }

  Future<Document> _resolveArxiv(
    String arxivId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final resp = await _dio.get(
        'https://export.arxiv.org/api/query',
        queryParameters: {'id_list': arxivId},
        cancelToken: cancelToken,
      );

      final xmlDoc = XmlDocument.parse(resp.data as String);
      final entry = xmlDoc.findAllElements('entry').firstOrNull;
      if (entry == null) {
        throw const IdentifierResolveException('未找到该标识符对应的文献');
      }

      final idText = entry.findElements('id').firstOrNull?.innerText ?? '';
      if (idText.isEmpty) {
        throw const IdentifierResolveException('未找到该标识符对应的文献');
      }

      final title =
          entry
              .findElements('title')
              .firstOrNull
              ?.innerText
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          arxivId;
      final authors = entry
          .findElements('author')
          .map(
            (author) =>
                author.findElements('name').firstOrNull?.innerText ?? '',
          )
          .where((name) => name.isNotEmpty)
          .toList();
      final journal = entry
          .findAllElements('journal_ref')
          .firstOrNull
          ?.innerText
          .trim();
      final published = entry.findElements('published').firstOrNull?.innerText;
      final year = published != null && published.length >= 4
          ? published.substring(0, 4)
          : null;
      // arXiv API 仅在论文已有正式 DOI 时返回 <arxiv:doi>；缺失时用 arXiv
      // 规范 DataCite DOI 兜底，保证 PDF 拉取统一走 DOI 下载管道。
      final doi =
          entry
              .findAllElements('doi')
              .firstOrNull
              ?.innerText
              .trim()
              .toLowerCase() ??
          arxivCanonicalDoi(arxivId);

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        authors: authors,
        journal: journal,
        year: year,
        doi: doi,
        addedAt: DateTime.now(),
      );
    } on IdentifierResolveException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      log.e('arXiv 解析失败', error: e, stackTrace: st);
      throw IdentifierResolveException('解析 arXiv 时发生错误: $e');
    }
  }

  Future<Document> _resolveIsbn(String isbn, {CancelToken? cancelToken}) async {
    try {
      final resp = await _dio.get(
        'https://openlibrary.org/isbn/$isbn.json',
        cancelToken: cancelToken,
      );
      final data = resp.data as Map<String, dynamic>;

      final title = data['title'] as String? ?? isbn;
      final publishers = data['publishers'] as List?;
      final publisher = publishers != null && publishers.isNotEmpty
          ? publishers.first as String?
          : null;
      final publishDate = data['publish_date'] as String?;
      final year = _extractYearFromString(publishDate);

      final authors = <String>[];
      final authorKeys = data['authors'] as List?;
      if (authorKeys != null) {
        final limit = authorKeys.length > 5 ? 5 : authorKeys.length;
        for (int i = 0; i < limit; i++) {
          final authorKey =
              (authorKeys[i] as Map<String, dynamic>)['key'] as String?;
          if (authorKey != null) {
            try {
              final authorResp = await _dio.get(
                'https://openlibrary.org$authorKey.json',
                cancelToken: cancelToken,
              );
              final name = authorResp.data['name'] as String?;
              if (name != null) authors.add(name);
            } catch (_) {}
          }
        }
      }

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        authors: authors,
        journal: publisher,
        year: year,
        addedAt: DateTime.now(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      log.e('ISBN 解析失败', error: e, stackTrace: st);
      throw IdentifierResolveException('解析 ISBN 时发生错误: $e');
    }
  }

  // ─── arXiv 规范 DOI ─────────────────────────────────────────────────────

  /// 判断是否为 arXiv 规范 DataCite DOI（10.48550/arxiv.*）。
  static bool _isArxivCanonicalDoi(String doi) {
    return RegExp(
      r'^10\.48550/arxiv\..+$',
      caseSensitive: false,
    ).hasMatch(doi.trim());
  }

  /// arXiv 规范 DataCite DOI（无版本号），如 10.48550/arxiv.2412.14135。
  /// 旧式 ID 的规范 DOI 不含子类别：math.GT/0309136 → 10.48550/arxiv.math/0309136。
  @visibleForTesting
  static String? arxivCanonicalDoi(String arxivId) {
    var clean = arxivId.trim().replaceFirst(
      RegExp(r'v\d+$', caseSensitive: false),
      '',
    );
    if (clean.isEmpty) return null;
    // 旧式 ID（archive[/subcategory]/number）丢弃子类别段
    final slashIdx = clean.indexOf('/');
    if (slashIdx > 0) {
      final archive = clean.substring(0, slashIdx).split('.').first;
      clean = '$archive${clean.substring(slashIdx)}';
    }
    return '10.48550/arxiv.${clean.toLowerCase()}';
  }

  /// 经 doi.org 重定向把 arXiv 规范 DOI 解析为完整 arXiv ID，失败返回 null。
  Future<String?> _arxivIdFromDoiRedirect(
    String doi, {
    CancelToken? cancelToken,
  }) async {
    try {
      final resp = await _dio.head(
        _doiUrl(doi),
        options: Options(
          followRedirects: true,
          maxRedirects: 10,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
        cancelToken: cancelToken,
      );
      final match = RegExp(r'^/abs/(.+)$').firstMatch(resp.realUri.path);
      return match?.group(1);
    } catch (e) {
      log.d('arXiv 规范 DOI 重定向解析失败: $e');
      return null;
    }
  }

  String _doiUrl(String doi) {
    return 'https://doi.org/${_encodeDoiPathSegment(doi)}';
  }

  String _encodeDoiPathSegment(String doi) {
    return Uri.encodeComponent(doi);
  }

  // ─── 元数据提取工具 ───────────────────────────────────────────────────────

  @visibleForTesting
  static String normalizeElifeDoiForMetadata(String doi) {
    final trimmed = doi.trim();
    final match = _elifeDoiRegExp.firstMatch(trimmed);
    if (match == null) return trimmed;
    return '10.7554/elife.${match.group(1)}';
  }

  static String? _extractElifeArticleId(String doi) {
    return _elifeDoiRegExp.firstMatch(doi.trim())?.group(1);
  }

  String? _extractFirst(dynamic list) {
    if (list is List && list.isNotEmpty) return list.first.toString();
    return null;
  }

  List<String> _extractCrossRefAuthors(dynamic authorList) {
    if (authorList is! List) return [];
    return authorList
        .map((author) {
          final map = author as Map<String, dynamic>;
          return MetadataNames.formatPersonName(
            map['given'] as String?,
            map['family'] as String?,
          );
        })
        .where((name) => name.isNotEmpty)
        .toList();
  }

  List<String> _extractElifeAuthors(dynamic authorList, dynamic authorLine) {
    final authors = <String>[];
    if (authorList is List) {
      for (final author in authorList) {
        if (author is! Map) continue;
        final name = author['name'];
        if (name is Map) {
          final preferred = name['preferred']?.toString().trim();
          if (preferred != null && preferred.isNotEmpty) {
            authors.add(preferred);
          }
        }
      }
    }

    if (authors.isNotEmpty) return authors;
    if (authorLine is! String || authorLine.trim().isEmpty) return authors;
    return MetadataNames.splitAuthorLine(authorLine);
  }

  List<String> _extractElifeKeywords(dynamic keywordList, dynamic subjectList) {
    final keywords = <String>[];
    final seen = <String>{};

    void addKeyword(String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (seen.add(trimmed.toLowerCase())) keywords.add(trimmed);
    }

    if (keywordList is List) {
      for (final keyword in keywordList) {
        addKeyword(keyword?.toString());
      }
    }

    if (subjectList is List) {
      for (final subject in subjectList) {
        if (subject is Map) {
          addKeyword(subject['name']?.toString());
        }
      }
    }

    return keywords;
  }

  String? _extractCrossRefYear(Map<String, dynamic> msg) {
    for (final key in ['published-print', 'published-online', 'published']) {
      final published = msg[key];
      if (published is Map && published['date-parts'] is List) {
        final parts = published['date-parts'] as List;
        if (parts.isNotEmpty && parts.first is List) {
          final year = (parts.first as List).firstOrNull;
          if (year != null) return year.toString();
        }
      }
    }
    return null;
  }

  String? _extractYearFromString(String? text) {
    if (text == null) return null;
    final match = RegExp(r'\d{4}').firstMatch(text);
    return match?.group(0);
  }

  IdentifierResolveException _handleDioError(DioException e) {
    if (CancelToken.isCancel(e)) throw e;
    if (e.response?.statusCode == 404) {
      return const IdentifierResolveException('未找到该标识符对应的文献');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const IdentifierResolveException('网络连接失败，请检查网络');
    }
    return const IdentifierResolveException('网络请求失败，请稍后重试');
  }
}
