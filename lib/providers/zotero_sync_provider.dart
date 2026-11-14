// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/rust_backend.dart';
import '../core/rust_models.dart';
import '../core/storage/credential_vault.dart';

/// Zotero 同步凭据。当前单向导入只需 API Key（userID 由 Key 自动反查）。
class ZoteroSyncState {
  final String apiKey;

  const ZoteroSyncState({this.apiKey = ''});

  ZoteroSyncState copyWith({String? apiKey}) {
    return ZoteroSyncState(apiKey: apiKey ?? this.apiKey);
  }

  bool get isConfigured => apiKey.trim().isNotEmpty;
}

class ZoteroSyncNotifier extends StateNotifier<ZoteroSyncState> {
  static const _apiKeyKey = 'zotero_api_key';

  ZoteroSyncNotifier() : super(_load());

  static ZoteroSyncState _load() {
    return ZoteroSyncState(apiKey: CredentialVault.read(_apiKeyKey));
  }

  Future<void> setApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    state = state.copyWith(apiKey: trimmed);
    await CredentialVault.write(_apiKeyKey, trimmed);
  }

  void reload() {
    state = _load();
  }
}

final zoteroSyncProvider =
    StateNotifierProvider<ZoteroSyncNotifier, ZoteroSyncState>((ref) {
      return ZoteroSyncNotifier();
    });

/// 已从 Zotero 云端导入、仍在文库中的条目数。
final zoteroImportedCountProvider = FutureProvider<int>((ref) async {
  ref.watch(libraryEpochProvider);
  return (await RustBackend.instance.zoteroImportedCount()).toInt();
});
