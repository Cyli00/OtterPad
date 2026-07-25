// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/db_convert.dart';
import '../core/storage/secure_credential_vault.dart';
import '../core/storage/storage.dart';
import '../core/storage/zotero_snapshot.dart';

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
    return ZoteroSyncState(apiKey: SecureCredentialVault.read(_apiKeyKey));
  }

  Future<void> setApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    state = state.copyWith(apiKey: trimmed);
    await SecureCredentialVault.write(_apiKeyKey, trimmed);
  }

  void reload() {
    state = _load();
  }
}

final zoteroSyncProvider =
    StateNotifierProvider<ZoteroSyncNotifier, ZoteroSyncState>((ref) {
      return ZoteroSyncNotifier();
    });

/// Zotero 同步簿记：zotero_items 表 + meta.zotero_library_version（Drift）。
///
/// 记录 `zoteroKey → {documentId, version}` 作为幂等键，以及库级版本增量游标。
/// 静态类被多处直接调用（含无 `Ref` 的 backup_merge、task_provider 的同步去重
/// 循环），故保留**同步读 API**——读走 [ZoteroSnapshot]（`watch()` 驱动派生快照，
/// ADR-0002），写只写 DB 并乐观更新快照让同步读立即可见。
class ZoteroSyncStore {
  ZoteroSyncStore._();

  static const _libraryVersionMetaKey = ZoteroSnapshot.libraryVersionKey;

  /// 上次同步到的库版本号，用于 `?since=` 增量拉取。
  static int get libraryVersion => ZoteroSnapshot.libraryVersion;

  static Future<void> setLibraryVersion(int version) async {
    ZoteroSnapshot.libraryVersion = version;
    await GStorage.db.into(GStorage.db.meta).insertOnConflictUpdate(
          metaCompanion(_libraryVersionMetaKey, version.toString()),
        );
  }

  static bool hasItem(String zoteroKey) =>
      ZoteroSnapshot.items.containsKey(zoteroKey);

  /// 已导入条目数。
  static int get importedCount => ZoteroSnapshot.items.length;

  static Future<void> recordItem(
    String zoteroKey,
    String documentId,
    int version,
  ) async {
    ZoteroSnapshot.items[zoteroKey] =
        (docId: documentId, version: version);
    await GStorage.db.into(GStorage.db.zoteroItems).insertOnConflictUpdate(
          zoteroItemCompanion(zoteroKey, documentId, version),
        );
  }

  /// 本地删除文献时回收对应簿记，保持 [importedCount] 与 [hasItem] 判重诚实。
  /// 内容去重可能让多个 zoteroKey 映射到同一 documentId，故清掉全部匹配记录。
  static Future<void> removeByDocumentId(String documentId) async {
    final stale = ZoteroSnapshot.items.entries
        .where((e) => e.value.docId == documentId)
        .map((e) => e.key)
        .toList();
    for (final key in stale) {
      ZoteroSnapshot.items.remove(key);
    }
    await (GStorage.db.delete(GStorage.db.zoteroItems)
          ..where((t) => t.docId.equals(documentId)))
        .go();
  }

  static Future<void> clear() async {
    ZoteroSnapshot.items = {};
    ZoteroSnapshot.libraryVersion = 0;
    await GStorage.db.delete(GStorage.db.zoteroItems).go();
    await (GStorage.db.delete(GStorage.db.meta)
          ..where((t) => t.metaKey.equals(_libraryVersionMetaKey)))
        .go();
  }
}