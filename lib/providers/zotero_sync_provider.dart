// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

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
    final box = GStorage.setting;
    return ZoteroSyncState(
      apiKey: box.get(_apiKeyKey, defaultValue: '') as String,
    );
  }

  Future<void> setApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    state = state.copyWith(apiKey: trimmed);
    await GStorage.setting.put(_apiKeyKey, trimmed);
  }

  void reload() {
    state = _load();
  }
}

final zoteroSyncProvider =
    StateNotifierProvider<ZoteroSyncNotifier, ZoteroSyncState>((ref) {
      return ZoteroSyncNotifier();
    });

/// Zotero 同步簿记表（`GStorage.zoteroSync` box）。
///
/// 记录 `zoteroKey → {documentId, version}` 作为幂等键，以及库级
/// `_libraryVersion` 增量游标。结构按双向同步预留：单向导入暂只读 version 游标
/// 和判重，回写时可直接复用 documentId/version。
class ZoteroSyncStore {
  ZoteroSyncStore._();

  static const _libraryVersionKey = '_libraryVersion';

  static String _itemKey(String zoteroKey) => 'item:$zoteroKey';

  /// 上次同步到的库版本号，用于 `?since=` 增量拉取。
  static int get libraryVersion =>
      GStorage.zoteroSync.get(_libraryVersionKey, defaultValue: 0) as int;

  static Future<void> setLibraryVersion(int version) =>
      GStorage.zoteroSync.put(_libraryVersionKey, version);

  static bool hasItem(String zoteroKey) =>
      GStorage.zoteroSync.containsKey(_itemKey(zoteroKey));

  /// 已导入条目数（不含库版本标量）。
  static int get importedCount => GStorage.zoteroSync.keys
      .whereType<String>()
      .where((key) => key.startsWith('item:'))
      .length;

  static Future<void> recordItem(
    String zoteroKey,
    String documentId,
    int version,
  ) {
    return GStorage.zoteroSync.put(_itemKey(zoteroKey), {
      'documentId': documentId,
      'version': version,
    });
  }

  /// 本地删除文献时回收对应簿记，保持 [importedCount] 与 [hasItem] 判重诚实。
  /// 内容去重可能让多个 zoteroKey 映射到同一 documentId，故清掉全部匹配记录。
  static Future<void> removeByDocumentId(String documentId) async {
    final box = GStorage.zoteroSync;
    final stale = box.keys
        .whereType<String>()
        .where((key) => key.startsWith('item:'))
        .where((key) {
          final value = box.get(key);
          return value is Map && value['documentId'] == documentId;
        })
        .toList();
    for (final key in stale) {
      await box.delete(key);
    }
  }

  static Future<void> clear() => GStorage.zoteroSync.clear();
}
