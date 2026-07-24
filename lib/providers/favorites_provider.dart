import 'dart:async';
import 'dart:ui';

import 'package:drift/drift.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
import '../data/models/collection/favorite.dart';

/// 收藏夹状态管理
///
/// 收藏夹通过稳定 documentId 引用文献，不保存 PDF 绝对路径。
/// 持久化：favorites 表 + favorite_documents 关联表（Drift）。
class FavoritesNotifier extends StateNotifier<List<Favorite>> {
  FavoritesNotifier() : super([]) {
    _init();
  }

  void _init() {
    state = GStorage.cache.favorites;
    _ensureDefault();
  }

  void reload() {
    _init();
  }

  /// 首次启动或数据缺失时确保默认"我的收藏"存在且置顶。
  void _ensureDefault() {
    if (!state.any((f) => f.isDefault)) {
      final def = _createDefault();
      state = [def, ...state];
      unawaited(_upsertFav(def));
    } else if (!state.first.isDefault) {
      final def = state.firstWhere((f) => f.isDefault);
      state = [def, ...state.where((f) => !f.isDefault)];
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
    state = [...state, favorite];
    await _upsertFav(favorite);
    return favorite;
  }

  /// 重命名收藏夹
  Future<void> rename(String id, {String? emoji, String? name}) async {
    final match = state.where((f) => f.id == id).toList();
    if (match.isEmpty) return;
    final updated = match.first.copyWith(emoji: emoji, name: name);
    state = [for (final f in state) if (f.id == id) updated else f];
    await _upsertFav(updated);
  }

  /// 删除收藏夹（默认收藏夹不可删除）
  Future<void> delete(String id) async {
    if (id == Favorite.defaultId) return;
    state = state.where((f) => f.id != id).toList();
    await _deleteFav(id);
  }

  /// 向收藏夹添加文献。
  Future<void> addDocument(String favoriteId, String documentId) async {
    final target = state.firstWhere(
      (f) => f.id == favoriteId,
      orElse: () => _createDefault(),
    );
    if (target.id != favoriteId) return;
    if (target.documentIds.contains(documentId)) return;
    state = [
      for (final f in state)
        if (f.id == favoriteId)
          f.copyWith(documentIds: [...f.documentIds, documentId])
        else
          f,
    ];
    await _link(favoriteId, documentId);
  }

  /// 批量向收藏夹添加文献（已存在的自动跳过，单次写盘）。
  ///
  /// 返回真正新增的篇数——用于 UI 区分"已经在里面跳过了 N 篇"vs"全是新加的"。
  Future<int> addDocuments(
    String favoriteId,
    Iterable<String> documentIds,
  ) async {
    final target = state.firstWhere(
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

    state = [
      for (final f in state)
        if (f.id == favoriteId)
          f.copyWith(documentIds: [...f.documentIds, ...toAdd])
        else
          f,
    ];
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

  /// 从所有收藏夹中移除指定文献（级联删除时使用）。
  Future<void> removeDocumentFromAll(String documentId) async {
    bool changed = false;
    final updated = <Favorite>[];
    for (final f in state) {
      if (f.documentIds.contains(documentId)) {
        changed = true;
        updated.add(
          f.copyWith(
            documentIds: f.documentIds.where((id) => id != documentId).toList(),
          ),
        );
      } else {
        updated.add(f);
      }
    }
    if (changed) {
      state = updated;
      await _unlinkByDoc(documentId);
    }
  }

  /// 从收藏夹移除文献。
  Future<void> removeDocument(String favoriteId, String documentId) async {
    state = [
      for (final f in state)
        if (f.id == favoriteId)
          f.copyWith(
            documentIds: f.documentIds.where((id) => id != documentId).toList(),
          )
        else
          f,
    ];
    await _unlink(favoriteId, documentId);
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<Favorite>>((ref) {
      return FavoritesNotifier();
    });