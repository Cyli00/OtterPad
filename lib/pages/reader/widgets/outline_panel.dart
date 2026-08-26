import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/snackbar_service.dart';
import '../../../widgets/tactile_press.dart';

import '../../../data/models/book/document.dart';
import '../../../providers/summary_image_provider.dart';
import '../../../services/figure_extract_service.dart';
import '../../../services/haptics.dart';
import '../chat/document_chat_page.dart';
import 'figure_viewer.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';

// ─── 数据模型 ───

class _ReferenceItem {
  final int number;
  final String text;
  final int charOffset;
  final bool isNumbered;

  const _ReferenceItem({
    required this.number,
    required this.text,
    required this.charOffset,
    this.isNumbered = true,
  });
}

// ─── 解析工具 ───

/// 从 Markdown 中提取参考文献列表。
///
/// 优先识别编号格式（`1.` / `1)` / `[1]`），无编号时回退到按空行切分的段落模式
/// （适用于 APA 等 Author-Year 格式）。
List<_ReferenceItem> _parseReferences(String markdown) {
  final refHeadingRe = RegExp(
    r'^#{1,3}\s+(?:References|参考文献|Bibliography|Works?\s+Cited)',
    multiLine: true,
    caseSensitive: false,
  );
  final refMatch = refHeadingRe.firstMatch(markdown);
  if (refMatch == null) return [];

  final afterRef = markdown.substring(refMatch.end);
  final nextHeading = RegExp(
    r'^#{1,3}\s+\S',
    multiLine: true,
  ).firstMatch(afterRef);
  final refSection = nextHeading != null
      ? afterRef.substring(0, nextHeading.start)
      : afterRef;

  final numbered = _parseNumberedRefs(refSection, refMatch.end);
  if (numbered.isNotEmpty) return numbered;

  return _parseParagraphRefs(refSection, refMatch.end);
}

List<_ReferenceItem> _parseNumberedRefs(String refSection, int baseOffset) {
  final items = <_ReferenceItem>[];
  // 同时支持 "1. "、"1) " 与 "[1] " 三种前缀
  final refItemRe = RegExp(r'^\s*(?:\[(\d+)\]|(\d+)[.\)])\s+', multiLine: true);
  final matches = refItemRe.allMatches(refSection).toList();

  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final numStr = match.group(1) ?? match.group(2)!;
    final num = int.tryParse(numStr) ?? (i + 1);
    final textStart = match.end;
    final textEnd = i + 1 < matches.length
        ? matches[i + 1].start
        : refSection.length;
    final text = refSection
        .substring(textStart, textEnd)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isNotEmpty) {
      items.add(
        _ReferenceItem(
          number: num,
          text: text,
          charOffset: baseOffset + match.start,
        ),
      );
    }
  }
  return items;
}

List<_ReferenceItem> _parseParagraphRefs(String refSection, int baseOffset) {
  final items = <_ReferenceItem>[];
  // 按空行切分段落：每条引用默认是一个独立段落
  final boundary = RegExp(r'\n[ \t]*\n');
  final matches = boundary.allMatches(refSection).toList();

  final chunks = <({int start, int end})>[];
  int cursor = 0;
  for (final m in matches) {
    chunks.add((start: cursor, end: m.start));
    cursor = m.end;
  }
  chunks.add((start: cursor, end: refSection.length));

  int num = 1;
  for (final chunk in chunks) {
    final raw = refSection.substring(chunk.start, chunk.end);
    final leadingWs = raw.length - raw.trimLeft().length;
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (normalized.length < 20) continue;
    if (!_looksLikeReference(normalized)) continue;

    items.add(
      _ReferenceItem(
        number: num++,
        text: normalized,
        charOffset: baseOffset + chunk.start + leadingWs,
        isNumbered: false,
      ),
    );
  }
  return items;
}

/// 启发式判断一个段落是否像学术引用：含年份括号 / 裸年份 / DOI / URL。
bool _looksLikeReference(String text) {
  return RegExp(
    r'\((?:19|20)\d{2}[a-z]?\)|\b(?:19|20)\d{2}[.,;]|\bdoi[:\s]|https?://',
    caseSensitive: false,
  ).hasMatch(text);
}

// ─── 大纲面板 ───

class OutlinePanel extends StatefulWidget {
  final String markdownContent;
  final String? documentId;
  final Document? document;
  final LocateQuoteInReader? onLocateQuote;
  final void Function(DocumentChatPageArgs args)? onOpenChat;
  final ValueListenable<SummaryImageState> summaryImageState;
  final void Function(int charOffset) onNavigate;
  final VoidCallback? onUploadSummaryImage;

  /// AI 排版修复完成后递增，触发 manifest 重读 + ImageCache evict。
  final ValueListenable<int>? figuresEpoch;

