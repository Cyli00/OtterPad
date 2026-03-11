import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../data/models/book/document.dart';
import '../providers/documents_provider.dart';
import 'identifier_parser.dart';

/// 閺嶅洩鐦戠粭锕佇掗弸鎰磽鐢潻绱濋崠鍛儓閻劍鍩涢崣瀣偨閻ㄥ嫪鑵戦弬鍥ㄥ絹缁€?
class IdentifierResolveException implements Exception {
  final String message;
  const IdentifierResolveException(this.message);

  @override
  String toString() => message;
}

/// 閺嶅洩鐦戠粭锕佇掗弸鎰箛閸斺槄绱扮拫鍐暏閸忣剙鍙?API 鐏?DOI/PMID/arXiv/ISBN 鐟欙絾鐎芥稉?Document
class IdentifierResolver {
  IdentifierResolver._();
  static final IdentifierResolver instance = IdentifierResolver._();

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'NightReader/0.1 (Flutter; mailto:dev@nightreader.app)',
      },
    ),
  );

  /// 閺嶈宓佹禒锝囨倞濡€崇础闁板秶鐤?Dio 閻?HTTP 娴狅絿鎮?
  ///
  /// [mode] 閹恒儱褰?ProxyMode 閺嬫矮濡囬崐纭风礉閸愬懘鍎撮柅姘崇箖 name 閸栧綊鍘ゆ禒銉╀缉閸忓秴鎯婇悳顖氼嚤閸忋儯鈧?
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

  /// 濞村鐦潻鐐衡偓姘偓褝绱濇潻鏂挎礀閸濆秴绨查懓妤佹閿涘牊顕犵粔鎺炵礆
  Future<int> testConnectivity(String url, {CancelToken? cancelToken}) async {
    final sw = Stopwatch()..start();
    await _dio.head(url, cancelToken: cancelToken);
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  /// 鐟欙絾鐎介崢鐔奉潗鏉堟挸鍙嗙€涙顑佹稉璇х礉鏉╂柨娲?Document
  ///
  /// [metadataOnly] 娑?true 閺冩湹绮庨懢宄板絿閸忓啯鏆熼幑顕嗙礉鐠哄疇绻?PDF 娑撳娴?
  Future<Document> resolve(
    String rawInput, {
    bool metadataOnly = false,
    CancelToken? cancelToken,
  }) async {
    final parsed = IdentifierParser.parse(rawInput);

    switch (parsed.type) {
      case IdentifierType.doi:
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
        throw const IdentifierResolveException(
          '\u672a\u627e\u5230\u8be5\u6807\u8bc6\u7b26\u5bf9\u5e94\u7684\u6587\u732e',
        );
    }
  }

  // 閳光偓閳光偓 DOI 閳?CrossRef REST API 閳光偓閳光偓

  Future<Document> _resolveDoi(
    String doi, {
    bool metadataOnly = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final resp = await _dio.get(
        'https://api.crossref.org/works/$doi',
        cancelToken: cancelToken,
      );
      final msg = resp.data['message'] as Map<String, dynamic>;

      final title = _extractFirst(msg['title']) ?? doi;
      final authors = _extractCrossRefAuthors(msg['author']);
      final journal =
          _extractFirst(msg['container-title']) ??
          _extractFirst(msg['short-container-title']);
      final year = _extractCrossRefYear(msg);
      final resolvedDoi = (msg['DOI'] as String? ?? doi).toLowerCase();

      String filePath = '';
      if (!metadataOnly) {
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
          debugPrint('閸戣櫣澧楃粈?PDF 閼惧嘲褰囨径杈Е: $e');
        }

        if (filePath.isEmpty) {
          try {
            final unpaywallResponse = await _dio.get(
              'https://api.unpaywall.org/v2/$doi',
              queryParameters: {'email': 'dev@nightreader.app'},
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
                fallbackId: doi.replaceAll('/', '_'),
                cancelToken: cancelToken,
              );
            }
          } catch (e) {
            debugPrint('Unpaywall PDF 娑撳娴囨径杈Е: $e');
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
        filePath: filePath,
        addedAt: DateTime.now(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      debugPrint('DOI 鐟欙絾鐎芥径杈Е: $e\n$st');
      throw IdentifierResolveException('鐟欙絾鐎?DOI 閸濆秴绨查弫鐗堝祦婢惰精瑙? $e');
    }
  }

  Future<Document> _resolvePmid(
    String pmid, {
    bool metadataOnly = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final resp = await _dio.get(
        'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi',
        queryParameters: {'db': 'pubmed', 'id': pmid, 'retmode': 'json'},
        cancelToken: cancelToken,
      );

      final result = resp.data['result'] as Map<String, dynamic>;
      final entry = result[pmid] as Map<String, dynamic>?;
      if (entry == null || entry.containsKey('error')) {
        throw const IdentifierResolveException(
          '\u672a\u627e\u5230\u8be5\u6807\u8bc6\u7b26\u5bf9\u5e94\u7684\u6587\u732e',
        );
      }

      final title = (entry['title'] as String?)?.trim() ?? pmid;
      final authors = <String>[];
      if (entry['authors'] is List) {
        for (final author in entry['authors'] as List) {
          if (author is Map && author['name'] != null) {
            authors.add(author['name'] as String);
          }
        }
      }
      final journal = entry['source'] as String?;
      final year = _extractPubMedYear(entry['pubdate'] as String?);

      String? doi;
      String? pmcid;
      if (entry['articleids'] is List) {
        for (final articleId in entry['articleids'] as List) {
          if (articleId is Map) {
            if (articleId['idtype'] == 'doi') {
              doi = articleId['value'] as String?;
            }
            if (articleId['idtype'] == 'pmc') {
              pmcid = articleId['value'] as String?;
            }
          }
        }
      }
      final normalizedDoi = doi?.toLowerCase();

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
            debugPrint('閸戣櫣澧楃粈?PDF 閼惧嘲褰囨径杈Е: $e');
          }
        }

        if (filePath.isEmpty && pmcid != null && pmcid.isNotEmpty) {
          try {
            filePath = await _downloadPdf(
              url:
                  'https://europepmc.org/backend/ptpmcrender.fcgi?accid=$pmcid&blobtype=pdf',
              year: year,
              authors: authors,
              title: title,
              fallbackId: pmid,
              cancelToken: cancelToken,
            );
          } catch (e) {
            debugPrint('PMC PDF 娑撳娴囨径杈Е: $e');
          }
        }

        if (filePath.isEmpty &&
            normalizedDoi != null &&
            normalizedDoi.isNotEmpty) {
          try {
            final unpaywallResponse = await _dio.get(
              'https://api.unpaywall.org/v2/$normalizedDoi',
              queryParameters: {'email': 'dev@nightreader.app'},
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
            debugPrint('Unpaywall PDF 娑撳娴囨径杈Е: $e');
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
        filePath: filePath,
        addedAt: DateTime.now(),
      );
    } on IdentifierResolveException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      debugPrint('PMID 鐟欙絾鐎芥径杈Е: $e\n$st');
      throw IdentifierResolveException('鐟欙絾鐎?PMID 閸濆秴绨查弫鐗堝祦婢惰精瑙? $e');
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
        throw const IdentifierResolveException(
          '\u672a\u627e\u5230\u8be5\u6807\u8bc6\u7b26\u5bf9\u5e94\u7684\u6587\u732e',
        );
      }

      final idText = entry.findElements('id').firstOrNull?.innerText ?? '';
      if (idText.isEmpty) {
        throw const IdentifierResolveException(
          '\u672a\u627e\u5230\u8be5\u6807\u8bc6\u7b26\u5bf9\u5e94\u7684\u6587\u732e',
        );
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
      final doi = entry
          .findAllElements('doi')
          .firstOrNull
          ?.innerText
          .trim()
          .toLowerCase();

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
          debugPrint('arXiv PDF 娑撳娴囨径杈Е: $e');
        }
      }

      return Document(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        authors: authors,
        journal: journal,
        year: year,
        doi: doi,
        filePath: filePath,
        addedAt: DateTime.now(),
      );
    } on IdentifierResolveException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      debugPrint('arXiv 鐟欙絾鐎芥径杈Е: $e\n$st');
      throw IdentifierResolveException('鐟欙絾鐎?arXiv 閸濆秴绨查弫鐗堝祦婢惰精瑙? $e');
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
        filePath: '',
        addedAt: DateTime.now(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, st) {
      debugPrint('ISBN 鐟欙絾鐎芥径杈Е: $e\n$st');
      throw IdentifierResolveException('鐟欙絾鐎?ISBN 閸濆秴绨查弫鐗堝祦婢惰精瑙? $e');
    }
  }

  // 鈥斺€?鏍规嵁 DOI 涓嬭浇 PDF 鈥斺€?

  Future<String> downloadPdfByDoi({
    required String doi,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    CancelToken? cancelToken,
  }) async {
    String filePath = '';

    // 缁涙牜鏆?1: 閸戣櫣澧楅崯鍡欐纯閹恒儴骞忛崣鏍电礄閺嶁€虫疮缂?閺堢儤鐎禒锝囨倞閿?
    try {
      filePath = await _tryPublisherPdf(
        doi: doi,
        year: year,
        authors: authors,
        title: title,
        fallbackId: fallbackId,
        cancelToken: cancelToken,
      );
    } catch (e) {
      debugPrint('閸戣櫣澧楅崯?PDF 閼惧嘲褰囨径杈Е: $e');
    }
    if (filePath.isNotEmpty) return filePath;

    // 缁涙牜鏆?2: Unpaywall 瀵偓閺€鎹愬箯閸?
    try {
      final uResp = await _dio.get(
        'https://api.unpaywall.org/v2/$doi',
        queryParameters: {'email': 'dev@nightreader.app'},
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
          cancelToken: cancelToken,
        );
      }
    } catch (e) {
      debugPrint('Unpaywall PDF 娑撳娴囨径杈Е: $e');
    }
    if (filePath.isNotEmpty) return filePath;

    // 缁涙牜鏆?3: Sci-Hub 閸忔粌绨抽懢宄板絿
    try {
      final sResp = await _dio.get(
        'https://sci-hub.se/$doi',
        cancelToken: cancelToken,
      );
      final html = sResp.data as String;
      // 閸栧綊鍘?<embed src="..."> 閹?<iframe src="...">
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
          cancelToken: cancelToken,
        );
      }
    } catch (e) {
      debugPrint('Sci-Hub PDF 娑撳娴囨径杈Е: $e');
    }

    return filePath;
  }

  // 閳光偓閳光偓 閸戣櫣澧楅崯?PDF 閼惧嘲褰?閳光偓閳光偓

  /// 鐏忔繆鐦柅姘崇箖閸戣櫣澧楅崯鍡欐纯閹恒儴骞忛崣?PDF閿涘牊鐗庨崶顓犵秹 / 閺堢儤鐎禒锝囨倞閸︾儤娅欓敍?
  ///
  /// 閸ョ偤鈧偓闁? HEAD 閹恒垺绁?DOI 闁插秴鐣鹃崥?閳?濡偓濞?content-type 閳?閸戣櫣澧楅崯?URL 濡€崇础
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

      // 閸戣櫣澧楅崯鍡楊嚠閺嶁€冲敶 IP / 娴狅絿鎮婇惄瀛樺复鏉╂柨娲?PDF
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
      debugPrint('DOI 闁插秴鐣鹃崥鎴炲赴濞村銇戠拹? $e');
    }

    // 閺嶈宓侀崙铏瑰閸熷棗鐓欓崥宥嗙€柅?PDF 娑撳娴囬柧鐐复
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
          debugPrint('閸戣櫣澧楅崯?URL 濡€崇础娑撳娴囨径杈Е: $e');
        }
      }
    }

    return '';
  }

  /// 閺嶈宓侀崙铏瑰閸熷棗鐓欓崥宥呮嫲妞ょ敻娼?URL 閺嬪嫰鈧?PDF 娑撳娴囬柧鐐复閿涘矁绻戦崶?null 鐞涖劎銇氭稉宥嗘暜閹?
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

  // 閳光偓閳光偓 PDF 娑撳娴?閳光偓閳光偓

  /// 娑撳娴?PDF 閸掔増鏋冩惔鎾舵窗瑜版洩绱濇潻鏂挎礀閺堫剙婀寸捄顖氱窞閿涙稑銇戠拹銉﹀灗闂?PDF 閸愬懎顔愭潻鏂挎礀缁屽搫鐡х粭锔胯
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

    // 妤犲矁鐦?PDF 閺堝鏅ラ幀褝绱欏Λ鈧弻?%PDF 姒勬梹鏆熼敍?
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

  // 閳光偓閳光偓 閺傚洣娆㈤崨钘夋倳 閳光偓閳光偓

  /// 閺嶈宓侀崗鍐╂殶閹诡喚鏁撻幋?PDF 閺傚洣娆㈤崥宥忕礉閺嶇厧绱￠敍姝絜ar-mainAuthor-title.pdf
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

  // 閳光偓閳光偓 鏉堝懎濮弬瑙勭《 閳光偓閳光偓

  String? _extractFirst(dynamic list) {
    if (list is List && list.isNotEmpty) return list.first.toString();
    return null;
  }

  List<String> _extractCrossRefAuthors(dynamic authorList) {
    if (authorList is! List) return [];
    return authorList
        .map((author) {
          final map = author as Map<String, dynamic>;
          final given = map['given'] as String? ?? '';
          final family = map['family'] as String? ?? '';
          return '$family, $given'.trim().replaceAll(
            RegExp(r'^,\s*|,\s*$'),
            '',
          );
        })
        .where((name) => name.isNotEmpty)
        .toList();
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

  String? _extractPubMedYear(String? pubdate) {
    if (pubdate == null) return null;
    final match = RegExp(r'\d{4}').firstMatch(pubdate);
    return match?.group(0);
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
