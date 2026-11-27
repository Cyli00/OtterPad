import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../services/snackbar_service.dart';
import '../../../src/rust/api/document.dart';
import '../../../src/rust/document.dart';
import '../../../src/rust/document/references.dart';
import '../../../widgets/tactile_press.dart';
import 'figure_viewer.dart';
import '../../../core/design_tokens.dart';

/// 大纲：目录、图表（含总结图）与参考文献三页。sheet / 停靠栏外壳负责圆角与背景。
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({
    super.key,
    required this.model,
    required this.summaryPath,
    required this.generatingSummary,
    required this.onNavigate,
    required this.onOpenFigure,
    this.onGenerateSummary,
    this.onOpenSummary,
  });

  /// 原文文档模型（不含译文块）。
  final ReaderDocument model;
  final String summaryPath;
  final bool generatingSummary;
  final ValueChanged<String> onNavigate;
  final ValueChanged<Block> onOpenFigure;
  final VoidCallback? onGenerateSummary;
  final VoidCallback? onOpenSummary;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: context.l10n.outlineContents),
            Tab(text: context.l10n.outlineFigures),
            Tab(text: context.l10n.outlineReferences),
          ],
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          indicatorWeight: 2.5,
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: theme.textTheme.labelLarge,
          dividerHeight: 0,
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ContentsTab(model: widget.model, onNavigate: widget.onNavigate),
              _FiguresTab(
                model: widget.model,
                summaryPath: widget.summaryPath,
                generatingSummary: widget.generatingSummary,
                onNavigate: widget.onNavigate,
                onOpenFigure: widget.onOpenFigure,
                onGenerateSummary: widget.onGenerateSummary,
                onOpenSummary: widget.onOpenSummary,
              ),
              _ReferencesTab(references: widget.model.references),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── 目录 ───

class _ContentsTab extends StatelessWidget {
  const _ContentsTab({required this.model, required this.onNavigate});

  final ReaderDocument model;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headings = [
      for (final block in model.blocks)
        if (block.kind == BlockKind.heading &&
            block.ownerId == null &&
            block.text.trim().isNotEmpty)
          block,
    ];
    if (headings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.toc_rounded,
              size: 48,
              color: cs.onSurfaceVariant.withAlpha(80),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.outlineContentsEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    // 以文中最浅的标题层级为第一级缩进。
    final top = headings
        .map((b) => b.headingLevel ?? 1)
        .reduce((a, b) => a < b ? a : b);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: headings.length,
      itemBuilder: (context, index) {
        final block = headings[index];
        final depth = (block.headingLevel ?? 1) - top;
        return TactilePress(
          baseColor: Colors.transparent,
          onTap: () => onNavigate(block.id),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          padding: EdgeInsets.fromLTRB(8 + depth * 16.0, 10, 8, 10),
          child: Text(
            block.text.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: depth == 0
                ? theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
          ),
        );
      },
    );
  }
}

// ─── 图表 ───

class _FiguresTab extends StatefulWidget {
  const _FiguresTab({
    required this.model,
    required this.summaryPath,
    required this.generatingSummary,
    required this.onNavigate,
    required this.onOpenFigure,
    this.onGenerateSummary,
    this.onOpenSummary,
  });

  final ReaderDocument model;
  final String summaryPath;
  final bool generatingSummary;
  final ValueChanged<String> onNavigate;
  final ValueChanged<Block> onOpenFigure;
  final VoidCallback? onGenerateSummary;
  final VoidCallback? onOpenSummary;

  @override
  State<_FiguresTab> createState() => _FiguresTabState();
}

