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
      return '未找到 Markdown 文件，请先完成文档提取';
    }

    // 3. 生成生图 prompt（含文献元数据 + Markdown + figure 索引）
    final String prompt;
    try {
      final config = ref.read(imageGenerationConfigProvider);
      final language = ref.read(translationConfigProvider).targetLanguage;
      final role = AgentApiNotifier.globalImageRole;
      prompt = await DocumentSummaryImageService.instance.composePrompt(
        document: document,
        config: config,
        provider: role.provider ?? AgentApiProvider.openai,
        language: language,
      );
    } on DocumentSummaryImageException catch (e) {
      return e.message;
    } catch (e) {
      return '生成 prompt 失败：$e';
    }

    // 4. 平台分流
    try {
      if (_isDesktop) {
        // 桌面：打包 ZIP（全平铺：根目录直接放 figure / article.md / prompt.md，
        // 用户解压后一次框选拖到 ChatGPT 网页版即可）
        final targetPath = await FilePicker.platform.saveFile(
          dialogTitle: '保存导出 ZIP',
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
        return '已导出到 ${p.basename(targetPath)}，prompt 已复制';
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
      return '导出失败：$e';
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
            icon: Symbols.ios_share_rounded,
            label: '一键导出',
            description: Platform.isAndroid || Platform.isIOS
                ? '同时分享 figures + Markdown，prompt 自动复制到剪贴板'
                : '打包 figures + article.md + prompt.md 为 ZIP，prompt 自动复制到剪贴板',
            enabled: !_running,
            onTap: () => _run(widget.onExportAll),
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
