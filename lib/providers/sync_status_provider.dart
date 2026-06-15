import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup_fingerprint.dart';
import '../services/backup_remote.dart';
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

/// 云同步状态的聚合结果——云图标角标与云同步页共用的单一真值源。
///
/// 语义：状态 = 「相对上次备份快照是否有变化」（纯本地指纹比对），
/// 不是远端逐文件对齐。
class SyncStatusResult {
  final bool remoteConfigured;
  final BackupSnapshot? snapshot;
  final Map<String, DocSyncInfo> docs;

  const SyncStatusResult({
    required this.remoteConfigured,
    required this.snapshot,
    required this.docs,
  });

  int countOf(DocSyncState state) =>
      docs.values.where((d) => d.state == state).length;

  bool get hasPendingChanges =>
      docs.values.any((d) => d.state != DocSyncState.synced);
}

/// 备份成功后由 BackupOrchestrator invalidate 重算；文献列表与远端配置
/// 变化经 watch 自动重算。批注等不经 documentsProvider 的变更在打开
/// 云同步页时手动 invalidate 兜底。
final syncStatusProvider = FutureProvider<SyncStatusResult>((ref) async {
  final docs = ref.watch(documentsProvider);
  final remoteType = ref.watch(backupRemoteTypeProvider);
  final s3 = ref.watch(backupS3Provider);
  final webDav = ref.watch(backupWebDavProvider);

  final remoteConfigured = resolveBackupRemote(remoteType, s3, webDav) != null;
  final snapshot = BackupFingerprintService.loadSnapshot();

  if (snapshot == null) {
    return SyncStatusResult(
      remoteConfigured: remoteConfigured,
      snapshot: null,
      docs: {
        for (final doc in docs)
          doc.id: const DocSyncInfo(DocSyncState.neverBackedUp),
      },
    );
  }

  final current = await BackupFingerprintService.compute(docs);
  final result = <String, DocSyncInfo>{};
  for (final entry in current.entries) {
    final previous = snapshot.docs[entry.key];
    if (previous == null) {
      result[entry.key] = const DocSyncInfo(
        DocSyncState.changed,
        DocChangeReason.added,
      );
    } else if (previous.content != entry.value.content) {
      result[entry.key] = const DocSyncInfo(
        DocSyncState.changed,
        DocChangeReason.content,
      );
    } else if (previous.meta != entry.value.meta) {
      result[entry.key] = const DocSyncInfo(
        DocSyncState.changed,
        DocChangeReason.meta,
      );
    } else if (previous.files != entry.value.files) {
      result[entry.key] = const DocSyncInfo(
        DocSyncState.changed,
        DocChangeReason.files,
      );
    } else {
      result[entry.key] = const DocSyncInfo(DocSyncState.synced);
    }
  }
  return SyncStatusResult(
    remoteConfigured: remoteConfigured,
    snapshot: snapshot,
    docs: result,
  );
});