  const OutlinePanel({
    super.key,
    required this.markdownContent,
    this.documentId,
    this.document,
    this.onLocateQuote,
    this.onOpenChat,
    required this.summaryImageState,
    this.figuresEpoch,
    required this.onNavigate,
    this.onUploadSummaryImage,
  });

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<_ReferenceItem> _references;
  List<FigureManifestEntry>? _figures;
  Set<String> _existingImages = const {};
  bool _figuresLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _references = _parseReferences(widget.markdownContent);
    _loadFigures();
    widget.figuresEpoch?.addListener(_loadFigures);
  }

  Future<void> _loadFigures() async {
    if (widget.documentId == null || widget.documentId!.isEmpty) {
      if (mounted) setState(() => _figuresLoaded = true);
      return;
    }
    final all = await FigureExtractService.loadManifest(widget.documentId!);
    // Outline 只展示有 caption 身份的 figure；匿名图留在 manifest 供 AI 补检。
    final figures = all == null ? null : FigureManifestEntry.forDisplay(all);
    // 重新提取会原地覆盖 figures/*.png,但 Flutter 全局 ImageCache 以
    // FileImage(path) 为 key,不感知 mtime,导致 Image.file 还显示旧字节.
    // 显式 evict 这批 path,下次构建时 Image.file 重读磁盘.
    if (figures != null && figures.isNotEmpty) {
      final imageCache = PaintingBinding.instance.imageCache;
      final exists = <String>{};
      for (final fig in figures) {
        imageCache.evict(FileImage(File(fig.imagePath)));
        if (File(fig.imagePath).existsSync()) {
          exists.add(fig.imagePath);
        }
      }
      if (mounted) {
        setState(() {
          _figures = figures;
          _existingImages = exists;
          _figuresLoaded = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _figures = figures;
          _existingImages = const {};
          _figuresLoaded = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant OutlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.figuresEpoch != widget.figuresEpoch) {
      oldWidget.figuresEpoch?.removeListener(_loadFigures);
      widget.figuresEpoch?.addListener(_loadFigures);
    }
  }

  @override
  void dispose() {
    widget.figuresEpoch?.removeListener(_loadFigures);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final content = Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Figures'),
            Tab(text: 'References'),
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
        Divider(height: 1, color: cs.outlineVariant.withAlpha(80)),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ValueListenableBuilder<SummaryImageState>(
                valueListenable: widget.summaryImageState,
                builder: (context, summaryState, _) {
                  return _FiguresTab(
                    figures: _figures,
                    existingImages: _existingImages,
                    loaded: _figuresLoaded,
                    markdownContent: widget.markdownContent,
                    documentId: widget.documentId,
                    document: widget.document,
                    onLocateQuote: widget.onLocateQuote,
                    onOpenChat: widget.onOpenChat,
                    onNavigate: widget.onNavigate,
                    summaryState: summaryState,
                    onUploadSummaryImage: widget.onUploadSummaryImage,
                  );
                },
              ),
              _ReferencesTab(references: _references),
            ],
          ),
        ),
      ],
    );

    // sheet / dock 外壳负责圆角与背景；本组件只出内容。
    return content;
  }
}

// ─── Figures Tab ───

class _FiguresTab extends StatelessWidget {
  final List<FigureManifestEntry>? figures;
  final Set<String> existingImages;
  final bool loaded;
  final String markdownContent;
  final String? documentId;
  final Document? document;
  final LocateQuoteInReader? onLocateQuote;
  final void Function(DocumentChatPageArgs args)? onOpenChat;
  final void Function(int charOffset) onNavigate;
  final SummaryImageState summaryState;
  final VoidCallback? onUploadSummaryImage;

