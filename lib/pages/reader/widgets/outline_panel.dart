import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../providers/summary_image_provider.dart';
import '../../../services/figure_extract_service.dart';
import 'figure_viewer.dart';
import 'package:material_symbols_icons/symbols.dart';

// ─── 数据模型 ───

class ReferenceItem {
  final int number;
  final String text;
  final int charOffset;
  final bool isNumbered;

  const ReferenceItem({
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
List<ReferenceItem> parseReferences(String markdown) {
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

List<ReferenceItem> _parseNumberedRefs(String refSection, int baseOffset) {
  final items = <ReferenceItem>[];
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
        ReferenceItem(
          number: num,
          text: text,
          charOffset: baseOffset + match.start,
        ),
      );
    }
  }
  return items;
}

List<ReferenceItem> _parseParagraphRefs(String refSection, int baseOffset) {
  final items = <ReferenceItem>[];
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
      ReferenceItem(
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
  final ValueListenable<SummaryImageState> summaryImageState;
  final void Function(int charOffset) onNavigate;
  final VoidCallback? onRegenerateSummary;

  /// true: 嵌入 bottom sheet（外壳由 caller 提供圆角+drag handle，本组件不再加
  /// Scaffold/SafeArea-top，避免双层背景盖住 sheet 顶部圆角）。
  /// false: 作为 Drawer 内容渲染，自带 Scaffold + SafeArea(top: true)。
  final bool inSheet;

  const OutlinePanel({
    super.key,
    required this.markdownContent,
    this.documentId,
    required this.summaryImageState,
    required this.onNavigate,
    this.onRegenerateSummary,
    this.inSheet = false,
  });

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<ReferenceItem> _references;
  List<FigureManifestEntry>? _figures;
  bool _figuresLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _references = parseReferences(widget.markdownContent);
    _loadFigures();
  }

  Future<void> _loadFigures() async {
    if (widget.documentId == null || widget.documentId!.isEmpty) {
      if (mounted) setState(() => _figuresLoaded = true);
      return;
    }
    final figures = await FigureExtractService.loadManifest(widget.documentId!);
    // 重新提取会原地覆盖 figures/*.png,但 Flutter 全局 ImageCache 以
    // FileImage(path) 为 key,不感知 mtime,导致 Image.file 还显示旧字节.
    // 显式 evict 这批 path,下次构建时 Image.file 重读磁盘.
    if (figures != null && figures.isNotEmpty) {
      final imageCache = PaintingBinding.instance.imageCache;
      for (final fig in figures) {
        imageCache.evict(FileImage(File(fig.imagePath)));
      }
    }
    if (mounted) {
      setState(() {
        _figures = figures;
        _figuresLoaded = true;
      });
    }
  }

  @override
  void dispose() {
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
                    loaded: _figuresLoaded,
                    markdownContent: widget.markdownContent,
                    onNavigate: widget.onNavigate,
                    summaryState: summaryState,
                    onRegenerateSummary: widget.onRegenerateSummary,
                  );
                },
              ),
              _ReferencesTab(references: _references),
            ],
          ),
        ),
      ],
    );

    // Sheet 模式：外层由 caller 提供圆角 + drag handle + 背景，本组件只负责内容。
    // SafeArea(top: false) 因为 sheet 不接触 status bar；bottom: false 留给内层 ListView
    // 的 viewPadding 处理（_FiguresTab/_ReferencesTab 的 ListView padding 都已含
    // MediaQuery.padding.bottom）。
    if (widget.inSheet) {
      return content;
    }

    return Scaffold(
      backgroundColor: cs.surface,
      // SafeArea 必须显式加：Drawer 内嵌 Scaffold 时 Drawer 自带的 inset 不会
      // 透传到嵌套 Scaffold 的 body，TabBar 会侵占 Android 透明状态栏。
      // bottom: false——drawer 自己处理底部 inset + 内层 ListView 自带 viewPadding。
      body: SafeArea(top: true, bottom: false, child: content),
    );
  }
}

