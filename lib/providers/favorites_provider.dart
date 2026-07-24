import 'dart:async';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_database_provider.dart';
import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
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
    // 默认收藏夹幂等补建（首次启动或恢复的备份缺默认夹时）。写不触发 build 重跑
    // （build 只在 appDatabaseProvider 失效时重跑），故无自激循环。
    unawaited(_ensureDefault());
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

  List<Favorite> get _current => state.value ?? const <Favorite>[];

  /// 首次启动或数据缺失时确保默认"我的收藏"存在且置顶。
  Future<void> _ensureDefault() async {
    final exists = await (GStorage.db.select(GStorage.db.favorites)
          ..where((t) => t.id.equals(Favorite.defaultId)))
        .getSingleOrNull();
    if (exists == null) {
      await _upsertFav(_createDefault());
    }
  }

  static Favorite _createDefault() {
    final lang = PlatformDispatcher.instance.locale.languageCode;
    return Favorite(
      id: Favorite.defaultId,
      emoji: '📖',
      name: lang == 'zh' ? '我的收藏' : 'My Favorites',
      documentIds: [],
      createdAt: DateTime.now(),
    );
  }

  Future<void> _upsertFav(Favorite f) async {
    await GStorage.db
        .into(GStorage.db.favorites)
        .insertOnConflictUpdate(favoriteCompanion(f));
  }

  Future<void> _deleteFav(String id) async {
    await (GStorage.db.delete(GStorage.db.favorites)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  Future<void> _link(String favoriteId, String docId) async {
    await GStorage.db.into(GStorage.db.favoriteDocuments).insert(
          favoriteDocumentCompanion(favoriteId, docId),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _unlinkByDoc(String docId) async {
    await (GStorage.db.delete(GStorage.db.favoriteDocuments)
          ..where((t) => t.docId.equals(docId)))
        .go();
  }

  Future<void> _unlink(String favoriteId, String docId) async {
    await (GStorage.db.delete(GStorage.db.favoriteDocuments)
          ..where(
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

  /// 重命名收藏夹
  Future<void> rename(String id, {String? emoji, String? name}) async {
    final match = _current.where((f) => f.id == id).toList();
    if (match.isEmpty) return;
    final updated = match.first.copyWith(emoji: emoji, name: name);
    await _upsertFav(updated);
  }

  /// 删除收藏夹（默认收藏夹不可删除）
  Future<void> delete(String id) async {
    if (id == Favorite.defaultId) return;
    await _deleteFav(id);
  }

  /// 向收藏夹添加文献。
  Future<void> addDocument(String favoriteId, String documentId) async {
    final target = _current.firstWhere(
      (f) => f.id == favoriteId,
      orElse: () => _createDefault(),
    );
    if (target.id != favoriteId) return;
    if (target.documentIds.contains(documentId)) return;
    await _link(favoriteId, documentId);
  }

  /// 批量向收藏夹添加文献（已存在的自动跳过，单次写盘）。
  ///
  /// 返回真正新增的篇数——用于 UI 区分"已经在里面跳过了 N 篇"vs"全是新加的"。
  Future<int> addDocuments(
    String favoriteId,
    Iterable<String> documentIds,
  ) async {
    final target = _current.firstWhere(
      (f) => f.id == favoriteId,
      orElse: () => _createDefault(),
    );
    if (target.id != favoriteId) return 0;

    final existing = target.documentIds.toSet();
    final toAdd = <String>[];
    for (final id in documentIds) {
      if (existing.add(id)) toAdd.add(id);
    }
    if (toAdd.isEmpty) return 0;

    await GStorage.db.batch((b) {
      for (final id in toAdd) {
        b.insert(
          GStorage.db.favoriteDocuments,
          favoriteDocumentCompanion(favoriteId, id),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
    return toAdd.length;
  }

  /// 从所有收藏夹中移除指定文献（不删文献本身）。
  Future<void> removeDocumentFromAll(String documentId) async {
    if (!_current.any((f) => f.documentIds.contains(documentId))) return;
    await _unlinkByDoc(documentId);
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