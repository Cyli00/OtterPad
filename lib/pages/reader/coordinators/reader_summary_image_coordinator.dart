import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/animation_constants.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/api_provider.dart';
import '../../../providers/document_task_provider.dart';
import '../../../providers/image_generation_config_provider.dart';
import '../../../providers/reader_session_provider.dart';
import '../../../providers/summary_image_provider.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../router/app_routes.dart';
import '../../../services/document_summary_image_service.dart';
import '../../../services/figure_extract_service.dart';
import '../../../services/snackbar_service.dart';
import '../../../core/l10n.dart';
import '../../../utils/doc_paths.dart';
import '../../../widgets/tactile_press.dart';
import '../widgets/figure_viewer.dart';

class ReaderSummaryImageCoordinator {
  final BuildContext context;
  final WidgetRef ref;
  final Document document;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final ValueNotifier<SummaryImageState> summaryImageState;
  final ReaderSessionNotifier sessionNotifier;
  final VoidCallback openOutlineSheet;

  const ReaderSummaryImageCoordinator({
    required this.context,
    required this.ref,
    required this.document,
    required this.scaffoldKey,
    required this.summaryImageState,
    required this.sessionNotifier,
    required this.openOutlineSheet,
  });

  Future<void> generate({bool openOutline = true}) async {
    final imageRole = AgentApiNotifier.globalImageRole;
    final hasImageRole =
        imageRole.id != null && imageRole.modelId != null;

    final choice = await _showCostDialog(hasImageRole: hasImageRole);
    if (!context.mounted ||
        choice == null ||
        choice == _SummaryImageChoice.cancel) {
      return;
    }

    if (choice == _SummaryImageChoice.official) {
      await _showOfficialGenDialog();
      return;
    }

    if (!hasImageRole) {
      scaffoldKey.currentState?.closeEndDrawer();
      ref
          .read(snackBarServiceProvider)
          .showResult(
            message: context.l10n.selectImageModelFirst,
            action: SnackBarAction(
              label: context.l10n.goToSettings,
              onPressed: () => context.push(AppRoutes.settingsApi),
            ),
          );
      return;
    }

    if (openOutline) openOutlineSheet();

    final taskKey = DocumentTaskKey(
      type: DocumentTaskType.generateSummaryImage,
      documentId: document.id,
    );
    final alreadyRunning =
        ref.read(documentTaskProvider)[taskKey]?.isActive == true;
    final current = summaryImageState.value;
    if (alreadyRunning) {
      if (!current.generating) {
        summaryImageState.value = SummaryImageState(
          imagePath: current.imagePath,
          revision: current.revision,
          generating: true,
        );
      }
      return;
    }

    summaryImageState.value = SummaryImageState(
      imagePath: current.imagePath,
      revision: current.revision,
      generating: true,
    );

    await ref
        .read(documentTaskProvider.notifier)
        .generateSummaryImage(
          document: document,
          onSuccess: (imagePath) {
            unawaited(FileImage(File(imagePath)).evict());
            if (!context.mounted) return;
            final revision = summaryImageState.value.revision + 1;
            sessionNotifier.setSummaryImagePath(imagePath);
            summaryImageState.value = SummaryImageState(
              imagePath: imagePath,
              revision: revision,
            );
          },
        );

    if (!context.mounted || !summaryImageState.value.generating) return;
    final latest = summaryImageState.value;
    summaryImageState.value = SummaryImageState(
      imagePath: latest.imagePath,
      revision: latest.revision,
    );
  }

  Future<void> openSummaryImage([String? imagePath]) async {
    final path =
        imagePath ?? DocumentSummaryImageService.imagePathFor(document.id);
    if (!await File(path).exists()) {
      ref.read(snackBarServiceProvider).showResult(message: context.l10n.summaryNotFound);
      return;
    }
    if (!context.mounted) return;
    final entry = FigureManifestEntry(
      imagePath: path,
      captionText: 'Graphical Summary',
      pageIndex: 0,
      blockIds: const [],
    );
    await showFigureViewer(context, [entry]);
  }

