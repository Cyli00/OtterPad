import 'dart:convert';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';
import '../core/storage/storage.dart';
import '../data/models/collection/favorite.dart';

/// 收藏夹状态管理
///
/// 收藏夹通过稳定 documentId 引用文献，不保存 PDF 绝对路径。
class FavoritesNotifier extends StateNotifier<List<Favorite>> {
  final Box _box;

  FavoritesNotifier(this._box) : super([]) {
    _load();
  }

  /// 从 Hive 加载收藏夹列表，确保默认"我的收藏"始终存在且置顶
  void _load() {
    final raw = _box.get('favorites') as List<dynamic>?;
    var needsSchemaUpgrade = false;
    if (raw != null) {
      state = raw.map((e) {
        final json = Map<String, dynamic>.from(jsonDecode(e as String));
        if (json.containsKey('docPaths') && !json.containsKey('documentIds')) {
          needsSchemaUpgrade = true;
        }
        return Favorite.fromJson(json);
      }).toList();
    }
    // 首次启动或数据迁移：确保默认收藏夹存在
    if (!state.any((f) => f.isDefault)) {
      state = [_createDefault(), ...state];
      _save();
    } else if (!state.first.isDefault) {
      final def = state.firstWhere((f) => f.isDefault);
      state = [def, ...state.where((f) => !f.isDefault)];
      _save();
    } else if (needsSchemaUpgrade) {
      _save();
    }
  }

  static Favorite _createDefault() => Favorite(
    id: Favorite.defaultId,
    emoji: '📖',
    name: '我的收藏',
    documentIds: [],
    createdAt: DateTime.now(),
  );

  void reload() {
    _load();
  }

  /// 持久化到 Hive
  Future<void> _save() async {
    final encoded = state.map((f) => jsonEncode(f.toJson())).toList();
    await _box.put('favorites', encoded);
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

  /// 删除收藏夹（默认收藏夹不可删除）
  Future<void> delete(String id) async {
    if (id == Favorite.defaultId) return;
    state = state.where((f) => f.id != id).toList();
    await _save();
  }

  /// 向收藏夹添加文献。
  Future<void> addDocument(String favoriteId, String documentId) async {
    state = [
      for (final f in state)
        if (f.id == favoriteId && !f.documentIds.contains(documentId))
          f.copyWith(documentIds: [...f.documentIds, documentId])
        else
          f,
    ];
    await _save();
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
      await _save();
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
    await _save();
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<Favorite>>((ref) {
      return FavoritesNotifier(GStorage.favorites);
    });
