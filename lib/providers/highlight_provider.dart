import '../core/storage/storage_activity.dart';
import 'dart:async';
import 'dart:convert';
import '../core/app_logger.dart';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_database.dart'
    show AppDatabase, HighlightsCompanion;
import '../core/storage/app_database_provider.dart';
import '../core/storage/db_convert.dart';
import '../data/models/book/highlight.dart';
import '../data/models/book/reader_anchor.dart';
import '../services/reader/reader_document_index.dart';
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
    return (database.select(
      database.highlights,
    )..where((t) => t.docId.equals(documentId))).map(highlightFromRow).watch();
  }

  List<Highlight> get _current => state.value ?? const <Highlight>[];

  /// Drift 实例统一经 [appDatabaseProvider] 取（唯一来源，禁止直用 GStorage.db）。
  AppDatabase get _db => ref.read(appDatabaseProvider);

  Future<void> _upsert(Highlight h) => StorageActivity.run(() async {
    await _db
        .into(_db.highlights)
        .insertOnConflictUpdate(highlightCompanion(h));
  });

  Future<void> _delete(String id) async {
    await (_db.delete(_db.highlights)..where((t) => t.id.equals(id))).go();
  }

  /// 按组联动删除（同一次跨段落选择共享 groupId）。限定 docId 防误删他篇。
  Future<void> _deleteByGroup(String groupId) async {
    await (_db.delete(
          _db.highlights,
        )..where((t) => t.groupId.equals(groupId) & t.docId.equals(documentId)))
        .go();
  }

  /// 按 id 从 DB 查目标行（唯一真值源）——不读 watch() 流 state，
  /// 避免流未 emit 时误判不存在而静默丢弃。限定 docId 防跨篇误改。
  Future<Highlight?> _findById(String id) async {
    final row =
        await (_db.select(_db.highlights)
              ..where((t) => t.id.equals(id) & t.docId.equals(documentId)))
            .getSingleOrNull();
    return row == null ? null : highlightFromRow(row);
  }

  /// 新增标注并**同步**返回构造的 Highlight——阅读器 JS 桥需要立即拿到 id
  /// 画高亮（见 ReaderSessionNotifier.addHighlight），故写盘 fire-and-forget，
  /// 是 ADR-0001「写必 await 上抛」的有意例外。
  Highlight? add(
    String text, {
    String color = kDefaultHighlightColor,
    ReaderAnchor? anchor,
  }) {
    if (_current.any(
      (h) =>
          h.text == text &&
          h.anchor?.toJson().toString() == anchor?.toJson().toString(),
    )) {
      return null;
    }

    final highlight = Highlight(
      id: generateUuid(),
      documentId: documentId,
      text: text,
      color: color,
      anchor: anchor,
      createdAt: DateTime.now(),
    );
    unawaited(
      _upsert(highlight).catchError((Object e, StackTrace st) {
        log.w('[Highlight] 标注保存失败：$documentId', error: e, stackTrace: st);
      }),
    );
    return highlight;
  }

  Future<void> remove(String highlightId) => StorageActivity.run(() async {
    final target = await _findById(highlightId);
    if (target == null) return;

    if (target.groupId != null) {
      await _deleteByGroup(target.groupId!);
    } else {
      await _delete(highlightId);
    }
  });

  Future<void> updateColor(String highlightId, String color) =>
      StorageActivity.run(() async {
        final match = await _findById(highlightId);
        if (match == null) return;
        await _upsert(match.withColor(color));
      });

  Future<void> updateNote(String highlightId, String note) =>
      StorageActivity.run(() async {
        final match = await _findById(highlightId);
        if (match == null) return;
        await _upsert(match.withNote(note.isEmpty ? null : note));
      });

  Future<void> restoreAnchors(
    ReaderDocumentIndex index,
    Map<String, String> translations,
    String language,
  ) => StorageActivity.run(() async {
    final rows = await (_db.select(
      _db.highlights,
    )..where((t) => t.docId.equals(documentId))).get();
    for (final row in rows) {
      final h = highlightFromRow(row);
      if (h.anchor != null &&
          h.anchor!.ranges.every((r) => index.byId(r.paragraphId) != null)) {
        continue;
      }
      final oldRanges = h.anchor?.ranges;
      final repaired = <ReaderAnchorRange>[];
      for (final old in oldRanges ?? <ReaderAnchorRange?>[null]) {
        final matches = <ReaderAnchorRange>[];
        for (final p in index.paragraphs) {
          for (final entry in {
            'source': p.plainText,
            if (translations[p.hash]?.isNotEmpty == true)
              language: readerTranslatedText(translations[p.hash]!),
          }.entries) {
            if (old != null && old.language != entry.key) continue;
            final quote = old?.paragraphId.startsWith('pdf-page:') == true
                ? old!.quote.replaceAll(RegExp(r'\s+'), ' ').trim()
                : old?.quote ?? h.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            final at = entry.value.indexOf(quote);
            if (quote.isEmpty ||
                at < 0 ||
                entry.value.indexOf(quote, at + 1) >= 0) {
              continue;
            }
            if (old != null &&
                (!entry.value.substring(0, at).endsWith(old.prefix) ||
                    !entry.value
                        .substring(at + quote.length)
                        .startsWith(old.suffix))) {
              continue;
            }
            matches.add(
              p
                  .anchor(
                    language: entry.key,
                    displayText: entry.value,
                    start: at,
                    end: at + quote.length,
                  )
                  .ranges
                  .single,
            );
          }
        }
        if (matches.length != 1) {
          repaired.clear();
          break;
        }
        repaired.add(matches.single);
      }
      if (repaired.isEmpty) continue;
      final value = jsonEncode(ReaderAnchor(repaired).toJson());
      // 只补锚点，异步定位期间新增的笔记或颜色不能被旧快照覆盖。
      await (_db.update(_db.highlights)
            ..where((t) => t.id.equals(h.id) & t.docId.equals(documentId)))
          .write(HighlightsCompanion(anchor: Value(value)));
    }
  });
}

final highlightProvider =
    StreamNotifierProvider.family<HighlightNotifier, List<Highlight>, String>(
      HighlightNotifier.new,
    );