  const _FiguresTab({
    required this.figures,
    required this.existingImages,
    required this.loaded,
    required this.markdownContent,
    this.documentId,
    this.document,
    this.onLocateQuote,
    this.onOpenChat,
    required this.onNavigate,
    required this.summaryState,
    this.onUploadSummaryImage,
  });

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
          strokeWidth: 2,
        ),
      );
    }

    final summaryImagePath = summaryState.imagePath;
    final hasSummary =
        summaryImagePath != null && File(summaryImagePath).existsSync();
    final hasFigures = figures != null && figures!.isNotEmpty;

    // Graphical Summary 栏始终显示（标题 + 添加按钮），即使无图也无 figure。
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const summaryOffset = 1;
    final totalCount = summaryOffset + (hasFigures ? figures!.length : 0);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: totalCount,
      separatorBuilder: (_, _) =>
          Divider(color: cs.outlineVariant.withAlpha(80), height: 32),
      itemBuilder: (context, index) {
        if (index == 0 && summaryOffset == 1) {
          return _buildSummaryBlock(context, theme, cs, hasSummary: hasSummary);
        }
        final figIndex = index - summaryOffset;
        final fig = figures![figIndex];
        final imageExists = existingImages.contains(fig.imagePath);

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fig.captionText,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                  height: 1.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              if (imageExists)
                GestureDetector(
                  onTap: () {
                    Haptics.soft();
                    showFigureViewer(
                      context,
                      figures!,
                      initialIndex: figIndex,
                      documentId: documentId,
                      document: document,
                      onLocateQuote: onLocateQuote,
                      onOpenChat: onOpenChat,
                    );
                  },
                  child: Hero(
                    tag: 'figure_${fig.imagePath}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(fig.imagePath),
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
                    borderRadius: BorderRadius.circular(8),
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
              Row(
                children: [
                  _ActionLink(
                    icon: Symbols.article_rounded,
                    label: context.l10n.viewInDocument,
                    onTap: () => _navigateToFigure(fig),
                  ),
                  const SizedBox(width: 16),
                  if (imageExists)
                    _ActionLink(
                      icon: Symbols.open_in_full_rounded,
                      label: context.l10n.viewOriginalImage,
                      onTap: () => showFigureViewer(
                        context,
                        figures!,
                        initialIndex: figIndex,
                        documentId: documentId,
                        document: document,
                        onLocateQuote: onLocateQuote,
                        onOpenChat: onOpenChat,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryBlock(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs, {
    required bool hasSummary,
  }) {
    final imagePath = summaryState.imagePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行：始终显示，刷新按钮 → 添加按钮（从相册上传）
        Row(
          children: [
            Icon(Symbols.auto_awesome_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              'Graphical Summary',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                height: 1.4,
              ),
            ),
            const Spacer(),
            if (summaryState.generating) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (onUploadSummaryImage != null)
              TactilePress(
                onTap: summaryState.generating
                    ? null
                    : () {
                        onUploadSummaryImage!();
                      },
                baseColor: Colors.transparent,
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Symbols.add_photo_alternate_rounded,
                  size: 18,
                  color: summaryState.generating
                      ? cs.onSurfaceVariant.withAlpha(90)
                      : cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        // 内容区：有图显示图，仅 generating 时显示占位框，否则不渲染
        if (hasSummary && imagePath != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              Haptics.soft();
              final entry = FigureManifestEntry(
                imagePath: imagePath,
                captionText: 'Graphical Summary',
                pageIndex: 0,
                blockIds: const [],
              );
              showFigureViewer(
                context,
                [entry],
                documentId: documentId,
                document: document,
                onLocateQuote: onLocateQuote,
                onOpenChat: onOpenChat,
              );
            },
            child: Hero(
              tag: 'figure_$imagePath',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(imagePath),
                  key: ValueKey('${imagePath}_${summaryState.revision}'),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  cacheWidth: 600,
                ),
              ),
            ),
          ),
        ] else if (summaryState.generating) ...[
          const SizedBox(height: 10),
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
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

  void _navigateToFigure(FigureManifestEntry fig) {
    final fileName = fig.imagePath.split(RegExp(r'[/\\]')).last;
    final idx = markdownContent.indexOf(fileName);
    if (idx >= 0) onNavigate(idx);
  }
}

// ─── References Tab ───

class _ReferencesTab extends ConsumerStatefulWidget {
  final List<_ReferenceItem> references;

  const _ReferencesTab({required this.references});

  @override
  ConsumerState<_ReferencesTab> createState() => _ReferencesTabState();
}

class _ReferencesTabState extends ConsumerState<_ReferencesTab> {
  /// 最近复制的条目索引——行高亮 + check 图标维持 2 秒，给"刚才点中的
  /// 是哪条"明确的指向反馈（透明底上的按压色太弱，单凭它无法定位）。
  int? _copiedIndex;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(int index, _ReferenceItem item) async {
    final text = item.isNumbered ? '[${item.number}] ${item.text}' : item.text;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copiedIndex = index);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedIndex = null);
    });
    // 摘要进 snackbar：让"复制了什么"可确认，不再只报一个编号
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
    final references = widget.references;
    if (references.isEmpty) {
      return _EmptyState(
        icon: Symbols.menu_book_rounded,
        message: context.l10n.referencesNotFound,
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: references.length,
      separatorBuilder: (_, _) =>
          Divider(color: cs.outlineVariant.withAlpha(80), height: 1),
      itemBuilder: (context, index) {
        final item = references[index];
        final copied = index == _copiedIndex;

        return RepaintBoundary(
          child: TactilePress(
            // 复制后的 2 秒高亮复用 TactilePress 内部的 AnimatedContainer
            baseColor: copied
                ? cs.primaryContainer.withAlpha(110)
                : Colors.transparent,
            onTap: () => _copy(index, item),
            borderRadius: BorderRadius.circular(8),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface,
                      height: 1.5,
                    ),
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

// ─── 共享组件 ───

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: cs.onSurfaceVariant.withAlpha(80)),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ActionLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TactilePress(
      onTap: onTap,
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 4),
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
