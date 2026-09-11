import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('otter_schema_test_');
  });

  tearDown(() async => directory.delete(recursive: true));

  test('固定的 v1 旧库可打开并保留所有表和关联', () async {
    final path = '${directory.path}/v1.db';
    final raw = sqlite3.open(path);
    raw.execute(
      await File('test/core/storage/fixtures/schema_v1.sql').readAsString(),
    );
    raw.close();
    await AppDatabase.validateBackup(path);
    final database = AppDatabase.file(path);
    try {
      expect(
        (await database.select(database.documents).get()).single.title,
        '旧版中文论文',
      );
      expect(
        (await database.select(database.highlights).get()).single.note,
        '笔记',
      );
      for (final table in database.allTables) {
        expect(
          (await database
                  .customSelect(
                    'SELECT count(*) AS c FROM "${table.actualTableName}"',
                  )
                  .getSingle())
              .read<int>('c'),
          1,
        );
      }
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    } finally {
      await database.close();
    }
  });

  test('拒绝较新版本数据库，并保留原版本和记录', () async {
    final path = '${directory.path}/future.db';
    final raw = sqlite3.open(path);
    raw.execute('CREATE TABLE future_data (value TEXT)');
    raw.execute("INSERT INTO future_data VALUES ('保留资料')");
    raw.execute('PRAGMA user_version = 999');
    raw.close();

    final database = AppDatabase.file(path);
    try {
      await expectLater(
        database.customSelect('SELECT 1').get(),
        throwsException,
      );
    } finally {
      await database.close();
    }
    final reopened = sqlite3.open(path);
    try {
      expect(reopened.userVersion, 999);
      expect(
        reopened.select('SELECT value FROM future_data').single['value'],
        '保留资料',
      );
    } finally {
      reopened.close();
    }
  });

  test('文件库每次打开都启用 WAL、外键和完整同步', () async {
    final path = '${directory.path}/configuration.db';
    for (var i = 0; i < 2; i++) {
      final database = AppDatabase.file(path);
      try {
        expect(
          (await database.customSelect('PRAGMA journal_mode').getSingle())
              .read<String>('journal_mode'),
          'wal',
        );
        expect(
          (await database.customSelect('PRAGMA foreign_keys').getSingle())
              .read<int>('foreign_keys'),
          1,
        );
        expect(
          (await database.customSelect('PRAGMA synchronous').getSingle())
              .read<int>('synchronous'),
          2,
        );
      } finally {
        await database.close();
      }
    }
  });
}
