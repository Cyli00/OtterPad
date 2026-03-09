import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';


import '../data/models/book/document.dart';
import '../providers/documents_provider.dart';
import 'identifier_parser.dart';

/// 标识符解析异常，包含用户友好的中文提示
class IdentifierResolveException implements Exception {
  final String message;
  const IdentifierResolveException(this.message);

  @override
  String toString() => message;
}

/// 标识符解析服务：调用公共 API 将 DOI/PMID/arXiv/ISBN 解析为 Document
class IdentifierResolver {
  IdentifierResolver._();
  static final IdentifierResolver instance = IdentifierResolver._();

  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'NightReader/0.1 (Flutter; mailto:dev@nightreader.app)',
    },
  ));

  /// 根据代理模式配置 Dio 的 HTTP 代理
  ///
  /// [mode] 接受 ProxyMode 枚举值，内部通过 name 匹配以避免循环导入。
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

  /// 测试连通性，返回响应耗时（毫秒）
  Future<int> testConnectivity(String url, {CancelToken? cancelToken}) async {
    final sw = Stopwatch()..start();
    await _dio.head(url, cancelToken: cancelToken);
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  /// 解析原始输入字符串，返回 Document
  ///
  /// [metadataOnly] 为 true 时仅获取元数据，跳过 PDF 下载
  Future<Document> resolve(
    String rawInput, {
    bool metadataOnly = false,
    CancelToken? cancelToken,
  }) async {
    final parsed = IdentifierParser.parse(rawInput);

    switch (parsed.type) {
      case IdentifierType.doi:
        return _resolveDoi(parsed.value, metadataOnly: metadataOnly, cancelToken: cancelToken);
      case IdentifierType.pmid:
        return _resolvePmid(parsed.value, metadataOnly: metadataOnly, cancelToken: cancelToken);
      case IdentifierType.arxiv:
        return _resolveArxiv(parsed.value, metadataOnly: metadataOnly, cancelToken: cancelToken);
      case IdentifierType.isbn:
        return _resolveIsbn(parsed.value, cancelToken: cancelToken);
      case IdentifierType.unknown:
        throw const IdentifierResolveException('无法识别的标识符格式');
    }
  }

  // ── DOI → CrossRef REST API ──

  Future<Document> _resolveDoi(String doi, {bool metadataOnly = false, CancelToken? cancelToken}) async {
    try {
      final resp = await _dio.get('https://api.crossref.org/works/$doi', cancelToken: cancelToken);
      final msg = resp.data['message'] as Map<String, dynamic>;

      final title = _extractFirst(msg['title']) ?? doi;
      final authors = _extractCrossRefAuthors(msg['author']);
      final journal = _extractFirst(msg['container-title']);
      final journalAbbr = _extractFirst(msg['short-container-title']);
      final publisher = msg['publisher'] as String?;
      final volume = msg['volume'] as String?;
      final issue = msg['issue'] as String? ??
          (msg['journal-issue'] is Map
              ? (msg['journal-issue'] as Map)['issue'] as String?
              : null);
      final pages = msg['page'] as String?;
      final year = _extractCrossRefYear(msg);
      final date = _extractCrossRefDate(msg);
      final resolvedDoi = msg['DOI'] as String? ?? doi;
      final url = msg['URL'] as String? ?? 'https://doi.org/$doi';
      final language = msg['language'] as String?;
      final issn = _extractFirst(msg['ISSN']);
      final itemType = _mapCrossRefType(msg['type'] as String?);

      // CrossRef abstract 可能带 HTML 标签，做简单清理
      String? abstractText;
      if (msg['abstract'] is String) {
        abstractText = (msg['abstract'] as String)
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
      }

      String filePath = '';
      if (!metadataOnly) {
        // 策略 1: 通过出版商直接获取 PDF（校园网/机构代理）
        try {
          filePath = await _tryPublisherPdf(
            doi: resolvedDoi,
            year: year,
            authors: authors,
            title: title,
            fallbackId: doi.replaceAll('/', '_'),
            cancelToken: cancelToken,
          );
        } catch (e) {
          debugPrint('出版商 PDF 获取失败: $e');
        }

        // 策略 2: Unpaywall 开放获取
        if (filePath.isEmpty) {
          try {
            final uResp = await _dio.get(
              'https://api.unpaywall.org/v2/$doi',
              queryParameters: {'email': 'dev@nightreader.app'},
              cancelToken: cancelToken,
            );
            final bestOa =
                (uResp.data as Map<String, dynamic>)['best_oa_location'];
            final pdfUrl =
                (bestOa as Map<String, dynamic>?)?['url_for_pdf'] as String?;
            if (pdfUrl != null && pdfUrl.isNotEmpty) {
              filePath = await _downloadPdf(
                url: pdfUrl,
                year: year,
                authors: authors,
                title: title,
                fallbackId: doi.replaceAll('/', '_'),
                cancelToken: cancelToken,
              );
            }
          } catch (e) {
            debugPrint('Unpaywall PDF 下载失败: $e');
          }
        }
      }

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        itemType: itemType,
        title: title,
        authors: authors,
        journal: journal,
        journalAbbr: journalAbbr,
        publisher: publisher,
        volume: volume,
        issue: issue,
        pages: pages,
        year: year,
        date: date,
        doi: resolvedDoi,
        url: url,
        language: language,
        issn: issn,
        abstractText: abstractText,
        filePath: filePath,
        addedAt: DateTime.now(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      debugPrint('DOI 解析失败: $e\n$st');
      throw IdentifierResolveException('解析 DOI 响应数据失败: $e');
    }
  }

  // ── PMID → PubMed eSummary + eFetch ──

  Future<Document> _resolvePmid(String pmid, {bool metadataOnly = false, CancelToken? cancelToken}) async {
    try {
      // eSummary 获取基本元数据
      final resp = await _dio.get(
        'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi',
        queryParameters: {
          'db': 'pubmed',
          'id': pmid,
          'retmode': 'json',
        },
        cancelToken: cancelToken,
      );

      final result = resp.data['result'] as Map<String, dynamic>;
      final entry = result[pmid] as Map<String, dynamic>?;
      if (entry == null || entry.containsKey('error')) {
        throw const IdentifierResolveException('未找到该标识符对应的文献');
      }

      final title = (entry['title'] as String?)?.trim() ?? pmid;
      final authors = <String>[];
      if (entry['authors'] is List) {
        for (final a in entry['authors'] as List) {
          if (a is Map && a['name'] != null) {
            authors.add(a['name'] as String);
          }
        }
      }
      final journal = entry['source'] as String?;
      final volume = entry['volume'] as String?;
      final issue = entry['issue'] as String?;
      final pages = entry['pages'] as String?;
      final year = _extractPubMedYear(entry['pubdate'] as String?);
      final date = _normalizePubMedDate(entry['pubdate'] as String?);
      final language = entry['lang'] is List
          ? (entry['lang'] as List).firstOrNull as String?
          : entry['lang'] as String?;
      final issn = entry['issn'] as String? ?? entry['essn'] as String?;

      // 从 articleids 中提取 DOI 和 PMCID
      String? doi;
      String? pmcid;
      if (entry['articleids'] is List) {
        for (final aid in entry['articleids'] as List) {
          if (aid is Map) {
            if (aid['idtype'] == 'doi') doi = aid['value'] as String?;
            if (aid['idtype'] == 'pmc') pmcid = aid['value'] as String?;
          }
        }
      }

      final url = doi != null
          ? 'https://doi.org/$doi'
          : 'https://pubmed.ncbi.nlm.nih.gov/$pmid/';

      // eFetch 获取摘要（XML）
      String? abstractText;
      try {
        final efetchResp = await _dio.get(
          'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi',
          queryParameters: {
            'db': 'pubmed',
            'id': pmid,
            'retmode': 'xml',
          },
          cancelToken: cancelToken,
        );
        final xmlDoc = XmlDocument.parse(efetchResp.data as String);
        final abstractParts = xmlDoc
            .findAllElements('AbstractText')
            .map((e) => e.innerText.trim())
            .where((t) => t.isNotEmpty);
        if (abstractParts.isNotEmpty) {
          abstractText = abstractParts.join('\n');
        }
      } catch (_) {
        // 摘要获取失败不影响主流程
      }

      String filePath = '';
      if (!metadataOnly) {
        // 策略 1: 有 DOI 时尝试出版商直接获取（校园网/机构代理）
        if (doi != null && doi.isNotEmpty) {
          try {
            filePath = await _tryPublisherPdf(
              doi: doi,
              year: year,
              authors: authors,
              title: title,
              fallbackId: pmid,
              cancelToken: cancelToken,
            );
          } catch (e) {
            debugPrint('出版商 PDF 获取失败: $e');
          }
        }

        // 策略 2: PMC 开放获取
        if (filePath.isEmpty && pmcid != null && pmcid.isNotEmpty) {
          try {
            filePath = await _downloadPdf(
              url: 'https://europepmc.org/backend/ptpmcrender.fcgi'
                  '?accid=$pmcid&blobtype=pdf',
              year: year,
              authors: authors,
              title: title,
              fallbackId: pmid,
              cancelToken: cancelToken,
            );
          } catch (e) {
            debugPrint('PMC PDF 下载失败: $e');
          }
        }

        // 策略 3: Unpaywall（出版商与 PMC 均无果）
        if (filePath.isEmpty && doi != null && doi.isNotEmpty) {
          try {
            final uResp = await _dio.get(
              'https://api.unpaywall.org/v2/$doi',
              queryParameters: {'email': 'dev@nightreader.app'},
              cancelToken: cancelToken,
            );
            final bestOa =
                (uResp.data as Map<String, dynamic>)['best_oa_location'];
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
            debugPrint('Unpaywall PDF 下载失败: $e');
          }
        }
      }

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        itemType: 'journalArticle',
        title: title,
        authors: authors,
        journal: journal,
        volume: volume,
        issue: issue,
        pages: pages,
        year: year,
        date: date,
        doi: doi,
        pmid: pmid,
        pmcid: pmcid,
        url: url,
        language: language,
        issn: issn,
        abstractText: abstractText,
        filePath: filePath,
        addedAt: DateTime.now(),
      );
    } on IdentifierResolveException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      debugPrint('PMID 解析失败: $e\n$st');
      throw IdentifierResolveException('解析 PMID 响应数据失败: $e');
    }
  }

  // ── arXiv → Atom XML API + PDF 下载 ──

  Future<Document> _resolveArxiv(String arxivId, {bool metadataOnly = false, CancelToken? cancelToken}) async {
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

      final title = entry
              .findElements('title')
              .firstOrNull
              ?.innerText
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          arxivId;

      final authors = entry
          .findElements('author')
          .map((a) => a.findElements('name').firstOrNull?.innerText ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final journalRef = entry
          .findAllElements('journal_ref')
          .firstOrNull
          ?.innerText
          .trim();

      final published =
          entry.findElements('published').firstOrNull?.innerText;
      final year = published != null && published.length >= 4
          ? published.substring(0, 4)
          : null;
      final date = published != null && published.length >= 10
          ? published.substring(0, 10)
          : null;

      final doi =
          entry.findAllElements('doi').firstOrNull?.innerText.trim();

      final url = idText;

      // 摘要
      final abstractText = entry
          .findElements('summary')
          .firstOrNull
          ?.innerText
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      String filePath = '';
      if (!metadataOnly) {
        try {
          filePath = await _downloadPdf(
            url: 'https://arxiv.org/pdf/$arxivId.pdf',
            year: year,
            authors: authors,
            title: title,
            fallbackId: arxivId.replaceAll('/', '_'),
            cancelToken: cancelToken,
          );
        } catch (e) {
          debugPrint('arXiv PDF 下载失败: $e');
        }
      }

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        itemType: 'preprint',
        title: title,
        authors: authors,
        journal: journalRef,
        year: year,
        date: date,
        doi: doi,
        arxivId: arxivId,
        url: url,
        abstractText: abstractText,
        filePath: filePath,
        addedAt: DateTime.now(),
      );
    } on IdentifierResolveException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      debugPrint('arXiv 解析失败: $e\n$st');
      throw IdentifierResolveException('解析 arXiv 响应数据失败: $e');
    }
  }

  // ── ISBN → Open Library API ──

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
      final pages = data['number_of_pages']?.toString();
      final url = 'https://openlibrary.org/isbn/$isbn';

      // 语言
      String? language;
      if (data['languages'] is List) {
        final langList = data['languages'] as List;
        if (langList.isNotEmpty && langList.first is Map) {
          final langKey =
              (langList.first as Map<String, dynamic>)['key'] as String?;
          if (langKey != null) {
            language = langKey.split('/').last; // "/languages/eng" → "eng"
          }
        }
      }

      // 解析作者（需二次请求）
      final authors = <String>[];
      final authorKeys = data['authors'] as List?;
      if (authorKeys != null) {
        final limit = authorKeys.length > 5 ? 5 : authorKeys.length;
        for (int i = 0; i < limit; i++) {
          final authorKey =
              (authorKeys[i] as Map<String, dynamic>)['key'] as String?;
          if (authorKey != null) {
            try {
              final authorResp =
                  await _dio.get('https://openlibrary.org$authorKey.json', cancelToken: cancelToken);
              final name = authorResp.data['name'] as String?;
              if (name != null) authors.add(name);
            } catch (_) {}
          }
        }
      }

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        itemType: 'book',
        title: title,
        authors: authors,
        publisher: publisher,
        pages: pages,
        year: year,
        date: publishDate,
        isbn: isbn,
        url: url,
        language: language,
        filePath: '',
        addedAt: DateTime.now(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      debugPrint('ISBN 解析失败: $e\n$st');
      throw IdentifierResolveException('解析 ISBN 响应数据失败: $e');
    }
  }

  // ── 出版商 PDF 获取 ──

  /// 尝试通过出版商直接获取 PDF（校园网 / 机构代理场景）
  ///
  /// 回退链: HEAD 探测 DOI 重定向 → 检测 content-type → 出版商 URL 模式
  Future<String> _tryPublisherPdf({
    required String doi,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    CancelToken? cancelToken,
  }) async {
    Uri? publisherUri;
    try {
      final resp = await _dio.head(
        'https://doi.org/$doi',
        options: Options(
          followRedirects: true,
          maxRedirects: 10,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
        cancelToken: cancelToken,
      );
      publisherUri = resp.realUri;

      // 出版商对校内 IP / 代理直接返回 PDF
      if (_isPdfContentType(resp.headers)) {
        return await _downloadPdf(
          url: publisherUri.toString(),
          year: year,
          authors: authors,
          title: title,
          fallbackId: fallbackId,
          cancelToken: cancelToken,
        );
      }
    } catch (e) {
      debugPrint('DOI 重定向探测失败: $e');
    }

    // 根据出版商域名构造 PDF 下载链接
    if (publisherUri != null) {
      final pdfUrl = _buildPublisherPdfUrl(publisherUri, doi);
      if (pdfUrl != null) {
        try {
          final path = await _downloadPdf(
            url: pdfUrl,
            year: year,
            authors: authors,
            title: title,
            fallbackId: fallbackId,
            cancelToken: cancelToken,
          );
          if (path.isNotEmpty) return path;
        } catch (e) {
          debugPrint('出版商 URL 模式下载失败: $e');
        }
      }
    }

    return '';
  }

  /// 根据出版商域名和页面 URL 构造 PDF 下载链接，返回 null 表示不支持
  String? _buildPublisherPdfUrl(Uri publisherUri, String doi) {
    final host = publisherUri.host.toLowerCase();

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

  bool _isPdfContentType(Headers headers) {
    final ct = headers.value('content-type');
    return ct != null && ct.contains('application/pdf');
  }

  // ── PDF 下载 ──

  /// 下载 PDF 到文库目录，返回本地路径；失败或非 PDF 内容返回空字符串
  Future<String> _downloadPdf({
    required String url,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    CancelToken? cancelToken,
  }) async {
    final docsDir = await DocumentsNotifier.getDocsDir();
    final fileName = buildPdfFileName(
      year: year,
      authors: authors,
      title: title,
      fallbackId: fallbackId,
    );
    final pdfPath = p.join(docsDir.path, fileName);

    if (await File(pdfPath).exists()) return pdfPath;

    await _dio.download(url, pdfPath, cancelToken: cancelToken);

    // 验证 PDF 有效性（检查 %PDF 魔数）
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

  // ── 文件命名 ──

  /// 根据元数据生成 PDF 文件名，格式：year-mainAuthor-title.pdf
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

  // ── 辅助方法 ──

  String? _extractFirst(dynamic list) {
    if (list is List && list.isNotEmpty) return list.first.toString();
    return null;
  }

  List<String> _extractCrossRefAuthors(dynamic authorList) {
    if (authorList is! List) return [];
    return authorList.map((a) {
      final map = a as Map<String, dynamic>;
      final given = map['given'] as String? ?? '';
      final family = map['family'] as String? ?? '';
      return '$family, $given'.trim().replaceAll(RegExp(r'^,\s*|,\s*$'), '');
    }).where((n) => n.isNotEmpty).toList();
  }

  /// 映射 CrossRef 的 type 到 Zotero 风格的 itemType
  String _mapCrossRefType(String? type) {
    return switch (type) {
      'journal-article' => 'journalArticle',
      'book' => 'book',
      'book-chapter' => 'bookSection',
      'proceedings-article' => 'conferencePaper',
      'posted-content' => 'preprint',
      'dissertation' => 'thesis',
      'report' => 'report',
      'dataset' => 'dataset',
      _ => 'journalArticle',
    };
  }

  String? _extractCrossRefYear(Map<String, dynamic> msg) {
    for (final key in ['published-print', 'published-online', 'published']) {
      final pub = msg[key];
      if (pub is Map && pub['date-parts'] is List) {
        final parts = pub['date-parts'] as List;
        if (parts.isNotEmpty && parts.first is List) {
          final year = (parts.first as List).firstOrNull;
          if (year != null) return year.toString();
        }
      }
    }
    return null;
  }

  /// 从 CrossRef date-parts 提取完整日期
  String? _extractCrossRefDate(Map<String, dynamic> msg) {
    for (final key in ['published-print', 'published-online', 'published']) {
      final pub = msg[key];
      if (pub is Map && pub['date-parts'] is List) {
        final parts = pub['date-parts'] as List;
        if (parts.isNotEmpty && parts.first is List) {
          final dp = (parts.first as List);
          if (dp.isEmpty) continue;
          final y = dp[0].toString().padLeft(4, '0');
          final m = dp.length > 1 ? dp[1].toString().padLeft(2, '0') : '01';
          final d = dp.length > 2 ? dp[2].toString().padLeft(2, '0') : '01';
          return '$y-$m-$d';
        }
      }
    }
    return null;
  }

  String? _extractPubMedYear(String? pubdate) {
    if (pubdate == null) return null;
    final match = RegExp(r'\d{4}').firstMatch(pubdate);
    return match?.group(0);
  }

  /// PubMed pubdate 格式多样："2002 Apr 30"、"2021"、"2021 Jan-Feb"
  String? _normalizePubMedDate(String? pubdate) {
    if (pubdate == null) return null;
    // 尝试匹配 "YYYY Mon DD" 格式
    final full =
        RegExp(r'(\d{4})\s+(\w{3})\s+(\d{1,2})').firstMatch(pubdate);
    if (full != null) {
      final y = full.group(1)!;
      final m = _monthToNum(full.group(2)!);
      final d = full.group(3)!.padLeft(2, '0');
      return '$y-$m-$d';
    }
    // 仅年月
    final ym = RegExp(r'(\d{4})\s+(\w{3})').firstMatch(pubdate);
    if (ym != null) {
      return '${ym.group(1)!}-${_monthToNum(ym.group(2)!)}';
    }
    // 仅年
    final y = RegExp(r'\d{4}').firstMatch(pubdate);
    if (y != null) return y.group(0);
    return null;
  }

  String _monthToNum(String mon) {
    const months = {
      'jan': '01', 'feb': '02', 'mar': '03', 'apr': '04',
      'may': '05', 'jun': '06', 'jul': '07', 'aug': '08',
      'sep': '09', 'oct': '10', 'nov': '11', 'dec': '12',
    };
    return months[mon.toLowerCase()] ?? '01';
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
