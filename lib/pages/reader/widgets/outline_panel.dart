import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../../../services/figure_extract_service.dart';

// ─── 数据模型 ───

class OutlineHeading {
  final int level;
  final String title;
  final int charOffset;

  const OutlineHeading({
    required this.level,
    required this.title,
    required this.charOffset,
  });
}

class ReferenceItem {
  final int number;
  final String text;
  final int charOffset;

  const ReferenceItem({
    required this.number,
    required this.text,
    required this.charOffset,
  });
}

// ─── 解析工具 ───

/// 从 Markdown 中提取所有 ATX 标题及其字符偏移
List<OutlineHeading> parseHeadings(String markdown) {
  final headings = <OutlineHeading>[];
  final re = RegExp(r'^(#{1,6})\s+(.+?)(?:\s+#+\s*)?$', multiLine: true);
  for (final match in re.allMatches(markdown)) {
    final title = _stripInlineFormatting(match.group(2)!);
    if (title.isNotEmpty) {
      headings.add(OutlineHeading(
        level: match.group(1)!.length,
        title: title,
        charOffset: match.start,
      ));
    }
  }
  return headings;
}

/// 从 Markdown 中提取参考文献列表（定位 References 标题后按编号切分）
List<ReferenceItem> parseReferences(String markdown) {
  final refHeadingRe = RegExp(
    r'^#{1,3}\s+(?:References|参考文献|Bibliography|Works?\s+Cited)',
    multiLine: true,
    caseSensitive: false,
  );
  final refMatch = refHeadingRe.firstMatch(markdown);
  if (refMatch == null) return [];

  final afterRef = markdown.substring(refMatch.end);
  final nextHeading =
      RegExp(r'^#{1,3}\s+\S', multiLine: true).firstMatch(afterRef);
  final refSection =
      nextHeading != null ? afterRef.substring(0, nextHeading.start) : afterRef;

  final items = <ReferenceItem>[];
  final refItemRe = RegExp(r'^\s*(\d+)[.\)]\s+', multiLine: true);
  final matches = refItemRe.allMatches(refSection).toList();

  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final num = int.tryParse(match.group(1)!) ?? (i + 1);
    final textStart = match.end;
    final textEnd =
        i + 1 < matches.length ? matches[i + 1].start : refSection.length;
    final text = refSection
        .substring(textStart, textEnd)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isNotEmpty) {
      items.add(ReferenceItem(
        number: num,
        text: text,
        charOffset: refMatch.end + match.start,
      ));
    }
  }
  return items;
}

String _stripInlineFormatting(String text) {
  return text
      .replaceAll(RegExp(r'\*{1,3}'), '')
      .replaceAll(RegExp(r'`'), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
      .trim();
}

// ─── 大纲面板 ───

class OutlinePanel extends StatefulWidget {
  final String markdownContent;
  final String? pdfPath;
  final void Function(int charOffset) onNavigate;

  const OutlinePanel({
    super.key,
    required this.markdownContent,
    this.pdfPath,
    required this.onNavigate,
  });

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<OutlineHeading> _headings;
  late final List<ReferenceItem> _references;
  List<FigureManifestEntry>? _figures;
  bool _figuresLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _headings = parseHeadings(widget.markdownContent);
    _references = parseReferences(widget.markdownContent);
    _loadFigures();
  }

  Future<void> _loadFigures() async {
    if (widget.pdfPath == null || widget.pdfPath!.isEmpty) {
      if (mounted) setState(() => _figuresLoaded = true);
      return;
    }
    final figures = await FigureExtractService.loadManifest(widget.pdfPath!);
    if (mounted) {
      setState(() {
        _figures = figures;
        _figuresLoaded = true;
      });
    }
  }

  void _navigateAndClose(int charOffset) {
    Scaffold.of(context).closeEndDrawer();
    widget.onNavigate(charOffset);
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

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Sections'),
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
              _SectionsTab(
                headings: _headings,
                onTap: _navigateAndClose,
              ),
              _FiguresTab(
                figures: _figures,
                loaded: _figuresLoaded,
                markdownContent: widget.markdownContent,
                onNavigate: _navigateAndClose,
              ),
              _ReferencesTab(
                references: _references,
                onTap: _navigateAndClose,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Sections Tab ───

class _SectionsTab extends StatelessWidget {
  final List<OutlineHeading> headings;
  final void Function(int charOffset) onTap;

  const _SectionsTab({required this.headings, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (headings.isEmpty) {
      return const _EmptyState(
        icon: Icons.segment_rounded,
        message: '未找到章节标题',
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: headings.length,
      itemBuilder: (context, index) {
        final h = headings[index];
        final indent = (h.level - 1) * 16.0;
        final isTopLevel = h.level <= 2;

        return InkWell(
          onTap: () => onTap(h.charOffset),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 + indent, 14, 16, 14),
            child: Text(
              h.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.primary,
                fontWeight: isTopLevel ? FontWeight.w600 : FontWeight.normal,
                fontSize: isTopLevel ? 15 : 14,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Figures Tab ───

class _FiguresTab extends StatelessWidget {
  final List<FigureManifestEntry>? figures;
  final bool loaded;
  final String markdownContent;
  final void Function(int charOffset) onNavigate;

  const _FiguresTab({
    required this.figures,
    required this.loaded,
    required this.markdownContent,
    required this.onNavigate,
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
    if (figures == null || figures!.isEmpty) {
      return const _EmptyState(
        icon: Icons.image_not_supported_outlined,
        message: '未找到图表\n请先提取文档',
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: figures!.length,
      separatorBuilder: (_, __) => Divider(
        color: cs.outlineVariant.withAlpha(60),
        height: 32,
      ),
      itemBuilder: (context, index) {
        final fig = figures![index];
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
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            if (imageExists)
              GestureDetector(
                onTap: () => _showViewer(context, fig),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    cacheWidth: 600,
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
                    Icons.broken_image_outlined,
                    color: cs.onSurfaceVariant.withAlpha(120),
                    size: 32,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ActionLink(
                  icon: Icons.article_outlined,
                  label: '在文中查看',
                  onTap: () {
                    final searchText = fig.captionText.substring(
                      0,
                      min(40, fig.captionText.length),
                    );
                    final idx = markdownContent.indexOf(searchText);
                    if (idx >= 0) onNavigate(idx);
                  },
                ),
                const SizedBox(width: 16),
                if (imageExists)
                  _ActionLink(
                    icon: Icons.open_in_full_rounded,
                    label: '查看原图',
                    onTap: () => _showViewer(context, fig),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showViewer(BuildContext context, FigureManifestEntry figure) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FigureViewerPage(figure: figure),
      ),
    );
  }
}

// ─── References Tab ───

class _ReferencesTab extends StatelessWidget {
  final List<ReferenceItem> references;
  final void Function(int charOffset) onTap;

  const _ReferencesTab({required this.references, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (references.isEmpty) {
      return const _EmptyState(
        icon: Icons.menu_book_rounded,
        message: '未找到参考文献',
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: references.length,
      separatorBuilder: (_, __) => Divider(
        color: cs.outlineVariant.withAlpha(40),
        height: 1,
      ),
      itemBuilder: (context, index) {
        final ref = references[index];

        return InkWell(
          onTap: () => onTap(ref.charOffset),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '${ref.number}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    ref.text,
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

// ─── 图片全屏查看器 ───

class _FigureViewerPage extends StatelessWidget {
  final FigureManifestEntry figure;

  const _FigureViewerPage({required this.figure});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.file(
                  File(figure.imagePath),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            color: Colors.black87,
            width: double.infinity,
            child: Text(
              figure.captionText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
