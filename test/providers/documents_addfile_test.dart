import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/db_convert.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/core/storage/zotero_snapshot.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/providers/documents_provider.dart';
import 'package:otter_pad/utils/doc_paths.dart';
import 'package:path/path.dart' as p;

Document _doc({required String id, String? contentHash}) => Document(
      id: id,
      title: 'T-$id',
      authors: const [],
      contentHash: contentHash,
      addedAt: DateTime.now(),
    );

void main() {
  late db_lib.AppDatabase db;
  late ProviderContainer container;
  late Directory tempLibDir;

  setUp(() async {
    db = db_lib.AppDatabase(NativeDatabase.memory());
    tempLibDir = await Directory.systemTemp.createTemp('otter_lib_');
    await GStorage.initForTest(db, libraryDirPath: tempLibDir.path);
    container = ProviderContainer();
    container.listen(documentsProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await ZoteroSnapshot.detach();
    await db.close();
    if (await tempLibDir.exists()) await tempLibDir.delete(recursive: true);
  });

  group('contentHash UNIQUE 约束（迁移引入的回归根因）', () {
    test('相同 contentHash 不同 id：insertOnConflictUpdate 应抛 UNIQUE 冲突', () async {
      final d1 = _doc(id: 'id1', contentHash: 'HASH_X');
      final d2 = _doc(id: 'id2', contentHash: 'HASH_X');

      // 第一条写入成功
      await db.into(db.documents).insertOnConflictUpdate(documentCompanion(d1));
      expect((await db.select(db.documents).get()).length, 1);

      // 第二条相同 hash、不同 id → PK(id) 不冲突，但 contentHash UNIQUE index 冲突
      // insertOnConflictUpdate 只声明 ON CONFLICT(id)，不覆盖 contentHash 冲突
      await expectLater(
        db.into(db.documents).insertOnConflictUpdate(documentCompanion(d2)),
        throwsA(isA<Exception>()),
      );
    });

    test('相同 contentHash 相同 id：upsert 正常覆盖（PK 命中）', () async {
      final d1 = _doc(id: 'same', contentHash: 'HASH_Y');
      final d2 = _doc(id: 'same', contentHash: 'HASH_Y', );

      await db.into(db.documents).insertOnConflictUpdate(documentCompanion(d1));
      // 同 id 同 hash → PK 冲突 → ON CONFLICT(id) DO UPDATE，正常
      await db.into(db.documents).insertOnConflictUpdate(
        documentCompanion(d2.copyWith(title: 'T-updated')),
      );
      final rows = await db.select(db.documents).get();
      expect(rows.length, 1);
      expect(rows.first.title, 'T-updated');
    });
  });

  group('addFile 文件复制（绕过 _repairDocument 的 pdfrx 依赖）', () {
    /// PdfIdentifierExtractor 依赖 pdfrx 原生，测试环境未初始化会 hang 30s。
    /// 此处只验证 _writePdfForDocument 的文件落盘路径正确性——用 attachFile
    /// 的前半段语义（先写库再补文件）不足以绕过，故直接调底层文件操作复刻
    /// _writePdfForDocument 的逻辑，确认 DocPaths 路径推导无误。
    test('DocPaths.pdf 路径推导与文件落盘一致', () async {
      final documentId = 'test-doc-id';
      final srcDir = await Directory.systemTemp.createTemp('otter_src_');
      final sourcePath = p.join(srcDir.path, 'fake.pdf');
      await File(sourcePath).writeAsBytes([0x25, 0x50, 0x44, 0x46]);

      // 复刻 _writePdfForDocument 逻辑
      final docDir = Directory(DocPaths.docDir(documentId));
      if (!await docDir.exists()) await docDir.create(recursive: true);
      final destPath = DocPaths.pdf(documentId);
      await File(sourcePath).copy(destPath);

      expect(File(destPath).existsSync(), isTrue, reason: '文件应复制到 DocPaths.pdf');
      expect(p.basename(destPath), DocPaths.pdfName);
      expect(p.dirname(destPath), DocPaths.docDir(documentId));

      await srcDir.delete(recursive: true);
    });
  });

  group('addFile 重复导入回归（修复：查重走 DB，不依赖异步流）', () {
    test('DB 已有同 contentHash 时 addFile 返回 duplicate，不抛异常', () async {
      final srcDir = await Directory.systemTemp.createTemp('otter_src_');
      final sourcePath = p.join(srcDir.path, 'dup.pdf');
      await File(sourcePath).writeAsBytes([1, 2, 3, 4, 5]);

      // 算 hash，预写 DB（模拟已导入过该文件）
      final hash = await DocPaths.computeHash(File(sourcePath));
      await db.into(db.documents).insertOnConflictUpdate(
        documentCompanion(_doc(id: 'existing', contentHash: hash)),
      );

      // addFile 同内容文件——查重应走 DB 命中，返回 duplicate（不跑 _repairDocument）
      final notifier = container.read(documentsProvider.notifier);
      final result = await notifier.addFile(sourcePath);

      expect(result.type, AddFileResultType.duplicate, reason: '同内容应判重');
      expect(result.document!.id, 'existing');

      // DB 仍只有一条记录（没产生重复/孤儿）
      final rows = await db.select(db.documents).get();
      expect(rows.length, 1);

      await srcDir.delete(recursive: true);
    });
  });
}