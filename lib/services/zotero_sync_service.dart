import 'package:dio/dio.dart';
import 'proxy_adapter.dart';
import 'package:flutter/foundation.dart';

enum ZoteroLocalFailure {
  unavailable,
  disabled,
  incompatible,
  changed,
  invalidResponse,
  invalidFile,
}

class ZoteroLocalException implements Exception {
  const ZoteroLocalException(this.reason);
  final ZoteroLocalFailure reason;
}

class ZoteroLocalLibrary {
  const ZoteroLocalLibrary({
    required this.port,
    required this.items,
    this.serverId,
  });
  final int port;
  final String? serverId;
  final List<Map<String, dynamic>> items;
}

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

  @visibleForTesting
  ZoteroSyncService.forTesting(Dio localDio) {
    _localDio = localDio;
  }

  late Dio _localDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
      headers: {'Zotero-API-Version': '3'},
    ),
  );

  Future<Response<dynamic>> _localGet(
    int port,
    String path, {
    String? serverId,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    bool plain = false,
  }) async {
    if (port < 1 || port > 65535) {
      throw const ZoteroLocalException(ZoteroLocalFailure.unavailable);
    }
    try {
      final response = await _localDio.get<dynamic>(
        'http://127.0.0.1:$port/api/$path',
        queryParameters: query,
        options: Options(
          followRedirects: false,
          responseType: plain ? ResponseType.plain : ResponseType.json,
          headers: {'Zotero-Server-ID': ?serverId},
        ),
        cancelToken: cancelToken,
      );
      if (serverId != null &&
          response.headers.value('zotero-server-id') != serverId) {
        throw const ZoteroLocalException(ZoteroLocalFailure.changed);
      }
      return response;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ZoteroLocalException(switch (e.response?.statusCode) {
        403 => ZoteroLocalFailure.disabled,
        412 => ZoteroLocalFailure.changed,
        404 || 501 => ZoteroLocalFailure.incompatible,
        _ => ZoteroLocalFailure.unavailable,
      });
    }
  }

  Future<ZoteroLocalLibrary> fetchLocalLibrary({
    int port = 23119,
    CancelToken? cancelToken,
    void Function(int fetched, int total)? onProgress,
  }) async {
    final hello = await _localGet(
      port,
      '',
      cancelToken: cancelToken,
      plain: true,
    );
    if (hello.headers.value('zotero-api-version') != '3') {
      throw const ZoteroLocalException(ZoteroLocalFailure.incompatible);
    }
    final serverId = hello.headers.value('zotero-server-id');
    final items = <Map<String, dynamic>>[];
    final seen = <String>{};
    String? version;
    var start = 0;
    while (true) {
      final response = await _localGet(
        port,
        'users/0/items',
        serverId: serverId,
        cancelToken: cancelToken,
        // 旧版的 since=0 会漏掉尚未云端同步的条目，首次和后续均按页完整读取。
        query: {
          'format': 'json',
          'limit': _pageSize,
          'start': start,
          'sort': 'dateAdded',
          'direction': 'asc',
        },
      );
      final pageVersion = response.headers.value('last-modified-version');
      if (version != null && pageVersion != version) {
        throw const ZoteroLocalException(ZoteroLocalFailure.changed);
      }
      version = pageVersion;
      if (response.data is! List) {
        throw const ZoteroLocalException(ZoteroLocalFailure.invalidResponse);
      }
      final page = response.data as List;
      for (final entry in page) {
        if (entry is! Map<String, dynamic> ||
            entry['data'] is! Map ||
            entry['key'] is! String ||
            !RegExp(r'^[A-Z0-9]{8}$').hasMatch(entry['key'] as String)) {
          throw const ZoteroLocalException(ZoteroLocalFailure.invalidResponse);
        }
        if (!seen.add(entry['key'] as String)) {
          throw const ZoteroLocalException(ZoteroLocalFailure.changed);
        }
        items.add(entry);
      }
      start += page.length;
      final total = int.tryParse(response.headers.value('total-results') ?? '');
      onProgress?.call(start, total ?? start);
      if (page.isEmpty ||
          (total != null ? start >= total : page.length < _pageSize)) {
        break;
      }
    }
    return ZoteroLocalLibrary(port: port, serverId: serverId, items: items);
  }

  Future<Uri?> localAttachmentUri(
    ZoteroLocalLibrary library,
    String attachmentKey, {
    CancelToken? cancelToken,
  }) async {
    if (!RegExp(r'^[A-Z0-9]{8}$').hasMatch(attachmentKey)) {
      throw const ZoteroLocalException(ZoteroLocalFailure.invalidResponse);
    }
    final response = await _localGet(
      library.port,
      'users/0/items/$attachmentKey/file/view/url',
      serverId: library.serverId,
      cancelToken: cancelToken,
      plain: true,
    );
    final text = response.data?.toString().trim() ?? '';
    if (text.isEmpty || text == 'false') return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'file' ||
        (uri.host.isNotEmpty && uri.host != 'localhost') ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.toLowerCase().endsWith('.pdf')) {
      throw const ZoteroLocalException(ZoteroLocalFailure.invalidFile);
    }
    return uri;
  }

  Future<void> verifyLocalLibrary(
    ZoteroLocalLibrary library, {
    CancelToken? cancelToken,
  }) async {
    await _localGet(
      library.port,
      '',
      serverId: library.serverId,
      cancelToken: cancelToken,
      plain: true,
    );
  }

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Zotero-API-Version': '3'},
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

      return ZoteroSyncFetchResult(
        items: items,
        libraryVersion: libraryVersion,
      );
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
