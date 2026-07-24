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
          // 8 张普通表 + 索引（来自 tables.drift）。FTS5 虚表与触发器在
          // [ensureFts5] 里建——它依赖 jieba tokenizer 扩展，与 Drift 迁移
          // 解耦，使数据库无扩展也能打开（测试友好 + 扩展加载失败不致开库崩溃）。
          await m.createAll();
        },
        beforeOpen: (details) async {
          // 每次连接（含 restore 后 reopen）都要重设：FK 默认关、WAL 持久。
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  /// 建 FTS5 虚表（jieba 分词）+ documents 的 insert/update/delete 触发器，
  /// 自动同步 documents_fts。standalone（不 external-content）：id UNINDEXED 存
  /// UUID 但不分词，搜索结果直接取回 id，免整数 rowid 映射。
  /// 幂等（IF NOT EXISTS），在 GStorage.init 加载 Simple 扩展后调用。
  Future<void> ensureFts5() async {
    await customStatement(
      "CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5("
      "id UNINDEXED, title, authors, journal, keywords, "
      "tokenize = 'jieba')",
    );
    await customStatement(
      "CREATE TRIGGER IF NOT EXISTS documents_ai AFTER INSERT ON documents BEGIN "
      "INSERT INTO documents_fts(id,title,authors,journal,keywords) "
      "VALUES (new.id,new.title,new.authors,new.journal,new.keywords); END",
    );
    await customStatement(
      "CREATE TRIGGER IF NOT EXISTS documents_ad AFTER DELETE ON documents BEGIN "
      "INSERT INTO documents_fts(documents_fts,id,title,authors,journal,keywords) "
      "VALUES ('delete',old.id,old.title,old.authors,old.journal,old.keywords); END",
    );
    await customStatement(
      "CREATE TRIGGER IF NOT EXISTS documents_au AFTER UPDATE ON documents BEGIN "
      "INSERT INTO documents_fts(documents_fts,id,title,authors,journal,keywords) "
      "VALUES ('delete',old.id,old.title,old.authors,old.journal,old.keywords); "
      "INSERT INTO documents_fts(id,title,authors,journal,keywords) "
      "VALUES (new.id,new.title,new.authors,new.journal,new.keywords); END",
    );
  }
}