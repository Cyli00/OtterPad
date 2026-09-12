import 'package:dio/dio.dart';
import 'proxy_adapter.dart';
import 'package:html/parser.dart' as html_parser;

/// 客户端 URL 内容提取——为不支持原生 URL 工具的模型（OpenAI / 兼容端、
/// 旧版 Claude/Gemini）提供回退：把消息中的链接抓回来转成纯文本，由调用方
/// 注入提问上下文并随消息持久化（多轮重放保持一致）。
///
/// Anthropic `web_fetch` / Gemini `url_context` 的原生 server tool 路径
/// 不经过这里（见 AgentChatService）。
class UrlContextService {
  UrlContextService._();
  static final UrlContextService instance = UrlContextService._();

  /// 单条消息最多抓取的 URL 数。
  static const _maxUrls = 3;

  /// 单页正文截断长度（字符）——文献全文已占 system prompt 大头，网页
  /// 上下文只保留摘要级体量。
  static const _maxCharsPerPage = 10000;

  /// 排除空白与中英文常见包裹符，句尾标点在 [extractUrls] 里再剥一次。
  static final _urlPattern = RegExp('''https?://[^\\s<>"'()\\[\\]（）【】《》「」]+''');

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
      headers: {'User-Agent': 'Mozilla/5.0 (compatible; OtterPad)'},
    ),
  );

  /// 接入 `ProxyProvider` 代理总线，签名与其他网络服务一致。
  void applyProxy(Enum mode, String host, int port) {
    _dio.httpClientAdapter = buildProxyAdapter(
      mode.name,
      host,
      port,
    );
  }

  static bool containsUrl(String text) => _urlPattern.hasMatch(text);

  /// 提取消息中前 [_maxUrls] 个去重 URL（剥掉粘连的句尾标点）。
  static List<String> extractUrls(String text) {
    final seen = <String>{};
    for (final m in _urlPattern.allMatches(text)) {
      final url = m.group(0)!.replaceFirst(RegExp(r'[.,;:!?。，；：！？]+$'), '');
      seen.add(url);
      if (seen.length >= _maxUrls) break;
    }
    return seen.toList();
  }

  /// 抓取 [text] 中的链接并拼成上下文块；无链接返回 null。单页失败写入
  /// 失败说明（模型据此告知用户读取失败，而不是凭空臆造网页内容）。
  Future<String?> buildContext(String text, {CancelToken? cancelToken}) async {
    final urls = extractUrls(text);
    if (urls.isEmpty) return null;
    final blocks = <String>[];
    for (final url in urls) {
      blocks.add(await _fetchOne(url, cancelToken));
    }
    return blocks.join('\n\n');
  }

  Future<String> _fetchOne(String url, CancelToken? cancelToken) async {
    try {
      final resp = await _dio.get<String>(url, cancelToken: cancelToken);
      final contentType = resp.headers.value('content-type') ?? '';
      final body = resp.data ?? '';
      if (contentType.contains('html')) {
        final doc = html_parser.parse(body);
        doc
            .querySelectorAll('script, style, noscript')
            .forEach((e) => e.remove());
        final title = doc.querySelector('title')?.text.trim();
        final content = _clean(doc.body?.text ?? '');
        return _block(url, title: title, content: content);
      }
      if (contentType.contains('text') || contentType.contains('json')) {
        return _block(url, content: _clean(body));
      }
      return _block(url, content: '（不支持的内容类型：$contentType，未读取）');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      final reason = e.response != null
          ? 'HTTP ${e.response!.statusCode}'
          : e.type.name;
      return _block(url, content: '（获取失败：$reason）');
    }
  }

  static String _block(String url, {String? title, required String content}) {
    final truncated = content.length > _maxCharsPerPage
        ? '${content.substring(0, _maxCharsPerPage)}\n（已截断）'
        : content;
    return [
      '[网页内容] $url',
      if (title != null && title.isNotEmpty) '标题：$title',
      truncated,
    ].join('\n');
  }

  /// HTML 转文本后行内空白与空行大量堆积，折叠成可读形态。
  static String _clean(String text) => text
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*(\s*\n\s*)+'), '\n\n')
      .trim();
}
