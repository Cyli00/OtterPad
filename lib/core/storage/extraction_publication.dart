import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'storage_activity.dart';
import 'storage_exception.dart';

/// 多文件发布先落日志；未写提交标记时，启动恢复完整旧版本。
class ExtractionPublication {
  static final _active = <String>{};

  static Future<void> publish(Map<String, String> contents) =>
      StorageActivity.run(() async {
        if (contents.isEmpty) return;
        var root = p.dirname(p.absolute(contents.keys.first));
        for (final target in contents.keys) {
          while (!p.isWithin(root, p.absolute(target))) {
            root = p.dirname(root);
          }
        }
        if (_active.any(
          (other) =>
              p.equals(other, root) ||
              p.isWithin(other, root) ||
              p.isWithin(root, other),
        )) {
          throw const StorageException(StorageFailure.operationInProgress);
        }
        _active.add(root);
        Directory? stage;
        try {
          await recoverDirectory(root);
          stage = await Directory(root).createTemp('.extract_publish_');
          final entries = <Map<String, Object>>[];
          var index = 0;
          for (final entry in contents.entries) {
            final target = p.absolute(entry.key);
            // 目标目录不能借链接跳出文献目录。
            final realRoot = await Directory(root).resolveSymbolicLinks();
            final parent = await Directory(
              p.dirname(target),
            ).resolveSymbolicLinks();
            if (!p.equals(realRoot, parent) && !p.isWithin(realRoot, parent)) {
              throw const StorageException(StorageFailure.invalidBackup);
            }
            entries.add({
              'target': p.relative(target, from: root),
              'existed': await File(target).exists(),
            });
            await File(
              p.join(stage.path, '${index++}.new'),
            ).writeAsString(entry.value, flush: true);
          }
          final pending = File(p.join(stage.path, 'journal.pending'));
          await pending.writeAsString(jsonEncode(entries), flush: true);
          await pending.rename(p.join(stage.path, 'journal.json'));
          for (var i = 0; i < entries.length; i++) {
            final target = p.join(root, entries[i]['target'] as String);
            if (entries[i]['existed'] == true) {
              await File(target).rename(p.join(stage.path, '$i.old'));
            }
            await File(p.join(stage.path, '$i.new')).rename(target);
          }
          await _commit(stage);
        } finally {
          try {
            if (stage != null) await _recover(stage);
          } finally {
            _active.remove(root);
          }
        }
      });

  static Future<void> recoverLibrary(String library) async {
    if (!await Directory(library).exists()) return;
    await for (final doc in Directory(library).list(followLinks: false)) {
      if (doc is! Directory || p.basename(doc.path).startsWith('.')) continue;
      await recoverDirectory(doc.path);
      final figures = p.join(doc.path, 'figures');
      if (await Directory(figures).exists()) await recoverDirectory(figures);
    }
  }

  static Future<void> recoverDirectory(String root) async {
    await for (final entry in Directory(root).list(followLinks: false)) {
      if (entry is Directory &&
          p.basename(entry.path).startsWith('.extract_cleanup_')) {
        await entry.delete(recursive: true);
      } else if (entry is Directory &&
          p.basename(entry.path).startsWith('.extract_publish_')) {
        await _recover(entry);
      }
    }
  }

  static Future<void> _commit(Directory stage) async {
    final pending = File(p.join(stage.path, 'commit.pending'));
    await pending.writeAsString('1', flush: true);
    await pending.rename(p.join(stage.path, 'committed'));
  }

  static Future<void> _recover(Directory stage) async {
    final journal = File(p.join(stage.path, 'journal.json'));
    final committed = File(p.join(stage.path, 'committed'));
    if (!await journal.exists()) {
      // 旧版没有持久化日志，不能猜测 .old 文件原来属于哪个目标。
      if (await stage.list().any((e) => e.path.endsWith('.old'))) {
        throw const StorageException(StorageFailure.pendingRestore);
      }
    } else if (!await committed.exists()) {
      final entries = jsonDecode(await journal.readAsString()) as List;
      final root = p.dirname(stage.path);
      final realRoot = await Directory(root).resolveSymbolicLinks();
      for (var i = 0; i < entries.length; i++) {
        final relative = entries[i]['target'] as String;
        final target = p.normalize(p.join(root, relative));
        if (p.isAbsolute(relative) || !p.isWithin(root, target)) {
          throw const StorageException(StorageFailure.invalidBackup);
        }
        final parent = await Directory(
          p.dirname(target),
        ).resolveSymbolicLinks();
        if (!p.equals(realRoot, parent) && !p.isWithin(realRoot, parent)) {
          throw const StorageException(StorageFailure.invalidBackup);
        }
        final backup = File(p.join(stage.path, '$i.old'));
        if (await backup.exists()) {
          // copy 保留备份，回滚过程中再次退出也能重试。
          await backup.copy(target);
        } else if (entries[i]['existed'] == false &&
            await File(target).exists()) {
          await File(target).delete();
        }
      }
      // 回滚已完成：先改名日志，避免清理到一半后再次按残缺备份回滚。
      await _commit(stage);
    }
    try {
      final cleanup = await stage.rename(
        p.join(
          p.dirname(stage.path),
          p
              .basename(stage.path)
              .replaceFirst('.extract_publish_', '.extract_cleanup_'),
        ),
      );
      await cleanup.delete(recursive: true);
    } on FileSystemException {
      // 已发布或已回滚；被占用的清理项下次重试。
    }
  }
}
