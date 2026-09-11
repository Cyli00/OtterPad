import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'storage_exception.dart';

class RestoreCheckpoint {
  RestoreCheckpoint(this.dbPath, this.libraryPath);

  final String dbPath;
  final String libraryPath;

  File get _marker => File(p.join(p.dirname(dbPath), 'restore_pending.json'));

  Future<void> begin() async {
    if (await _marker.exists() ||
        await File('$dbPath.bak').exists() ||
        await Directory('$libraryPath.bak').exists()) {
      throw const StorageException(StorageFailure.pendingRestore);
    }
    final pending = File('${_marker.path}.pending');
    await pending.writeAsString(
      jsonEncode({
        'hadDatabase': await File(dbPath).exists(),
        'hadLibrary': await Directory(libraryPath).exists(),
      }),
      flush: true,
    );
    await pending.rename(_marker.path);
  }

  Future<void> commit() async {
    // 先移除未完成标记，再清理副本。进程在清理期间退出也不会回退已确认的新库。
    await _marker.delete();
    await _cleanup();
  }

  Future<void> recover() async {
    if (!await _marker.exists()) return;
    final state =
        jsonDecode(await _marker.readAsString()) as Map<String, dynamic>;
    final database = File(dbPath);
    final backup = File('$dbPath.bak');
    if (await backup.exists() || state['hadDatabase'] == false) {
      // 新库打开过后可能留下 WAL，必须与新库一起丢弃，不能应用到旧库。
      for (final path in [dbPath, '$dbPath-wal', '$dbPath-shm']) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      if (await backup.exists()) await backup.rename(database.path);
    }
    final library = Directory(libraryPath);
    final libraryBackup = Directory('$libraryPath.bak');
    if (await libraryBackup.exists() || state['hadLibrary'] == false) {
      if (await library.exists()) await library.delete(recursive: true);
      if (await libraryBackup.exists()) {
        await libraryBackup.rename(library.path);
      }
    }
    await _marker.delete();
  }

  Future<void> _cleanup() async {
    // 清理失败只留下副本；不能把已提交的恢复当作失败再回滚。
    try {
      final database = File('$dbPath.bak');
      if (await database.exists()) await database.delete();
      final library = Directory('$libraryPath.bak');
      if (await library.exists()) await library.delete(recursive: true);
    } on FileSystemException {
      // 下一次恢复会因副本仍存在而停止，避免覆盖用户唯一的旧资料。
    }
  }
}
