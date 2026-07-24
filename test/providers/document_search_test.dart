import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/db_convert.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/providers/document_search_provider.dart';

/// 搜索降级路径测试。
///
/// 单测环境不打包 sqlite3_simple 的 simple.dll 原生扩展，故不调
/// `loadSimpleExtension` / `ensureFts5`——documents_fts 表不存在，
/// `searchDocuments` 的 FTS5 查询抛错被吞，退化为全字段 LIKE。
/// FTS5（jieba 分词 + 拼音）本体需 app 运行时（原生扩展已打包）验证。
void main() {
  late db_lib.AppDatabase db;

  setUp(() async {
    db = db_lib.AppDatabase(NativeDatabase.memory());
    await GStorage.initForTest(db);
  });

  tearDown(() async => db.close());

  test('LIKE 降级：标题子串命中（中文）', () async {
    final doc = Document(
      id: 'd1',
      title: '白细胞介素信号通路研究',
      authors: const [],
      contentHash: null,
      addedAt: DateTime.now(),
    );
    await db.into(db.documents).insertOnConflictUpdate(documentCompanion(doc));

    expect((await searchDocuments('信号')).any((d) => d.id == 'd1'), isTrue);
    expect((await searchDocuments('白细胞')).any((d) => d.id == 'd1'), isTrue);
  });

  test('LIKE 降级：doi / year 命中', () async {
    final doc = Document(
      id: 'd2',
      title: '无关标题',
      authors: const [],
      doi: '10.9999/abc',
      year: '2024',
      contentHash: null,
      addedAt: DateTime.now(),
    );
    await db.into(db.documents).insertOnConflictUpdate(documentCompanion(doc));

    expect((await searchDocuments('10.9999')).any((d) => d.id == 'd2'), isTrue);
    expect((await searchDocuments('2024')).any((d) => d.id == 'd2'), isTrue);
  });

  test('LIKE 降级：作者 / 期刊 / 关键词命中', () async {
    final doc = Document(
      id: 'd3',
      title: 'X',
      authors: const ['Smith J'],
      journal: 'Nature',
      keywords: const ['kinase'],
      contentHash: null,
      addedAt: DateTime.now(),
    );
    await db.into(db.documents).insertOnConflictUpdate(documentCompanion(doc));

    expect((await searchDocuments('Smith')).any((d) => d.id == 'd3'), isTrue);
    expect((await searchDocuments('Nature')).any((d) => d.id == 'd3'), isTrue);
    expect((await searchDocuments('kinase')).any((d) => d.id == 'd3'), isTrue);
  });

  test('空查询返回空', () async {
    expect(await searchDocuments(''), const []);
    expect(await searchDocuments('   '), const []);
  });
}