// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';

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
  static const String _modeKey = SettingsKeys.proxyMode;
  static const String _hostKey = SettingsKeys.proxyHost;
  static const String _portKey = SettingsKeys.proxyPort;

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
  }

  Future<void> setAddress(String host, int port) async {
    state = state.copyWith(host: host, port: port);
    await Future.wait([
      GStorage.setting.put(_hostKey, host),
      GStorage.setting.put(_portKey, port),
    ]);
  }

  void reload() {
    state = _load();
  }
}

final proxyProvider = StateNotifierProvider<ProxyNotifier, ProxyState>((ref) {
  return ProxyNotifier();
});
