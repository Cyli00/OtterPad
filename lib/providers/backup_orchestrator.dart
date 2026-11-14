import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/rust_backend.dart';
import '../core/rust_models.dart';
import '../core/storage/secure_credential_vault.dart';
import '../core/storage/storage.dart';
import '../services/prompts.dart';
import '../src/rust/api/backup.dart';
import '../src/rust/api/remote.dart';
import '../src/rust/api/sync.dart';
import '../src/rust/error.dart';
import '../src/rust/sync/archive.dart';
import '../src/rust/sync/backup.dart';
import '../src/rust/sync/remote.dart';
import 'agent_api_provider.dart';
import 'auto_backup_provider.dart';
import 'backup_provider.dart';
import 'doc_extract_api_provider.dart';
import 'document_task_provider.dart';
import 'proxy_provider.dart';
import 'reader_settings_provider.dart';
import 'sync_status_provider.dart';
import 'task_activity_provider.dart';
import 'theme_provider.dart';
import 'zotero_sync_provider.dart';

/// 备份编排：打包、上传、下载与恢复都在 Rust；这里组装远端配置、接收进度并在
/// 恢复后刷新界面状态。设置页与自动备份都只调这里。
class BackupOrchestrator {
  BackupOrchestrator(this._ref);

  final Ref _ref;

  /// 当前配置的远端；未配置返回 null。密钥由凭据注入 Rust。
  RemoteConfig? get remote {
    switch (_ref.read(backupRemoteTypeProvider)) {
      case BackupRemoteType.webdav:
        final w = _ref.read(backupWebDavProvider);
        if (!w.isConfigured) return null;
        return RemoteConfig.webdav(
          serverUrl: w.serverUrl.trim(),
          username: w.username.trim(),
          remoteDir: BackupWebDavState.normalizeRemoteDir(w.remoteDir),
          fileName: w.fileName.trim().isEmpty
              ? BackupWebDavState.defaultFileName
              : w.fileName.trim(),
        );
      case BackupRemoteType.s3:
        final s = _ref.read(backupS3Provider);
        if (!s.isConfigured) return null;
        return RemoteConfig.s3(
          endpoint: s.endpoint.trim(),
          region: s.region.trim(),
          bucket: s.bucket.trim(),
          objectKey: s.objectKey.trim(),
          pathStyle: s.usePathStyle,
          accessKey: s.accessKeyId.trim(),
        );
    }
  }

  static String get _device => Platform.localHostname;

  /// 本地导出：打包到 [path]。
  Future<void> exportTo(String path, BackupScope scope) => _backupEvents(
    RustBackend.instance.createBackup(
      path: path,
      scope: scope,
      deviceName: _device,
      taskId: rustTaskId('backup'),
    ),
  );

  /// 打包并上传（Rust 保留最近 3 份版本化备份），返回上传的文件名。
  Future<String> backupToRemote({required BackupScope scope}) async {
    final config = remote;
    if (config == null) {
      throw const OtterError(code: ErrorCode.invalidArgument, detail: 'remote');
    }
    try {
      await for (final event in RustBackend.instance.backupToRemote(
        config: config,
        scope: scope,
        device: _device,
        onlyIfDue: false,
        taskId: rustTaskId('backup-remote'),
      )) {
        switch (event) {
          case SyncEvent_Uploaded(:final name):
            return name;
          case SyncEvent_Failed(:final error):
            throw error;
          default:
        }
      }
      throw const OtterError(
        code: ErrorCode.cancelled,
        detail: 'backup stream',
      );
    } finally {
      _ref.invalidate(syncStatusProvider);
    }
  }