  Future<_SummaryImageChoice?> _showCostDialog({
    required bool hasImageRole,
  }) async {
    final cfg = ref.read(imageGenerationConfigProvider);
    final role = AgentApiNotifier.globalImageRole;
    final protocol = role.id == null
        ? null
        : AgentApiNotifier.loadInstance(role.id!)?.provider;
    final cost = protocol == AgentApiProvider.openai
        ? estimateOpenAICost(
            aspectRatio: cfg.aspectRatio,
            fidelity: cfg.fidelity,
          )
        : null;
    final costLine = cost != null
        ? context.l10n.estimatedCost('\$', cost.toStringAsFixed(3))
        : '';

    return showDialog<_SummaryImageChoice>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            context.l10n.generateSummaryTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.summaryApiCostHint,
                style: theme.textTheme.bodyMedium,
              ),
              if (costLine.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  costLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                context.l10n.useAppImageGen,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_SummaryImageChoice.cancel),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_SummaryImageChoice.official),
              child: Text(context.l10n.appImageGen),
            ),
            TextButton(
              onPressed: hasImageRole
                  ? () => Navigator.of(ctx).pop(_SummaryImageChoice.confirm)
                  : null,
              child: Text(context.l10n.confirm),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showOfficialGenDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _OfficialGenDialog(onExportAll: _exportAll),
    );
  }

  /// 一键导出：移动端 share figures + markdown，桌面端打包 ZIP；
  /// 两种路径都同步把生图 prompt 写入剪贴板，方便用户在 ChatGPT
  /// 等目标 app 内直接粘贴。
  Future<String?> _exportAll() async {
    // 1. 收集 figures（允许为空——某些文献可能没图）
    final figuresDir = Directory(DocPaths.figuresDir(document.id));
    final figureFiles = <File>[];
    if (await figuresDir.exists()) {
      await for (final entity in figuresDir.list()) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.webp')) {
          figureFiles.add(entity);
        }
      }
    }

    // 2. 必须有 markdown,否则没有正文可导出
    final mdFile = File(DocPaths.md(document.id));
    if (!await mdFile.exists()) {
      return context.l10n.markdownNotFound;
    }

    // 3. 生成生图 prompt（含文献元数据 + Markdown + figure 索引）
    final String prompt;
    try {
      final config = ref.read(imageGenerationConfigProvider);
      final language = ref.read(translationConfigProvider).targetLanguage;
      final role = AgentApiNotifier.globalImageRole;
      final protocol = role.id == null
          ? null
          : AgentApiNotifier.loadInstance(role.id!)?.provider;
      prompt = await DocumentSummaryImageService.instance.composePrompt(
        document: document,
        config: config,
        provider: protocol ?? AgentApiProvider.openai,
        language: language,
      );
    } on DocumentSummaryImageException catch (e) {
      return e.message;
    } catch (e) {
      return context.l10n.promptGenerationFailed('$e');
    }

    // 4. 平台分流
    try {
      if (_isDesktop) {
        // 桌面：打包 ZIP（全平铺：根目录直接放 figure / article.md / prompt.md，
        // 用户解压后一次框选拖到 ChatGPT 网页版即可）
        final targetPath = await FilePicker.platform.saveFile(
          dialogTitle: context.l10n.saveExportZip,
          fileName: '${_safeFileStem(document.title)}.zip',
          lockParentWindow: true,
        );
        if (targetPath == null) return null; // 用户取消,不写剪贴板

        final mdContent = await mdFile.readAsString();
        final archive = Archive()
          ..add(ArchiveFile.string('article.md', mdContent))
          ..add(ArchiveFile.string('prompt.md', prompt));
        for (final f in figureFiles) {
          archive.add(
            ArchiveFile.bytes(p.basename(f.path), await f.readAsBytes()),
          );
        }
        final bytes = ZipEncoder().encodeBytes(archive);
        await File(targetPath).writeAsBytes(bytes, flush: true);

        await Clipboard.setData(ClipboardData(text: prompt));
        return context.l10n.exportedWithPromptCopied(p.basename(targetPath));
      } else {
        // 移动：share sheet 多文件 + 剪贴板。markdown 放在 list 第一位让目标
        // app 的附件列表把 .md 排在最显眼位置。
        await Clipboard.setData(ClipboardData(text: prompt));
        final files = <XFile>[
          XFile(mdFile.path),
          for (final f in figureFiles) XFile(f.path),
        ];
        await Share.shareXFiles(files, subject: document.title);
        return null; // share sheet 自带反馈,不另加 toast
      }
    } catch (e) {
      return context.l10n.exportFailed('$e');
    }
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  String _safeFileStem(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'document';
    final sanitized = trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return sanitized.length > 80 ? sanitized.substring(0, 80) : sanitized;
  }
}

enum _SummaryImageChoice { cancel, official, confirm }

class _OfficialGenDialog extends StatefulWidget {
  final Future<String?> Function() onExportAll;

  const _OfficialGenDialog({required this.onExportAll});

  @override
  State<_OfficialGenDialog> createState() => _OfficialGenDialogState();
}

class _OfficialGenDialogState extends State<_OfficialGenDialog> {
  String? _notice;
  Timer? _noticeTimer;
  bool _running = false;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final msg = await action();
      if (!mounted) return;
      if (msg == null) {
        setState(() {});
        return;
      }
      _noticeTimer?.cancel();
      setState(() => _notice = msg);
      _noticeTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _notice = null);
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        context.l10n.exportToAppImageGen,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.exportToAppImageGenHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _OfficialGenAction(
            icon: Symbols.ios_share_rounded,
            label: context.l10n.exportAll,
            description: Platform.isAndroid || Platform.isIOS
                ? context.l10n.exportShareHint
                : context.l10n.exportZipHint,
            enabled: !_running,
            onTap: () => _run(widget.onExportAll),
          ),
          AnimatedSize(
            duration: kAnim,
            curve: kAnimCurve,
            alignment: Alignment.topCenter,
            child: _notice == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: cs.inverseSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Symbols.check_circle_rounded,
                            color: cs.onInverseSurface,
                            size: 18,
                            fill: 1,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _notice!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onInverseSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

class _OfficialGenAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool enabled;
  final VoidCallback onTap;

  const _OfficialGenAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return TactilePress(
      baseColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Row(
          children: [
            Icon(icon, color: cs.primary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Symbols.chevron_right_rounded,
              color: cs.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
