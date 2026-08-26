import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../../data/models/book/document.dart';
import '../../providers/auto_backup_provider.dart';
import '../../providers/backup_orchestrator.dart';
import '../../providers/documents_provider.dart';
import '../../providers/sync_status_provider.dart';
import '../../router/app_routes.dart';
import '../../services/backup_restore_service.dart';
import '../../services/haptics.dart';
import '../../services/snackbar_service.dart';
import '../../widgets/backup_scope_dialog.dart';

/// 云同步状态页：摘要卡（远端目标 / 上次备份 / 立即备份）+ 按同步状态
/// 分组的文献列表。状态数据全部来自 [syncStatusProvider]；本页只读 +
/// 推备份，恢复等危险操作留在备份设置页。
class CloudSyncPage extends ConsumerStatefulWidget {
  const CloudSyncPage({super.key});

  @override
  ConsumerState<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends ConsumerState<CloudSyncPage> {
  bool _backingUp = false;

  @override
  void initState() {
    super.initState();
    // 批注等不经 documentsProvider 的变更不会触发自动重算，进页兜底刷新。
    // ref 依赖 InheritedWidget 定位容器，initState 内不可同步调用，推迟一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(syncStatusProvider);
    });
  }

  Future<void> _backupNow() async {
    final scope = await showBackupScopeDialog(context);
    if (scope == null || !mounted) return;
    setState(() => _backingUp = true);
    final snackBar = ref.read(snackBarServiceProvider);
    try {
      final target = await ref
          .read(backupOrchestratorProvider)
          .backupToRemote(scope: scope);
      if (mounted) {
        snackBar.showResult(message: context.l10n.remoteBackupUploaded(target));
      }
    } catch (e) {
      if (mounted) {
        snackBar.showResult(
          message: context.l10n.uploadRemoteFailed(
            e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = ref.watch(syncStatusProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          context.l10n.cloudSync,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            '$e',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
          ),
        ),
        data: (result) => _buildBody(context, result),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SyncStatusResult result) {
    final docs = ref.watch(documentsProvider).value ?? const [];
    final byId = {for (final doc in docs) doc.id: doc};

    List<Document> docsIn(DocSyncState state) => [
      for (final entry in result.docs.entries)
        if (entry.value.state == state && byId[entry.key] != null)
          byId[entry.key]!,
    ];

    final changed = docsIn(DocSyncState.changed);
    final never = docsIn(DocSyncState.neverBackedUp);
    final synced = docsIn(DocSyncState.synced);
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ).copyWith(bottom: 40),
      children: [
        _summaryCard(context, result),
        if (changed.isNotEmpty)
          _group(
            context,
            title: l10n.syncGroupChanged,
            count: changed.length,
            accent: cs.tertiary,
            docs: changed,
            trailingOf: (doc) =>
                _reasonLabel(l10n, result.docs[doc.id]?.reason),
          ),
        if (never.isNotEmpty)
          _group(
            context,
            title: l10n.syncGroupNever,
            count: never.length,
            accent: cs.error,
            docs: never,
          ),
        if (synced.isNotEmpty)
          _group(
            context,
            title: l10n.syncGroupSynced,
            count: synced.length,
            accent: cs.primary,
            docs: synced,
          ),
      ],
    );
  }

  Widget _summaryCard(BuildContext context, SyncStatusResult result) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final autoBackup = ref.watch(autoBackupProvider);

    if (!result.remoteConfigured) {
      return _cardShell(
        cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.cloud_off_rounded, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.syncRemoteNotConfigured,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.syncRemoteNotConfiguredDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Haptics.soft();
                  context.push(AppRoutes.settingsOverlayBackup);
                },
                child: Text(l10n.goToSettings),
              ),
            ),
          ],
        ),
      );
    }

    final snapshot = result.snapshot;
    final intervalLabel = switch (autoBackup.interval) {
      AutoBackupInterval.off => l10n.autoBackupOff,
      AutoBackupInterval.daily => l10n.autoBackupDaily,
      AutoBackupInterval.weekly => l10n.autoBackupWeekly,
    };
    final scopeLabel = snapshot == null
        ? null
        : switch (snapshot.scope) {
            BackupScope.full => l10n.backupScopeFull,
            BackupScope.dataOnly => l10n.backupScopeData,
          };

    return _cardShell(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.hasPendingChanges
                    ? Symbols.cloud_sync_rounded
                    : Symbols.cloud_done_rounded,
                color: result.hasPendingChanges ? cs.tertiary : cs.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  snapshot?.remote ??
                      ref
                          .read(backupOrchestratorProvider)
                          .remote
                          ?.targetLabel ??
                      '',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            snapshot == null
                ? l10n.syncLastBackupNever
                : l10n.syncLastBackup(
                    '${_formatTime(snapshot.at)} · $scopeLabel'
                    '${snapshot.device.isEmpty ? '' : ' · ${snapshot.device}'}',
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${l10n.autoBackup}：$intervalLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _backingUp ? null : _backupNow,
              icon: _backingUp
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.cloud_upload_rounded, size: 18),
              label: Text(l10n.syncBackupNow),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardShell(ColorScheme cs, {required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withAlpha(60)),
      ),
      child: child,
    );
  }

  Widget _group(
    BuildContext context, {
    required String title,
    required int count,
    required Color accent,
    required List<Document> docs,
    String? Function(Document doc)? trailingOf,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withAlpha(60)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < docs.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: cs.outlineVariant.withAlpha(40),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            docs[i].title,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (trailingOf?.call(docs[i]) case final reason?) ...[
                          const SizedBox(width: 12),
                          Text(
                            reason,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _reasonLabel(AppLocalizations l10n, DocChangeReason? reason) =>
      switch (reason) {
        DocChangeReason.added => l10n.syncReasonAdded,
        DocChangeReason.content => l10n.syncReasonContent,
        DocChangeReason.meta => l10n.syncReasonMeta,
        DocChangeReason.files => l10n.syncReasonFiles,
        null => null,
      };

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
