import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import 'documents_provider.dart';

class StarredNotifier extends StateNotifier<Set<String>> {
  StarredNotifier() : super({}) {
    _load();
  }

  static const _key = 'starredDocIds';

  void _load() {
    final raw = GStorage.setting.get(_key) as List<dynamic>?;
    if (raw != null) {
      state = raw.cast<String>().toSet();
    }
  }

  Future<void> _save() async {
    await GStorage.setting.put(_key, state.toList());
  }

  void toggle(String docId) {
    final next = Set<String>.from(state);
    if (!next.remove(docId)) next.add(docId);
    state = next;
    _save();
  }

  /// 批量切换：若全部已星标则取消，否则全部加星
  void toggleMany(Set<String> docIds) {
    if (docIds.isEmpty) return;
    final allStarred = docIds.every(state.contains);
    final next = Set<String>.from(state);
    if (allStarred) {
      next.removeAll(docIds);
    } else {
      next.addAll(docIds);
    }
    state = next;
    _save();
  }

  void remove(String docId) {
    if (!state.contains(docId)) return;
    state = Set<String>.from(state)..remove(docId);
    _save();
  }
}

final starredProvider =
    StateNotifierProvider<StarredNotifier, Set<String>>((ref) {
  return StarredNotifier();
});

final starredDocsProvider = Provider<List<Document>>((ref) {
  final starredIds = ref.watch(starredProvider);
  final docs = ref.watch(documentsProvider);
  return docs.where((d) => starredIds.contains(d.id)).toList();
});

final starredCountProvider = Provider<int>((ref) {
  return ref.watch(starredDocsProvider).length;
});
