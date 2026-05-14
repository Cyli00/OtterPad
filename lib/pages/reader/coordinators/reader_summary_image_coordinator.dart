import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

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
import '../../../utils/doc_paths.dart';
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
        imageRole.provider != null && imageRole.modelId != null;

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
            message: '请先在「AI 设置」中选择生图模型',
            action: SnackBarAction(
              label: '前往设置',
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
      ref.read(snackBarServiceProvider).showResult(message: '总结图文件不存在');
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
    final cost = role.provider == AgentApiProvider.openai
        ? estimateOpenAICost(
            aspectRatio: cfg.aspectRatio,
            fidelity: cfg.fidelity,
          )
        : null;
    final costLine = cost != null
        ? '当前设置预估费用约 \$${cost.toStringAsFixed(3)} / 张'
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
            '生成总结图',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '总结图由第三方生图模型生成，可能产生 API 调用费用。',
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
                '若希望使用 App 生图，请点击 App 生图，手动上传素材。',
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
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_SummaryImageChoice.official),
              child: const Text('App 生图'),
            ),
            TextButton(
              onPressed: hasImageRole
                  ? () => Navigator.of(ctx).pop(_SummaryImageChoice.confirm)
                  : null,
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showOfficialGenDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _OfficialGenDialog(
        onExportFigures: _exportFigures,
        onExportMarkdown: _exportMarkdown,
        onCopyPrompt: _copyGenPrompt,
      ),
    );
  }

  Future<String?> _exportFigures() async {
    final figuresDir = Directory(DocPaths.figuresDir(document.id));
    if (!await figuresDir.exists()) {
      return '未找到 figures 目录，请先完成文档提取';
    }
    final files = <File>[];
    await for (final entity in figuresDir.list()) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.webp')) {
        files.add(entity);
      }
    }
    if (files.isEmpty) return 'figures 目录为空';

    try {
      if (_isDesktop) {
        final targetDir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择保存目录',
          lockParentWindow: true,
        );
        if (targetDir == null) return null;
        var copied = 0;
        for (final f in files) {
          final name = p.basename(f.path);
          await f.copy(p.join(targetDir, name));
          copied++;
        }
        return '已保存 $copied 个 figure 到 $targetDir';
      } else {
        await Share.shareXFiles(
          files.map((f) => XFile(f.path)).toList(),
          subject: 'figures',
        );
        return null;
      }
    } catch (e) {
      return '保存失败：$e';
    }
  }

  Future<String?> _exportMarkdown() async {
    final mdPath = DocPaths.md(document.id);
    final mdFile = File(mdPath);
    if (!await mdFile.exists()) {
      return '未找到 Markdown 文件，请先完成文档提取';
    }
    final defaultName = '${_safeFileStem(document.title)}.md';

    try {
      if (_isDesktop) {
        final targetPath = await FilePicker.platform.saveFile(
          dialogTitle: '保存 Markdown',
          fileName: defaultName,
          lockParentWindow: true,
        );
        if (targetPath == null) return null;
        final target = File(targetPath);
        if (await target.exists()) await target.delete();
        await mdFile.copy(target.path);
        return '已保存到 ${target.path}';
      } else {
        await Share.shareXFiles([XFile(mdFile.path)], subject: defaultName);
        return null;
      }
    } catch (e) {
      return '保存失败：$e';
    }
  }

  Future<String?> _copyGenPrompt() async {
    try {
      final config = ref.read(imageGenerationConfigProvider);
      final language = ref.read(translationConfigProvider).targetLanguage;
      final role = AgentApiNotifier.globalImageRole;
      final prompt = await DocumentSummaryImageService.instance.composePrompt(
        document: document,
        config: config,
        provider: role.provider ?? AgentApiProvider.openai,
        language: language,
      );
      await Clipboard.setData(ClipboardData(text: prompt));
      return '已复制生图提示词到剪贴板';
    } on DocumentSummaryImageException catch (e) {
      return e.message;
    } catch (e) {
      return '复制失败：$e';
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
  final Future<String?> Function() onExportFigures;
  final Future<String?> Function() onExportMarkdown;
  final Future<String?> Function() onCopyPrompt;

  const _OfficialGenDialog({
    required this.onExportFigures,
    required this.onExportMarkdown,
    required this.onCopyPrompt,
  });

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
        '导出至 App 生图',
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '将文献素材导出后，到 ChatGPT / Gemini 等官方 App 中手动上传以生图。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _OfficialGenAction(
            icon: Symbols.image_rounded,
            label: '保存文献 figures',
            description: '导出提取出的所有 figure 图片',
            enabled: !_running,
            onTap: () => _run(widget.onExportFigures),
          ),
          const SizedBox(height: 8),
          _OfficialGenAction(
            icon: Symbols.description_rounded,
            label: '保存文献 Markdown',
            description: '导出 .md 全文，用于补充 prompt',
            enabled: !_running,
            onTap: () => _run(widget.onExportMarkdown),
          ),
          const SizedBox(height: 8),
          _OfficialGenAction(
            icon: Symbols.content_copy_rounded,
            label: '复制生图提示词',
            description: '复制完整 prompt 到剪贴板',
            enabled: !_running,
            onTap: () => _run(widget.onCopyPrompt),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
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
          child: const Text('关闭'),
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
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
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
        ),
      ),
    );
  }
}
