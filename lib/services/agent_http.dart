import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

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

  void _applyAdapter(Dio dio) {
    final proxy = _proxy;
    if (proxy == null) return; // 启动早期未注入配置，保持默认（系统）行为
    final adapter = IOHttpClientAdapter();
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
    dio.httpClientAdapter = adapter;
  }
}
