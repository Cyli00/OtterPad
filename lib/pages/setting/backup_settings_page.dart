import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auto_backup_provider.dart';
import '../../providers/backup_orchestrator.dart';
import '../../providers/backup_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/zotero_sync_provider.dart';
import '../../services/backup_merge_service.dart';
import '../../services/backup_restore_service.dart';
import '../../services/backup_s3_service.dart';
import '../../services/haptics.dart';
import '../../widgets/backup_scope_dialog.dart';
import '../../widgets/tactile_press.dart';
import '../../services/snackbar_service.dart';
import '../../services/storage_usage_service.dart';
import '../../utils/debounced_action.dart';
import '../../core/l10n.dart';
import '../../router/app_routes.dart';
import 'package:material_symbols_icons/symbols.dart';

class BackupSettingsPage extends ConsumerStatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  ConsumerState<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends ConsumerState<BackupSettingsPage> {
  bool _busy = false;
  String _busyText = '';
  String _pingCacheKey = '';
  Future<bool>? _pingFuture;
  String? _totalSizeText;

  late final TextEditingController _zoteroKeyCtrl;
  final _zoteroKeyDebounce = DebouncedAction();
  bool _zoteroKeyObscured = true;

  @override
  void initState() {
    super.initState();
    _zoteroKeyCtrl = TextEditingController(
      text: ref.read(zoteroSyncProvider).apiKey,
    );
    _refreshSizeLabels();
  }

  @override
  void dispose() {
    _zoteroKeyDebounce.cancel();
    _zoteroKeyCtrl.dispose();
    super.dispose();
  }

