import 'dart:io';
import '../core/app_logger.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/backup_fingerprint.dart';
import '../services/backup_merge_service.dart';
import '../services/backup_remote.dart';
import '../services/backup_restore_service.dart';
import 'agent_api_provider.dart';
import 'doc_extract_api_provider.dart';
import 'auto_backup_provider.dart';
import 'backup_provider.dart';
import '../core/storage/app_database_provider.dart';
import '../core/storage/storage_exception.dart';
import 'documents_provider.dart';
import 'document_task_provider.dart';
import '../services/doc_extract_usage_service.dart';
import 'proxy_provider.dart';
import 'reader_settings_provider.dart';
import 'sync_status_provider.dart';
import 'task_activity_provider.dart';
import 'theme_provider.dart';
import 'zotero_sync_provider.dart';

/// 备份编排——「打包 → 上传 → 清理」「下载 → 排空任务 → 恢复 → 刷新」
/// 两条链的唯一实现。设置页与自动备份任务都只调这里，不再各自拼接
/// BackupRestoreService / BackupRemote 与恢复后的 provider 刷新。
class BackupOrchestrator {
  BackupOrchestrator(this._ref);

  final Ref _ref;

  /// 当前配置解析出的远端 adapter；未配置返回 null。
  BackupRemote? get remote => resolveBackupRemote(
    _ref.read(backupRemoteTypeProvider),
    _ref.read(backupS3Provider),
    _ref.read(backupWebDavProvider),
  );

  /// 远端保留的版本化备份份数（时间戳文件名），超出按最旧删除。
  static const kKeepRemoteBackups = 3;

  /// 时间戳备份文件名（与 buildBackupFileName 的输出对应），按字符串
  /// 排序即按时间排序。
  static final _versionedNamePattern = RegExp(
    r'^otter_pad_backup_\d{8}_\d{6}\.zip$',
  );

  /// 打包并上传到远端（时间戳文件名，保留最近 [kKeepRemoteBackups] 份），
  /// 成功后落备份指纹快照。返回目标描述用于提示。临时 zip 无论成败都清理。
  Future<String> backupToRemote({required BackupScope scope}) async {
    final target = remote;
    if (target == null) {
      throw StateError('远端备份未配置');
    }
    final docs = _ref.read(documentsProvider).value ?? const [];
    String? tempArchivePath;
    try {
      // 指纹在打包前算（flush 后、打包中内容稳定），快照在上传成功后落。
      final fingerprints = await BackupFingerprintService.compute(docs);
      tempArchivePath = await BackupRestoreService.createBackupArchive(
        scope: scope,
        manifestExtra: {
          'device': Platform.localHostname,
          'documentCount': docs.length,
        },
      );
      final remoteName = BackupRestoreService.buildBackupFileName();
      await target.upload(tempArchivePath, remoteName);
      await _pruneOldBackups(target);
      await BackupFingerprintService.saveSnapshot(
        BackupSnapshot(
          at: DateTime.now(),
          scope: scope,
          remote: target.targetLabel,
          device: Platform.localHostname,
          docs: fingerprints,
        ),
      );
      _ref.invalidate(syncStatusProvider);
      return target.targetLabel;
    } finally {
      await _deleteTempFile(tempArchivePath);
    }
  }

  /// 清理超出保留份数的旧版本备份。尽力而为：清理失败不影响本次备份
  /// 成功（下次备份会再试）。固定文件名的旧式备份不在清理范围。
  Future<void> _pruneOldBackups(BackupRemote target) async {
    try {
      final versioned =
          (await target.list())
              .where((e) => _versionedNamePattern.hasMatch(e.name))
              .toList()
            ..sort((a, b) => b.name.compareTo(a.name));
      for (final entry in versioned.skip(kKeepRemoteBackups)) {
        await target.delete(entry.name);
      }
    } catch (e, st) {
      log.w('[Backup] 旧备份清理失败', error: e, stackTrace: st);
    }
  }

