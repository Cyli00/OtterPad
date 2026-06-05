// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';
import '../services/batch_extract_service.dart';
import '../services/doc_extract_service.dart';
import '../services/identifier_resolver.dart';
import '../services/metadata_search_service.dart';
import '../services/zotero_sync_service.dart';

enum ProxyMode { custom, system, none }

class ProxyState {
  final ProxyMode mode;
  final String host;
  final int port;

  const ProxyState({
    this.mode = ProxyMode.system,
    this.host = '127.0.0.1',
    this.port = 7890,
  });

  ProxyState copyWith({ProxyMode? mode, String? host, int? port}) {
    return ProxyState(
      mode: mode ?? this.mode,
      host: host ?? this.host,
      port: port ?? this.port,
    );
  }

  String get address => '$host:$port';
}

class ProxyNotifier extends StateNotifier<ProxyState> {
  static const String _modeKey = 'proxy_mode';
  static const String _hostKey = 'proxy_host';
  static const String _portKey = 'proxy_port';

  ProxyNotifier() : super(_load());

  static ProxyState _load() {
    final box = GStorage.setting;
    final modeStr = box.get(_modeKey, defaultValue: 'system') as String;
    final host = box.get(_hostKey, defaultValue: '127.0.0.1') as String;
    final port = box.get(_portKey, defaultValue: 7890) as int;

    final mode = ProxyMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => ProxyMode.system,
    );

    return ProxyState(mode: mode, host: host, port: port);
  }

  Future<void> setMode(ProxyMode mode) async {
    state = state.copyWith(mode: mode);
    await GStorage.setting.put(_modeKey, mode.name);
    _applyToResolver();
  }

  Future<void> setAddress(String host, int port) async {
    state = state.copyWith(host: host, port: port);
    await Future.wait([
      GStorage.setting.put(_hostKey, host),
      GStorage.setting.put(_portKey, port),
    ]);
    _applyToResolver();
  }

  void _applyToResolver() {
    IdentifierResolver.instance.applyProxy(state.mode, state.host, state.port);
    DocExtractService.instance.applyProxy(state.mode, state.host, state.port);
    BatchExtractService.instance.applyProxy(state.mode, state.host, state.port);
    ZoteroSyncService.instance.applyProxy(state.mode, state.host, state.port);
    MetadataSearchService.instance.applyProxy(state.mode, state.host, state.port);
  }

  /// 启动时调用，将已保存的配置应用到 Dio
  void applyInitial() => _applyToResolver();

  void reload() {
    state = _load();
    _applyToResolver();
  }
}

final proxyProvider = StateNotifierProvider<ProxyNotifier, ProxyState>((ref) {
  return ProxyNotifier();
});
