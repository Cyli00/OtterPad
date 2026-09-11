import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_database.dart';
import 'storage_exception.dart';

class DocumentFileOperations {
  DocumentFileOperations(this.database, this.libraryPath);

  final AppDatabase database;
  final String libraryPath;

  static final _active = <String>{};

  static Directory _pending(String library) =>
      Directory(p.join(library, '.operations'));

  static Future<bool> hasPending(String library) async {
    final directory = _pending(library);
    return await directory.exists() && !await directory.list().isEmpty;
  }

  Future<void> run(
    String id, {
    required bool deleting,
    required Future<void> Function() action,
  }) async {
    if (id.isEmpty ||
        p.basename(id) != id ||
        id == '.' ||
        id == '..' ||
        id == '.operations') {
      throw const StorageException(StorageFailure.invalidBackup);
    }
    final operation = p.normalize(p.absolute(libraryPath, id));
    if (!_active.add(operation)) {
      throw const StorageException(StorageFailure.operationInProgress);
    }
    try {
      await _run(id, deleting: deleting, action: action);
    } finally {
      _active.remove(operation);
    }
  }

  Future<void> _run(
    String id, {
    required bool deleting,
    required Future<void> Function() action,
  }) async {
    final target = Directory(p.join(libraryPath, id));
    final entry = Directory(p.join(_pending(libraryPath).path, id));
    if (await entry.exists() || (!deleting && await target.exists())) {
      throw const StorageException(StorageFailure.operationInProgress);
    }
    await entry.create(recursive: true);
    // 标记写完后才动文献目录；启动时按数据库是否已有记录判断提交或回退。
    final marker = File(p.join(entry.path, 'operation.json'));
    final pending = File(p.join(entry.path, 'operation.pending'));
    await pending.writeAsString(
      jsonEncode({'deleting': deleting}),
      flush: true,
    );
    await pending.rename(marker.path);
    try {
      if (deleting && await target.exists()) {
        await target.rename(p.join(entry.path, 'files'));
      }
      await action();
    } catch (_) {
      await _recoverEntry(entry);
      rethrow;
    }
    try {
      await _recoverEntry(entry);
    } on FileSystemException {
      // 数据库已提交；文件被占用时保留标记，下次启动继续清理。
    }
  }

  Future<void> recover() async {
    final directory = _pending(libraryPath);
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) await _recoverEntry(entity);
    }
  }

  Future<void> _recoverEntry(Directory entry) async {
    final marker = File(p.join(entry.path, 'operation.json'));
    if (!await marker.exists()) {
      // 创建空操作目录后中断，文献文件尚未改动。
      final pending = File(p.join(entry.path, 'operation.pending'));
      if (await pending.exists()) await pending.delete();
      if (await entry.list().isEmpty) await entry.delete();
      return;
    }
    final deleting =
        (jsonDecode(await marker.readAsString())
            as Map<String, dynamic>)['deleting'] ==
        true;
    final id = p.basename(entry.path);
    final exists =
        await (database.select(
          database.documents,
        )..where((t) => t.id.equals(id))).getSingleOrNull() !=
        null;
    final target = Directory(p.join(libraryPath, id));
    final saved = Directory(p.join(entry.path, 'files'));
    if (deleting && exists && await saved.exists()) {
      if (await target.exists()) {
        throw const StorageException(StorageFailure.pendingRestore);
      }
      await saved.rename(target.path);
    } else if (!deleting && !exists && await target.exists()) {
      await target.delete(recursive: true);
    }
    await entry.delete(recursive: true);
  }
}
