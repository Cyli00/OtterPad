import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/db_convert.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/data/models/book/highlight.dart';
import 'package:otter_pad/data/models/book/history_entry.dart';
import 'package:otter_pad/data/models/collection/favorite.dart';

/// 5.4 外键级联测试（ADR-0003）。
void main() {
  late db_lib.AppDatabase db;

  setUp(() => db = db_lib.AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('PRAGMA foreign_keys 为 ON', () async {
    final r = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(r.read<int>('foreign_keys'), 1);
  });

  test('history 对 documents 声明 ON DELETE CASCADE', () async {
    final rows = await db.customSelect('PRAGMA foreign_key_list(history)').get();
    final hasCascade = rows.any((r) {
      final table = r.read<String>('table');
      final onDelete = r.read<String>('on_delete');
      return table == 'documents' && onDelete == 'CASCADE';
    });
    expect(hasCascade, isTrue, reason: 'history.docId 必须对 documents CASCADE');
  });

  test('删 document 级联清 highlights/history/favorite_documents/zotero_items', () async {
    const id = 'd1';
    final now = DateTime.now();
    await db.into(db.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: id,
              title: 'T',
              authors: const [],
              keywords: const [],
              contentHash: null,
              addedAt: now,
            ),
          ),
        );
    // favorites 父行（favorite_documents.favoriteId REFERENCES favorites(id)）
    await db.into(db.favorites).insertOnConflictUpdate(
          favoriteCompanion(
            Favorite(
              id: '_default_',
              emoji: '📖',
              name: 'F',
              documentIds: const [],
              createdAt: now,
            ),
          ),
        );
    await db.into(db.highlights).insert(
          highlightCompanion(
            Highlight(
              id: 'h1',
              documentId: id,
              text: 'x',
              color: kDefaultHighlightColor,
              createdAt: now,
            ),
          ),
        );
    await db.into(db.history).insert(
          historyCompanion(HistoryEntry(docId: id, openedAt: now)),
        );
    await db.into(db.favoriteDocuments).insert(
          favoriteDocumentCompanion('_default_', id),
        );
    await db.into(db.zoteroItems).insert(zoteroItemCompanion('z1', id, 1));

    await (db.delete(db.documents)..where((t) => t.id.equals(id))).go();

    expect((await db.select(db.highlights).get()), isEmpty);
    expect((await db.select(db.history).get()), isEmpty);
    expect((await db.select(db.favoriteDocuments).get()), isEmpty);
    expect((await db.select(db.zoteroItems).get()), isEmpty);
  });
}