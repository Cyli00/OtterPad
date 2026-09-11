import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart' show AppDatabase;
import 'package:otter_pad/core/storage/db_convert.dart';
import 'package:otter_pad/core/storage/document_file_operations.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/core/storage/storage_exception.dart';
import 'package:otter_pad/core/storage/zotero_snapshot.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/providers/documents_provider.dart';
import 'package:otter_pad/utils/doc_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('otter_file_failure_');
    database = AppDatabase(NativeDatabase.memory());
    final library = await Directory(p.join(root.path, 'library')).create();
    await GStorage.initForTest(database, libraryDirPath: library.path);
    container = ProviderContainer();
    container.listen(documentsProvider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await ZoteroSnapshot.detach();
    await database.close();
    await root.delete(recursive: true);
  });

  test('同一文献的并发文件操作只允许一个进入', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var actions = 0;
    Future<void> action() async {
      actions++;
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }

    final first = DocumentFileOperations(
      database,
      GStorage.libraryDirPath,
    ).run('d', deleting: true, action: action);
    final second = DocumentFileOperations(
      database,
      GStorage.libraryDirPath,
    ).run('d', deleting: true, action: action);
    final outcomes = Future.wait([
      first.then<Object?>((_) => null, onError: (Object e) => e),
      second.then<Object?>((_) => null, onError: (Object e) => e),
    ]);
    await entered.future;
    release.complete();
    final results = await outcomes;
    expect(actions, 1);
    expect(
      results.whereType<StorageException>().single.reason,
      StorageFailure.operationInProgress,
    );
    expect(results.where((e) => e == null), hasLength(1));
  });

  test('数据库拒绝删除时，原 PDF 和文献记录一起保留', () async {
    await database
        .into(database.documents)
        .insert(
          documentCompanion(
            Document(
              id: 'd',
              title: '论文',
              authors: const [],
              addedAt: DateTime(2020),
            ),
          ),
        );
    final pdf = File(DocPaths.pdf('d'));
    await pdf.parent.create(recursive: true);
    await pdf.writeAsString('原 PDF');
    await database.customStatement(
      "CREATE TRIGGER fail_delete BEFORE DELETE ON documents BEGIN SELECT RAISE(ABORT,'测试失败'); END",
    );
    await expectLater(
      container.read(documentsProvider.notifier).delete('d'),
      throwsA(anything),
    );
    expect(await pdf.exists(), true);
    expect(await pdf.readAsString(), '原 PDF');
    expect((await database.select(database.documents).get()).single.id, 'd');
  });

  test('数据库拒绝导入时，保留源文件并清理本次复制的孤立文件', () async {
    final source = File(p.join(root.path, 'source.pdf'));
    await source.writeAsString('测试源文件');
    await database.customStatement(
      "CREATE TRIGGER fail_import BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT,'测试失败'); END",
    );
    await expectLater(
      container.read(documentsProvider.notifier).addFile(source.path),
      throwsA(anything),
    );
    expect(await source.readAsString(), '测试源文件');
    expect(await database.select(database.documents).get(), isEmpty);
    final pdfs = await Directory(GStorage.libraryDirPath)
        .list(recursive: true)
        .where((f) => f is File && f.path.endsWith('.pdf'))
        .toList();
    expect(pdfs, isEmpty);
  });

  for (final committed in [false, true]) {
    test('删除中断后按数据库提交状态恢复：已提交=$committed', () async {
      if (!committed) {
        await database.customStatement(
          "INSERT INTO documents(id,title,authors,keywords,addedAt) VALUES ('d','论文','[]','[]',1)",
        );
      }
      final entry = Directory(
        p.join(GStorage.libraryDirPath, '.operations', 'd'),
      );
      await Directory(p.join(entry.path, 'files')).create(recursive: true);
      await File(
        p.join(entry.path, 'operation.json'),
      ).writeAsString('{"deleting":true}');
      await File(
        p.join(entry.path, 'files', 'source.pdf'),
      ).writeAsString('原 PDF');
      final operations = DocumentFileOperations(
        database,
        GStorage.libraryDirPath,
      );
      await operations.recover();
      await operations.recover();
      expect(await File(DocPaths.pdf('d')).exists(), !committed);
      expect(
        await DocumentFileOperations.hasPending(GStorage.libraryDirPath),
        false,
      );
    });
  }

  test('导入中断且尚未入库时，清理本次副本', () async {
    final entry = Directory(
      p.join(GStorage.libraryDirPath, '.operations', 'd'),
    );
    await entry.create(recursive: true);
    await File(
      p.join(entry.path, 'operation.json'),
    ).writeAsString('{"deleting":false}');
    final pdf = File(DocPaths.pdf('d'));
    await pdf.parent.create();
    await pdf.writeAsString('未入库副本');
    await DocumentFileOperations(database, GStorage.libraryDirPath).recover();
    expect(await pdf.exists(), false);
  });
}
