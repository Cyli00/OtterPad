import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/core/storage/zotero_snapshot.dart';
import 'package:otter_pad/services/backup_restore_service.dart';
import 'package:otter_pad/core/storage/storage_exception.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase live;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('otter_restore_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    live = AppDatabase(NativeDatabase.memory());
    final library = await Directory(p.join(directory.path, 'library')).create();
    final dbDir = await Directory(p.join(directory.path, 'db')).create();
    await GStorage.initForTest(
      live,
      libraryDirPath: library.path,
      dbDirPath: dbDir.path,
    );
    await GStorage.setting.put('test_setting', '本地设置');
  });

  tearDown(() async {
    await ZoteroSnapshot.detach();
    await live.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  Future<String> archiveWithDatabase(List<int>? bytes) async {
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'otter_pad_backup/manifest.json',
        jsonEncode({'app': 'OtterPad', 'formatVersion': 3, 'scope': 'full'}),
      ),
    );
    if (bytes != null) {
      archive.addFile(
        ArchiveFile('otter_pad_backup/db/otter.db', bytes.length, bytes),
      );
    }
    final file = File(p.join(directory.path, 'backup.zip'));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file.path;
  }

  for (final entry in <String, List<int>?>{
    '缺少数据库': null,
    '空数据库': <int>[],
    '损坏数据库': utf8.encode('损坏的内容'),
  }.entries) {
    test('${entry.key}必须在替换本地设置前拒绝', () async {
      final archive = await archiveWithDatabase(entry.value);
      await expectLater(
        BackupRestoreService.restoreBackupArchive(
          archivePath: archive,
          scope: BackupRestoreScope.settingsOnly,
        ),
        throwsA(anything),
      );
      expect(GStorage.setting.get('test_setting'), '本地设置');
      expect((await live.select(live.settings).get()).single.value, '"本地设置"');
    });
  }

  Future<List<int>> oldDatabaseBytes() async {
    final path = p.join(directory.path, 'fixture.db');
    final raw = sqlite3.open(path);
    raw.execute(
      await File('test/core/storage/fixtures/schema_v1.sql').readAsString(),
    );
    raw.close();
    return File(path).readAsBytes();
  }

  test('轻量备份排除可重新生成的 MinerU 导出包', () {
    expect(
      BackupRestoreService.includeInDataOnly('doc/mineru.exports.zip'),
      isFalse,
    );
    expect(
      BackupRestoreService.includeInDataOnly('doc/translations.json'),
      isTrue,
    );
  });

  test('旧版备份可仅恢复设置，不要求包含附件目录', () async {
    final archive = await archiveWithDatabase(await oldDatabaseBytes());
    await BackupRestoreService.restoreBackupArchive(
      archivePath: archive,
      scope: BackupRestoreScope.settingsOnly,
    );
    expect(GStorage.setting.get('fixture_setting'), true);
    expect(GStorage.setting.containsKey('test_setting'), false);
  });

  test('备份与恢复往返后设置一致，快照文件互不覆盖', () async {
    final first = await BackupRestoreService.createBackupArchive();
    final second = await BackupRestoreService.createBackupArchive();
    expect(first, isNot(second));
    expect(await File(first).exists(), true);
    await GStorage.setting.put('test_setting', '后来修改');
    await BackupRestoreService.restoreBackupArchive(
      archivePath: first,
      scope: BackupRestoreScope.settingsOnly,
    );
    expect(GStorage.setting.get('test_setting'), '本地设置');
  });

  test('并行备份被拒绝，不干扰已开始的备份', () async {
    final first = BackupRestoreService.createBackupArchive();
    await expectLater(
      BackupRestoreService.createBackupArchive(),
      throwsA(
        isA<StorageException>().having(
          (e) => e.reason,
          '原因',
          StorageFailure.operationInProgress,
        ),
      ),
    );
    expect(await File(await first).exists(), true);
  });

  for (final mutation in [
    'PRAGMA user_version = 999',
    'ALTER TABLE settings RENAME COLUMN value TO unexpected',
    "UPDATE highlights SET docId = 'missing'",
  ]) {
    test('不兼容或关联损坏的备份被拒绝：$mutation', () async {
      await oldDatabaseBytes();
      final path = p.join(directory.path, 'fixture.db');
      final raw = sqlite3.open(path);
      raw.execute(mutation);
      raw.close();
      final archive = await archiveWithDatabase(await File(path).readAsBytes());
      await expectLater(
        BackupRestoreService.restoreBackupArchive(
          archivePath: archive,
          scope: BackupRestoreScope.settingsOnly,
        ),
        throwsA(isA<StorageException>()),
      );
      expect(GStorage.setting.get('test_setting'), '本地设置');
    });
  }

  test('新备份丢失清单中的附件时，在修改本地资料前拒绝', () async {
    final attachment = File(p.join(GStorage.libraryDirPath, 'd', 'notes.json'));
    await attachment.parent.create(recursive: true);
    await attachment.writeAsString('测试笔记');
    final originalPath = await BackupRestoreService.createBackupArchive();
    final original = ZipDecoder().decodeBytes(
      await File(originalPath).readAsBytes(),
    );
    final incomplete = Archive();
    for (final file in original) {
      if (!file.name.endsWith('notes.json')) incomplete.addFile(file);
    }
    final damagedPath = p.join(directory.path, 'missing-attachment.zip');
    await File(damagedPath).writeAsBytes(ZipEncoder().encode(incomplete));
    await expectLater(
      BackupRestoreService.restoreBackupArchive(
        archivePath: damagedPath,
        scope: BackupRestoreScope.settingsOnly,
      ),
      throwsA(isA<StorageException>()),
    );
    expect(GStorage.setting.get('test_setting'), '本地设置');
    expect(await attachment.readAsString(), '测试笔记');
  });

  test('备份期间修改数据库会拒绝发布不一致的归档', () async {
    final backup = BackupRestoreService.createBackupArchive();
    final assertion = expectLater(
      backup,
      throwsA(
        isA<StorageException>().having(
          (e) => e.reason,
          '原因',
          StorageFailure.changedDuringBackup,
        ),
      ),
    );
    // 等待快照阶段开始后持续写入，覆盖打包前后检查的窗口。
    var done = false;
    final writing = () async {
      var i = 0;
      while (!done) {
        await GStorage.setting.put('concurrent', i++);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }();
    try {
      await assertion;
    } finally {
      done = true;
      await writing;
    }
  });
}
