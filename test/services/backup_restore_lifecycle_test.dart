import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/db_convert.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/core/storage/restore_checkpoint.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/services/backup_restore_service.dart';
import 'package:otter_pad/utils/doc_paths.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform original;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'otter_restore_lifecycle_',
    );
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    await GStorage.init();
  });

  tearDown(() async {
    await GStorage.close();
    PathProviderPlatform.instance = original;
    await directory.delete(recursive: true);
  });

  Future<void> addDocument(String id) async {
    final file = File(DocPaths.pdf(id));
    await file.parent.create(recursive: true);
    await file.writeAsString('PDF $id');
    await GStorage.db
        .into(GStorage.db.documents)
        .insertOnConflictUpdate(
          documentCompanion(
            Document(
              id: id,
              title: id,
              authors: const [],
              addedAt: DateTime(2020),
              contentHash: await DocPaths.computeHash(file),
            ),
          ),
        );
  }

  for (final scope in [
    BackupRestoreScope.full,
    BackupRestoreScope.libraryOnly,
  ]) {
    test('${scope.name}：数据备份恢复保留原 PDF，并按备份还原文献', () async {
      await addDocument('old');
      await GStorage.setting.put('fixture', '备份设置');
      final archive = await BackupRestoreService.createBackupArchive(
        scope: BackupScope.dataOnly,
      );
      await addDocument('later');
      await GStorage.setting.put('fixture', '新设置');
      await BackupRestoreService.restoreBackupArchive(
        archivePath: archive,
        scope: scope,
      );
      expect(
        (await GStorage.db.select(GStorage.db.documents).get()).map(
          (d) => d.id,
        ),
        ['old'],
      );
      expect(await File(DocPaths.pdf('old')).readAsString(), 'PDF old');
      expect(await File(DocPaths.pdf('later')).exists(), false);
      expect(
        GStorage.setting.get('fixture'),
        scope.restoreSettings ? '备份设置' : '新设置',
      );
      expect(
        await File(p.join(GStorage.dbDirPath, 'restore_pending.json')).exists(),
        false,
      );
      expect(
        await GStorage.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });
  }

  test('合并中途失败后，数据库和附件一起回退且新连接可写', () async {
    await addDocument('backup');
    final archive = await BackupRestoreService.createBackupArchive();
    await GStorage.db.delete(GStorage.db.documents).go();
    await Directory(DocPaths.docDir('backup')).delete(recursive: true);
    await addDocument('local');
    await expectLater(
      BackupRestoreService.restoreBackupArchive(
        archivePath: archive,
        scope: BackupRestoreScope.full,
        mode: RestoreMode.merge,
        onProgress: (message) {
          if (message == '正在合并标注...') throw StateError('测试中断');
        },
      ),
      throwsStateError,
    );
    expect(
      (await GStorage.db.select(GStorage.db.documents).get()).map((d) => d.id),
      ['local'],
    );
    expect(await File(DocPaths.pdf('local')).readAsString(), 'PDF local');
    expect(await File(DocPaths.pdf('backup')).exists(), false);
    await GStorage.setting.put('afterRollback', true);
    expect(GStorage.setting.get('afterRollback'), true);
  });

  test('轻量备份没有可保留的本地 PDF 时恢复为无文件条目', () async {
    await addDocument('missing');
    final archive = await BackupRestoreService.createBackupArchive(
      scope: BackupScope.dataOnly,
    );
    await File(DocPaths.pdf('missing')).delete();
    await BackupRestoreService.restoreBackupArchive(
      archivePath: archive,
      scope: BackupRestoreScope.libraryOnly,
    );
    expect(
      (await GStorage.db.select(GStorage.db.documents).get())
          .single
          .contentHash,
      isNull,
    );
    expect(await File(DocPaths.pdf('missing')).exists(), false);
  });

  test('完整替换中断后，下次初始化先回退再打开数据库', () async {
    await addDocument('local');
    final databasePath = p.join(GStorage.dbDirPath, 'otter.db');
    final libraryPath = GStorage.libraryDirPath;
    await RestoreCheckpoint(databasePath, libraryPath).begin();
    await GStorage.close();
    await File(databasePath).rename('$databasePath.bak');
    await Directory(libraryPath).rename('$libraryPath.bak');
    await File(databasePath).writeAsString('中断后留下的不可用数据库');
    await Directory(libraryPath).create();
    await GStorage.init();
    expect(
      (await GStorage.db.select(GStorage.db.documents).get()).single.id,
      'local',
    );
    expect(await File(DocPaths.pdf('local')).readAsString(), 'PDF local');
    expect(
      await File(p.join(GStorage.dbDirPath, 'restore_pending.json')).exists(),
      false,
    );
  });

  test('大附件完整备份恢复后字节不变', () async {
    await addDocument('large');
    final attachment = File(p.join(DocPaths.docDir('large'), 'large.bin'));
    final sink = attachment.openWrite();
    final chunk = List<int>.generate(65536, (i) => (i * 31 + i ~/ 257) % 256);
    for (var i = 0; i < 512; i++) {
      sink.add(chunk);
    }
    await sink.close();
    final originalHash = await DocPaths.computeHash(attachment);
    final archive = await BackupRestoreService.createBackupArchive();
    await attachment.writeAsString('后来修改');
    await BackupRestoreService.restoreBackupArchive(
      archivePath: archive,
      scope: BackupRestoreScope.full,
    );
    expect(await attachment.length(), 32 * 1024 * 1024);
    expect(await DocPaths.computeHash(attachment), originalHash);
  });
}
