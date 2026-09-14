import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/app_database_provider.dart';
import '../core/storage/db_convert.dart';
import '../data/models/collection/favorite.dart';

/// 收藏夹列表（ADR-0001：Drift `watch()` 异步视图）。
///
/// `build()` 订阅 `favorites` + `favorite_documents` 两表 `watch()`，任一变更都重发，
/// 组装成带 `documentIds` 的 [Favorite] 列表（默认收藏夹置顶）。写方法非乐观——
/// 只写 DB，流自动刷新 `state`。
class FavoritesNotifier extends StreamNotifier<List<Favorite>> {
  @override
  Stream<List<Favorite>> build() {
    final database = ref.watch(appDatabaseProvider);
    // 默认收藏夹补建已移至 GStorage.init/reopen（副作用归 init 钩子，build 纯读）。
    // favorites 与 favorite_documents 任一表变更都重发组装结果（ADR-0001）。
    final controller = StreamController<List<Favorite>>();
    Future<void> emit() async {
      final favs = await database.select(database.favorites).get();
      final fds = await database.select(database.favoriteDocuments).get();
      final docsByFav = <String, List<String>>{};
      for (final fd in fds) {
        docsByFav.putIfAbsent(fd.favoriteId, () => []).add(fd.docId);
      }
      final list = [
        for (final f in favs)
          Favorite(
            id: f.id,
            emoji: f.emoji,
            name: f.name,
            documentIds: docsByFav[f.id] ?? const <String>[],
            createdAt: DateTime.fromMillisecondsSinceEpoch(f.createdAt),
          ),
      ];
      list.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });
      controller.add(list);
    }

    final sub1 = database
        .select(database.favorites)
        .watch()
        .listen((_) => emit());
    final sub2 = database
        .select(database.favoriteDocuments)
        .watch()
        .listen((_) => emit());
    emit();
    ref.onDispose(() {
      sub1.cancel();
      sub2.cancel();
      controller.close();
    });
    return controller.stream;
  }

  void reload() => ref.invalidateSelf();

  /// Drift 实例统一经 [appDatabaseProvider] 取（唯一来源，禁止直用 GStorage.db）。
  AppDatabase get _db => ref.read(appDatabaseProvider);

  /// 收藏夹存在性走 DB 查询（唯一真值源）——不读 watch() 流 state，
  /// 避免流未 emit 时误判不存在而静默丢弃写入。
  Future<bool> _favExists(String favoriteId) async {
    final row = await (_db.select(
      _db.favorites,
    )..where((t) => t.id.equals(favoriteId))).getSingleOrNull();
    return row != null;
  }

  Future<void> _upsertFav(Favorite f) async {
    await _db.into(_db.favorites).insertOnConflictUpdate(favoriteCompanion(f));
  }

  Future<void> _deleteFav(String id) async {
    await (_db.delete(_db.favorites)..where((t) => t.id.equals(id))).go();
  }

  Future<void> _link(String favoriteId, String docId) async {
    await _db
        .into(_db.favoriteDocuments)
        .insert(
          favoriteDocumentCompanion(favoriteId, docId),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _unlink(String favoriteId, String docId) async {
    await (_db.delete(_db.favoriteDocuments)..where(
          (t) => t.favoriteId.equals(favoriteId) & t.docId.equals(docId),
        ))
        .go();
  }

  /// 创建新收藏夹
  Future<Favorite> create({required String emoji, required String name}) async {
    final favorite = Favorite(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      emoji: emoji,
      name: name,
      documentIds: [],
      createdAt: DateTime.now(),
    );
    await _upsertFav(favorite);
    return favorite;
  }

  /// 重命名收藏夹（存在性走 DB 查询，见 [_favExists] 注释）
  Future<void> rename(String id, {String? emoji, String? name}) async {
    final row = await (_db.select(
      _db.favorites,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await _upsertFav(
      Favorite(
        id: row.id,
        emoji: emoji ?? row.emoji,
        name: name ?? row.name,
        documentIds: const [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      ),
    );
  }

  /// 删除收藏夹（默认收藏夹不可删除）
  Future<void> delete(String id) async {
    if (id == Favorite.defaultId) return;
    await _deleteFav(id);
  }

  /// 向收藏夹添加文献。重复添加由 _link 的 insertOrIgnore 天然去重。
  Future<void> addDocument(String favoriteId, String documentId) async {
    if (!await _favExists(favoriteId)) return;
    await _link(favoriteId, documentId);
  }

  /// 批量向收藏夹添加文献（已存在的自动跳过，单次写盘）。
  ///
  /// 返回真正新增的篇数——用于 UI 区分"已经在里面跳过了 N 篇"vs"全是新加的"。
  Future<int> addDocuments(
    String favoriteId,
    Iterable<String> documentIds,
  ) async {
    if (!await _favExists(favoriteId)) return 0;

    // 已有关联从 DB 读（唯一真值源），计算真正新增集
    final existing =
        (await (_db.select(
              _db.favoriteDocuments,
            )..where((t) => t.favoriteId.equals(favoriteId))).get())
            .map((r) => r.docId)
            .toSet();
    final toAdd = <String>[];
    for (final id in documentIds) {
      if (existing.add(id)) toAdd.add(id);
    }
    if (toAdd.isEmpty) return 0;

    await _db.batch((b) {
      for (final id in toAdd) {
        b.insert(
          _db.favoriteDocuments,
          favoriteDocumentCompanion(favoriteId, id),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
    return toAdd.length;
  }

  /// 从收藏夹移除文献。
  Future<void> removeDocument(String favoriteId, String documentId) async {
    await _unlink(favoriteId, documentId);
  }
}

final favoritesProvider =
    StreamNotifierProvider<FavoritesNotifier, List<Favorite>>(
      FavoritesNotifier.new,
    );
