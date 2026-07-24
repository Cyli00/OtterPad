import 'dart:async';

import 'app_database.dart';

/// Zotero 簿记的同步快照（ADR-0002：`watch()` 驱动，非手动写穿透缓存）。
///
/// `ZoteroSyncStore` 的同步读（`hasItem` / `importedCount` / `libraryVersion`）
/// 服务于无 `Ref` 调用点（backup_merge）与同步控制流（task_provider 的去重
/// 循环），不能改成 Riverpod provider。本类持有 `zotero_items` + 库版本游标
/// 的**派生快照**：[attach] 订阅两张表的 `watch()` 流，DB 任一变更（merge 写入、
/// restore reopen、文档删除触发 `zotero_items` CASCADE）自动同步到快照。
/// DB 仍是唯一真值源，快照是派生视图——不是三源之一。
class ZoteroSnapshot {
  static const libraryVersionKey = 'zotero_library_version';

  static Map<String, ({String? docId, int version})> items = const {};
  static int libraryVersion = 0;

  static StreamSubscription<List<Object>>? _itemsSub;
  static StreamSubscription<List<Object>>? _versionSub;

  /// 订阅 `zotero_items` + `meta` 流，填充快照。重开库前先 [detach]。
  static Future<void> attach(AppDatabase database) async {
    await detach();
    _itemsSub = database.select(database.zoteroItems).watch().listen((rows) {
      items = {
        for (final r in rows) r.zoteroKey: (docId: r.docId, version: r.version),
      };
    });
    _versionSub = (database.select(database.meta)
          ..where((t) => t.metaKey.equals(libraryVersionKey)))
        .watch()
        .listen((rows) {
      libraryVersion =
          rows.isEmpty ? 0 : (int.tryParse(rows.first.value) ?? 0);
    });
  }

  static Future<void> detach() async {
    await _itemsSub?.cancel();
    await _versionSub?.cancel();
    _itemsSub = null;
    _versionSub = null;
  }
}