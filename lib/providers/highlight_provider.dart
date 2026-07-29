import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/app_database_provider.dart';
import '../core/storage/db_convert.dart';
import '../data/models/book/highlight.dart';
import '../utils/uuid.dart';

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

  /// Drift 实例统一经 [appDatabaseProvider] 取（唯一来源，禁止直用 GStorage.db）。
  AppDatabase get _db => ref.read(appDatabaseProvider);

  Future<void> _upsert(Highlight h) async {
    await _db
        .into(_db.highlights)
        .insertOnConflictUpdate(highlightCompanion(h));
  }

  Future<void> _delete(String id) async {
    await (_db.delete(_db.highlights)..where((t) => t.id.equals(id))).go();
  }

  /// 按组联动删除（同一次跨段落选择共享 groupId）。限定 docId 防误删他篇。
  Future<void> _deleteByGroup(String groupId) async {
    await (_db.delete(_db.highlights)
          ..where(
            (t) => t.groupId.equals(groupId) & t.docId.equals(documentId),
          ))
        .go();
  }

  /// 按 id 从 DB 查目标行（唯一真值源）——不读 watch() 流 state，
  /// 避免流未 emit 时误判不存在而静默丢弃。限定 docId 防跨篇误改。
  Future<Highlight?> _findById(String id) async {
    final row = await (_db.select(_db.highlights)
          ..where((t) => t.id.equals(id) & t.docId.equals(documentId)))
        .getSingleOrNull();
    return row == null ? null : highlightFromRow(row);
  }

  /// 新增标注并**同步**返回构造的 Highlight——阅读器 JS 桥需要立即拿到 id
  /// 画高亮（见 ReaderSessionNotifier.addHighlight），故写盘 fire-and-forget，
  /// 是 ADR-0001「写必 await 上抛」的有意例外。
  Highlight? add(String text, {String color = kDefaultHighlightColor}) {
    if (_current.any((h) => h.text == text)) return null;

    final highlight = Highlight(
      id: generateUuid(),
      documentId: documentId,
      text: text,
      color: color,
      createdAt: DateTime.now(),
    );
    unawaited(_upsert(highlight));
    return highlight;
  }

  Future<void> remove(String highlightId) async {
    final target = await _findById(highlightId);
    if (target == null) return;

    if (target.groupId != null) {
      await _deleteByGroup(target.groupId!);
    } else {
      await _delete(highlightId);
    }
  }

  Future<void> updateColor(String highlightId, String color) async {
    final match = await _findById(highlightId);
    if (match == null) return;
    await _upsert(match.withColor(color));
  }

  Future<void> updateNote(String highlightId, String note) async {
    final match = await _findById(highlightId);
    if (match == null) return;
    await _upsert(match.withNote(note.isEmpty ? null : note));
  }
}

final highlightProvider =
    StreamNotifierProvider.family<HighlightNotifier, List<Highlight>, String>(
      HighlightNotifier.new,
    );