  /// 从远端下载备份到临时文件，返回 zip 路径。优先取最新的时间戳版本，
  /// 远端没有（或不支持列目录）时回退到配置中的固定文件名（兼容旧备份）。
  /// 调用方恢复完成后负责删除（恢复与下载分属两个用户可见阶段）。
  Future<String> downloadBackupToTemp() async {
    final target = remote;
    if (target == null) {
      throw StateError('远端备份未配置');
    }
    String remoteName = target.fixedName;
    try {
      final versioned =
          (await target.list())
              .where((e) => _versionedNamePattern.hasMatch(e.name))
              .toList()
            ..sort((a, b) => b.name.compareTo(a.name));
      if (versioned.isNotEmpty) remoteName = versioned.first.name;
    } catch (_) {}

    final tempDir = await getTemporaryDirectory();
    final archivePath = p.join(
      tempDir.path,
      'OtterPad',
      'restore',
      BackupRestoreService.buildBackupFileName(),
    );
    await Directory(p.dirname(archivePath)).create(recursive: true);
    await target.download(remoteName, archivePath);
    return archivePath;
  }

  /// 从本地 zip 恢复：排空在飞任务 → 执行恢复 → 刷新受影响 provider。
  /// merge 模式返回合并统计，overwrite 返回 null。
  Future<MergeResult?> restoreFromArchive({
    required String archivePath,
    required BackupRestoreScope scope,
    required RestoreMode mode,
  }) async {
    await _drainActiveTasks();
    try {
      return await BackupRestoreService.restoreBackupArchive(
        archivePath: archivePath,
        scope: scope,
        mode: mode,
      );
    } finally {
      // 失败回滚也会换连接，旧订阅必须一起重建。
      _refreshAfterRestore(scope);
    }
  }

  /// 恢复会 close Drift 连接（overwrite）或整批读写 DB（merge）——
  /// 先取消所有 Active Task 并等活集合清空，避免在飞任务（翻译写盘、
  /// 提取 saveResult 等）撞上 close 窗口炸出 "database has been closed"。
  /// 取消是协作式的，已在飞的网络请求要跑完才退出，超时则停止恢复。
  Future<void> _drainActiveTasks() async {
    final notifier = _ref.read(taskActivityProvider.notifier);
    notifier.cancelAll();
    final documentTasks = _ref.read(documentTaskProvider.notifier);
    for (final task in _ref.read(documentTaskProvider).values.toList()) {
      if (task.isActive) documentTasks.cancelTask(task.key);
    }
    bool hasActiveTasks() =>
        _ref.read(taskActivityProvider).isNotEmpty ||
        _ref.read(documentTaskProvider).values.any((task) => task.isActive);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (hasActiveTasks() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (hasActiveTasks()) {
      throw const StorageException(StorageFailure.activeTasks);
    }
  }

  /// 恢复后刷新受影响的 provider。设置类 notifier 从重开的 Drift 缓存
  /// 重新加载；文献类数据 provider 经 [appDatabaseProvider] 失效自动重建
  /// 并重订阅新库（ADR-0001）。
  void _refreshAfterRestore(BackupRestoreScope scope) {
    if (scope.restoreSettings) {
      _ref.read(themeProvider.notifier).reload();
      _ref.read(proxyProvider.notifier).reload();
      _ref.read(agentApiProvider.notifier).reload();
      _ref.read(docExtractApiProvider.notifier).reload();
      _ref.read(docExtractUsageProvider.notifier).reload();
      _ref.read(readerSettingsProvider.notifier).reload();
      _ref.read(backupRemoteTypeProvider.notifier).reload();
      _ref.read(backupS3Provider.notifier).reload();
      _ref.read(backupWebDavProvider.notifier).reload();
      _ref.read(autoBackupProvider.notifier).reload();
      _ref.read(zoteroSyncProvider.notifier).reload();
    }

    if (scope.restoreLibrary) {
      // invalidate 数据库 provider → 所有 watch() 它的数据 provider（含
      // highlightProvider(docId) family 全部实例）重建并重订阅新库。
      _ref.invalidate(appDatabaseProvider);
    }
    _ref.invalidate(syncStatusProvider);
  }

  Future<void> _deleteTempFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final backupOrchestratorProvider = Provider<BackupOrchestrator>(
  (ref) => BackupOrchestrator(ref),
);
