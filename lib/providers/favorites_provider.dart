import 'dart:convert';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';
import '../core/storage/storage.dart';
import '../data/models/collection/favorite.dart';

/// 收藏夹状态管理
///
/// 收藏夹通过 Hive 存储文献的原始路径引用（指向 NightReader/docs/ 中的文件），
/// 不复制文件，不创建链接——同一份 PDF 只占一份磁盘和一份缩略图缓存。
class FavoritesNotifier extends StateNotifier<List<Favorite>> {
  final Box _box;

  FavoritesNotifier(this._box) : super([]) {
    _load();
  }

  /// 从 Hive 加载收藏夹列表
  void _load() {
    final raw = _box.get('favorites') as List<dynamic>?;
    if (raw == null) {
      state = [];
      return;
    }
    state = raw
        .map((e) => Favorite.fromJson(
            Map<String, dynamic>.from(jsonDecode(e as String))))
        .toList();
  }

  /// 持久化到 Hive
  Future<void> _save() async {
    final encoded = state.map((f) => jsonEncode(f.toJson())).toList();
    await _box.put('favorites', encoded);
  }

  /// 创建新收藏夹
  Future<Favorite> create({
    required String emoji,
    required String name,
  }) async {
    final favorite = Favorite(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      emoji: emoji,
      name: name,
      docPaths: [],
      createdAt: DateTime.now(),
    );
    state = [...state, favorite];
    await _save();
    return favorite;
  }

  /// 重命名收藏夹
  Future<void> rename(String id, {String? emoji, String? name}) async {
    state = [
      for (final f in state)
        if (f.id == id) f.copyWith(emoji: emoji, name: name) else f,
    ];
    await _save();
  }

  /// 删除收藏夹
  Future<void> delete(String id) async {
    state = state.where((f) => f.id != id).toList();
    await _save();
  }

  /// 向收藏夹添加文档
  Future<void> addDoc(String favoriteId, String docPath) async {
    state = [
      for (final f in state)
        if (f.id == favoriteId && !f.docPaths.contains(docPath))
          f.copyWith(docPaths: [...f.docPaths, docPath])
        else
          f,
    ];
    await _save();
  }

  /// 从收藏夹移除文档
  Future<void> removeDoc(String favoriteId, String docPath) async {
    state = [
      for (final f in state)
        if (f.id == favoriteId)
          f.copyWith(
              docPaths: f.docPaths.where((p) => p != docPath).toList())
        else
          f,
    ];
    await _save();
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<Favorite>>((ref) {
  return FavoritesNotifier(GStorage.favorites);
});
