import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';

void main() {
  late AppDatabase database;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    // 单测使用 SQLite 内置分词器，只验证同步与回滚，不代替 jieba 设备测试。
    await database.customStatement(
      'CREATE VIRTUAL TABLE documents_fts USING fts5(id UNINDEXED, title, authors, journal, keywords)',
    );
    await database.ensureFts5();
  });
  tearDown(() => database.close());

  Future<void> addDocument() => database.customStatement(
    "INSERT INTO documents(id,title,authors,keywords,addedAt) VALUES ('d','论文','[]','[]',1)",
  );

  test('正常索引不重建', () async {
    await addDocument();
    expect(await database.synchronizeFts(), false);
  });
  test('文献为空也要清理残留索引', () async {
    await database.customStatement(
      "INSERT INTO documents_fts(id,title) VALUES ('ghost','旧资料')",
    );
    expect(await database.synchronizeFts(), true);
    expect(
      await database.customSelect('SELECT * FROM documents_fts').get(),
      isEmpty,
    );
  });
  for (final change in ["id='ghost'", "rowid=42", "title='旧内容'"]) {
    test('行数相同仍修复 $change', () async {
      await addDocument();
      await database.customStatement('UPDATE documents_fts SET $change');
      expect(await database.synchronizeFts(), true);
      final row = await database
          .customSelect('SELECT rowid,id,title FROM documents_fts')
          .getSingle();
      expect(row.read<int>('rowid'), 1);
      expect(row.read<String>('id'), 'd');
      expect(row.read<String>('title'), '论文');
      expect(await database.synchronizeFts(), false);
    });
  }
  test('重建失败时保留原索引，不留下清空一半的状态', () async {
    await addDocument();
    await database.customStatement("UPDATE documents_fts SET title='旧内容'");
    await database.customStatement(
      "INSERT INTO documents_fts(id,title) VALUES ('extra','额外索引')",
    );
    await database.customStatement(
      'ALTER TABLE documents RENAME COLUMN keywords TO invalid_column',
    );
    await expectLater(database.synchronizeFts(), throwsA(anything));
    expect(
      (await database
              .customSelect("SELECT title FROM documents_fts WHERE id='d'")
              .getSingle())
          .read<String>('title'),
      '旧内容',
    );
  });
}
