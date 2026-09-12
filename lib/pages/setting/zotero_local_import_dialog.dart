import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
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
      setState(() => _message = context.l10n.zoteroLocalInvalidPort);
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
        setState(() => _message = zoteroLocalErrorMessage(context.l10n, e));
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
        setState(() => _message = context.l10n.zoteroLocalDirectoryHint);
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
      setState(
        () => _message = result == null
            ? l10n.zoteroLocalStopped
            : '${l10n.zoteroLocalResult(result.added, result.updated, result.copied, result.missing, result.kept, result.failedTitles.length)}'
                  '${result.failedTitles.isEmpty ? '' : '\n${result.failedTitles.join('\n')}'}',
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = _library?.serverId == null
              ? context.l10n.zoteroLocalDirectoryHint
              : zoteroLocalErrorMessage(context.l10n, e),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(l10n.zoteroLocalTitle),
        content: SizedBox(
          width: 492,
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.zoteroLocalHint,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _port,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            maxLength: 5,
                            decoration: InputDecoration(
                              labelText: l10n.zoteroLocalPort,
                              counterText: '',
                            ),
                            onChanged: (_) => setState(() {
                              _library = null;
                              _candidates = [];
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  Haptics.soft();
                                  _connect();
                                },
                          child: Text(l10n.zoteroLocalConnect),
                        ),
                      ],
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      Text(l10n.zoteroLocalLoading(_fetched, _total)),
                    ],
                    if (_library != null && _library!.serverId == null)
                      Tooltip(
                        message: _directory == null
                            ? l10n.zoteroLocalDirectoryHint
                            : '${l10n.zoteroLocalDirectoryHint}\n$_directory',
                        child: TextButton.icon(
                          onPressed: _busy ? null : _pickDirectory,
                          icon: const Icon(Symbols.folder_open_rounded),
                          label: Text(
                            _directory == null
                                ? l10n.zoteroLocalDirectory
                                : l10n.zoteroLocalDirectorySelected,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    if (_library != null)
                      Row(
                        children: [
                          Checkbox(
                            value:
                                _candidates.isNotEmpty &&
                                _selected.length == _candidates.length,
                            onChanged: _busy
                                ? null
                                : (value) {
                                    Haptics.light();
                                    setState(() {
                                      _selected.clear();
                                      if (value == true) {
                                        _selected.addAll(
                                          _candidates.map((c) => c.key),
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
                            ),
                          ),
                        ],
                      ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(_message!),
                      ),
                    if (_library != null && _candidates.isEmpty)
                      Text(l10n.zoteroLocalEmpty),
                    if (_importing) const LinearProgressIndicator(),
                  ],
                ),
              ),
              SliverList.separated(
                itemCount: _library == null ? 0 : _candidates.length,
                separatorBuilder: (_, _) => const AppDivider.full(),
                itemBuilder: (_, index) {
                  final candidate = _candidates[index];
                  final selected = _selected.contains(candidate.key);
                  return Padding(
                    key: ValueKey(candidate.key),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        TactilePress(
                          baseColor: Colors.transparent,
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
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      candidate.document.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      candidate.document.authors.join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (candidate.attachments.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: IgnorePointer(
                              ignoring: _busy || !selected,
                              child: SettingPicker<String>(
                                current: _attachments[candidate.key] ?? '',
                                options: [
                                  '',
                                  ...candidate.attachments.map((a) => a.key),
                                ],
                                labelFor: (key) => key.isEmpty
                                    ? l10n.zoteroLocalMetadataOnly
                                    : candidate.attachments
                                          .firstWhere((a) => a.key == key)
                                          .title,
                                sheetTitle: l10n.zoteroLocalChoosePdf,
                                onChanged: (key) {
                                  if (_busy || !selected) return;
                                  setState(
                                    () => _attachments[candidate.key] =
                                        key.isEmpty ? null : key,
                                  );
                                },
                              ),
                            ),
                          )
                        else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.zoteroLocalNoPdf,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              _token?.cancel();
              if (_importing) _task?.cancelTask(TaskType.zoteroSync);
              Navigator.pop(context);
            },
            child: Text(_busy ? l10n.cancel : l10n.close),
          ),
          TextButton(
            onPressed:
                _busy ||
                    _library == null ||
                    _selected.isEmpty ||
                    (_library!.serverId == null && _directory == null)
                ? null
                : _import,
            child: Text(l10n.zoteroLocalImport),
          ),
        ],
      ),
    );
  }
}
