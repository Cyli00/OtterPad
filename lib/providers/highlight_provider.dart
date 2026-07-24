import 'dart:async';

import 'package:drift/drift.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
import '../data/models/book/highlight.dart';

/// 按文献 ID 管理划线标注的状态管理器。
///
/// 使用 `ref.watch(highlightProvider(documentId))` 获取当前文献的所有划线。
class HighlightNotifier extends StateNotifier<List<Highlight>> {
  final String documentId;

  HighlightNotifier(this.documentId)
      : super(GStorage.cache.highlightsByDoc[documentId] ?? const []);

  Future<void> _upsert(Highlight h) async {
    await GStorage.db
        .into(GStorage.db.highlights)
        .insertOnConflictUpdate(highlightCompanion(h));
  }

  Future<void> _delete(String id) async {
    await (GStorage.db.delete(GStorage.db.highlights)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  /// 按组联动删除（同一次跨段落选择共享 groupId）。限定 docId 防误删他篇。
  Future<void> _deleteByGroup(String groupId) async {
    await (GStorage.db.delete(GStorage.db.highlights)
          ..where(
            (t) => t.groupId.equals(groupId) & t.docId.equals(documentId),
          ))
        .go();
  }

  void add(String text, {String color = kDefaultHighlightColor}) {
    if (state.any((h) => h.text == text)) return;

    final highlight = Highlight(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      documentId: documentId,
      text: text,
      color: color,
      createdAt: DateTime.now(),
    );
    state = [...state, highlight];
    unawaited(_upsert(highlight));
  }

  void remove(String highlightId) {
    final idx = state.indexWhere((h) => h.id == highlightId);
    if (idx < 0) return;
    final target = state[idx];

    if (target.groupId != null) {
      state = state.where((h) => h.groupId != target.groupId).toList();
      unawaited(_deleteByGroup(target.groupId!));
    } else {
      state = state.where((h) => h.id != highlightId).toList();
      unawaited(_delete(highlightId));
    }
  }

  void updateColor(String highlightId, String color) {
    final match = state.where((h) => h.id == highlightId).toList();
    if (match.isEmpty) return;
    final updated = match.first.withColor(color);
    state = [for (final h in state) if (h.id == highlightId) updated else h];
    unawaited(_upsert(updated));
  }

  void updateNote(String highlightId, String note) {
    final match = state.where((h) => h.id == highlightId).toList();
    if (match.isEmpty) return;
    final updated = match.first.withNote(note.isEmpty ? null : note);
    state = [for (final h in state) if (h.id == highlightId) updated else h];
    unawaited(_upsert(updated));
  }
}

final highlightProvider =
    StateNotifierProvider.family<HighlightNotifier, List<Highlight>, String>(
  (ref, documentId) => HighlightNotifier(documentId),
);