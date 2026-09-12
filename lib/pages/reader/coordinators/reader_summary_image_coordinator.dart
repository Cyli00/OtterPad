import '../../../widgets/setting_controls.dart';
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:extended_image/extended_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/animation_constants.dart';
import '../../../core/app_logger.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/agent_api_provider.dart';
import '../../../providers/document_task_provider.dart';
import '../../../providers/image_generation_config_provider.dart';
import '../../../providers/reader_session_provider.dart';
import '../../../providers/summary_image_provider.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../router/app_routes.dart';
import '../../../services/document_summary_image_service.dart';
import '../../../services/figure_extract_service.dart';
import '../../../services/haptics.dart';
import '../../../services/snackbar_service.dart';
import '../../../core/l10n.dart';
import '../../../utils/desktop.dart';
import '../../../utils/doc_paths.dart';
import '../../../widgets/tactile_press.dart';
import '../../setting/setting_picker.dart';
import '../chat/document_chat_page.dart';
import '../widgets/figure_viewer.dart';

class ReaderSummaryImageCoordinator {
  final BuildContext context;
  final WidgetRef ref;
  final Document document;
  final ValueNotifier<SummaryImageState> summaryImageState;
  final ReaderSessionNotifier sessionNotifier;
  final VoidCallback openOutlineSheet;
  final void Function(DocumentChatPageArgs args)? onOpenChat;

  const ReaderSummaryImageCoordinator({
    required this.context,
    required this.ref,
    required this.document,
    required this.summaryImageState,
    required this.sessionNotifier,
    required this.openOutlineSheet,
    this.onOpenChat,
  });

  Future<void> generate({bool openOutline = true}) async {
    final imageRole = AgentApiNotifier.globalImageRole;
    final hasImageRole = imageRole.id != null && imageRole.modelId != null;

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

    if (!hasImageRole) return;

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

    // 成功路径收敛：onSuccess 只记录生成的路径，统一在 generate 完成后驱逐
    // Thumbnail + Viewer 三类缓存，再递增 revision 更新状态——避免 unawaited
    // FileImage evict 的竞态导致 Viewer 仍显示旧图。
    String? generatedPath;
    await ref
        .read(documentTaskProvider.notifier)
        .generateSummaryImage(
          document: document,
          onSuccess: (imagePath) {
            generatedPath = imagePath;
          },
        );

    if (!context.mounted || !summaryImageState.value.generating) return;
    final latest = summaryImageState.value;
    final newPath = generatedPath;
    if (newPath != null) {
      // 在 revision/state 更新前清缓存，确保新缩略图可点击前 extended_image 键已失效。
      await evictSummaryImageCaches(newPath);
      if (!context.mounted) return;
      final revision = latest.revision + 1;
      sessionNotifier.setSummaryImagePath(newPath);
      summaryImageState.value = SummaryImageState(
        imagePath: newPath,
        revision: revision,
      );
    } else {
      // 未生成图片：沿用现有 generating 收尾逻辑。
      summaryImageState.value = SummaryImageState(
        imagePath: latest.imagePath,
        revision: latest.revision,
      );
    }
  }

