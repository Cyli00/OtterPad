import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/app_logger.dart';
import '../../core/storage/storage.dart';
import '../proxy_adapter.dart';

/// 学术文献 PDF 获取——从 DOI/PMID 到本地 PDF 文件的全部网络逻辑。
///
/// 下载链（按顺序尝试）：
///   1. 出版商：GET doi.org 落地页 → `<meta name="citation_pdf_url">` 全文入口
///      → 域名直链模式兜底
///   2. Unpaywall 开放获取
///
/// 校园网 / 机构 IP 靠第 1 步命中，因此该步请求按浏览器形态构造：真实 Chrome
/// UA、Accept 头、下载带 Referer。出版商对非浏览器 UA 与无来源的 PDF 直链会直接
/// 拒绝，即使 IP 有订阅权限也拿不到全文。
class PdfFetchService {
  PdfFetchService._();
  static final PdfFetchService instance = PdfFetchService._();

  /// 出版商站点普遍按 UA 拦截非浏览器客户端（Cloudflare / Incapsula 等）。
  static const _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// 公共 API（Unpaywall / NCBI）要求可识别客户端，不用浏览器 UA。
  static const _apiUserAgent = 'OtterPad/0.1 (Flutter; mailto:dev@otterpad.app)';

  static const _browserHeaders = {
    'User-Agent': _browserUserAgent,
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,'
        'image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 落地页/PDF 下载允许的重定向数：出版商登录跳转与 CDN 常见多跳。
  static const _maxRedirects = 10;

  /// 落地页最多读取的字节数，防止异常大页面拖住下载链。
  static const _maxLandingBytes = 3 << 20;

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: true,
      maxRedirects: _maxRedirects,
      headers: _browserHeaders,
    ),
  );

  /// 接入 `ProxyProvider` 代理总线，签名与其他网络服务一致。
  void applyProxy(Enum mode, String host, int port) {
    _dio.httpClientAdapter = buildProxyAdapter(mode.name, host, port);
  }

  // ─── DOI ─────────────────────────────────────────────────────────────────

  /// 按 DOI 依次尝试出版商 / Unpaywall，返回本地 PDF 路径。
  ///
  /// 全部失败返回空字符串（调用方据此判定"没有可用源"）。
  Future<String> fetchByDoi({
    required String doi,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    String? targetPath,
    CancelToken? cancelToken,
  }) async {
    String filePath = '';

    // 步骤 1: 出版商（落地页全文入口 + 域名直链模式）
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
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      log.d('出版商 PDF 获取失败: $e');
    }
    if (filePath.isNotEmpty) return filePath;

    // 步骤 2: Unpaywall 开放获取
    try {
      final uResp = await _dio.get(
        'https://api.unpaywall.org/v2/${_encodePathSegment(doi)}',
        queryParameters: {'email': 'dev@otterpad.app'},
        options: Options(headers: {'User-Agent': _apiUserAgent}),
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
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      log.d('Unpaywall PDF 获取失败: $e');
    }
    if (filePath.isNotEmpty) return filePath;

    return '';
  }

  // ─── PMID ────────────────────────────────────────────────────────────────

  /// Europe PMC PDF 直出端点。旧端点 backend/ptpmcrender.fcgi 已失效（520）。
  static String _pmcPdfUrl(String pmcid) =>
      'https://europepmc.org/articles/$pmcid?pdf=render';

  /// PMID 兜底：esummary 取 PMCID → Europe PMC 直出；任一步失败返回空。
  Future<String> fetchByPmid({
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
        options: Options(headers: {'User-Agent': _apiUserAgent}),
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
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      log.d('PMC PDF 获取失败: $e');
      return '';
    }
  }

  // ─── 出版商获取 ───────────────────────────────────────────────────────────

  /// 先取 DOI 落地页，优先走页面自带的全文入口，再退回域名直链模式。
  Future<String> _tryPublisherPdf({
    required String doi,
    String? year,
    List<String> authors = const [],
    required String title,
    required String fallbackId,
    String? targetPath,
    CancelToken? cancelToken,
  }) async {
    final doiUrl = _doiUrl(doi);
    Uri? landingUri;

    try {
      final probe = await _probeLanding(doiUrl, cancelToken: cancelToken);
      landingUri = probe.realUri;

      // DOI 直落 PDF（预印本服务器等）
      if (probe.isPdf) {
        return await _downloadPdf(
          url: probe.realUri.toString(),
          referer: doiUrl,
          year: year,
          authors: authors,
          title: title,
          fallbackId: fallbackId,
          targetPath: targetPath,
          cancelToken: cancelToken,
        );
      }

      // 出版商埋的全文入口：订阅态与 OA 态都指向真正的 PDF 地址
      final citationUrl = probe.html == null
          ? null
          : extractCitationPdfUrl(probe.html!, probe.realUri);
      if (citationUrl != null) {
        try {
          final path = await _downloadPdf(
            url: citationUrl,
            referer: probe.realUri.toString(),
            year: year,
            authors: authors,
            title: title,
            fallbackId: fallbackId,
            targetPath: targetPath,
            cancelToken: cancelToken,
          );
          if (path.isNotEmpty) return path;
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          log.d('citation_pdf_url 下载失败: $e');
        }
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) rethrow;
      log.d('DOI 落地页探测失败: $e');
    }

    // 域名直链模式兜底
    if (landingUri != null) {
      final pdfUrl = buildPublisherPdfUrl(landingUri, doi);
      if (pdfUrl != null) {
        try {
          return await _downloadPdf(
            url: pdfUrl,
            referer: landingUri.toString(),
            year: year,
            authors: authors,
            title: title,
            fallbackId: fallbackId,
            targetPath: targetPath,
            cancelToken: cancelToken,
          );
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          log.d('出版商直链下载失败: $e');
        }
      }
    }

    return '';
  }

  /// 取 DOI 落地页：一次 GET 同时拿到最终 URL、内容类型与 HTML。
  ///
  /// 不用 HEAD 探路——相当多出版商对 HEAD 直接 403/405，会让整条链空转。
  Future<({Uri realUri, bool isPdf, String? html})> _probeLanding(
    String url, {
    CancelToken? cancelToken,
  }) async {
    final resp = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (s) => s != null && s >= 200 && s < 400,
      ),
      cancelToken: cancelToken,
    );

    final realUri = resp.realUri;
    final contentType = resp.headers.value(Headers.contentTypeHeader) ?? '';
    final contentDisposition =
        resp.headers.value('content-disposition') ?? '';
    final body = resp.data;

    // 部分出版商/CDN 用 application/octet-stream + attachment 文件名下发 PDF
    if (contentType.contains('application/pdf') ||
        contentDisposition.toLowerCase().contains('.pdf')) {
      // 不在这里消费响应体：文件由 _downloadPdf 统一下载与校验
      await body?.stream.listen(null, onError: (_) {}).cancel();
      return (realUri: realUri, isPdf: true, html: null);
    }

    if (body == null) return (realUri: realUri, isPdf: false, html: null);

    final buffer = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      buffer.add(chunk);
      if (buffer.length >= _maxLandingBytes) break;
    }

    // 非 UTF-8 页面（gbk 等）中文会乱码，但 meta 标签是 ASCII，抽取不受影响
    return (
      realUri: realUri,
      isPdf: false,
      html: utf8.decode(buffer.takeBytes(), allowMalformed: true),
    );
  }

  // ─── 落地页全文入口抽取 ───────────────────────────────────────────────────

  static final _metaTagRe = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  static final _attrRe = RegExp(
    '''([\\w:-]+)\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'>]+))''',
  );

  /// 从落地页 HTML 抽取 `<meta name="citation_pdf_url">` 指向的绝对地址。
  ///
  /// 这是 Highwire/OpenAIRE 标准元标记（Google Scholar 同款），出版商在订阅态与
  /// OA 态都会给出真正的 PDF 入口，比硬编码直链稳。找不到返回 null。
  @visibleForTesting
  static String? extractCitationPdfUrl(String html, Uri baseUri) {
    for (final match in _metaTagRe.allMatches(html)) {
      final tag = match.group(0)!;
      final name = _attrValue(tag, 'name') ?? _attrValue(tag, 'property');
      if (name == null || name.toLowerCase() != 'citation_pdf_url') continue;

      final content = _attrValue(tag, 'content');
      if (content == null || content.trim().isEmpty) continue;

      final uri = baseUri.resolve(_unescapeHtml(content.trim()));
      if (uri.scheme == 'http' || uri.scheme == 'https') return uri.toString();
    }
    return null;
  }

  static String? _attrValue(String tag, String attr) {
    for (final match in _attrRe.allMatches(tag)) {
      if (match.group(1)!.toLowerCase() != attr) continue;
      return match.group(2) ?? match.group(3) ?? match.group(4);
    }
    return null;
  }

  static String _unescapeHtml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

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

  // ─── PDF 下载 ─────────────────────────────────────────────────────────────

  /// 下载 PDF 到文档目录，校验 %PDF 魔数后返回文件路径，校验失败则删除文件并返回空字符串。
  ///
  /// [referer] 传落地页地址：订阅态出版商会校验来源，缺失时拒绝直链。
  Future<String> _downloadPdf({
    required String url,
    String? referer,
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

    try {
      await _dio.download(
        url,
        pdfPath,
        options: Options(
          headers: {
            'Referer': ?referer,
            // 部分出版商按 Accept 决定返回全文还是 HTML 落地页
            'Accept': 'application/pdf,application/octet-stream;q=0.9,*/*;q=0.8',
          },
          // 大 PDF 与慢网络：30s 的默认收包超时会掐断传输，这里放到 3 分钟
          receiveTimeout: const Duration(minutes: 3),
        ),
        cancelToken: cancelToken,
      );
    } catch (e) {
      // 失败留下的是半截文件，不清掉会被下一次的 exists 短路当成有效 PDF
      final partial = File(pdfPath);
      if (await partial.exists()) await partial.delete();
      rethrow;
    }

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

  String _doiUrl(String doi) => 'https://doi.org/${_encodePathSegment(doi)}';

  String _encodePathSegment(String value) => Uri.encodeComponent(value);
}