  /// 下载最新的远端备份到临时文件，返回路径；调用方恢复后删除。
  /// 优先取时间戳命名的最新版本，没有时用配置中的固定文件名（兼容旧备份）。
  Future<String> downloadBackupToTemp() async {
    final config = remote;
    if (config == null) {
      throw const OtterError(code: ErrorCode.invalidArgument, detail: 'remote');
    }
    var name = switch (config) {
      RemoteConfig_Webdav(:final fileName) => fileName,
      RemoteConfig_S3(:final objectKey) => p.posix.basename(objectKey),
    };
    try {
      final versioned = (await RustBackend.instance.remoteBackups(
        config: config,
        taskId: rustTaskId('backup-list'),
      )).map((e) => e.name).where(_versioned.hasMatch).toList()..sort();
      if (versioned.isNotEmpty) name = versioned.last;
    } catch (_) {}
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'OtterPad', 'restore'),
    );
    await directory.create(recursive: true);
    final path = p.join(directory.path, name);
    await for (final event in RustBackend.instance.transferBackup(
      config: config,
      name: name,
      path: path,
      direction: TransferDirection.download,
      taskId: rustTaskId('backup-download'),
    )) {
      switch (event) {
        case RemoteTransferEvent_Completed():
          return path;
        case RemoteTransferEvent_Failed(:final error):
          throw error;
        default:
      }
    }
    throw const OtterError(
      code: ErrorCode.cancelled,
      detail: 'download stream',
    );
  }

  static final _versioned = RegExp(r'^otter_pad_backup_\d{8}_\d{6}\.zip$');

  /// 从本地 zip 恢复：Rust 先校验并在副本上准备，确认后替换；提交时 Rust
  /// 取消其余任务。返回合并统计。
  Future<RestoreReport> restoreFromArchive({
    required String archivePath,
    required RestoreScope scope,
    required RestoreMode mode,
  }) async {
    _cancelActiveTasks();
    RestorePreview? preview;
    await _backupEvents(
      RustBackend.instance.prepareRestore(
        path: archivePath,
        scope: scope,
        mode: mode,
        taskId: rustTaskId('restore-prepare'),
      ),
      onPrepared: (p) => preview = p,
    );
    final prepared = preview;
    if (prepared == null) {
      throw const OtterError(code: ErrorCode.invalidData, detail: 'restore');
    }
    RestoreReport? report;
    try {
      await _backupEvents(
        RustBackend.instance.commitRestore(
          id: prepared.id,
          taskId: rustTaskId('restore-commit'),
        ),
        onRestored: (r) => report = r,
      );
    } finally {
      await _refreshAfterRestore(scope);
    }
    return report ?? prepared.report;
  }

  void _cancelActiveTasks() {
    _ref.read(taskActivityProvider.notifier).cancelAll();
    final documentTasks = _ref.read(documentTaskProvider.notifier);
    for (final task in _ref.read(documentTaskProvider).values.toList()) {
      if (task.isActive) documentTasks.cancelTask(task.key);
    }
  }

  Future<void> _backupEvents(
    Stream<BackupEvent> events, {
    void Function(RestorePreview)? onPrepared,
    void Function(RestoreReport)? onRestored,
  }) async {
    await for (final event in events) {
      switch (event) {
        case BackupEvent_Prepared(:final preview):
          onPrepared?.call(preview);
        case BackupEvent_Restored(:final report):
          onRestored?.call(report);
        case BackupEvent_Failed(:final error):
          throw error;
        default:
      }
    }
  }

  /// 恢复后从 Rust 重新载入设置与文献数据。
  Future<void> _refreshAfterRestore(RestoreScope scope) async {
    if (scope != RestoreScope.libraryOnly) {
      await GStorage.reloadSettings();
      await SecureCredentialVault.rewriteIndex();
      await Prompts.load();
      _ref.read(themeProvider.notifier).reload();
      _ref.read(proxyProvider.notifier).reload();
      _ref.read(agentApiProvider.notifier).reload();
      _ref.read(docExtractApiProvider.notifier).reload();
      _ref.read(readerSettingsProvider.notifier).reload();
      _ref.read(backupRemoteTypeProvider.notifier).reload();
      _ref.read(backupS3Provider.notifier).reload();
      _ref.read(backupWebDavProvider.notifier).reload();
      _ref.read(autoBackupProvider.notifier).reload();
      _ref.read(zoteroSyncProvider.notifier).reload();
    }
    _ref.invalidate(extractionUsageProvider);
    _ref.read(autoBackupSchedulerProvider).restart();
    bumpLibrary(_ref);
    _ref.invalidate(syncStatusProvider);
  }
}

final backupOrchestratorProvider = Provider<BackupOrchestrator>(
  (ref) => BackupOrchestrator(ref),
);
