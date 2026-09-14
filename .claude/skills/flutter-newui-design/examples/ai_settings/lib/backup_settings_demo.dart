import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'l10n.dart';
import 'paper_surfaces.dart';
import 'paper_widgets.dart';

class BackupSettingsDemo extends StatefulWidget {
  const BackupSettingsDemo({super.key});
  @override
  State<BackupSettingsDemo> createState() => _BackupSettingsDemoState();
}

class _BackupSettingsDemoState extends State<BackupSettingsDemo> {
  String _remote = 'S3', _interval = 'off', _scope = 'data';
  final _configs = <String, Map<String, String>>{};
  final _zotero = TextEditingController();
  bool _obscured = true, _busy = false;
  int _imported = 0;
  String? _result;
  bool get _configured => _configs[_remote]?.isNotEmpty == true;
  @override
  void dispose() {
    _zotero.dispose();
    super.dispose();
  }

  Future<void> _run({bool sync = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = context.l10n.demoOperationDone;
      if (sync) _imported = 12;
    });
    paperSnack(context, context.l10n.demoOperationDone);
  }

  Future<void> _configure() async {
    final target = _remote;
    final next = await showPaperDialog<Map<String, String>>(
      context,
      (_) => RemoteConfigDemo(type: target, initial: _configs[target] ?? {}),
    );
    if (!mounted || next == null) return;
    setState(() => _configs[target] = next);
  }

  Future<void> _scopeDialog({required bool restore}) async {
    final l = context.l10n;
    String mode = 'merge', scope = restore ? 'full' : 'data';
    final confirmed = await showPaperDialog<bool>(
      context,
      (context) => StatefulBuilder(
        builder: (context, update) => PaperDialog(
          title: restore ? l.restoreSettingsTitle : l.backupScopeTitle,
          children: [
            Text(
              restore ? 'otterpad-demo-backup.zip' : l.demoArchiveHint,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (restore)
              PaperOptions(
                label: l.restoreMethod,
                value: mode,
                options: {
                  'overwrite': l.restoreModeOverwrite,
                  'merge': l.restoreModeMerge,
                },
                onChanged: (v) => update(() => mode = v),
              ),
            if (restore)
              PaperNotice(
                title: mode == 'merge'
                    ? l.restoreModeMerge
                    : l.restoreModeOverwrite,
                message: mode == 'merge'
                    ? l.restoreModeMergeDescription
                    : l.restoreModeOverwriteDescription,
                error: mode == 'overwrite',
              ),
            PaperOptions(
              label: restore ? l.restoreScope : l.backupScopeTitle,
              help: restore
                  ? (scope == 'full'
                        ? l.restoreScopeFullDescription
                        : scope == 'library'
                        ? l.restoreScopeLibraryDescription
                        : l.restoreScopeSettingsDescription)
                  : (scope == 'data'
                        ? l.backupScopeDataDesc
                        : l.backupScopeFullDesc),
              value: scope,
              options: restore
                  ? {
                      'full': l.restoreScopeFull,
                      'library': l.restoreScopeLibrary,
                      'settings': l.restoreScopeSettings,
                    }
                  : {'data': l.backupScopeData, 'full': l.backupScopeFull},
              onChanged: (v) => update(() => scope = v),
            ),
          ],
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                restore
                    ? (mode == 'merge' ? l.startMerge : l.startRestore)
                    : l.startBackup,
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) await _run();
  }

  Future<void> _resync() async {
    final l = context.l10n;
    final yes = await showPaperDialog<bool>(
      context,
      (context) => PaperDialog(
        title: l.resetZoteroSync,
        children: [Text(l.resetZoteroConfirm)],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.reimport),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await _run(sync: true);
  }

  void _localZotero() {
    final l = context.l10n;
    showPaperDialog<void>(
      context,
      (context) => PaperDialog(
        title: l.zoteroLocalTitle,
        children: [
          PaperNotice(title: l.demoLocalSource, message: l.demoLocalSourceHint),
          TextFormField(
            initialValue: 'Demo/Zotero',
            readOnly: true,
            decoration: InputDecoration(labelText: l.zoteroLocalDirectory),
          ),
          Text(l.demoLocalPapers),
          Text(
            l.zoteroLocalMetadataOnly,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _run(sync: true);
            },
            child: Text(l.demoImport),
          ),
        ],
      ),
    );
  }

  void _storage() {
    final l = context.l10n;
    showPaperDialog<void>(
      context,
      (context) => PaperDialog(
        title: l.storageSpace,
        children: [
          Text(l.demoStorageHint),
          for (final e in {
            l.demoDocuments: '842 MB',
            l.demoThumbnails: '36 MB',
            l.demoTemporary: '18 MB',
          }.entries)
            Row(
              children: [
                Expanded(child: Text(e.key)),
                Text(e.value),
              ],
            ),
          const LinearProgressIndicator(value: .63),
        ],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final config = _configs[_remote];
    final configuredStatus = _configured
        ? [
            config!['address'],
            if (_remote == 'S3') ...[
              'Bucket: ${config['bucket']} · ${config['region']}',
              '${l.objectPath}: ${config['path']!.isEmpty ? 'otter-pad/otter_pad_backup.zip' : config['path']}',
            ] else ...[
              '${l.account}: ${config['account']}',
              '${l.objectPath}: /OtterPad/otter_pad_backup.zip',
            ],
            l.demoConfigured,
          ].join('\n')
        : l.remoteNotConfigured(_remote);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spaced([
        if (_busy)
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.demoOperationRunning),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
            ),
          ),
        if (_result != null)
          PaperNotice(title: l.demoResult, message: _result!),
        PaperSection(
          title: l.remoteBackup,
          help: l.demoRemoteHelp,
          children: [
            PaperOptions(
              label: l.backupMethod,
              value: _remote,
              options: const {'S3': 'S3', 'WebDAV': 'WebDAV'},
              icons: const {
                'S3': Symbols.cloud_circle,
                'WebDAV': Symbols.cloud_sync,
              },
              onChanged: _busy ? null : (v) => setState(() => _remote = v),
            ),
            const Divider(),
            PaperActionRow(
              title: _remote == 'S3' ? l.s3Config : l.webDavConfig,
              icon: Symbols.cloud,
              status: configuredStatus,
              action: _configured ? l.edit : l.configure,
              onTap: _busy ? null : _configure,
            ),
            const Divider(),
            PaperOptions(
              label: l.autoBackup,
              help: l.autoBackupHint,
              value: _interval,
              options: {
                'off': l.autoBackupOff,
                'daily': l.autoBackupDaily,
                'weekly': l.autoBackupWeekly,
              },
              onChanged: _busy ? null : (v) => setState(() => _interval = v),
            ),
            if (_interval != 'off')
              PaperOptions(
                label: l.backupScopeTitle,
                value: _scope,
                options: {'data': l.backupScopeData, 'full': l.backupScopeFull},
                onChanged: (v) => setState(() => _scope = v),
              ),
            const Divider(),
            PaperActionRow(
              title: l.backupTo(_remote),
              icon: Symbols.cloud_upload,
              help: l.uploadBackupTo(_remote),
              status: _configured ? null : l.pleaseConfigureFirst(_remote),
              onTap: _configured && !_busy
                  ? () => _scopeDialog(restore: false)
                  : null,
            ),
            PaperActionRow(
              title: l.restoreFromRemote(_remote),
              icon: Symbols.cloud_download,
              help: l.downloadAndRestore(_remote),
              status: _configured ? null : l.pleaseConfigureFirst(_remote),
              onTap: _configured && !_busy
                  ? () => _scopeDialog(restore: true)
                  : null,
            ),
          ],
        ),
        PaperSection(
          title: l.zoteroSync,
          help: l.demoZoteroHelp,
          children: [
            if (!paperMobile(context)) ...[
              PaperActionRow(
                title: l.zoteroLocalTitle,
                icon: Symbols.computer,
                help: l.zoteroLocalEntryHint,
                onTap: _busy ? null : _localZotero,
              ),
              const Divider(),
            ],
            Row(
              children: [
                Expanded(
                  child: PaperLabel(title: l.apiKey, help: l.keyHint),
                ),
                IconButton(
                  tooltip: l.getToken,
                  onPressed: () => showPaperDialog<void>(
                    context,
                    (context) => PaperDialog(
                      title: l.getToken,
                      children: [
                        SelectableText(
                          'https://www.zotero.org/settings/keys/new',
                        ),
                        Text(l.demoTokenHint),
                      ],
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l.close),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Symbols.arrow_outward),
                ),
              ],
            ),
            TextField(
              key: const ValueKey('zotero-key'),
              controller: _zotero,
              obscureText: _obscured,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l.keyPlaceholder,
                suffixIcon: IconButton(
                  tooltip: _obscured ? l.showKey : l.hideKey,
                  onPressed: () => setState(() => _obscured = !_obscured),
                  icon: Icon(
                    _obscured ? Symbols.visibility_off : Symbols.visibility,
                  ),
                ),
              ),
            ),
            PaperActionRow(
              title: l.syncZoteroLibrary,
              icon: Symbols.sync,
              help: l.zoteroImportHint,
              status: _zotero.text.trim().isEmpty
                  ? l.pleaseFillApiKey
                  : _imported > 0
                  ? l.zoteroImportedPull(_imported)
                  : null,
              onTap: _zotero.text.trim().isEmpty || _busy
                  ? null
                  : () => _run(sync: true),
            ),
            if (_zotero.text.trim().isNotEmpty)
              PaperActionRow(
                title: l.fullResync,
                icon: Symbols.restart_alt,
                help: l.zoteroResetHint,
                onTap: _busy ? null : _resync,
              ),
          ],
        ),
        PaperSection(
          title: l.localBackup,
          help: l.demoLocalHelp,
          children: [
            PaperActionRow(
              title: l.exportBackup,
              icon: Symbols.download,
              help: l.generateZipAndSave,
              onTap: _busy ? null : () => _scopeDialog(restore: false),
            ),
            const Divider(),
            PaperActionRow(
              title: l.restoreFromBackup,
              icon: Symbols.restore_page,
              help: l.selectLocalZipRestore,
              onTap: _busy ? null : () => _scopeDialog(restore: true),
            ),
          ],
        ),
        PaperSection(
          title: l.storage,
          help: l.thumbnailsAndTemp,
          children: [
            PaperActionRow(
              title: l.storageSpace,
              icon: Symbols.folder_managed,
              status: l.demoStorageSummary,
              onTap: _busy ? null : _storage,
            ),
          ],
        ),
      ], 32),
    );
  }
}