// ─── Figures Tab ───

class _FiguresTab extends StatelessWidget {
  final List<FigureManifestEntry>? figures;
  final bool loaded;
  final String markdownContent;
  final void Function(int charOffset) onNavigate;
  final SummaryImageState summaryState;
  final VoidCallback? onRegenerateSummary;

  const _FiguresTab({
    required this.figures,
    required this.loaded,
    required this.markdownContent,
    required this.onNavigate,
    required this.summaryState,
    this.onRegenerateSummary,
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

    if (!summaryState.generating && !hasSummary && !hasFigures) {
      return const _EmptyState(
        icon: Symbols.image_not_supported,
        message: '未找到图表\n请先提取文档',
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final summaryOffset = (summaryState.generating || hasSummary) ? 1 : 0;
    final totalCount = summaryOffset + (hasFigures ? figures!.length : 0);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: totalCount,
      separatorBuilder: (_, _) =>
          Divider(color: cs.outlineVariant.withAlpha(60), height: 32),
      itemBuilder: (context, index) {
        if (index == 0 && summaryOffset == 1) {
          return _buildSummaryBlock(context, theme, cs, hasSummary: hasSummary);
        }
        final figIndex = index - summaryOffset;
        final fig = figures![figIndex];
        final imageFile = File(fig.imagePath);
        final imageExists = imageFile.existsSync();

        return Column(
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
                onTap: () =>
                    showFigureViewer(context, figures!, initialIndex: figIndex),
                child: Hero(
                  tag: 'figure_${fig.imagePath}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      imageFile,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      cacheWidth: 600,
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
                    Symbols.broken_image,
                    color: cs.onSurfaceVariant.withAlpha(120),
                    size: 32,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ActionLink(
                  icon: Symbols.article,
                  label: '在文中查看',
                  onTap: () => _navigateToFigure(fig),
                ),
                const SizedBox(width: 16),
                if (imageExists)
                  _ActionLink(
                    icon: Symbols.open_in_full_rounded,
                    label: '查看原图',
                    onTap: () => showFigureViewer(
                      context,
                      figures!,
                      initialIndex: figIndex,
                    ),
                  ),
              ],
            ),
          ],
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
            if (onRegenerateSummary != null)
              GestureDetector(
                onTap: summaryState.generating ? null : onRegenerateSummary,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Symbols.refresh_rounded,
                    size: 18,
                    color: summaryState.generating
                        ? cs.onSurfaceVariant.withAlpha(90)
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (hasSummary && imagePath != null)
          GestureDetector(
            onTap: () {
              final entry = FigureManifestEntry(
                imagePath: imagePath,
                captionText: 'Graphical Summary',
                pageIndex: 0,
                blockIds: const [],
              );
              showFigureViewer(context, [entry]);
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
          )
        else
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              summaryState.generating ? '正在生成总结图…' : '暂无总结图',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
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

class _ReferencesTab extends StatelessWidget {
  final List<ReferenceItem> references;

  const _ReferencesTab({required this.references});

  @override
  Widget build(BuildContext context) {
    if (references.isEmpty) {
      return const _EmptyState(
        icon: Symbols.menu_book_rounded,
        message: '未找到参考文献',
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: references.length,
      separatorBuilder: (_, _) =>
          Divider(color: cs.outlineVariant.withAlpha(40), height: 1),
      itemBuilder: (context, index) {
        final item = references[index];

        return InkWell(
          onTap: () {
            final text = item.isNumbered
                ? '[${item.number}] ${item.text}'
                : item.text;
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  elevation: 6,
                  duration: const Duration(seconds: 2),
                  content: Text(
                    '已复制参考文献 ${item.number}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
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
    return GestureDetector(
      onTap: onTap,
      child: Padding(
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
      ),
    );
  }
}
