import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/figure_extract_service.dart';
import 'figure_viewer.dart';
import 'package:material_symbols_icons/symbols.dart';

// ─── 数据模型 ───

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

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
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
                _FiguresTab(
                  figures: _figures,
                  loaded: _figuresLoaded,
                  markdownContent: widget.markdownContent,
                  onNavigate: _navigateAndClose,
                ),
                _ReferencesTab(references: _references),
              ],
            ),
          ),
        ],
      ),
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
        icon: Symbols.image_not_supported,
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
            // 标题（最多1行）
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
            // 图片
            if (imageExists)
              GestureDetector(
                onTap: () => showFigureViewer(context, figures!, initialIndex: index),
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
            // 操作按钮
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
                    onTap: () => showFigureViewer(context, figures!, initialIndex: index),
                  ),
              ],
            ),
          ],
        );
      },
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
      separatorBuilder: (_, __) => Divider(
        color: cs.outlineVariant.withAlpha(40),
        height: 1,
      ),
      itemBuilder: (context, index) {
        final item = references[index];

        return InkWell(
          onTap: () {
            final text = '[${item.number}] ${item.text}';
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                elevation: 6,
                duration: const Duration(seconds: 2),
                content: Text(
                  '已复制参考文献 ${item.number}',
                  style: const TextStyle(fontSize: 14),
                ),
              ));
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

