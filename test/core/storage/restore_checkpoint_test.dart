import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/restore_checkpoint.dart';
import 'package:otter_pad/core/storage/storage_exception.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late File database;
  late Directory library;
  late RestoreCheckpoint checkpoint;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('otter_checkpoint_test_');
    database = File(p.join(root.path, 'otter.db'));
    library = Directory(p.join(root.path, 'library'));
    await database.writeAsString('旧数据库');
    await library.create();
    await File(p.join(library.path, 'source.pdf')).writeAsString('旧附件');
    checkpoint = RestoreCheckpoint(database.path, library.path);
  });

  tearDown(() async => root.delete(recursive: true));

  Future<void> replaceLibrary() async {
    await library.rename('${library.path}.bak');
    await library.create();
    await File(p.join(library.path, 'source.pdf')).writeAsString('新附件');
  }

  Future<void> replaceDatabase() async {
    await database.rename('${database.path}.bak');
    await database.writeAsString('新数据库');
    await File('${database.path}-wal').writeAsString('新库日志');
  }

  for (final stage in [0, 1, 2]) {
    test('第 $stage 步中断后，重新创建恢复器可还原配套资料', () async {
      await checkpoint.begin();
      if (stage >= 1) await replaceLibrary();
      if (stage >= 2) await replaceDatabase();
      final restarted = RestoreCheckpoint(database.path, library.path);
      await restarted.recover();
      await restarted.recover();
      expect(await database.readAsString(), '旧数据库');
      expect(
        await File(p.join(library.path, 'source.pdf')).readAsString(),
        '旧附件',
      );
      expect(await File('${database.path}-wal').exists(), isFalse);
    });
  }

  test('提交后重新启动保留新资料', () async {
    await checkpoint.begin();
    await replaceLibrary();
    await replaceDatabase();
    await checkpoint.commit();
    await checkpoint.recover();
    expect(await database.readAsString(), '新数据库');
    expect(
      await File(p.join(library.path, 'source.pdf')).readAsString(),
      '新附件',
    );
  });

  test('已有旧副本时拒绝开始，副本内容不变', () async {
    await File('${database.path}.bak').writeAsString('待处理旧副本');
    await expectLater(checkpoint.begin(), throwsA(isA<StorageException>()));
    expect(await File('${database.path}.bak').readAsString(), '待处理旧副本');
  });
}
