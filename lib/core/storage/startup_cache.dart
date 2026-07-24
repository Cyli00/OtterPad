import 'package:drift/drift.dart' show OrderingTerm;

import '../../data/models/book/document.dart';
import '../../data/models/book/highlight.dart';
import '../../data/models/book/history_entry.dart';
import '../../data/models/collection/favorite.dart';
import 'app_database.dart' as db;
import 'db_convert.dart';

/// 启动时一次性从 Drift 预加载进内存的缓存（G2 决策）。
///
/// provider 构造时**同步**从这里读，写时更新缓存 + 写穿透 Drift——
/// 保住全代码库的同步状态契约，无空窗。history 取最近 500（bubble 语义）。
class StartupCache {
  List<Document> documents = [];
  List<HistoryEntry> history = [];
  List<Favorite> favorites = [];
  Map<String, List<Highlight>> highlightsByDoc = {};
  Map<String, ({String? docId, int version})> zoteroItems = {};
  int zoteroLibraryVersion = 0;

  static const zoteroLibraryVersionKey = 'zotero_library_version';

  static Future<StartupCache> load(db.AppDatabase database) async {
    final cache = StartupCache();

    // documents
    final docRows = await database.select(database.documents).get();
    cache.documents = docRows.map(documentFromRow).toList();

    // history：最近 500，按 openedAt 倒序
    final histRows = await (database.select(database.history)
          ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
          ..limit(500))
        .get();
    cache.history = histRows.map(historyFromRow).toList();

    // favorites + 关联表 documentIds
    final favRows = await database.select(database.favorites).get();
    final fdRows = await database.select(database.favoriteDocuments).get();
    final docsByFav = <String, List<String>>{};
    for (final r in fdRows) {
      docsByFav.putIfAbsent(r.favoriteId, () => []).add(r.docId);
    }
    cache.favorites = [
      for (final r in favRows)
        Favorite(
          id: r.id,
          emoji: r.emoji,
          name: r.name,
          documentIds: docsByFav[r.id] ?? const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
        ),
    ];

    // highlights：按 docId 分组
    final hlRows = await database.select(database.highlights).get();
    for (final r in hlRows) {
      cache.highlightsByDoc.putIfAbsent(r.docId, () => []).add(
            highlightFromRow(r),
          );
    }

    // zotero_items
    final zRows = await database.select(database.zoteroItems).get();
    for (final r in zRows) {
      cache.zoteroItems[r.zoteroKey] = zoteroItemFromRow(r);
    }

    // zotero 库版本游标（meta 表）
    final metaRow = await (database.select(database.meta)
          ..where((t) => t.metaKey.equals(zoteroLibraryVersionKey)))
        .getSingleOrNull();
    cache.zoteroLibraryVersion =
        metaRow == null ? 0 : (int.tryParse(metaRow.value) ?? 0);

    return cache;
  }
}