class _FiguresTabState extends State<_FiguresTab> {
  @override
  void didUpdateWidget(_FiguresTab old) {
    super.didUpdateWidget(old);
    // 重新生成会原地覆盖总结图；ImageCache 以路径为键，不感知内容变化。
    if (old.generatingSummary && !widget.generatingSummary) {
      PaintingBinding.instance.imageCache.evict(
        FileImage(File(widget.summaryPath)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = {
      for (final image in widget.model.figureImages) image.blockId: image.path,
    };
    // 只列有题注的图表；匿名图仍在正文中显示。
    final figures = [
      for (final block in widget.model.blocks)
        if (block.ownerId == null &&
            (block.kind == BlockKind.figure || block.kind == BlockKind.table) &&
            block.text.trim().isNotEmpty)
          block,
    ];
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: figures.length + 1,
      separatorBuilder: (_, _) => Divider(color: cs.outlineVariant, height: 32),
      itemBuilder: (context, index) {
        if (index == 0) return _summary(context);
        final block = figures[index - 1];
        return RepaintBoundary(
          child: _FigureEntry(
            block: block,
            imagePath: images[block.id],
            onNavigate: () => widget.onNavigate(block.id),
            onOpen: () => widget.onOpenFigure(block),
          ),
        );
      },
    );
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final generating = widget.generatingSummary;
    final exists = File(widget.summaryPath).existsSync();
    final onGenerate = widget.onGenerateSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Symbols.auto_awesome_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              context.l10n.graphicalSummary,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const Spacer(),
            if (generating)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              )
            else if (onGenerate != null)
              Tooltip(
                message: context.l10n.generateSummary,
                child: TactilePress(
                  onTap: onGenerate,
                  baseColor: Colors.transparent,
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    exists ? Symbols.refresh_rounded : Symbols.add_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        if (exists && !generating) ...[
          const SizedBox(height: 10),
          TactilePress(
            baseColor: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            pressedScale: 0.98,
            onTap: widget.onOpenSummary,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Hero(
                tag: figureHeroTag(
                  FigureHeroSource.outline,
                  widget.summaryPath,
                ),
                child: Image.file(
                  File(widget.summaryPath),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  cacheWidth: 600,
                ),
              ),
            ),
          ),
        ] else if (generating) ...[
          const SizedBox(height: 10),
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Text(
              context.l10n.generatingSummary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FigureEntry extends StatelessWidget {
  const _FigureEntry({
    required this.block,
    required this.imagePath,
    required this.onNavigate,
    required this.onOpen,
  });

  final Block block;
  final String? imagePath;
  final VoidCallback onNavigate;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final path = imagePath;
    final hasImage = path != null && File(path).existsSync();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          block.text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        if (hasImage)
          TactilePress(
            baseColor: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            pressedScale: 0.98,
            onTap: onOpen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Hero(
                tag: figureHeroTag(FigureHeroSource.outline, path),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  cacheWidth: 600,
                  gaplessPlayback: true,
                ),
              ),
            ),
          )
        else
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(
              child: Icon(
                Symbols.broken_image_rounded,
                color: cs.onSurfaceVariant.withAlpha(120),
                size: 32,
              ),
            ),
          ),
        const SizedBox(height: 8),
        // 链接自带横向留白做反馈底色，整体左移同样距离让文字与标题对齐。
        Transform.translate(
          offset: const Offset(-8, 0),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _ActionLink(
                icon: Symbols.article_rounded,
                label: context.l10n.viewInDocument,
                onTap: onNavigate,
              ),
              if (hasImage)
                _ActionLink(
                  icon: Symbols.open_in_full_rounded,
                  label: context.l10n.viewOriginalImage,
                  onTap: onOpen,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── 参考文献 ───

class _ReferencesTab extends ConsumerStatefulWidget {
  const _ReferencesTab({required this.references});

  final List<Reference> references;

  @override
  ConsumerState<_ReferencesTab> createState() => _ReferencesTabState();
}

class _ReferencesTabState extends ConsumerState<_ReferencesTab> {
  /// 最近复制的条目：行高亮与勾选维持 2 秒，指明刚才点中的是哪条。
  int? _copied;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy(int index, Reference item) async {
    await Clipboard.setData(
      ClipboardData(
        text: item.numbered ? '[${item.number}] ${item.text}' : item.text,
      ),
    );
    if (!mounted) return;
    setState(() => _copied = index);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = null);
    });
    final snippet = item.text.length > 30
        ? '${item.text.substring(0, 30)}…'
        : item.text;
    ref
        .read(snackBarServiceProvider)
        .showResult(
          message: context.l10n.copiedReference(item.number, snippet),
          duration: const Duration(seconds: 2),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final references = widget.references;
    if (references.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.menu_book_rounded,
              size: 48,
              color: cs.onSurfaceVariant.withAlpha(80),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.referencesNotFound,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: references.length,
      separatorBuilder: (_, _) => Divider(color: cs.outlineVariant, height: 1),
      itemBuilder: (context, index) {
        final item = references[index];
        final copied = index == _copied;
        return RepaintBoundary(
          child: TactilePress(
            baseColor: copied
                ? cs.primaryContainer.withAlpha(110)
                : Colors.transparent,
            onTap: () => _copy(index, item),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '${item.number}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.text,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedOpacity(
                  opacity: copied ? 1 : 0,
                  duration: kAnimFast,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Symbols.check_circle_rounded,
                      size: 18,
                      fill: 1,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionLink extends StatelessWidget {
  const _ActionLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TactilePress(
      onTap: onTap,
      baseColor: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      pressedScale: 0.94,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: cs.primary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
