import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';

import '../core/storage/storage.dart';

const _kHttp2Enabled = 'general_http2_enabled';

/// AI 请求统一 HTTP 出口：所有 Agent 调用（对话 / 翻译 / 生图 / 连通性
/// 测试）从这里取 Dio，禁止各自 `Dio(BaseOptions(...))`。
///
/// 解决两件事：
/// - **代理**：接入 `ProxyProvider` 代理总线（此前各调用点裸建 Dio，
///   自定义代理对 AI 请求完全不生效）；
/// - **连接复用**：按超时配置缓存实例（配置种类极少），同配置请求共享
///   HttpClient 连接池，省去逐条消息的 DNS/TLS 握手。
class AgentHttp {
  AgentHttp._();
  static final AgentHttp instance = AgentHttp._();

  final Map<String, Dio> _cache = {};
  (String mode, String host, int port)? _proxy;

  static bool get http2Enabled =>
      GStorage.setting.get(_kHttp2Enabled) as bool? ?? false;

  /// 取（或建）对应超时配置的共享 Dio。新实例自动带上当前代理配置。
  Dio dio({
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(minutes: 5),
  }) {
    final key =
        '${connectTimeout.inMilliseconds}:'
        '${receiveTimeout.inMilliseconds}';
    return _cache.putIfAbsent(key, () {
      final d = Dio(
        BaseOptions(
          connectTimeout: connectTimeout,
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: receiveTimeout,
        ),
      );
      _applyAdapter(d);
      return d;
    });
  }

  /// 接入 `ProxyProvider` 代理总线，签名与其他网络服务一致。
  void applyProxy(Enum mode, String host, int port) {
    _proxy = (mode.name, host, port);
    for (final d in _cache.values) {
      _applyAdapter(d);
    }
  }

  /// 清除缓存的 Dio 实例，下次请求时按当前设置重建。
  void resetInstances() {
    _cache.clear();
  }

  // ── HTTP/1.1 adapter ──

  IOHttpClientAdapter _buildH11Adapter() {
    final adapter = IOHttpClientAdapter();
    final proxy = _proxy;
    if (proxy == null) return adapter;
    switch (proxy.$1) {
      case 'custom':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY ${proxy.$2}:${proxy.$3}';
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
    return adapter;
  }

  // ── adapter 注入 ──

  void _applyAdapter(Dio dio) {
    final h11 = _buildH11Adapter();
    if (!http2Enabled) {
      dio.httpClientAdapter = h11;
      return;
    }
    dio.httpClientAdapter = Http2Adapter(
      ConnectionManager(
        idleTimeout: const Duration(seconds: 15),
      ),
      fallbackAdapter: h11,
    );
  }
}
