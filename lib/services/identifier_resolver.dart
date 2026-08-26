import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../core/storage/storage.dart';
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
    final adapter = IOHttpClientAdapter();
    switch (mode.name) {
      case 'custom':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY $host:$port';
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        };
      case 'system':
        adapter.createHttpClient = () => HttpClient();
      case 'none':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'DIRECT';
          return client;
        };
    }
    _dio.httpClientAdapter = adapter;
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
  /// [metadataOnly] 为 true 时仅获取元数据，不尝试下载 PDF。
  Future<Document> resolve(
    String rawInput, {
    bool metadataOnly = false,
    CancelToken? cancelToken,
  }) async {
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
          return _resolveArxiv(
            arxivId,
            metadataOnly: metadataOnly,
            cancelToken: cancelToken,
          );
        }
        return _resolveDoi(
          parsed.value,
          metadataOnly: metadataOnly,
          cancelToken: cancelToken,
        );
      case IdentifierType.pmid:
        return _resolvePmid(
          parsed.value,
          metadataOnly: metadataOnly,
          cancelToken: cancelToken,
        );
      case IdentifierType.arxiv:
        return _resolveArxiv(
          parsed.value,
          metadataOnly: metadataOnly,
          cancelToken: cancelToken,
        );
      case IdentifierType.isbn:
        return _resolveIsbn(parsed.value, cancelToken: cancelToken);
      case IdentifierType.unknown:
        throw const IdentifierResolveException('未找到该标识符对应的文献');
    }
  }

  // ─── DOI → CrossRef REST API ─────────────────────────────────────────────

  Future<Document> _resolveDoi(
    String doi, {
    bool metadataOnly = false,
    CancelToken? cancelToken,
  }) async {
    final normalizedDoiForMetadata = normalizeElifeDoiForMetadata(doi);
    final elifeArticleId = _extractElifeArticleId(normalizedDoiForMetadata);
    if (elifeArticleId != null) {
      try {
        return await _resolveElifeArticle(
          articleId: elifeArticleId,
          doi: normalizedDoiForMetadata,
          metadataOnly: metadataOnly,
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

      String filePath = '';
      if (!metadataOnly) {
        try {
          filePath = await _tryPublisherPdf(
            doi: resolvedDoi,
            year: year,
            authors: authors,
            title: title,
            fallbackId: normalizedDoiForMetadata.replaceAll('/', '_'),
            cancelToken: cancelToken,
          );
        } catch (e) {
          log.d('出版商 PDF 下载失败: $e');
        }

        if (filePath.isEmpty) {
          try {
            final unpaywallResponse = await _dio.get(
              'https://api.unpaywall.org/v2/${_encodeDoiPathSegment(normalizedDoiForMetadata)}',
              queryParameters: {'email': 'dev@otterpad.app'},
              cancelToken: cancelToken,
            );
            final bestOa =
                (unpaywallResponse.data
                    as Map<String, dynamic>)['best_oa_location'];
            final pdfUrl =
                (bestOa as Map<String, dynamic>?)?['url_for_pdf'] as String?;
            if (pdfUrl != null && pdfUrl.isNotEmpty) {
              filePath = await _downloadPdf(
                url: pdfUrl,
                year: year,
                authors: authors,
                title: title,
                fallbackId: normalizedDoiForMetadata.replaceAll('/', '_'),
                cancelToken: cancelToken,
              );
            }
          } catch (e) {
            log.d('Unpaywall PDF 下载失败: $e');
          }
        }
      }

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
    bool metadataOnly = false,
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

    if (!metadataOnly) {
      final pdfUrl = data['pdf'] as String?;
      if (pdfUrl != null && pdfUrl.isNotEmpty) {
        try {
          await _downloadPdf(
            url: pdfUrl,
            year: year,
            authors: authors,
            title: resolvedTitle,
            fallbackId: articleId,
            cancelToken: cancelToken,
          );
        } catch (e) {
          log.d('eLife PDF 下载失败: $e');
        }
      }
    }

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
    bool metadataOnly = false,
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

      // DOI + PMCID 在 PubmedData/ArticleIdList 下
      String? doi;
      String? pmcid;
      final articleIds = articleNode
          .findElements('PubmedData')
          .firstOrNull
          ?.findElements('ArticleIdList')
          .firstOrNull;
      if (articleIds != null) {
        for (final aid in articleIds.findElements('ArticleId')) {
          final idType = aid.getAttribute('IdType');
          final value = aid.innerText.trim();
          if (value.isEmpty) continue;
          if (idType == 'doi') doi = value;
          if (idType == 'pmc') pmcid = value;
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

      String filePath = '';
      if (!metadataOnly) {
        if (normalizedDoi != null && normalizedDoi.isNotEmpty) {
          try {
            filePath = await _tryPublisherPdf(
              doi: normalizedDoi,
              year: year,
              authors: authors,
              title: title,
              fallbackId: pmid,
              cancelToken: cancelToken,
            );
          } catch (e) {
            log.d('出版商 PDF 下载失败: $e');
          }
        }

        if (filePath.isEmpty && pmcid != null && pmcid.isNotEmpty) {
          try {
            filePath = await _downloadPdf(
              url: _pmcPdfUrl(pmcid),
              year: year,
              authors: authors,
              title: title,
              fallbackId: pmid,
              cancelToken: cancelToken,
            );
          } catch (e) {
            log.d('PMC PDF 下载失败: $e');
          }
        }

        if (filePath.isEmpty &&
            normalizedDoi != null &&
            normalizedDoi.isNotEmpty) {
          try {
            final unpaywallResponse = await _dio.get(
              'https://api.unpaywall.org/v2/${_encodeDoiPathSegment(normalizedDoi)}',
              queryParameters: {'email': 'dev@otterpad.app'},
              cancelToken: cancelToken,
            );
            final bestOa =
                (unpaywallResponse.data
                    as Map<String, dynamic>)['best_oa_location'];
            final pdfUrl =
                (bestOa as Map<String, dynamic>?)?['url_for_pdf'] as String?;
            if (pdfUrl != null && pdfUrl.isNotEmpty) {
              filePath = await _downloadPdf(
                url: pdfUrl,
                year: year,
                authors: authors,
                title: title,
                fallbackId: pmid,
                cancelToken: cancelToken,
              );
            }
          } catch (e) {
            log.d('Unpaywall PDF 下载失败: $e');
          }
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
    bool metadataOnly = false,
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

      if (!metadataOnly) {
        try {
          await _downloadPdf(
            url: 'https://arxiv.org/pdf/$arxivId.pdf',
            year: year,
            authors: authors,
            title: title,
            fallbackId: arxivId.replaceAll('/', '_'),
            cancelToken: cancelToken,
          );
        } catch (e) {
          log.d('arXiv PDF 下载失败: $e');
        }
      }

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

  // ─── 根据 DOI 下载 PDF ────────────────────────────────────────────────────

  Future<String> downloadPdfByDoi({
    required String doi,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    String? targetPath,
    CancelToken? cancelToken,
  }) async {
    String filePath = '';

    // 步骤 1: 出版商直接获取（DOI 重定向 + URL 模式）
    try {
      filePath = await _tryPublisherPdf(
        doi: doi,
        year: year,
        authors: authors,
        title: title,
        fallbackId: fallbackId,
        targetPath: targetPath,
        cancelToken: cancelToken,
      );
    } catch (e) {
      log.d('出版商 PDF 下载失败: $e');
    }
    if (filePath.isNotEmpty) return filePath;

    // 步骤 2: Unpaywall 开放获取
    try {
      final uResp = await _dio.get(
        'https://api.unpaywall.org/v2/${_encodeDoiPathSegment(doi)}',
        queryParameters: {'email': 'dev@otterpad.app'},
        cancelToken: cancelToken,
      );
      final bestOa = (uResp.data as Map<String, dynamic>)['best_oa_location'];
      final pdfUrl =
          (bestOa as Map<String, dynamic>?)?['url_for_pdf'] as String?;
      if (pdfUrl != null && pdfUrl.isNotEmpty) {
        filePath = await _downloadPdf(
          url: pdfUrl,
          year: year,
          authors: authors,
          title: title,
          fallbackId: fallbackId,
          targetPath: targetPath,
          cancelToken: cancelToken,
        );
      }
    } catch (e) {
      log.d('Unpaywall PDF 下载失败: $e');
    }
    if (filePath.isNotEmpty) return filePath;

    // 步骤 3: Sci-Hub 兜底
    try {
      final sResp = await _dio.get(
        'https://sci-hub.se/${_encodeDoiPathSegment(doi)}',
        cancelToken: cancelToken,
      );
      final html = sResp.data as String;
      // 提取 <embed src="..."> 或 <iframe src="...">
      final embedMatch =
          RegExp(
            r'<embed[^>]+src="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(html) ??
          RegExp(
            r'<iframe[^>]+src="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(html);

      if (embedMatch != null) {
        var pdfUrl = embedMatch.group(1)!;
        if (pdfUrl.startsWith('//')) {
          pdfUrl = 'https:$pdfUrl';
        } else if (pdfUrl.startsWith('/')) {
          pdfUrl = 'https://sci-hub.se$pdfUrl';
        }
        filePath = await _downloadPdf(
          url: pdfUrl,
          year: year,
          authors: authors,
          title: title,
          fallbackId: fallbackId,
          targetPath: targetPath,
          cancelToken: cancelToken,
        );
      }
    } catch (e) {
      log.d('Sci-Hub PDF 下载失败: $e');
    }

    return filePath;
  }

  // ─── 根据 PMID 下载 PDF（PMC 开放获取兜底） ───────────────────────────────

  /// Europe PMC PDF 直出端点。旧端点 backend/ptpmcrender.fcgi 已失效（520）。
  static String _pmcPdfUrl(String pmcid) =>
      'https://europepmc.org/articles/$pmcid?pdf=render';

  /// PMID 输入的 PDF 兑底：esummary 取 PMCID → Europe PMC 直出；任一步失败返回空。
  Future<String> downloadPdfByPmid({
    required String pmid,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    String? targetPath,
    CancelToken? cancelToken,
  }) async {
    try {
      final resp = await _dio.get(
        'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi',
        queryParameters: {'db': 'pubmed', 'id': pmid, 'retmode': 'json'},
        cancelToken: cancelToken,
      );
      final result = (resp.data as Map<String, dynamic>)['result'];
      final article = (result as Map<String, dynamic>?)?[pmid];
      final ids = (article as Map<String, dynamic>?)?['articleids'];
      String? pmcid;
      if (ids is List) {
        for (final id in ids) {
          final map = id as Map<String, dynamic>;
          if (map['idtype'] == 'pmc') {
            final value = map['value'] as String?;
            if (value != null && value.isNotEmpty) {
              pmcid = value;
              break;
            }
          }
        }
      }
      if (pmcid == null) return '';
      return await _downloadPdf(
        url: _pmcPdfUrl(pmcid),
        year: year,
        authors: authors,
        title: title,
        fallbackId: fallbackId,
        targetPath: targetPath,
        cancelToken: cancelToken,
      );
    } catch (e) {
      log.d('PMC PDF 下载失败: $e');
      return '';
    }
  }
  // ─── 出版商直接获取 PDF ───────────────────────────────────────────────────

  /// 优先通过 HEAD doi.org 重定向判断出版商，再构造 PDF 直链 / 出版商 URL 模式下载。
  ///
  /// 先通过 HEAD 请求 DOI 重定向，判断 content-type 及出版商 URL 再构造 PDF 链接。
  Future<String> _tryPublisherPdf({
    required String doi,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    String? targetPath,
    CancelToken? cancelToken,
  }) async {
    Uri? publisherUri;
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
      publisherUri = resp.realUri;

      // 出版商直接返回 PDF（如预印本服务器）
      if (_isPdfContentType(resp.headers)) {
        return await _downloadPdf(
          url: publisherUri.toString(),
          year: year,
          authors: authors,
          title: title,
          fallbackId: fallbackId,
          targetPath: targetPath,
          cancelToken: cancelToken,
        );
      }
    } catch (e) {
      log.d('DOI 重定向失败: $e');
    }

    // 根据出版商域名构造 PDF 直链
    if (publisherUri != null) {
      final pdfUrl = buildPublisherPdfUrl(publisherUri, doi);
      if (pdfUrl != null) {
        try {
          final path = await _downloadPdf(
            url: pdfUrl,
            year: year,
            authors: authors,
            title: title,
            fallbackId: fallbackId,
            targetPath: targetPath,
            cancelToken: cancelToken,
          );
          if (path.isNotEmpty) return path;
        } catch (e) {
          log.d('出版商 URL 模式下载失败: $e');
        }
      }
    }

    return '';
  }

  /// 根据出版商域名构造 PDF 直链，不支持则返回 null。
  @visibleForTesting
  static String? buildPublisherPdfUrl(Uri publisherUri, String doi) {
    final host = publisherUri.host.toLowerCase();

    // arXiv：/abs/{id} → /pdf/{id}。Unpaywall 未索引规范 DOI（10.48550/arxiv.*），
    // 必须出版商直达。
    if (host.contains('arxiv.org')) {
      final match = RegExp(r'^/abs/(.+)$').firstMatch(publisherUri.path);
      if (match != null) return 'https://arxiv.org/pdf/${match.group(1)}';
      return null;
    }

    // bioRxiv / medRxiv：realUri 为 /content/{doi}vN 页面，附 .full.pdf 后缀
    // 即为 PDF。直连可减少对 Unpaywall 的依赖，并降低触发 Cloudflare 限流的
    // 请求次数。
    if (host.contains('biorxiv.org') || host.contains('medrxiv.org')) {
      final path = publisherUri.path.replaceFirst(RegExp(r'/$'), '');
      if (path.startsWith('/content/10.1101/')) {
        return 'https://$host$path.full.pdf';
      }
      return null;
    }

    // Springer
    if (host.contains('link.springer.com')) {
      return 'https://link.springer.com/content/pdf/$doi.pdf';
    }

    // Nature
    if (host.contains('nature.com')) {
      final seg = publisherUri.pathSegments;
      if (seg.length >= 2 && seg[seg.length - 2] == 'articles') {
        return 'https://www.nature.com/articles/${seg.last}.pdf';
      }
    }

    // Wiley
    if (host.contains('onlinelibrary.wiley.com')) {
      return 'https://onlinelibrary.wiley.com/doi/pdfdirect/$doi?download=true';
    }

    // Elsevier / ScienceDirect
    if (host.contains('sciencedirect.com') ||
        host.contains('linkinghub.elsevier.com')) {
      final base = publisherUri.toString().split('?').first;
      return '$base/pdfft?download=true';
    }

    // ACS
    if (host.contains('pubs.acs.org')) {
      return 'https://pubs.acs.org/doi/pdf/$doi';
    }

    // Taylor & Francis
    if (host.contains('tandfonline.com')) {
      return 'https://www.tandfonline.com/doi/pdf/$doi';
    }

    // RSC
    if (host.contains('pubs.rsc.org')) {
      final path = publisherUri.path;
      if (path.contains('articlelanding')) {
        final pdfPath = path.replaceFirst('articlelanding', 'articlepdf');
        return 'https://pubs.rsc.org$pdfPath';
      }
    }

    // MDPI
    if (host.contains('mdpi.com')) {
      final base = publisherUri.toString().split('?').first;
      return base.endsWith('/') ? '${base}pdf' : '$base/pdf';
    }

    return null;
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

  bool _isPdfContentType(Headers headers) {
    final ct = headers.value('content-type');
    return ct != null && ct.contains('application/pdf');
  }

  String _doiUrl(String doi) {
    return 'https://doi.org/${_encodeDoiPathSegment(doi)}';
  }

  String _encodeDoiPathSegment(String doi) {
    return Uri.encodeComponent(doi);
  }

  // ─── PDF 下载 ─────────────────────────────────────────────────────────────

  /// 下载 PDF 到文档目录，校验 %PDF 魔数后返回文件路径，校验失败则删除文件并返回空字符串。
  Future<String> _downloadPdf({
    required String url,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    String? targetPath,
    CancelToken? cancelToken,
  }) async {
    final pdfPath =
        targetPath ??
        p.join(
          GStorage.libraryDirPath,
          buildPdfFileName(
            year: year,
            authors: authors,
            title: title,
            fallbackId: fallbackId,
          ),
        );

    if (await File(pdfPath).exists()) return pdfPath;
    await Directory(p.dirname(pdfPath)).create(recursive: true);

    await _dio.download(url, pdfPath, cancelToken: cancelToken);

    // 校验 PDF 魔数（%PDF），非法文件直接删除
    final file = File(pdfPath);
    final raf = await file.open();
    final header = await raf.read(4);
    await raf.close();
    if (header.length < 4 || String.fromCharCodes(header) != '%PDF') {
      await file.delete();
      return '';
    }

    return pdfPath;
  }

  // ─── 文件名生成 ───────────────────────────────────────────────────────────

  /// 根据年份、作者、标题生成规范 PDF 文件名：year-mainAuthor-title.pdf
  static String buildPdfFileName({
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
  }) {
    final parts = <String>[];

    if (year != null && year.isNotEmpty) parts.add(year);

    if (authors.isNotEmpty) {
      final first = authors.first.trim();
      final spaceIdx = first.lastIndexOf(' ');
      final lastName = spaceIdx > 0 ? first.substring(spaceIdx + 1) : first;
      parts.add(lastName);
    }

    parts.add(title.length > 80 ? title.substring(0, 80).trim() : title);

    final raw = parts.join('-');
    final sanitized = raw
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return '${sanitized.isEmpty ? fallbackId : sanitized}.pdf';
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
