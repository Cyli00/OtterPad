import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Zotero 拉取结果：本次返回的 item 列表 + 最新库版本号。
class ZoteroSyncFetchResult {
  final List<Map<String, dynamic>> items;
  final int libraryVersion;

  const ZoteroSyncFetchResult({
    required this.items,
    required this.libraryVersion,
  });
}

class ZoteroSyncException implements Exception {
  final String message;
  const ZoteroSyncException(this.message);

  @override
  String toString() => message;
}

/// Zotero Web API v3 客户端（只读，单向导入）。
///
/// 纯 API 客户端：只负责认证、分页与增量拉取，返回原始 item JSON。
/// 落盘与 `Document` 映射由调用方编排，保持与 `IdentifierResolver` 同样的职责边界。
class ZoteroSyncService {
  ZoteroSyncService._();
  static final ZoteroSyncService instance = ZoteroSyncService._();

  static const _base = 'https://api.zotero.org';
  static const _pageSize = 100;

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Zotero-API-Version': '3'},
    ),
  );

  /// 接入 `ProxyProvider` 代理总线，签名与其他网络服务一致。
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

  /// 由 API Key 反查所属个人库 userID，免去用户手填。
  Future<int> _resolveUserId(String apiKey) async {
    final resp = await _dio.get('$_base/keys/$apiKey');
    final data = resp.data as Map<String, dynamic>;
    final userId = data['userID'];
    if (userId is int) return userId;
    final parsed = int.tryParse('$userId');
    if (parsed != null) return parsed;
    throw const ZoteroSyncException('无法解析 Zotero 用户 ID，请检查 API Key');
  }

  /// 增量拉取个人库顶层文献条目（跳过附件/笔记子条目）。
  ///
  /// [sinceVersion] 为上次同步到的库版本号，0 表示全量首次同步。
  /// [onProgress] 在每页返回后回调 `(已拉取条数, 文库总条数)`，用于 UI 实时进度。
  Future<ZoteroSyncFetchResult> fetchTopItems({
    required String apiKey,
    int sinceVersion = 0,
    void Function(int fetched, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final userId = await _resolveUserId(apiKey);
      final items = <Map<String, dynamic>>[];
      var start = 0;
      var libraryVersion = sinceVersion;

      while (true) {
        final resp = await _dio.get(
          '$_base/users/$userId/items/top',
          queryParameters: {
            'format': 'json',
            'since': sinceVersion,
            'limit': _pageSize,
            'start': start,
          },
          options: Options(headers: {'Zotero-API-Key': apiKey}),
          cancelToken: cancelToken,
        );

        final lastModified = resp.headers.value('last-modified-version');
        if (lastModified != null) {
          libraryVersion = int.tryParse(lastModified) ?? libraryVersion;
        }

        final page = (resp.data as List).cast<Map<String, dynamic>>();
        items.addAll(page);

        final total =
            int.tryParse(resp.headers.value('total-results') ?? '') ??
            items.length;
        start += page.length;
        onProgress?.call(items.length, total);
        if (page.isEmpty || start >= total) break;
      }

      return ZoteroSyncFetchResult(items: items, libraryVersion: libraryVersion);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  ZoteroSyncException _handleError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 403) {
      return const ZoteroSyncException('API Key 无效或无权限');
    }
    if (code == 404) {
      return const ZoteroSyncException('未找到对应的 Zotero 文库');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const ZoteroSyncException('网络连接失败，请检查网络或代理设置');
    }
    return ZoteroSyncException('Zotero 请求失败（${code ?? e.type.name}）');
  }
}
