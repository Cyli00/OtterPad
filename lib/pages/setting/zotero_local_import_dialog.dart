import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../core/l10n.dart';
import '../../core/animation_constants.dart';
import '../../core/storage/settings_keys.dart';
import '../../core/storage/storage.dart';
import '../../providers/task_provider.dart';
import '../../core/rust_backend.dart';
import '../../providers/zotero_local_errors.dart';
import '../../services/haptics.dart';
import '../../src/rust/api.dart' show cancelTask;
import '../../src/rust/api/zotero.dart';
import '../../src/rust/sync/zotero/mapper.dart';
import '../../src/rust/sync/zotero/store.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_divider.dart';
import '../../widgets/tactile_press.dart';
import 'setting_picker.dart';
import 'setting_group.dart';
import '../../core/design_tokens.dart';

Future<void> showZoteroLocalImport(BuildContext context) => showAppDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const ZoteroLocalImportDialog(),
);

class ZoteroLocalImportDialog extends ConsumerStatefulWidget {
  const ZoteroLocalImportDialog({super.key});
  @override
  ConsumerState<ZoteroLocalImportDialog> createState() =>
      _ZoteroLocalImportDialogState();
}

class _ZoteroLocalImportDialogState
    extends ConsumerState<ZoteroLocalImportDialog> {
  late final TextEditingController _port;
  String? _fetchTask;
  TaskNotifier? _task;
  LocalZoteroSnapshot? _library;
  List<ImportCandidate> _candidates = [];
  final _selected = <String>{};
  final _attachments = <String, String?>{};
  String? _directory;
  String? _message;
  bool _messageIsError = false;
  bool _loading = false;
  bool _importing = false;
  int _fetched = 0;
  int _total = 0;
  bool get _busy => _loading || _importing;

  @override
  void initState() {
    super.initState();
    _port = TextEditingController(
      text:
          '${GStorage.setting.get(SettingsKeys.zoteroLocalPort, defaultValue: 23119)}',
    );
    _directory =
        GStorage.setting.get(SettingsKeys.zoteroLocalDirectory) as String?;
  }

  @override
  void dispose() {
    final fetch = _fetchTask;
    if (fetch != null) cancelTask(taskId: fetch);
    if (_importing) _task?.cancelTask(TaskType.zoteroSync);
    _port.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final port = int.tryParse(_port.text);
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _messageIsError = true;
        _message = context.l10n.zoteroLocalInvalidPort;
      });
      return;
    }
    final task = rustTaskId('zotero-local-fetch');
    _fetchTask = task;
    setState(() {
      _loading = true;
      _library = null;
      _message = null;
      _fetched = 0;
      _total = 0;
    });
    try {
      await for (final event in RustBackend.instance.fetchLocalZotero(
        port: port,
        taskId: task,
      )) {
        if (!mounted || _fetchTask != task) return;
        switch (event) {
          case ZoteroEvent_Progress(:final progress):
            setState(() {
              _fetched = progress.fetched.toInt();
              _total = progress.total?.toInt() ?? 0;
            });
          case ZoteroEvent_LocalReady(:final snapshot, :final candidates):
            await GStorage.setting.put(SettingsKeys.zoteroLocalPort, port);
            if (!mounted) return;
            setState(() {
              _library = snapshot;
              _candidates = candidates;
              _selected
                ..clear()
                ..addAll(candidates.map((c) => c.key));
              _attachments
                ..clear()
                ..addEntries(
                  candidates.map(
                    (c) => MapEntry(
                      c.key,
                      c.attachments.length == 1
                          ? c.attachments.single.key
                          : null,
                    ),
                  ),
                );
            });
          case ZoteroEvent_Failed(:final error):
            throw error;
          case ZoteroEvent_Imported():
        }
      }
    } catch (e) {
      if (mounted && _fetchTask == task && !isCancellation(e)) {
        setState(() {
          _messageIsError = true;
          _message = zoteroLocalErrorMessage(context.l10n, e);
        });
      }
    } finally {
      if (_fetchTask == task) _fetchTask = null;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDirectory() async {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: context.l10n.zoteroLocalDirectory,
    );
    if (directory == null || !mounted) return;
    if (!await File(p.join(directory, 'zotero.sqlite')).exists()) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = context.l10n.zoteroLocalDirectoryHint;
        });
      }
      return;
    }
    await GStorage.setting.put(SettingsKeys.zoteroLocalDirectory, directory);
    if (mounted) {
      setState(() {
        _directory = directory;
        _message = null;
      });
    }
  }

  Future<void> _import() async {
    final library = _library;
    if (library == null || _selected.isEmpty || _busy) return;
    setState(() {
      _importing = true;
      _message = null;
    });
    try {
      _task = ref.read(taskProvider.notifier);
      final titles = {for (final c in _candidates) c.key: c.document.title};
      final result = await _task!.importLocalZotero(
        snapshot: library,
        directory: library.hasServerId() ? null : _directory,
        selections: [
          for (final c in _candidates)
            if (_selected.contains(c.key))
              LocalSelection(
                itemKey: c.key,
                attachmentKey: _attachments[c.key],
              ),
        ],
      );
      if (!mounted) return;
      final l10n = context.l10n;
      final failed = [
        for (final k in result?.failedKeys ?? const <String>[]) titles[k] ?? k,
      ];
      setState(() {
        _messageIsError = failed.isNotEmpty;
        _message = result == null
            ? l10n.zoteroLocalStopped
            : '${l10n.zoteroLocalResult(result.added.toInt(), result.updated.toInt(), result.copied.toInt(), result.missing.toInt(), result.kept.toInt(), failed.length)}'
                  '${failed.isEmpty ? '' : '\n${failed.join('\n')}'}';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = zoteroLocalErrorMessage(context.l10n, e);
        });
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.zoteroLocalTitle,
                    style: theme.textTheme.titleLarge?.copyWith(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.zoteroLocalEntryHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _connectionSection(context)),
                        if (_library != null) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 24,
                                bottom: 8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.zoteroLocalDocuments,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.zoteroLocalSelectionHint,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value:
                                            _candidates.isNotEmpty &&
                                            _selected.length ==
                                                _candidates.length,
                                        onChanged: _busy
                                            ? null
                                            : (value) {
                                                Haptics.light();
                                                setState(() {
                                                  _selected.clear();
                                                  if (value == true) {
                                                    _selected.addAll(
                                                      _candidates.map(
                                                        (c) => c.key,
                                                      ),
                                                    );
                                                  }
                                                });
                                              },
                                      ),
                                      Expanded(
                                        child: Text(
                                          l10n.zoteroLocalSelection(
                                            _selected.length,
                                            _candidates.length,
                                          ),
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_candidates.isEmpty)
                                    Text(
                                      l10n.zoteroLocalEmpty,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          SliverList.separated(
                            itemCount: _candidates.length,
                            separatorBuilder: (_, _) => const AppDivider.full(),
                            itemBuilder: (_, index) =>
                                _candidate(context, _candidates[index]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_importing) ...[
                    const SizedBox(height: 12),
                    _progress(context),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _messageIsError
                                  ? cs.errorContainer
                                  : cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _messageIsError
                                      ? Symbols.error_rounded
                                      : Symbols.info_rounded,
                                  size: 20,
                                  color: _messageIsError
                                      ? cs.onErrorContainer
                                      : cs.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _message!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _messageIsError
                                          ? cs.onErrorContainer
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Haptics.soft();
                          final fetch = _fetchTask;
                          if (fetch != null) cancelTask(taskId: fetch);
                          if (_importing) {
                            _task?.cancelTask(TaskType.zoteroSync);
                          }
                          Navigator.pop(context);
                        },
                        child: Text(_busy ? l10n.cancel : l10n.close),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: TextButton(
                          onPressed:
                              _busy ||
                                  _library == null ||
                                  _selected.isEmpty ||
                                  (!_library!.hasServerId() &&
                                      _directory == null)
                              ? null
                              : _import,
                          child: Text(
                            l10n.zoteroLocalImport,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _connectionSection(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppStroke.rule(cs)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.zoteroLocalConnection,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _port,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 5,
            decoration: settingFieldDecoration(
              context,
              labelText: l10n.zoteroLocalPort,
            ).copyWith(counterText: ''),
            onChanged: (_) => setState(() {
              _library = null;
              _candidates = [];
              _message = null;
            }),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      Haptics.soft();
                      _connect();
                    },
              icon: const Icon(Symbols.sync_rounded, size: 20),
              label: Text(l10n.zoteroLocalConnect),
            ),
          ),
          if (_library == null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.zoteroLocalHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (_library != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Symbols.check_circle_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.connectionOk,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 8),
            _progress(context),
            const SizedBox(height: 8),
            Text(
              l10n.zoteroLocalLoading(_fetched, _total),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (_library != null && !_library!.hasServerId()) ...[
            const AppDivider.full(),
            const SizedBox(height: 12),
            Text(
              l10n.zoteroLocalDirectoryHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            Tooltip(
              message: _directory ?? '',
              child: TextButton.icon(
                onPressed: _busy ? null : _pickDirectory,
                icon: const Icon(Symbols.folder_open_rounded),
                label: Text(
                  _directory == null
                      ? l10n.zoteroLocalDirectory
                      : l10n.zoteroLocalDirectorySelected,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _progress(BuildContext context) => LinearProgressIndicator(
    minHeight: 4,
    borderRadius: BorderRadius.circular(AppRadius.xs),
    backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(80),
  );

  Widget _candidate(BuildContext context, ImportCandidate candidate) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _selected.contains(candidate.key);
    return Padding(
      key: ValueKey(candidate.key),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          TactilePress(
            baseColor: selected ? cs.primaryContainer : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.md),
            padding: const EdgeInsets.all(12),
            onTap: _busy
                ? null
                : () => setState(() {
                    if (selected) {
                      _selected.remove(candidate.key);
                    } else {
                      _selected.add(candidate.key);
                    }
                  }),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Symbols.check_box_rounded
                      : Symbols.check_box_outline_blank_rounded,
                  color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.document.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? cs.onPrimaryContainer
                              : cs.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        candidate.document.authors.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (candidate.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 36),
              child: ExcludeFocus(
                excluding: _busy || !selected,
                child: AnimatedOpacity(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : kAnimFast,
                  opacity: _busy || !selected ? 0.5 : 1,
                  child: IgnorePointer(
                    ignoring: _busy || !selected,
                    child: SettingPicker<String>(
                      current: _attachments[candidate.key] ?? '',
                      options: ['', ...candidate.attachments.map((a) => a.key)],
                      labelFor: (key) => key.isEmpty
                          ? l10n.zoteroLocalMetadataOnly
                          : candidate.attachments
                                .firstWhere((a) => a.key == key)
                                .title,
                      sheetTitle: l10n.zoteroLocalChoosePdf,
                      onChanged: (key) {
                        if (_busy || !selected) return;
                        setState(
                          () => _attachments[candidate.key] = key.isEmpty
                              ? null
                              : key,
                        );
                      },
                    ),
                  ),
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.zoteroLocalNoPdf,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
