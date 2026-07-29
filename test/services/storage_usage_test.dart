import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/db_convert.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/data/models/book/highlight.dart';
import 'package:otter_pad/services/storage_usage_service.dart';

/// clearGroups(papers) 回归测试。
///
/// 修复前 clearGroups(papers) 只删 highlights 行 + library 文件，遗漏：
/// 1. 未删 documents 表 → 文献数量不变
/// 2. 未 VACUUM → SQLite DELETE 不释放磁盘空间，otter.db 文件不缩 → 占用不变
/// 修复后删 documents（CASCADE 清子表）+ VACUUM 收缩 db。
void main() {
  late Directory tempRoot;
  late db_lib.AppDatabase db;
  late String dbDirPath;
  late String libraryDirPath;
  late String logsDirPath;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('otter_storage_test_');
    dbDirPath = p.join(tempRoot.path, 'db');
    libraryDirPath = p.join(tempRoot.path, 'library');
    logsDirPath = p.join(tempRoot.path, 'logs');
    await Directory(dbDirPath).create(recursive: true);
    await Directory(libraryDirPath).create(recursive: true);
    await Directory(logsDirPath).create(recursive: true);

    db = db_lib.AppDatabase.file(p.join(dbDirPath, 'otter.db'));
    await GStorage.initForTest(
      db,
      dbDirPath: dbDirPath,
      libraryDirPath: libraryDirPath,
      logsDirPath: logsDirPath,
    );
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  test('clearGroups(papers) 清空 documents 表', () async {
    final now = DateTime.now();
    await db.into(db.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'd1',
              title: 'T',
              authors: const [],
              keywords: const [],
              contentHash: null,
              addedAt: now,
            ),
          ),
        );
    expect((await db.select(db.documents).get()).length, 1);

    await StorageUsageService.clearGroups({StorageGroupKey.papers});

    expect((await db.select(db.documents).get()), isEmpty);
  });

  test('clearGroups(papers) CASCADE 清 highlights', () async {
    final now = DateTime.now();
    await db.into(db.documents).insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: 'd1',
              title: 'T',
              authors: const [],
              keywords: const [],
              contentHash: null,
              addedAt: now,
            ),
          ),
        );
    await db.into(db.highlights).insert(
          highlightCompanion(
            Highlight(
              id: 'h1',
              documentId: 'd1',
              text: 'x',
              color: kDefaultHighlightColor,
              createdAt: now,
            ),
          ),
        );
    expect((await db.select(db.highlights).get()).length, 1);

    await StorageUsageService.clearGroups({StorageGroupKey.papers});

    expect((await db.select(db.highlights).get()), isEmpty,
        reason: '删 documents 应 CASCADE 清 highlights');
  });

  test('clearGroups(papers) 删除 library 文献文件', () async {
    final now = DateTime.now();
    const id = 'd1';
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
    final docDir = Directory(p.join(libraryDirPath, id));
    await docDir.create(recursive: true);
    await File(p.join(docDir.path, 'source.pdf'))
        .writeAsBytes(List.filled(1024, 0));

    await StorageUsageService.clearGroups({StorageGroupKey.papers});

    expect(File(p.join(docDir.path, 'source.pdf')).existsSync(), isFalse,
        reason: 'library 文献文件应被清理');
  });

  test('clearGroups(papers) VACUUM 收缩数据库文件', () async {
    final now = DateTime.now();
    // 插入 documents + 大量高亮文本让 otter.db 有实质内容
    for (var i = 0; i < 5; i++) {
      await db.into(db.documents).insertOnConflictUpdate(
            documentCompanion(
              Document(
                id: 'd$i',
                title: '文档$i',
                authors: const [],
                keywords: const [],
                contentHash: null,
                addedAt: now,
              ),
            ),
          );
      for (var j = 0; j < 10; j++) {
        await db.into(db.highlights).insert(
              highlightCompanion(
                Highlight(
                  id: 'h${i}_$j',
                  documentId: 'd$i',
                  text: 'A' * 4000,
                  color: kDefaultHighlightColor,
                  createdAt: now,
                ),
              ),
            );
      }
    }
    // checkpoint 让数据落主 db，测到稳定的 before 主库大小
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final beforeSize = await File(p.join(dbDirPath, 'otter.db')).length();

    await StorageUsageService.clearGroups({StorageGroupKey.papers});
    // clearGroups 的 VACUUM 应已 checkpoint + 收缩；额外 checkpoint 排除 -wal 残留
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final afterSize = await File(p.join(dbDirPath, 'otter.db')).length();
    expect((await db.select(db.documents).get()), isEmpty);
    expect((await db.select(db.highlights).get()), isEmpty);
    expect(afterSize, lessThan(beforeSize),
        reason: 'VACUUM 应收缩 otter.db（删除数据 + 回收磁盘空间）');
  });

  test('clearGroups(papers) 后残留的是非文献数据（settings/favorites），不是文献', () async {
    final now = DateTime.now();
    final ms = now.millisecondsSinceEpoch;
    // 非文献数据：收藏夹分组 + 设置
    await db.customStatement(
      "INSERT INTO favorites (id, emoji, name, createdAt) VALUES ('fav1', 'X', '收藏夹', $ms)",
    );
    await db.customStatement(
      "INSERT INTO settings (settingKey, value) VALUES ('theme', 'dark')",
    );
    await db.customStatement(
      "INSERT INTO meta (metaKey, value) VALUES ('zotero_version', '5')",
    );
    // 文献数据：document + 大量高亮让 db 有实质体积
    for (var i = 0; i < 5; i++) {
      await db.into(db.documents).insertOnConflictUpdate(
        documentCompanion(Document(
          id: 'd$i',
          title: '文档$i',
          authors: const [],
          keywords: const [],
          contentHash: null,
          addedAt: now,
        )),
      );
      for (var j = 0; j < 10; j++) {
        await db.into(db.highlights).insert(
          highlightCompanion(Highlight(
            id: 'h${i}_$j',
            documentId: 'd$i',
            text: 'A' * 4000,
            color: kDefaultHighlightColor,
            createdAt: now,
          )),
        );
      }
    }
    // library 文献文件
    final docDir = Directory(p.join(libraryDirPath, 'd0'));
    await docDir.create(recursive: true);
    await File(p.join(docDir.path, 'source.pdf')).writeAsBytes(List.filled(2048, 0));

    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final beforeDbSize = await File(p.join(dbDirPath, 'otter.db')).length();

    await StorageUsageService.clearGroups({StorageGroupKey.papers});
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final afterDbSize = await File(p.join(dbDirPath, 'otter.db')).length();

    // 文献数据已清
    expect((await db.select(db.documents).get()), isEmpty, reason: 'documents 应清空');
    expect((await db.select(db.highlights).get()), isEmpty, reason: 'highlights 应 CASCADE 清');
    expect(File(p.join(libraryDirPath, 'd0', 'source.pdf')).existsSync(), isFalse,
        reason: 'library 文献文件应删');

    // 非文献数据残留——这是“清理不掉”的真因
    expect((await db.select(db.favorites).get()).length, 1, reason: '收藏夹分组保留');
    expect((await db.select(db.settings).get()).length, 1, reason: '设置保留');
    expect((await db.select(db.meta).get()).length, 1, reason: 'meta 保留');

    // db 文件不归零（含非文献数据 + schema），但应缩小（VACUUM 回收文献数据空间）
    expect(afterDbSize, greaterThan(0), reason: 'db 文件不归零（非文献数据 + schema）');
    expect(afterDbSize, lessThan(beforeDbSize), reason: 'VACUUM 应收缩 db');
  });

  test('clearGroups(database) 仅 VACUUM，不删非文献数据', () async {
    final ms = DateTime.now().millisecondsSinceEpoch;
    await db.customStatement(
      "INSERT INTO favorites (id, emoji, name, createdAt) VALUES ('fav1', 'X', '收藏', $ms)",
    );
    await db.customStatement(
      "INSERT INTO settings (settingKey, value) VALUES ('theme', 'dark')",
    );

    await StorageUsageService.clearGroups({StorageGroupKey.database});

    expect((await db.select(db.favorites).get()).length, 1, reason: 'VACUUM 不删 favorites');
    expect((await db.select(db.settings).get()).length, 1, reason: 'VACUUM 不删 settings');
  });

  test('clearGroups(papers) 在 FTS 同步触发器存在且索引不一致时不报错（FTS5 delete 触发器健壮性）',
      () async {
    // 真机有 documents_fts（simple 扩展）+ documents_ai/au/ad 触发器。历史上
    // documents_ad 用 FTS5 'delete' 命令、以 id 当 FTS rowid，而 documents_ai
    // 不指定 rowid 致 FTS 自动分配 rowid ≠ documents.rowid；清理时 'delete'
    // 找不到匹配报 SQL logic error (code 1)。clearGroups 现走
    // AppDatabase.clearAllDocuments（摘除同步触发器后清空），不依赖触发器健壮性。
    //
    // 测试环境无 simple 扩展，用内置 unicode61 建等价 FTS5，并复刻历史上脆弱的
    // 触发器形式（'delete' 命令 + id 当 rowid）+ 旧库 rowid 不匹配，验证清理安全。
    await db.customStatement(
      "CREATE VIRTUAL TABLE documents_fts USING fts5("
      "id UNINDEXED, title, authors, journal, keywords, tokenize = 'unicode61')",
    );
    await db.customStatement(
      "CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN "
      "INSERT INTO documents_fts(id,title,authors,journal,keywords) "
      "VALUES (new.id,new.title,new.authors,new.journal,new.keywords); END",
    );
    await db.customStatement(
      "CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN "
      "INSERT INTO documents_fts(documents_fts,id,title,authors,journal,keywords) "
      "VALUES ('delete',old.id,old.title,old.authors,old.journal,old.keywords); END",
    );
    await db.customStatement(
      "CREATE TRIGGER documents_au AFTER UPDATE ON documents BEGIN "
      "INSERT INTO documents_fts(documents_fts,id,title,authors,journal,keywords) "
      "VALUES ('delete',old.id,old.title,old.authors,old.journal,old.keywords); "
      "INSERT INTO documents_fts(id,title,authors,journal,keywords) "
      "VALUES (new.id,new.title,new.authors,new.journal,new.keywords); END",
    );

    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      await db.into(db.documents).insertOnConflictUpdate(documentCompanion(
        Document(
          id: 'd$i',
          title: '文献$i',
          authors: const [],
          keywords: const [],
          contentHash: null,
          addedAt: now,
        ),
      ));
    }
    // 脆弱 ai 不指定 rowid → FTS 自动分配 rowid ≠ documents.rowid（旧库状态）。
    // 修复前 clearGroups 调 DELETE FROM documents 触发脆弱 ad 'delete'，rowid
    // 不匹配报 SQL logic error；修复后 clearAllDocuments 摘触发器清空，不报错。
    await StorageUsageService.clearGroups({StorageGroupKey.papers});

    expect((await db.select(db.documents).get()), isEmpty, reason: 'documents 应清空');
    final ftsLeft =
        (await db.customSelect('SELECT count(*) AS c FROM documents_fts').getSingle())
            .read<int>('c');
    expect(ftsLeft, 0, reason: 'documents_fts 应清空');

    // clearAllDocuments 重建同步触发器（健壮形式）后，新文献应同步进 fts，
    // 验证清理未留下「触发器缺失致后续不同步」的二次 bug。
    await db.into(db.documents).insertOnConflictUpdate(documentCompanion(
      Document(
        id: 'after',
        title: '清理后新文献',
        authors: const [],
        keywords: const [],
        contentHash: null,
        addedAt: now,
      ),
    ));
    final ftsAfter = (await db.customSelect(
      "SELECT count(*) AS c FROM documents_fts WHERE id = 'after'",
    ).getSingle()).read<int>('c');
    expect(ftsAfter, 1, reason: 'documents_ai 触发器应重建并同步新文献进 fts');
  });
}