import 'dart:io';

import 'package:drift/drift.dart' show InsertMode;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/db_convert.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/core/storage/zotero_snapshot.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/data/models/book/highlight.dart';
import 'package:otter_pad/data/models/book/history_entry.dart';
import 'package:otter_pad/data/models/collection/favorite.dart';
import 'package:otter_pad/services/backup_merge_service.dart';
import 'package:otter_pad/services/backup_restore_service.dart';
import 'package:path/path.dart' as p;

/// 5.1 Backup merge 集成测试（ADR-0004：ID 重映射 + history 500 上限事务化）。
void main() {
  late db_lib.AppDatabase live;
  late Directory tmpDir;
  late String backupPath;

  setUp(() async {
    live = db_lib.AppDatabase(NativeDatabase.memory());
    await GStorage.initForTest(live);
    tmpDir = await Directory.systemTemp.createTemp('otter_merge_test');
    backupPath = p.join(tmpDir.path, 'backup.db');
  });

  tearDown(() async {
    await ZoteroSnapshot.detach();
    await live.close();
    await tmpDir.delete(recursive: true);
  });

  /// 用文件 DB 构造备份（merge 以 `AppDatabase.file(path)` 打开备份）。
  Future<db_lib.AppDatabase> openBackup() async {
    final f = File(backupPath);
    if (await f.exists()) await f.delete();
    return db_lib.AppDatabase(NativeDatabase(f));
  }

  test('相同 DOI、不同 ID：备份文档不插入，子记录重映射到本地保留文档', () async {
    // live: A (doi 10.0/a)
    await live.into(live.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'A',
              title: 'A',
              authors: const ['X'],
              keywords: const [],
              doi: '10.0/a',
              contentHash: null,
              addedAt: DateTime(2020, 1, 1),
            ),
          ),
        );

    // backup: B (doi 10.0/a，与 A 同 DOI 不同 ID) + highlight(docId=B)
    final backupDb = await openBackup();
    await backupDb.into(backupDb.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'B',
              title: 'B',
              authors: const ['X'],
              keywords: const [],
              doi: '10.0/a',
              contentHash: null,
              addedAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await backupDb.into(backupDb.highlights).insert(
          highlightCompanion(
            Highlight(
              id: 'hB',
              documentId: 'B',
              text: 't',
              color: kDefaultHighlightColor,
              createdAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await backupDb.close();

    final result = await BackupMergeService.merge(
      backupDbPath: backupPath,
      extractedDocsDir: null,
      scope: BackupRestoreScope.libraryOnly,
    );

    expect(result.documentsAdded, 0, reason: 'B 被 DOI 判重，不新增');
    final docs = await live.select(live.documents).get();
    expect(docs.map((d) => d.id).toList(), ['A']);
    final hls = await live.select(live.highlights).get();
    expect(hls.length, 1);
    expect(hls.single.id, 'hB');
    expect(hls.single.docId, 'A', reason: 'highlight 的 docId 重映射到保留的本地 A');
  });

  test('相同标题+年份+首作者、不同 ID：子记录重映射到本地保留文档', () async {
    await live.into(live.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'A',
              title: 'Same Title',
              authors: const ['Same Author'],
              year: '2020',
              keywords: const [],
              contentHash: null,
              addedAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    final backupDb = await openBackup();
    await backupDb.into(backupDb.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'B',
              title: 'Same Title',
              authors: const ['Same Author'],
              year: '2020',
              keywords: const [],
              contentHash: null,
              addedAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await backupDb.into(backupDb.highlights).insert(
          highlightCompanion(
            Highlight(
              id: 'hB',
              documentId: 'B',
              text: 't',
              color: kDefaultHighlightColor,
              createdAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await backupDb.close();

    await BackupMergeService.merge(
      backupDbPath: backupPath,
      extractedDocsDir: null,
      scope: BackupRestoreScope.libraryOnly,
    );

    final docs = await live.select(live.documents).get();
    expect(docs.map((d) => d.id).toList(), ['A']);
    final hls = await live.select(live.highlights).get();
    expect(hls.single.docId, 'A');
  });

  test('同 id 文档 enrich 不清空本地子记录（upsert 不走 REPLACE 级联）', () async {
    // live: A（无 contentHash）+ 本地独有的 highlight / history / 收藏关联
    await live.into(live.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'A',
              title: 'A',
              authors: const ['X'],
              keywords: const [],
              contentHash: null,
              addedAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await live.into(live.highlights).insert(
          highlightCompanion(
            Highlight(
              id: 'hA',
              documentId: 'A',
              text: 't',
              color: kDefaultHighlightColor,
              createdAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await live.into(live.history).insert(
          historyCompanion(
            HistoryEntry(docId: 'A', openedAt: DateTime(2020, 1, 2)),
          ),
        );
    await live.into(live.favorites).insert(
          favoriteCompanion(
            Favorite(
              id: 'fav1',
              emoji: '⭐',
              name: 'f',
              documentIds: const [],
              createdAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await live
        .into(live.favoriteDocuments)
        .insert(favoriteDocumentCompanion('fav1', 'A'));

    // backup: 同 id A 带 contentHash → 触发 _enrichDocument，upsert 已存在行
    final backupDb = await openBackup();
    await backupDb.into(backupDb.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'A',
              title: 'A',
              authors: const ['X'],
              keywords: const [],
              contentHash: 'hash1',
              addedAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await backupDb.close();

    await BackupMergeService.merge(
      backupDbPath: backupPath,
      extractedDocsDir: null,
      scope: BackupRestoreScope.libraryOnly,
    );

    final doc = await (live.select(live.documents)
          ..where((t) => t.id.equals('A')))
        .getSingle();
    expect(doc.contentHash, 'hash1', reason: 'enrich 生效');
    // INSERT OR REPLACE 是 DELETE+INSERT，FK ON 时内部删除触发 CASCADE 清空
    // 子表——upsert（ON CONFLICT DO UPDATE）必须保留本地子记录。
    expect((await live.select(live.highlights).get()).length, 1);
    expect((await live.select(live.history).get()).length, 1);
    expect((await live.select(live.favoriteDocuments).get()).length, 1);
  });

  test('孤儿子记录（docId 无映射）跳过并计数，不中断 merge', () async {
    final backupDb = await openBackup();
    // 构造备份自身的 dangling 引用：关 FK 后插入指向不存在文档的子记录
    await backupDb.customStatement('PRAGMA foreign_keys = OFF');
    await backupDb.into(backupDb.highlights).insert(
          highlightCompanion(
            Highlight(
              id: 'h1',
              documentId: 'ghost',
              text: 't',
              color: kDefaultHighlightColor,
              createdAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await backupDb.into(backupDb.history).insert(
          historyCompanion(
            HistoryEntry(docId: 'ghost', openedAt: DateTime(2020, 1, 1)),
          ),
        );
    await backupDb.into(backupDb.favorites).insert(
          favoriteCompanion(
            Favorite(
              id: 'f1',
              emoji: '⭐',
              name: 'f',
              documentIds: const [],
              createdAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await backupDb
        .into(backupDb.favoriteDocuments)
        .insert(favoriteDocumentCompanion('f1', 'ghost'));
    await backupDb
        .into(backupDb.zoteroItems)
        .insert(zoteroItemCompanion('zk1', 'ghost', 3));
    await backupDb.close();

    final result = await BackupMergeService.merge(
      backupDbPath: backupPath,
      extractedDocsDir: null,
      scope: BackupRestoreScope.full,
    );

    expect(result.skippedOrphans, 4,
        reason: 'highlight / history / 收藏关联 / zotero 各 1');
    expect(await live.select(live.highlights).get(), isEmpty);
    expect(await live.select(live.history).get(), isEmpty);
    expect(await live.select(live.favoriteDocuments).get(), isEmpty);
    expect(await live.select(live.zoteroItems).get(), isEmpty);
  });

  test('文献文件目录按 idMap 重映射（判重命中拷入本地 id 目录）', () async {
    // live: A；backup: B 与 A 同 DOI（判重映射 B→A）+ 文件目录 B/
    await live.into(live.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'A',
              title: 'A',
              authors: const ['X'],
              keywords: const [],
              doi: '10.0/a',
              contentHash: null,
              addedAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    final backupDb = await openBackup();
    await backupDb.into(backupDb.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'B',
              title: 'B',
              authors: const ['X'],
              keywords: const [],
              doi: '10.0/a',
              contentHash: 'hash1',
              addedAt: DateTime(2020, 1, 1),
            ),
          ),
        );
    await backupDb.close();

    final extracted = Directory(p.join(tmpDir.path, 'extracted'));
    Directory(p.join(extracted.path, 'B')).createSync(recursive: true);
    File(p.join(extracted.path, 'B', 'source.pdf')).writeAsStringSync('pdf');
    // 悬空目录（备份库中无对应文档行）不导入
    Directory(p.join(extracted.path, 'ghost')).createSync(recursive: true);
    File(p.join(extracted.path, 'ghost', 'source.pdf')).writeAsStringSync('x');

    final libDir = Directory(p.join(tmpDir.path, 'library'))
      ..createSync(recursive: true);
    await GStorage.initForTest(live, libraryDirPath: libDir.path);

    final result = await BackupMergeService.merge(
      backupDbPath: backupPath,
      extractedDocsDir: extracted,
      scope: BackupRestoreScope.libraryOnly,
    );

    expect(File(p.join(libDir.path, 'A', 'source.pdf')).existsSync(), isTrue,
        reason: 'B 判重映射到 A，文件应落入本地 A 目录');
    expect(Directory(p.join(libDir.path, 'B')).existsSync(), isFalse,
        reason: '按备份原 id 拷贝会产生打不开的孤儿目录');
    expect(Directory(p.join(libDir.path, 'ghost')).existsSync(), isFalse);
    expect(result.filesCopied, 1);
  });

  test('history merge 后 DB 不超过 500（事务化删除多余行）', () async {
    final base = DateTime(2020, 1, 1);
    // live: 500 docs + 500 history（h0..h499，openedAt 递增）
    await live.batch((b) {
      for (var i = 0; i < 500; i++) {
        final id = 'h$i';
        b.insert(
          live.documents,
          documentCompanion(
            Document(
              id: id,
              title: id,
              authors: const [],
              keywords: const [],
              contentHash: null,
              addedAt: base,
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );
        b.insert(
          live.history,
          historyCompanion(HistoryEntry(docId: id, openedAt: base.add(Duration(days: i)))),
          mode: InsertMode.insertOrReplace,
        );
      }
    });

    // backup: 10 docs + 10 history（b0..b9，openedAt 远新于 live）
    final backupDb = await openBackup();
    await backupDb.batch((b) {
      final newer = DateTime(2025, 1, 1);
      for (var i = 0; i < 10; i++) {
        final id = 'b$i';
        b.insert(
          backupDb.documents,
          documentCompanion(
            Document(
              id: id,
              title: id,
              authors: const [],
              keywords: const [],
              contentHash: null,
              addedAt: newer,
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );
        b.insert(
          backupDb.history,
          historyCompanion(HistoryEntry(docId: id, openedAt: newer.add(Duration(days: i)))),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    await backupDb.close();

    await BackupMergeService.merge(
      backupDbPath: backupPath,
      extractedDocsDir: null,
      scope: BackupRestoreScope.libraryOnly,
    );

    final historyCount = (await live.select(live.history).get()).length;
    // 510 条合并后按 openedAt desc 截 500，多余行被事务删除（P1-1）
    expect(historyCount, 500);
    // backup 的 10 条（最新）应在结果里
    final bIds = (await live.select(live.history).get()).map((r) => r.docId).toSet();
    for (var i = 0; i < 10; i++) {
      expect(bIds, contains('b$i'));
    }
  });
}