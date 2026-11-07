import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/rust_backend.dart';
import '../core/rust_models.dart';
import '../data/models/collection/favorite.dart';
import '../src/rust/api.dart';

/// 收藏夹列表（默认收藏夹置顶，其余按创建时间）。数据在 Rust。
class FavoritesNotifier extends AsyncNotifier<List<Favorite>> {
  Backend get _rust => RustBackend.instance;

  @override
  Future<List<Favorite>> build() async {
    ref.watch(libraryEpochProvider);
    return [for (final f in await _rust.favorites()) favoriteFromRust(f)];
  }

  void reload() => bumpLibrary(ref);

  Future<Favorite?> _find(String id) async {
    for (final f in await _rust.favorites()) {
      if (f.id == id) return favoriteFromRust(f);
    }
    return null;
  }

  Future<Favorite> create({required String emoji, required String name}) async {
    final favorite = Favorite(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      emoji: emoji,
      name: name,
      documentIds: const [],
      createdAt: DateTime.now(),
    );
    await _rust.putFavorite(favorite: favoriteToRust(favorite));
    bumpLibrary(ref);
    return favorite;
  }

  /// Rust 写收藏夹时以 `documentIds` 覆盖关联，故沿用现有关联。
  Future<void> rename(String id, {String? emoji, String? name}) async {
    final current = await _find(id);
    if (current == null) return;
    await _rust.putFavorite(
      favorite: favoriteToRust(current.copyWith(emoji: emoji, name: name)),
    );
    bumpLibrary(ref);
  }

  /// 删除收藏夹（默认收藏夹不可删除）。
  Future<void> delete(String id) async {
    if (id == Favorite.defaultId) return;
    await _rust.deleteFavorite(id: id);
    bumpLibrary(ref);
  }

  Future<void> addDocument(String favoriteId, String documentId) async {
    if (await _find(favoriteId) == null) return;
    await _rust.favoriteDocument(
      favorite: favoriteId,
      document: documentId,
      add: true,
    );
    bumpLibrary(ref);
  }

  /// 批量添加，返回真正新增的篇数（已在收藏夹中的跳过）。
  Future<int> addDocuments(
    String favoriteId,
    Iterable<String> documentIds,
  ) async {
    final current = await _find(favoriteId);
    if (current == null) return 0;
    final existing = current.documentIds.toSet();
    final toAdd = [
      for (final id in documentIds)
        if (existing.add(id)) id,
    ];
    if (toAdd.isEmpty) return 0;
    for (final id in toAdd) {
      await _rust.favoriteDocument(
        favorite: favoriteId,
        document: id,
        add: true,
      );
    }
    bumpLibrary(ref);
    return toAdd.length;
  }

  Future<void> removeDocument(String favoriteId, String documentId) async {
    await _rust.favoriteDocument(
      favorite: favoriteId,
      document: documentId,
      add: false,
    );
    bumpLibrary(ref);
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<Favorite>>(
      FavoritesNotifier.new,
    );

/// 启动时补建默认「我的收藏」收藏夹（首次启动或恢复的数据缺它时）。
Future<void> ensureDefaultFavorite(Backend rust) async {
  final favorites = await rust.favorites();
  if (favorites.any((f) => f.id == Favorite.defaultId)) return;
  await rust.putFavorite(
    favorite: favoriteToRust(
      Favorite.defaultFor(PlatformDispatcher.instance.locale.languageCode),
    ),
  );
}
