import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/rust_backend.dart';
import '../src/rust/sync/archive.dart';
import '../src/rust/sync/status.dart';
import 'backup_orchestrator.dart';
import 'backup_provider.dart';
import 'documents_provider.dart';

/// 单篇文献相对上次备份快照的同步状态。
enum DocSyncState { synced, changed, neverBackedUp }

/// 变更的主因（多维度同时变化时按 content > meta > files 取最显著者），
/// 云同步页行尾的「为什么未同步」提示用。
enum DocChangeReason { added, content, meta, files }

class DocSyncInfo {
  final DocSyncState state;
  final DocChangeReason? reason;

  const DocSyncInfo(this.state, [this.reason]);
}

/// 上次备份的概要。
class BackupSnapshotInfo {
  final DateTime at;
  final BackupScope scope;
  final String remote;
  final String device;

  const BackupSnapshotInfo({
    required this.at,
    required this.scope,
    required this.remote,
    required this.device,
  });
}

/// 云同步状态：Rust 按文献指纹与上次备份快照比对（纯本地计算）。
class SyncStatusResult {
  final bool remoteConfigured;
  final BackupSnapshotInfo? snapshot;
  final Map<String, DocSyncInfo> docs;

  const SyncStatusResult({
    required this.remoteConfigured,
    required this.snapshot,
    required this.docs,
  });

  bool get hasPendingChanges =>
      docs.values.any((d) => d.state != DocSyncState.synced);
}

/// 备份成功后由 BackupOrchestrator invalidate 重算；文献与远端配置变化经 watch 重算。
final syncStatusProvider = FutureProvider<SyncStatusResult>((ref) async {
  ref.watch(documentsProvider);
  ref.watch(backupRemoteTypeProvider);
  ref.watch(backupS3Provider);
  ref.watch(backupWebDavProvider);
  final remoteConfigured = ref.read(backupOrchestratorProvider).remote != null;
  final status = await RustBackend.instance.backupStatus(
    taskId: rustTaskId('backup-status'),
  );
  final at = status.lastBackupAt;
  return SyncStatusResult(
    remoteConfigured: remoteConfigured,
    snapshot: at == null
        ? null
        : BackupSnapshotInfo(
            at: DateTime.fromMillisecondsSinceEpoch(at),
            scope: status.lastScope ?? BackupScope.dataOnly,
            remote: status.lastRemote ?? '',
            device: status.lastDevice ?? '',
          ),
    docs: {
      for (final d in status.documents)
        d.documentId: switch (d.state) {
          BackupState.neverBackedUp => const DocSyncInfo(
            DocSyncState.neverBackedUp,
          ),
          BackupState.unchanged => const DocSyncInfo(DocSyncState.synced),
          BackupState.added => const DocSyncInfo(
            DocSyncState.changed,
            DocChangeReason.added,
          ),
          BackupState.contentChanged => const DocSyncInfo(
            DocSyncState.changed,
            DocChangeReason.content,
          ),
          BackupState.metadataChanged => const DocSyncInfo(
            DocSyncState.changed,
            DocChangeReason.meta,
          ),
          BackupState.filesChanged => const DocSyncInfo(
            DocSyncState.changed,
            DocChangeReason.files,
          ),
        },
    },
  );
});