  Future<void> openSummaryImage([String? imagePath]) async {
    final path =
        imagePath ?? DocumentSummaryImageService.imagePathFor(document.id);
    if (!await File(path).exists()) {
      if (!context.mounted) return;
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.summaryNotFound);
      return;
    }
    if (!context.mounted) return;
    final entry = FigureManifestEntry(
      imagePath: path,
      captionText: 'Graphical Summary',
      pageIndex: 0,
      blockIds: const [],
    );
    await showFigureViewer(
      context,
      [entry],
      documentId: document.id,
      document: document,
      onOpenChat: onOpenChat,
    );
  }

  /// 从相册/文件选择一张图片作为总结图（覆盖已有图）。
  ///
  /// 走 `file_picker`（Android 13+ 系统 Photo Picker）。
  /// **必须**关闭压缩：file_picker 默认 compressionQuality=30 会在 Android
  /// 的 Pictures 目录写出压缩副本，表现为相册多出一张所选图的新副本。
  Future<void> uploadFromGallery() async {
    File? staged;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowCompression: false,
        compressionQuality: 0,
      );
      if (!context.mounted || result == null || result.files.isEmpty) return;
      final sourcePath = result.files.first.path;
      if (sourcePath == null) return;

      final destPath = DocumentSummaryImageService.imagePathFor(document.id);
      final destFile = File(destPath);
      final metaFile = File(DocPaths.summaryMeta(document.id));
      await destFile.parent.create(recursive: true);

      final bytes = await File(sourcePath).readAsBytes();
      if (!context.mounted) return;
      staged = File('$destPath.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await staged.writeAsBytes(bytes, flush: true);

      // 先完成暂存再替换，选到当前总结图或读取失败时也不会提前删除旧图。
      await evictSummaryImageCaches(destPath);

      if (!context.mounted) return;
      await staged.rename(destPath);
      if (await metaFile.exists()) {
        await metaFile.delete();
      }

      // 写入后再清一次（含 extended_image 键），且必须在 revision/state 更新前完成。
      await evictSummaryImageCaches(destPath);

      if (!context.mounted) return;
      final current = summaryImageState.value;
      final revision = current.revision + 1;
      sessionNotifier.setSummaryImagePath(destPath);
      summaryImageState.value = SummaryImageState(
        imagePath: destPath,
        revision: revision,
      );
      // 与 document_task / 其它订阅 summaryImageProvider 的路径保持一致
      ref.read(summaryImageProvider(document.id).notifier).generated(destPath);
    } catch (e, st) {
      log.w('[SummaryImage] 上传失败', error: e, stackTrace: st);
      if (!context.mounted) return;
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.summaryUploadFailed);
    } finally {
      final pending = staged;
      try {
        if (pending != null && await pending.exists()) {
          await pending.delete();
        }
      } catch (e, st) {
        log.w('[SummaryImage] 临时文件清理失败', error: e, stackTrace: st);
      }
    }
  }

  /// 驱逐 summary 图相关的三类 ImageCache 条目。
  ///
  /// 与真实渲染路径保持一致：
  ///  - [FileImage]：无 resize 的普通加载；
  ///  - [ResizeImage]（width: 600）：Outline 缩略图 `Image.file(cacheWidth: 600)`
  ///    的实际缓存键，只 evict [FileImage] 不够，旧图 A 仍会残留；
  ///  - [ExtendedFileImageProvider]：FigureViewer 的 `ExtendedImage.file()`
  ///    走 extended_image 独立缓存键，缩略图刷新后 Viewer 仍可能显示旧图。
  /// 不调用 [ImageCache.clear]，避免清空全局无关图片缓存。
  ///
  /// @visibleForTesting 静态方法：测试直接调用验证三类键都被清理。
  @visibleForTesting
  static Future<void> evictSummaryImageCaches(String path) async {
    final provider = FileImage(File(path));
    await provider.evict();
    await ResizeImage(provider, width: 600).evict();
    await ExtendedFileImageProvider(File(path)).evict();
  }

  Future<_SummaryImageChoice?> _showCostDialog({
    required bool hasImageRole,
  }) async {
    return showDialog<_SummaryImageChoice>(
      context: context,
      builder: (ctx) => _CostDialog(
        hasImageRole: hasImageRole,
        onGoToSettings: () {
          Navigator.of(ctx).pop();
          context.push(AppRoutes.settingsOverlayApi);
        },
      ),
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
      if (!context.mounted) return null;
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
      if (!context.mounted) return null;
      return context.l10n.promptGenerationFailed('$e');
    }

    // 4. 平台分流
    try {
      if (isDesktopOs) {
        // 桌面：打包 ZIP（全平铺：根目录直接放 figure / article.md / prompt.md，
        // 用户解压后一次框选拖到 ChatGPT 网页版即可）
        if (!context.mounted) return null;
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
        if (!context.mounted) return null;
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
      if (!context.mounted) return null;
      return context.l10n.exportFailed('$e');
    }
  }

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

/// 生成总结图对话框：内联画幅/清晰度/参考图数量三个生图设置，
/// 实时读写 imageGenerationConfigProvider（与设置页共享同一份配置）。
class _CostDialog extends ConsumerStatefulWidget {
  final bool hasImageRole;
  final VoidCallback onGoToSettings;

  const _CostDialog({required this.hasImageRole, required this.onGoToSettings});

  @override
  ConsumerState<_CostDialog> createState() => _CostDialogState();
}

class _CostDialogState extends ConsumerState<_CostDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final cfg = ref.watch(imageGenerationConfigProvider);
    final notifier = ref.read(imageGenerationConfigProvider.notifier);

    // 预估费用随设置实时刷新
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
        ? l10n.estimatedCost('\$', cost.toStringAsFixed(3))
        : '';

    return AlertDialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        l10n.generateSummaryTitle,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 画幅比例 ──
              SettingTitle(l10n.aspectRatio, l10n.aspectRatioHint),
              const SizedBox(height: 12),
              SettingPicker<String>(
                current: cfg.aspectRatio,
                options: kSummaryAspectRatios,
                labelFor: (v) => v,
                subtitleFor: (v) => switch (v) {
                  '1:1' => l10n.aspectSquare,
                  '4:3' => l10n.aspectClassic,
                  '16:9' => l10n.aspectWide,
                  '21:9' => l10n.aspectUltraWide,
                  '9:16' => l10n.aspectTall,
                  '3:2' => l10n.classicPhotography,
                  _ => '',
                },
                sheetTitle: l10n.aspectRatio,
                onChanged: (v) {
                  Haptics.soft();
                  notifier.setAspectRatio(v);
                },
              ),
              const SizedBox(height: 20),
              // ── 清晰度 ──
              SettingTitle(l10n.resolution, l10n.resolutionHint),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    backgroundColor: cs.surface,
                    selectedBackgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onSurfaceVariant,
                    selectedForegroundColor: cs.onPrimaryContainer,
                    side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: theme.textTheme.bodyMedium,
                  ),
                  showSelectedIcon: false,
                  segments: kSummaryFidelityKeys
                      .map(
                        (v) => ButtonSegment<String>(
                          value: v,
                          label: Text(switch (v) {
                            'auto' => l10n.fidelityAuto,
                            'standard' => l10n.fidelityStandard,
                            'high' => l10n.fidelityHigh,
                            _ => v,
                          }, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  selected: {cfg.fidelity},
                  onSelectionChanged: (set) {
                    Haptics.soft();
                    notifier.setFidelity(set.first);
                  },
                ),
              ),
              const SizedBox(height: 20),
              // ── 参考图数量 ──
              SettingSlider(
                title: context.l10n.referenceImageCount,
                tooltip: context.l10n.imageRefCountHint,
                padding: EdgeInsets.zero,
                value: cfg.maxReferenceImages.toDouble(),
                fallback: kSummaryReferenceImageMin.toDouble(),
                min: kSummaryReferenceImageMin.toDouble(),
                max: kSummaryReferenceImageMax.toDouble(),
                divisions:
                    kSummaryReferenceImageMax - kSummaryReferenceImageMin,
                formatter: (v) => v.round().toString(),
                onChanged: (v) => notifier.setMaxReferenceImages(v.round()),
              ),
              const SizedBox(height: 16),
              Divider(color: cs.outlineVariant.withAlpha(80), height: 1),
              const SizedBox(height: 12),
              // ── 预估费用（随设置实时变化） ──
              if (costLine.isNotEmpty) ...[
                Text(
                  costLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // ── App 生图引导小字 ──
              Text(
                l10n.useAppImageGen,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              // ── 未配置模型警告 ──
              if (!widget.hasImageRole) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.warning_rounded,
                        color: cs.onErrorContainer,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.selectImageModelFirst,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.onGoToSettings,
                        child: Text(
                          l10n.goToSettings,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_SummaryImageChoice.cancel),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_SummaryImageChoice.official),
          child: Text(l10n.appImageGen),
        ),
        TextButton(
          onPressed: widget.hasImageRole
              ? () => Navigator.of(context).pop(_SummaryImageChoice.confirm)
              : null,
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

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