class RemoteConfigDemo extends StatefulWidget {
  const RemoteConfigDemo({
    super.key,
    required this.type,
    required this.initial,
  });
  final String type;
  final Map<String, String> initial;
  @override
  State<RemoteConfigDemo> createState() => _RemoteConfigDemoState();
}

class _RemoteConfigDemoState extends State<RemoteConfigDemo> {
  late final fields = {
    for (final id
        in widget.type == 'S3'
            ? ['address', 'region', 'bucket', 'access', 'secret', 'path']
            : ['address', 'account', 'password'])
      id: TextEditingController(
        text:
            widget.initial[id] ??
            (widget.type == 'S3'
                ? switch (id) {
                    'address' => 'https://s3.amazonaws.com',
                    'region' => 'us-east-1',
                    'path' => 'otter-pad/otter_pad_backup.zip',
                    _ => '',
                  }
                : ''),
      ),
  };
  bool _hidden = true, _invalid = false;
  late bool _pathStyle = widget.initial['pathStyle'] != 'false';
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final valid =
        Uri.tryParse(fields['address']!.text)?.hasAuthority == true &&
        fields['address']!.text.startsWith('https://') &&
        fields.entries
            .where((e) => e.key != 'path')
            .every((e) => e.value.text.trim().isNotEmpty);
    if (!valid) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, {
      for (final e in fields.entries) e.key: e.value.text.trim(),
      'pathStyle': '$_pathStyle',
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = {
      'address': l.address,
      'region': l.region,
      'bucket': 'Bucket',
      'access': 'Access Key',
      'secret': 'Secret Key',
      'path': l.objectPath,
      'account': l.account,
      'password': l.password,
    };
    return PaperDialog(
      title: widget.type == 'S3' ? l.s3Config : l.webDavConfig,
      children: [
        PaperNotice(
          title: l.demoConfiguration,
          message: l.demoConfigurationHint,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => setState(() {
              for (final e in fields.entries) {
                e.value.text = switch (e.key) {
                  'address' => 'https://backup.example.com',
                  'region' => 'us-east-1',
                  'bucket' => 'otterpad-demo',
                  'path' => 'backups/otterpad.zip',
                  _ => 'demo-only',
                };
              }
              _invalid = false;
            }),
            child: Text(l.demoFill),
          ),
        ),
        for (final e in fields.entries)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperLabel(
                title: labels[e.key]!,
                help: e.key == 'address'
                    ? (widget.type == 'S3'
                          ? l.s3Endpoint
                          : l.webDavServerAddress)
                    : e.key == 'path'
                    ? l.s3ObjectPathDefault
                    : null,
              ),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('config-${e.key}'),
                controller: e.value,
                obscureText: _hidden && ['secret', 'password'].contains(e.key),
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  suffixIcon: ['secret', 'password'].contains(e.key)
                      ? IconButton(
                          tooltip: _hidden ? l.showKey : l.hideKey,
                          onPressed: () => setState(() => _hidden = !_hidden),
                          icon: Icon(
                            _hidden
                                ? Symbols.visibility_off
                                : Symbols.visibility,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        if (widget.type == 'S3')
          Row(
            children: [
              Expanded(
                child: PaperLabel(
                  title: l.usePathStyle,
                  help: l.s3PathStyleHint,
                ),
              ),
              Switch(
                value: _pathStyle,
                onChanged: (v) => setState(() => _pathStyle = v),
              ),
            ],
          ),
        if (_invalid)
          PaperNotice(
            title: l.demoInvalidConfig,
            message: l.demoInvalidConfigHint,
            error: true,
          ),
      ],
      actions: [
        if (widget.initial.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, <String, String>{}),
            child: Text(l.clearField),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l.save)),
      ],
    );
  }
}
