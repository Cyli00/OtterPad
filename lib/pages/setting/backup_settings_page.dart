import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../providers/api_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/highlight_provider.dart';
import '../../providers/proxy_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/backup_restore_service.dart';
import '../../services/backup_s3_service.dart';
import '../../services/snackbar_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final remoteType = ref.watch(backupRemoteTypeProvider);
    final webDav = ref.watch(backupWebDavProvider);
    final s3 = ref.watch(backupS3Provider);
    _ensurePingFuture(remoteType, webDav, s3);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          '备份设置',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ).copyWith(bottom: 40),
            children: [
              _buildGroup(
                context,
                title: '远程备份',
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '备份方式',
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
                                  icon: Icon(Symbols.cloud_circle),
                                  label: Text('S3'),
                                ),
                                ButtonSegment(
                                  value: BackupRemoteType.webdav,
                                  icon: Icon(Symbols.cloud_sync),
                                  label: Text('WebDAV'),
                                ),
                              ],
                              selected: {remoteType},
                              onSelectionChanged: (value) {
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
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildDivider(context),
                    _buildRemoteConfigTile(context, remoteType, s3, webDav),
                    _buildDivider(context),
                    _ActionTile(
                      icon: Symbols.cloud_upload_rounded,
                      title: '备份到${remoteType.label}',
                      subtitle: _remoteConfigured(remoteType, s3, webDav)
                          ? '上传完整备份到${_remoteTargetLabel(remoteType, s3, webDav)}'
                          : '请先配置${remoteType.label}连接信息',
                      enabled: _remoteConfigured(remoteType, s3, webDav) && !_busy,
                      onTap: () => _backupToRemote(remoteType, s3, webDav),
                    ),
                    _buildDivider(context),
                    _ActionTile(
                      icon: Symbols.cloud_download_rounded,
                      title: '从${remoteType.label}恢复',
                      subtitle: _remoteConfigured(remoteType, s3, webDav)
                          ? '下载${_remoteTargetLabel(remoteType, s3, webDav)}并恢复'
                          : '请先配置${remoteType.label}连接信息',
                      enabled: _remoteConfigured(remoteType, s3, webDav) && !_busy,
                      onTap: () => _restoreFromRemote(remoteType, s3, webDav),
                    ),
                  ],
                ),
              ),
              _buildGroup(
                context,
                title: '本地备份',
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Symbols.download_rounded,
                      title: '导出备份文件',
                      subtitle: '生成 zip 备份并保存到本地',
                      enabled: !_busy,
                      onTap: _exportBackupToLocal,
                    ),
                    _buildDivider(context),
                    _ActionTile(
                      icon: Symbols.restore_page_rounded,
                      title: '从备份文件恢复',
                      subtitle: '选择本地 zip 备份文件进行恢复',
                      enabled: !_busy,
                      onTap: _restoreFromLocal,
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
                    child: Column(
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
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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

  Widget _buildRemoteConfigTile(
    BuildContext context,
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final configured = _remoteConfigured(remoteType, s3, webDav);
    final title = remoteType == BackupRemoteType.s3 ? 'S3 配置' : 'WebDAV 配置';
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
                    '未配置${remoteType.label}远程备份信息',
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
                          ? '正在检测连接'
                          : (success ? '连接正常' : '连接失败');
                      return _StatusBadge(color: color, label: label);
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: _busy ? null : () => _editRemoteConfig(remoteType, s3, webDav),
            child: Text(configured ? '编辑' : '配置'),
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
        'Bucket：${s3.bucket}  ·  区域：${s3.region}',
        '对象：${s3.normalizedObjectKey}',
      ];
    }
    return [
      webDav.serverUrl,
      '账号：${webDav.username}',
      '路径：${webDav.remoteFilePath}',
    ];
  }

  bool _remoteConfigured(
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) {
    return remoteType == BackupRemoteType.s3 ? s3.isConfigured : webDav.isConfigured;
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
    String? tempArchivePath;

    try {
      await _runBusy('正在生成本地备份...', () async {
        tempArchivePath = await BackupRestoreService.createBackupArchive();
      });
      if (!mounted || tempArchivePath == null) return;

      final targetPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存备份文件',
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
      _showMessage('备份已导出到 ${targetFile.path}');
    } catch (e) {
      _showMessage('导出备份失败：${_formatError(e)}');
    } finally {
      await _deleteTempFile(tempArchivePath);
    }
  }

  Future<void> _restoreFromLocal() async {
    final scope = await _pickRestoreScope();
    if (scope == null) return;

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      lockParentWindow: true,
    );
    final archivePath = result?.files.single.path;
    if (archivePath == null) return;

    try {
      await _restoreArchive(
        archivePath: archivePath,
        scope: scope,
        busyText: '正在恢复备份...',
      );
      _showMessage('恢复完成，当前页面状态已同步刷新');
    } catch (e) {
      _showMessage('恢复失败：${_formatError(e)}');
    }
  }

  Future<void> _backupToRemote(
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) async {
    String? tempArchivePath;

    try {
      await _runBusy('正在生成并上传远程备份...', () async {
        tempArchivePath = await BackupRestoreService.createBackupArchive();
        if (remoteType == BackupRemoteType.s3) {
          await BackupS3Service.instance.uploadFile(s3, tempArchivePath!);
        } else {
          final client = createBackupWebDavClient(webDav);
          await client.mkdirAll(webDav.remoteDir);
          await client.writeFromFile(tempArchivePath!, webDav.remoteFilePath);
        }
      });
      _showMessage('远程备份已上传到 ${_remoteTargetLabel(remoteType, s3, webDav)}');
    } catch (e) {
      _showMessage('上传远程备份失败：${_formatError(e)}');
    } finally {
      await _deleteTempFile(tempArchivePath);
    }
  }

  Future<void> _restoreFromRemote(
    BackupRemoteType remoteType,
    BackupS3State s3,
    BackupWebDavState webDav,
  ) async {
    final scope = await _pickRestoreScope();
    if (scope == null) return;

    String? tempArchivePath;
    try {
      final tempDir = await getTemporaryDirectory();
      final archivePath = p.join(
        tempDir.path,
        'NightReader',
        'restore',
        BackupRestoreService.buildBackupFileName(),
      );
      tempArchivePath = archivePath;
      await Directory(p.dirname(archivePath)).create(recursive: true);

      await _runBusy('正在下载远程备份...', () async {
        if (remoteType == BackupRemoteType.s3) {
          await BackupS3Service.instance.downloadFile(s3, archivePath);
        } else {
          final client = createBackupWebDavClient(webDav);
          await client.read2File(webDav.remoteFilePath, archivePath);
        }
      });

      await _restoreArchive(
        archivePath: archivePath,
        scope: scope,
        busyText: '正在恢复远程备份...',
      );
      _showMessage('远程恢复完成，当前页面状态已同步刷新');
    } catch (e) {
      _showMessage('远程恢复失败：${_formatError(e)}');
    } finally {
      await _deleteTempFile(tempArchivePath);
    }
  }

  Future<void> _restoreArchive({
    required String archivePath,
    required BackupRestoreScope scope,
    required String busyText,
  }) async {
    await _runBusy(busyText, () async {
      await BackupRestoreService.restoreBackupArchive(
        archivePath: archivePath,
        scope: scope,
      );
      await _refreshAfterRestore(scope);
    });
  }

  Future<void> _refreshAfterRestore(BackupRestoreScope scope) async {
    if (scope.restoreSettings) {
      ref.read(themeProvider.notifier).reload();
      ref.read(proxyProvider.notifier).reload();
      ref.read(agentApiProvider.notifier).reload();
      ref.read(docExtractApiProvider.notifier).reload();
      ref.read(readerSettingsProvider.notifier).reload();
      ref.read(backupRemoteTypeProvider.notifier).reload();
      ref.read(backupS3Provider.notifier).reload();
      ref.read(backupWebDavProvider.notifier).reload();
      if (mounted) {
        setState(() {
          _pingFuture = null;
          _pingCacheKey = '';
        });
      }
    }

    if (scope.restoreLibrary) {
      final previousDocIds = ref.read(documentsProvider).map((doc) => doc.id).toSet();
      ref.invalidate(documentsProvider);
      ref.invalidate(favoritesProvider);
      final currentDocIds = ref.read(documentsProvider).map((doc) => doc.id).toSet();
      for (final docId in {...previousDocIds, ...currentDocIds}) {
        ref.invalidate(highlightProvider(docId));
      }
    }
  }

  Future<BackupRestoreScope?> _pickRestoreScope() {
    var current = BackupRestoreScope.full;
    return showDialog<BackupRestoreScope>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('选择恢复范围'),
              content: SizedBox(
                width: 420,
                child: RadioGroup<BackupRestoreScope>(
                  groupValue: current,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => current = value);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final scope in BackupRestoreScope.values)
                        RadioListTile<BackupRestoreScope>(
                          value: scope,
                          activeColor: cs.primary,
                          contentPadding: EdgeInsets.zero,
                          title: Text(scope.label),
                          subtitle: Text(scope.description),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(current),
                  child: const Text('开始恢复'),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: enabled
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
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
        ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                ...children,
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onClear != null)
                      TextButton(
                        onPressed: onClear,
                        child: const Text('清空'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: onSave,
                      child: const Text('保存'),
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
  final String hint;
  final String? helperText;
  final bool obscureText;
  final Widget? suffixIcon;

  const _ConfigField({
    required this.controller,
    required this.icon,
    required this.hint,
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
        decoration: InputDecoration(
          hintText: hint,
          helperText: helperText,
          helperStyle: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          prefixIcon: Icon(icon, color: cs.onSurfaceVariant),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: cs.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
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
      title: 'WebDAV配置',
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
          hint: '地址',
          helperText: 'WebDAV服务器地址',
        ),
        _ConfigField(
          controller: _userController,
          icon: Symbols.account_circle_rounded,
          hint: '账号',
        ),
        _ConfigField(
          controller: _passwordController,
          icon: Symbols.password_rounded,
          hint: '密码',
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            icon: Icon(
              _obscurePassword
                  ? Symbols.visibility
                  : Symbols.visibility_off,
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
    _accessKeyController =
        TextEditingController(text: widget.initial.accessKeyId);
    _secretKeyController =
        TextEditingController(text: widget.initial.secretAccessKey);
    _objectKeyController =
        TextEditingController(text: widget.initial.objectKey);
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
      title: 'S3配置',
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
          hint: '地址',
          helperText: 'S3 / R2 / MinIO Endpoint',
        ),
        _ConfigField(
          controller: _regionController,
          icon: Symbols.public_rounded,
          hint: '区域',
        ),
        _ConfigField(
          controller: _bucketController,
          icon: Symbols.inventory_2_rounded,
          hint: 'Bucket',
        ),
        _ConfigField(
          controller: _accessKeyController,
          icon: Symbols.vpn_key_rounded,
          hint: 'Access Key',
        ),
        _ConfigField(
          controller: _secretKeyController,
          icon: Symbols.key_rounded,
          hint: 'Secret Key',
          obscureText: _obscureSecretKey,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscureSecretKey = !_obscureSecretKey;
              });
            },
            icon: Icon(
              _obscureSecretKey
                  ? Symbols.visibility
                  : Symbols.visibility_off,
            ),
          ),
        ),
        _ConfigField(
          controller: _objectKeyController,
          icon: Symbols.description,
          hint: '对象路径',
          helperText: '默认可用 night-reader/night_reader_backup.zip',
        ),
        SwitchListTile(
          value: _usePathStyle,
          contentPadding: EdgeInsets.zero,
          title: const Text('使用路径式地址'),
          subtitle: const Text('MinIO / R2 等 S3 兼容服务通常建议开启'),
          onChanged: (value) {
            setState(() {
              _usePathStyle = value;
            });
          },
        ),
      ],
    );
  }
}
