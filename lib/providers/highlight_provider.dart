import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';
import '../data/models/book/highlight.dart';

/// 按文献 ID 管理划线标注的状态管理器。
///
/// 使用 `ref.watch(highlightProvider(documentId))` 获取当前文献的所有划线。
final highlightProvider =
    StateNotifierProvider.family<HighlightNotifier, List<Highlight>, String>(
  (ref, documentId) => HighlightNotifier(documentId),
);

class HighlightNotifier extends StateNotifier<List<Highlight>> {
  final String documentId;

  HighlightNotifier(this.documentId) : super([]) {
    _load();
  }

  void _load() {
    final raw = GStorage.highlights.get(documentId);
    if (raw == null) return;
    final list = (jsonDecode(raw as String) as List<dynamic>)
        .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
        .toList();
    state = list;
  }

  void _save() {
    final json = jsonEncode(state.map((h) => h.toJson()).toList());
    GStorage.highlights.put(documentId, json);
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
    _save();
  }

  void remove(String highlightId) {
    final idx = state.indexWhere((h) => h.id == highlightId);
    if (idx < 0) return;
    final target = state[idx];

    if (target.groupId != null) {
      state = state.where((h) => h.groupId != target.groupId).toList();
    } else {
      state = state.where((h) => h.id != highlightId).toList();
    }
    _save();
  }

  void updateColor(String highlightId, String color) {
    state = [
      for (final h in state)
        if (h.id == highlightId) h.withColor(color) else h,
    ];
    _save();
  }

  void updateNote(String highlightId, String note) {
    state = [
      for (final h in state)
        if (h.id == highlightId)
          h.withNote(note.isEmpty ? null : note)
        else
          h,
    ];
    _save();
  }
}
