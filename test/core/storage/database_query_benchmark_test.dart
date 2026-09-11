import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';

void main() {
  test('比较全表读取计数与数据库计数', () async {
    for (final count in [1000, 10000, 50000]) {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await database.customStatement('''
          WITH RECURSIVE items(n) AS (
            SELECT 1 UNION ALL SELECT n + 1 FROM items WHERE n < $count
          )
          INSERT INTO documents(id, title, authors, keywords, addedAt)
          SELECT CAST(n AS TEXT), '中文论文 ' || n, '["作者"]', '["关键词"]', n FROM items
        ''');
        final oldTimes = <int>[];
        final newTimes = <int>[];
        for (var i = 0; i < 21; i++) {
          final watch = Stopwatch()..start();
          expect(
            (await database.select(database.documents).get()).length,
            count,
          );
          if (i > 0) oldTimes.add(watch.elapsedMicroseconds);
          watch.reset();
          expect(
            (await database
                    .customSelect('SELECT count(*) AS c FROM documents')
                    .getSingle())
                .read<int>('c'),
            count,
          );
          if (i > 0) newTimes.add(watch.elapsedMicroseconds);
        }
        oldTimes.sort();
        newTimes.sort();
        // 只报告测量，不用依赖机器负载的时限作为通过条件。
        // ignore: avoid_print
        print(
          '$count 条：全表 p50=${oldTimes[9]}µs p95=${oldTimes[18]}µs；SQL 计数 p50=${newTimes[9]}µs p95=${newTimes[18]}µs',
        );
      } finally {
        await database.close();
      }
    }
  }, tags: ['tools']);
}
