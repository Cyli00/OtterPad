import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../../core/animation_constants.dart';
import '../../core/storage/settings_keys.dart';
import '../../core/storage/storage.dart';
import '../../providers/task_provider.dart';
import '../../providers/zotero_local_import_provider.dart';
import '../../services/haptics.dart';
import '../../services/zotero_item_mapper.dart';
import '../../services/zotero_sync_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_divider.dart';
import '../../widgets/tactile_press.dart';
import 'setting_picker.dart';

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
  CancelToken? _token;
  TaskNotifier? _task;
  ZoteroLocalLibrary? _library;
  List<ZoteroImportCandidate> _candidates = [];
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
    _token?.cancel();
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
    final token = CancelToken();
    _token = token;
    setState(() {
      _loading = true;
      _library = null;
      _message = null;
      _fetched = 0;
      _total = 0;
    });
    try {
      final library = await ref
          .read(zoteroSyncServiceProvider)
          .fetchLocalLibrary(
            port: port,
            cancelToken: token,
            onProgress: (done, total) {
              if (mounted && !token.isCancelled) {
                setState(() {
                  _fetched = done;
                  _total = total;
                });
              }
            },
          );
      final candidates = ZoteroItemMapper.localCandidates(library.items);
      await GStorage.setting.put(SettingsKeys.zoteroLocalPort, port);
      if (!mounted || token.isCancelled) return;
      setState(() {
        _library = library;
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
                c.attachments.length == 1 ? c.attachments.single.key : null,
              ),
            ),
          );
      });
    } catch (e) {
      if (mounted && !token.isCancelled) {
        setState(() {
          _messageIsError = true;
          _message = zoteroLocalErrorMessage(context.l10n, e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDirectory() async {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: context.l10n.zoteroLocalDirectory,
    );
    if (directory == null || !mounted) return;
    try {
      await ZoteroLocalImporter.sourceIdentity(_library!, directory);
      await GStorage.setting.put(SettingsKeys.zoteroLocalDirectory, directory);
      if (mounted) {
        setState(() {
          _directory = directory;
          _message = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = context.l10n.zoteroLocalDirectoryHint;
        });
      }
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
      final source = await ZoteroLocalImporter.sourceIdentity(
        library,
        _directory,
      );
      if (!mounted) return;
      _task = ref.read(taskProvider.notifier);
      final result = await _task!.importLocalZotero(
        library: library,
        source: source,
        candidates: _candidates
            .where((c) => _selected.contains(c.key))
            .toList(),
        attachments: Map.of(_attachments),
      );
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _messageIsError = result != null && result.failedTitles.isNotEmpty;
        _message = result == null
            ? l10n.zoteroLocalStopped
            : '${l10n.zoteroLocalResult(result.added, result.updated, result.copied, result.missing, result.kept, result.failedTitles.length)}'
                  '${result.failedTitles.isEmpty ? '' : '\n${result.failedTitles.join('\n')}'}';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = _library?.serverId == null
              ? context.l10n.zoteroLocalDirectoryHint
              : zoteroLocalErrorMessage(context.l10n, e);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                              borderRadius: BorderRadius.circular(16),
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
                          _token?.cancel();
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
                                  (_library!.serverId == null &&
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
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.outlineVariant.withAlpha(100)),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
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
            decoration: InputDecoration(
              labelText: l10n.zoteroLocalPort,
              counterText: '',
              filled: true,
              fillColor: cs.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: border,
              enabledBorder: border,
              disabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
            ),
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
          if (_library != null && _library!.serverId == null) ...[
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
    borderRadius: BorderRadius.circular(4),
    backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(80),
  );

  Widget _candidate(BuildContext context, ZoteroImportCandidate candidate) {
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
            borderRadius: BorderRadius.circular(16),
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
