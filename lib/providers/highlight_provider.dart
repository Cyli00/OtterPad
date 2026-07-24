import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_database_provider.dart';
import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
import '../data/models/book/highlight.dart';

/// 按文献 ID 管理划线标注（ADR-0001：Drift `watch()` 异步视图，family by docId）。
///
/// `build()` 返回该 docId 的 highlights `watch()` 流；写方法非乐观——只写 DB，
/// 流自动刷新 `state`。删除文献时 FK CASCADE 清 highlights 行，流自动重发空。
class HighlightNotifier extends StreamNotifier<List<Highlight>> {
  HighlightNotifier(this.documentId);

  final String documentId;

  @override
  Stream<List<Highlight>> build() {
    final database = ref.watch(appDatabaseProvider);
    return (database.select(database.highlights)
          ..where((t) => t.docId.equals(documentId)))
        .map(highlightFromRow)
        .watch();
  }

  List<Highlight> get _current =>
      state.value ?? const <Highlight>[];

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

  Highlight? add(String text, {String color = kDefaultHighlightColor}) {
    if (_current.any((h) => h.text == text)) return null;

    final highlight = Highlight(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      documentId: documentId,
      text: text,
      color: color,
      createdAt: DateTime.now(),
    );
    unawaited(_upsert(highlight));
    return highlight;
  }

  void remove(String highlightId) {
    final idx = _current.indexWhere((h) => h.id == highlightId);
    if (idx < 0) return;
    final target = _current[idx];

    if (target.groupId != null) {
      unawaited(_deleteByGroup(target.groupId!));
    } else {
      unawaited(_delete(highlightId));
    }
  }

  void updateColor(String highlightId, String color) {
    final match = _current.where((h) => h.id == highlightId).toList();
    if (match.isEmpty) return;
    final updated = match.first.withColor(color);
    unawaited(_upsert(updated));
  }

  void updateNote(String highlightId, String note) {
    final match = _current.where((h) => h.id == highlightId).toList();
    if (match.isEmpty) return;
    final updated = match.first.withNote(note.isEmpty ? null : note);
    unawaited(_upsert(updated));
  }
}

final highlightProvider =
    StreamNotifierProvider.family<HighlightNotifier, List<Highlight>, String>(
      HighlightNotifier.new,
    );