  void _refreshSizeLabels() {
    StorageUsageService.computeReport().then((report) {
      if (mounted) {
        setState(
          () => _totalSizeText = context.l10n.storageUsage(
            StorageUsageService.formatSize(report.totalBytes),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final remoteType = ref.watch(backupRemoteTypeProvider);
    final webDav = ref.watch(backupWebDavProvider);
    final s3 = ref.watch(backupS3Provider);
    final autoBackup = ref.watch(autoBackupProvider);
    final zotero = ref.watch(zoteroSyncProvider);
    _ensurePingFuture(remoteType, webDav, s3);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          context.l10n.dataManagement,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: Listener(
        onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ).copyWith(bottom: 40),
              children: [
                _buildGroup(
                  context,
                  title: context.l10n.remoteBackup,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.backupMethod,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<BackupRemoteType>(
                                segments: const [
                                  ButtonSegment(
                                    value: BackupRemoteType.s3,
                                    icon: Icon(Symbols.cloud_circle_rounded),
                                    label: Text('S3'),
                                  ),
                                  ButtonSegment(
                                    value: BackupRemoteType.webdav,
                                    icon: Icon(Symbols.cloud_sync_rounded),
                                    label: Text('WebDAV'),
                                  ),
                                ],
                                selected: {remoteType},
                                onSelectionChanged: (value) {
                                  Haptics.soft();
                                  ref
                                      .read(backupRemoteTypeProvider.notifier)
                                      .setRemoteType(value.first);
                                  setState(() {
                                    _pingFuture = null;
                                    _pingCacheKey = '';
                                  });
                                },
                                style: SegmentedButton.styleFrom(
                                  backgroundColor: cs.surface,
                                  selectedBackgroundColor: cs.primaryContainer,
                                  side: BorderSide(
                                    color: cs.outlineVariant.withAlpha(100),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildDivider(context),
                      _buildRemoteConfigTile(context, remoteType, s3, webDav),
                      _buildDivider(context),
                      _buildAutoBackupSection(context, autoBackup),
                      _buildDivider(context),
                      _ActionTile(
                        icon: Symbols.cloud_upload_rounded,
                        title: context.l10n.backupTo(remoteType.label),
                        subtitle: _remoteConfigured(remoteType, s3, webDav)
                            ? context.l10n.uploadBackupTo(
                                _remoteTargetLabel(remoteType, s3, webDav),
                              )
                            : context.l10n.pleaseConfigureFirst(
                                remoteType.label,
                              ),
                        enabled:
                            _remoteConfigured(remoteType, s3, webDav) && !_busy,
                        onTap: _backupToRemote,
                      ),
                      _buildDivider(context),
                      _ActionTile(
                        icon: Symbols.cloud_download_rounded,
                        title: context.l10n.restoreFromRemote(remoteType.label),
                        subtitle: _remoteConfigured(remoteType, s3, webDav)
                            ? context.l10n.downloadAndRestore(
                                _remoteTargetLabel(remoteType, s3, webDav),
                              )
                            : context.l10n.pleaseConfigureFirst(
                                remoteType.label,
                              ),
                        enabled:
                            _remoteConfigured(remoteType, s3, webDav) && !_busy,
                        onTap: _restoreFromRemote,
                      ),
                    ],
                  ),
                ),
                _buildZoteroGroup(context, zotero),
                _buildGroup(
                  context,
                  title: context.l10n.localBackup,
                  child: Column(
                    children: [
                      _ActionTile(
                        icon: Symbols.download_rounded,
                        title: context.l10n.exportBackup,
                        subtitle: context.l10n.generateZipAndSave,
                        enabled: !_busy,
                        onTap: _exportBackupToLocal,
                      ),
                      _buildDivider(context),
                      _ActionTile(
                        icon: Symbols.restore_page_rounded,
                        title: context.l10n.restoreFromBackup,
                        subtitle: context.l10n.selectLocalZipRestore,
                        enabled: !_busy,
                        onTap: _restoreFromLocal,
                      ),
                    ],
                  ),
                ),
                _buildGroup(
                  context,
                  title: context.l10n.storage,
                  child: Column(
                    children: [
                      _ActionTile(
                        icon: Symbols.folder_managed_rounded,
                        title: context.l10n.storageSpace,
                        subtitle: _totalSizeText ??
                            context.l10n.thumbnailsAndTemp,
                        enabled: !_busy,
                        onTap: () => context.push(AppRoutes.settingsStorage),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: cs.scrim.withAlpha(80),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: _buildBusyIndicator(theme),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 忙碌遮罩内容：备份/恢复/清理期间的不确定转圈。
  Widget _buildBusyIndicator(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(height: 16),
        Text(
          _busyText,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildGroup(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12, top: 24),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 80,
      endIndent: 20,
      color: cs.outlineVariant.withAlpha(70),
    );
  }

  Widget _buildZoteroGroup(BuildContext context, ZoteroSyncState zotero) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final importedCount = ZoteroSyncStore.importedCount;

    return _buildGroup(
      context,
      title: context.l10n.zoteroSync,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'API Key',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        Haptics.soft();
                        launchUrl(
                          Uri.parse('https://www.zotero.org/settings/keys/new'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: Icon(
                        Symbols.arrow_outward_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: context.l10n.getToken,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _zoteroKeyCtrl,
                  onChanged: (v) {
                    _zoteroKeyDebounce.run(
                      () => ref
                          .read(zoteroSyncProvider.notifier)
                          .setApiKey(v.trim()),
                    );
                  },
                  obscureText: _zoteroKeyObscured,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Zotero API Key ...',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant.withAlpha(120),
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withAlpha(100),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _zoteroKeyObscured
                            ? Symbols.visibility_off_rounded
                            : Symbols.visibility_rounded,
                        size: 20,
                      ),
                      onPressed: () {
                        Haptics.soft();
                        setState(
                          () => _zoteroKeyObscured = !_zoteroKeyObscured,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildDivider(context),
          _ActionTile(
            icon: Symbols.sync_rounded,
            title: context.l10n.syncZoteroLibrary,
            subtitle: zotero.isConfigured
                ? (importedCount > 0
                      ? context.l10n.zoteroImportedPull(importedCount)
                      : context.l10n.zoteroImportHint)
                : context.l10n.pleaseFillApiKey,
            enabled: zotero.isConfigured && !_busy,
            onTap: () => _syncZotero(zotero),
          ),
          if (zotero.isConfigured) ...[
            _buildDivider(context),
            _ActionTile(
              icon: Symbols.restart_alt_rounded,
              title: context.l10n.fullResync,
              subtitle: context.l10n.zoteroResetHint,
              enabled: !_busy,
              onTap: () => _syncZotero(zotero, fullResync: true),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _syncZotero(
    ZoteroSyncState zotero, {
    bool fullResync = false,
  }) async {
    if (!zotero.isConfigured) return;
    if (fullResync) {
      final confirmed = await _confirmZoteroReset();
      if (confirmed != true) return;
    }
    // 同步走全局 TaskProvider（进度 snackbar + 可取消），与重构文库等后台任务一致。
    await ref
        .read(taskProvider.notifier)
        .syncZotero(zotero.apiKey, fullResync: fullResync);
    if (mounted) setState(() {}); // 刷新「已导入 N 篇」副标题
  }

  Future<bool?> _confirmZoteroReset() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text(
            ctx.l10n.resetZoteroSync,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            ctx.l10n.resetZoteroConfirm,
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.l10n.reimport),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRemoteConfigTile(
    BuildContext context,
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final configured = _remoteConfigured(remoteType, s3, webDav);
    final title = remoteType == BackupRemoteType.s3
        ? context.l10n.s3Config
        : context.l10n.webDavConfig;
    final icon = remoteType == BackupRemoteType.s3
        ? Symbols.cloud_circle_rounded
        : Symbols.cloud_sync_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                if (!configured)
                  Text(
                    context.l10n.remoteNotConfigured(remoteType.label),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  )
                else ...[
                  ..._remoteSummaryLines(remoteType, s3, webDav).map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<bool>(
                    future: _pingFuture,
                    builder: (context, snapshot) {
                      final waiting =
                          snapshot.connectionState != ConnectionState.done;
                      final success = snapshot.data == true;
                      final color = waiting
                          ? cs.tertiary
                          : (success ? Colors.green : cs.error);
                      final label = waiting
                          ? context.l10n.detecting
                          : (success
                                ? context.l10n.connectionOk
                                : context.l10n.connectionFailed);
                      return _StatusBadge(color: color, label: label);
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () {
                    Haptics.soft();
                    _editRemoteConfig(remoteType, s3, webDav);
                  },
            child: Text(
              configured ? context.l10n.edit : context.l10n.configure,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _remoteSummaryLines(
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) {
    if (remoteType == BackupRemoteType.s3) {
      return [
        s3.normalizedEndpoint,
        context.l10n.s3BucketInfo(s3.bucket, s3.region),
        context.l10n.s3ObjectInfo(s3.normalizedObjectKey),
      ];
    }
    return [
      webDav.serverUrl,
      context.l10n.webDavAccountInfo(webDav.username),
      context.l10n.webDavPathInfo(webDav.remoteFilePath),
    ];
  }

  bool _remoteConfigured(
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) {
    return remoteType == BackupRemoteType.s3
        ? s3.isConfigured
        : webDav.isConfigured;
  }

  String _remoteTargetLabel(
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) {
    return remoteType == BackupRemoteType.s3
        ? s3.normalizedObjectKey
        : webDav.remoteFilePath;
  }

  void _ensurePingFuture(
    BackupRemoteType remoteType,
    BackupWebDavState webDav,
    BackupS3State s3,
  ) {
    final cacheKey = switch (remoteType) {
      BackupRemoteType.s3 =>
        's3|${s3.normalizedEndpoint}|${s3.region}|${s3.bucket}|${s3.usePathStyle}',
      BackupRemoteType.webdav =>
        'webdav|${webDav.serverUrl}|${webDav.username}|${webDav.remoteFilePath}',
    };

    if (!_remoteConfigured(remoteType, s3, webDav)) {
      _pingCacheKey = '';
      _pingFuture = Future.value(false);
      return;
    }

    if (_pingFuture == null || _pingCacheKey != cacheKey) {
      _pingCacheKey = cacheKey;
      _pingFuture = _pingRemote(remoteType, s3, webDav);
    }
  }

  Future<bool> _pingRemote(
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) async {
    try {
      if (remoteType == BackupRemoteType.s3) {
        await BackupS3Service.instance.ping(s3);
      } else {
        await createBackupWebDavClient(webDav).ping();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _editRemoteConfig(
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) async {
    if (remoteType == BackupRemoteType.s3) {
      final next = await showDialog<BackupS3State>(
        context: context,
        builder: (context) => _S3ConfigDialog(initial: s3),
      );
      if (next == null) return;
      await ref.read(backupS3Provider.notifier).save(next);
    } else {
      final next = await showDialog<BackupWebDavState>(
        context: context,
        builder: (context) => _WebDavConfigDialog(initial: webDav),
      );
      if (next == null) return;
      await ref.read(backupWebDavProvider.notifier).save(next);
    }

    if (!mounted) return;
    setState(() {
      _pingFuture = null;
      _pingCacheKey = '';
    });
  }

  Future<void> _exportBackupToLocal() async {
    final scope = await showBackupScopeDialog(context);
    if (scope == null || !mounted) return;
    String? tempArchivePath;

    try {
      await _runBusy(context.l10n.generatingLocalBackup, () async {
        tempArchivePath = await BackupRestoreService.createBackupArchive(
          scope: scope,
        );
      });
      if (!mounted || tempArchivePath == null) return;

      final targetPath = await FilePicker.platform.saveFile(
        dialogTitle: context.l10n.saveBackupFile,
        fileName: BackupRestoreService.buildBackupFileName(),
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        lockParentWindow: true,
      );
      if (targetPath == null) return;

      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await File(tempArchivePath!).copy(targetFile.path);
      if (!mounted) return;
      _showMessage(context.l10n.backupExportedTo(targetFile.path));
    } catch (e) {
      if (!mounted) return;
      _showMessage(context.l10n.exportBackupFailed(_formatError(e)));
    } finally {
      await _deleteTempFile(tempArchivePath);
    }
  }

  Future<void> _restoreFromLocal() async {
    final l10n = context.l10n;
    final options = await _pickRestoreOptions();
    if (options == null) return;
    final (scope, mode) = options;

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.selectBackupFile,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      lockParentWindow: true,
    );
    final archivePath = result?.files.single.path;
    if (archivePath == null) return;

    try {
      if (!mounted) return;
      final mergeResult = await _restoreArchive(
        archivePath: archivePath,
        scope: scope,
        mode: mode,
        busyText: mode == RestoreMode.merge
            ? context.l10n.mergingBackup
            : context.l10n.restoringBackup,
      );
      _showRestoreMessage(mode, mergeResult);
    } catch (e) {
      if (!mounted) return;
      _showMessage(context.l10n.restoreFailed(_formatError(e)));
    }
  }

  Future<void> _backupToRemote() async {
    final scope = await showBackupScopeDialog(context);
    if (scope == null || !mounted) return;

    try {
      String? target;
      await _runBusy(context.l10n.generatingAndUploading, () async {
        target = await ref
            .read(backupOrchestratorProvider)
            .backupToRemote(scope: scope);
      });
      if (!mounted) return;
      _showMessage(context.l10n.remoteBackupUploaded(target ?? ''));
    } catch (e) {
      if (!mounted) return;
      _showMessage(context.l10n.uploadRemoteFailed(_formatError(e)));
    }
  }

  Future<void> _restoreFromRemote() async {
    final options = await _pickRestoreOptions();
    if (options == null || !mounted) return;
    final (scope, mode) = options;

    String? tempArchivePath;
    try {
      await _runBusy(context.l10n.downloadingRemoteBackup, () async {
        tempArchivePath = await ref
            .read(backupOrchestratorProvider)
            .downloadBackupToTemp();
      });
      if (!mounted || tempArchivePath == null) return;

      final mergeResult = await _restoreArchive(
        archivePath: tempArchivePath!,
        scope: scope,
        mode: mode,
        busyText: mode == RestoreMode.merge
            ? context.l10n.mergingRemoteBackup
            : context.l10n.restoringRemoteBackup,
      );
      _showRestoreMessage(mode, mergeResult, remote: true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(context.l10n.remoteRestoreFailed(_formatError(e)));
    } finally {
      await _deleteTempFile(tempArchivePath);
    }
  }

  /// 恢复链（排空任务 → 恢复 → provider 刷新）在 [BackupOrchestrator]；
  /// 页面只负责忙态遮罩与恢复后的页面级状态刷新。
  Future<MergeResult?> _restoreArchive({
    required String archivePath,
    required BackupRestoreScope scope,
    required String busyText,
    RestoreMode mode = RestoreMode.overwrite,
  }) async {
    MergeResult? mergeResult;
    await _runBusy(busyText, () async {
      mergeResult = await ref
          .read(backupOrchestratorProvider)
          .restoreFromArchive(
            archivePath: archivePath,
            scope: scope,
            mode: mode,
          );
      _refreshPageAfterRestore(scope);
    });
    return mergeResult;
  }

  void _showRestoreMessage(
    RestoreMode mode,
    MergeResult? result, {
    bool remote = false,
  }) {
    final l10n = context.l10n;
    final prefix = remote ? l10n.remote : '';
    if (mode == RestoreMode.overwrite || result == null) {
      _showMessage(l10n.restoreCompleteRefreshed(prefix));
      return;
    }
    if (!result.hasChanges) {
      _showMessage(l10n.mergeCompleteUpToDate(prefix));
      return;
    }
    final parts = <String>[];
    if (result.documentsAdded > 0) {
      parts.add(l10n.mergeDocumentsAdded(result.documentsAdded));
    }
    if (result.highlightsAdded > 0) {
      parts.add(l10n.mergeHighlightsAdded(result.highlightsAdded));
    }
    if (result.filesCopied > 0) {
      parts.add(l10n.mergeFilesCopied(result.filesCopied));
    }
    if (result.settingsAdded > 0) {
      parts.add(l10n.mergeSettingsAdded(result.settingsAdded));
    }
    _showMessage(l10n.mergeCompleteSummary(prefix, parts.join('、')));
  }

  Widget _buildAutoBackupSection(BuildContext context, AutoBackupState auto) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final notifier = ref.read(autoBackupProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.autoBackup,
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AutoBackupInterval>(
              segments: [
                ButtonSegment(
                  value: AutoBackupInterval.off,
                  label: Text(l10n.autoBackupOff),
                ),
                ButtonSegment(
                  value: AutoBackupInterval.daily,
                  label: Text(l10n.autoBackupDaily),
                ),
                ButtonSegment(
                  value: AutoBackupInterval.weekly,
                  label: Text(l10n.autoBackupWeekly),
                ),
              ],
              selected: {auto.interval},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                Haptics.soft();
                notifier.setInterval(value.first);
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: cs.surface,
                selectedBackgroundColor: cs.primaryContainer,
                side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (auto.interval != AutoBackupInterval.off) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<BackupScope>(
                segments: [
                  ButtonSegment(
                    value: BackupScope.dataOnly,
                    label: Text(l10n.backupScopeData),
                  ),
                  ButtonSegment(
                    value: BackupScope.full,
                    label: Text(l10n.backupScopeFull),
                  ),
                ],
                selected: {auto.scope},
                showSelectedIcon: false,
                onSelectionChanged: (value) {
                  Haptics.soft();
                  notifier.setScope(value.first);
                },
                style: SegmentedButton.styleFrom(
                  backgroundColor: cs.surface,
                  selectedBackgroundColor: cs.primaryContainer,
                  side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.autoBackupHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// provider 级刷新已由 [BackupOrchestrator] 完成；这里只同步本页持有的
  /// 编辑态（Zotero Key 输入框、连通性测试缓存）。
  void _refreshPageAfterRestore(BackupRestoreScope scope) {
    if (!scope.restoreSettings || !mounted) return;
    _zoteroKeyCtrl.text = ref.read(zoteroSyncProvider).apiKey;
    setState(() {
      _pingFuture = null;
      _pingCacheKey = '';
    });
  }

  Future<(BackupRestoreScope, RestoreMode)?> _pickRestoreOptions() {
    var scope = BackupRestoreScope.full;
    var mode = RestoreMode.merge;
    return showDialog<(BackupRestoreScope, RestoreMode)>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final ts = Theme.of(context).textTheme;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(context.l10n.restoreSettingsTitle),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.restoreMethod, style: ts.titleSmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<RestoreMode>(
                        segments: [
                          for (final m in RestoreMode.values)
                            ButtonSegment(value: m, label: Text(m.label)),
                        ],
                        selected: {mode},
                        onSelectionChanged: (set) {
                          Haptics.soft();
                          setState(() => mode = set.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mode.description,
                      style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const Divider(height: 24),
                    Text(context.l10n.restoreScope, style: ts.titleSmall),
                    RadioGroup<BackupRestoreScope>(
                      groupValue: scope,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => scope = value);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final s in BackupRestoreScope.values)
                            RadioListTile<BackupRestoreScope>(
                              value: s,
                              activeColor: cs.primary,
                              contentPadding: EdgeInsets.zero,
                              title: Text(s.label),
                              subtitle: Text(s.description),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop((scope, mode)),
                  child: Text(
                    mode == RestoreMode.merge
                        ? context.l10n.startMerge
                        : context.l10n.startRestore,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _runBusy(String text, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = '';
        });
      }
    }
  }

  void _showMessage(String message) {
    ref.read(snackBarServiceProvider).showResult(message: message);
  }

  String _formatError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  Future<void> _deleteTempFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return TactilePress(
      onTap: enabled ? onTap : null,
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: enabled ? cs.primaryContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: enabled ? cs.primary : cs.onSurfaceVariant,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Symbols.chevron_right_rounded,
            color: cs.onSurfaceVariant.withAlpha(120),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteDialogScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final VoidCallback? onClear;

  const _RemoteDialogScaffold({
    required this.title,
    required this.children,
    this.onSave,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      backgroundColor: cs.surfaceContainerLow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ...children,
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onClear != null)
                      TextButton(
                        onPressed: onClear,
                        style: TextButton.styleFrom(foregroundColor: cs.error),
                        child: Text(context.l10n.clearField),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onSave,
                      child: Text(context.l10n.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfigField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String? helperText;
  final bool obscureText;
  final Widget? suffixIcon;

  const _ConfigField({
    required this.controller,
    required this.icon,
    required this.label,
    this.helperText,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          helperText: helperText,
          helperStyle: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          prefixIcon: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: cs.surfaceContainerLow,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _WebDavConfigDialog extends StatefulWidget {
  final BackupWebDavState initial;

  const _WebDavConfigDialog({required this.initial});

  @override
  State<_WebDavConfigDialog> createState() => _WebDavConfigDialogState();
}

class _WebDavConfigDialogState extends State<_WebDavConfigDialog> {
  late final TextEditingController _serverController;
  late final TextEditingController _userController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.initial.serverUrl);
    _userController = TextEditingController(text: widget.initial.username);
    _passwordController = TextEditingController(text: widget.initial.password);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _RemoteDialogScaffold(
      title: context.l10n.webDavConfig,
      onClear: widget.initial.isConfigured
          ? () => Navigator.of(context).pop(const BackupWebDavState())
          : null,
      onSave: () {
        Navigator.of(context).pop(
          BackupWebDavState(
            serverUrl: _serverController.text.trim(),
            username: _userController.text.trim(),
            password: _passwordController.text,
          ),
        );
      },
      children: [
        _ConfigField(
          controller: _serverController,
          icon: Symbols.link_rounded,
          label: context.l10n.address,
          helperText: context.l10n.webDavServerAddress,
        ),
        _ConfigField(
          controller: _userController,
          icon: Symbols.account_circle_rounded,
          label: context.l10n.account,
        ),
        _ConfigField(
          controller: _passwordController,
          icon: Symbols.password_rounded,
          label: context.l10n.password,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            onPressed: () {
              Haptics.soft();
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            icon: Icon(
              _obscurePassword
                  ? Symbols.visibility_rounded
                  : Symbols.visibility_off_rounded,
            ),
          ),
        ),
      ],
    );
  }
}

class _S3ConfigDialog extends StatefulWidget {
  final BackupS3State initial;

  const _S3ConfigDialog({required this.initial});

  @override
  State<_S3ConfigDialog> createState() => _S3ConfigDialogState();
}

class _S3ConfigDialogState extends State<_S3ConfigDialog> {
  late final TextEditingController _endpointController;
  late final TextEditingController _regionController;
  late final TextEditingController _bucketController;
  late final TextEditingController _accessKeyController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _objectKeyController;
  late bool _usePathStyle;
  bool _obscureSecretKey = true;

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(text: widget.initial.endpoint);
    _regionController = TextEditingController(text: widget.initial.region);
    _bucketController = TextEditingController(text: widget.initial.bucket);
    _accessKeyController = TextEditingController(
      text: widget.initial.accessKeyId,
    );
    _secretKeyController = TextEditingController(
      text: widget.initial.secretAccessKey,
    );
    _objectKeyController = TextEditingController(
      text: widget.initial.objectKey,
    );
    _usePathStyle = widget.initial.usePathStyle;
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _regionController.dispose();
    _bucketController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _objectKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _RemoteDialogScaffold(
      title: context.l10n.s3Config,
      onClear: widget.initial.isConfigured
          ? () => Navigator.of(context).pop(const BackupS3State())
          : null,
      onSave: () {
        Navigator.of(context).pop(
          BackupS3State(
            endpoint: _endpointController.text.trim(),
            region: _regionController.text.trim(),
            bucket: _bucketController.text.trim(),
            accessKeyId: _accessKeyController.text.trim(),
            secretAccessKey: _secretKeyController.text,
            objectKey: _objectKeyController.text.trim(),
            usePathStyle: _usePathStyle,
          ),
        );
      },
      children: [
        _ConfigField(
          controller: _endpointController,
          icon: Symbols.link_rounded,
          label: context.l10n.address,
          helperText: context.l10n.s3Endpoint,
        ),
        _ConfigField(
          controller: _regionController,
          icon: Symbols.public_rounded,
          label: context.l10n.region,
        ),
        _ConfigField(
          controller: _bucketController,
          icon: Symbols.inventory_2_rounded,
          label: 'Bucket',
        ),
        _ConfigField(
          controller: _accessKeyController,
          icon: Symbols.vpn_key_rounded,
          label: 'Access Key',
        ),
        _ConfigField(
          controller: _secretKeyController,
          icon: Symbols.key_rounded,
          label: 'Secret Key',
          obscureText: _obscureSecretKey,
          suffixIcon: IconButton(
            onPressed: () {
              Haptics.soft();
              setState(() {
                _obscureSecretKey = !_obscureSecretKey;
              });
            },
            icon: Icon(
              _obscureSecretKey
                  ? Symbols.visibility_rounded
                  : Symbols.visibility_off_rounded,
            ),
          ),
        ),
        _ConfigField(
          controller: _objectKeyController,
          icon: Symbols.description_rounded,
          label: context.l10n.objectPath,
          helperText: context.l10n.s3ObjectPathDefault,
        ),
        SwitchListTile(
          value: _usePathStyle,
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.usePathStyle),
          subtitle: Text(context.l10n.s3PathStyleHint),
          onChanged: (value) {
            Haptics.soft();
            setState(() {
              _usePathStyle = value;
            });
          },
        ),
      ],
    );
  }
}
