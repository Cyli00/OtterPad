import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

@DriftDatabase(include: {'tables.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// 以文件路径打开（路径由 GStorage.init 提供，如 `dbDirPath/otter.db`）。
  /// 调用前必须已执行 sqlite3.loadSimpleExtension()（见 GStorage.init）。
  AppDatabase.file(String path) : super(NativeDatabase(File(path)));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // 9 张普通表 + 索引（来自 tables.drift）。FTS5 虚表与触发器在
          // [ensureFts5] 里建——它依赖 simple 扩展（simple tokenizer = jieba 分词 + 拼音），与 Drift 迁移
          // 解耦，使数据库无扩展也能打开（测试友好 + 扩展加载失败不致开库崩溃）。
          await m.createAll();
        },
        beforeOpen: (details) async {
          // 每次连接（含 restore 后 reopen）都要重设：FK 默认关、WAL 持久。
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  /// 建 FTS5 虚表（simple tokenizer = jieba 分词 + 拼音）+ documents 的 insert/update/delete 触发器，
  /// 自动同步 documents_fts。standalone（不 external-content）：id UNINDEXED 存
  /// UUID 但不分词，搜索结果直接取回 id，免整数 rowid 映射。
  /// 幂等（IF NOT EXISTS），在 GStorage.init 加载 Simple 扩展后调用。
  Future<void> ensureFts5() async {
    await customStatement(
      "CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5("
      "id UNINDEXED, title, authors, journal, keywords, "
      "tokenize = 'simple')",
    );
    await _ensureFts5Triggers();
  }

  /// 重建 documents → documents_fts 同步触发器（幂等：DROP IF EXISTS + CREATE）。
  /// 不建虚表——建表依赖 simple 扩展（tokenize='simple'），由 [ensureFts5] 负责。
  /// 被 [ensureFts5] 与 [clearAllDocuments] 复用，触发器 SQL 单一定义，避免散落。
  Future<void> _ensureFts5Triggers() async {
    await customStatement("DROP TRIGGER IF EXISTS documents_ai");
    await customStatement(
      "CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN "
      "INSERT INTO documents_fts(rowid,id,title,authors,journal,keywords) "
      "VALUES (new.rowid,new.id,new.title,new.authors,new.journal,new.keywords); END",
    );
    await customStatement("DROP TRIGGER IF EXISTS documents_ad");
    await customStatement(
      "CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN "
      "DELETE FROM documents_fts WHERE rowid = old.rowid; END",
    );
    await customStatement("DROP TRIGGER IF EXISTS documents_au");
    await customStatement(
      "CREATE TRIGGER documents_au AFTER UPDATE ON documents BEGIN "
      "DELETE FROM documents_fts WHERE rowid = old.rowid; "
      "INSERT INTO documents_fts(rowid,id,title,authors,journal,keywords) "
      "VALUES (new.rowid,new.id,new.title,new.authors,new.journal,new.keywords); END",
    );
  }

  /// 安全清空 documents 表 + 同步清空 documents_fts。
  ///
  /// 存储清理专用。直接 `DELETE FROM documents` 会触发 documents_ad 同步触发器
  /// 维护 FTS 索引——若 documents 与 documents_fts 历史不一致（旧版本导入、
  /// 触发器曾缺失致索引未同步、FTS 内部状态损坏等），同步语句可能失败报
  /// SQL logic error，致清理整批回滚。此处先摘除同步触发器、清空 FTS、再删
  /// documents，最后重建触发器，绕开同步路径的脆弱点：清理不依赖触发器
  /// 当前是否健壮。外键 CASCADE 同时清 highlights/history/favorite_documents/
  /// zotero_items。VACUUM 由调用方在事务外执行（SQLite 不允许事务内 VACUUM）。
  Future<void> clearAllDocuments() async {
    await transaction(() async {
      await customStatement('DROP TRIGGER IF EXISTS documents_ai');
      await customStatement('DROP TRIGGER IF EXISTS documents_ad');
      await customStatement('DROP TRIGGER IF EXISTS documents_au');
      final ftsExists = (await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='documents_fts'",
      ).getSingleOrNull()) !=
          null;
      if (ftsExists) {
        await customStatement('DELETE FROM documents_fts');
      }
      await (delete(documents).go());
      if (ftsExists) {
        await _ensureFts5Triggers();
      }
    });
  }
}