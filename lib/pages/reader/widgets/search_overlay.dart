import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../providers/reader_settings_provider.dart';
import '../../../services/haptics.dart';
import '../../../services/reader/markdown_document_cache_service.dart';
import '../../../utils/markdown_preprocessor.dart';
import 'reader_background.dart';
import 'md_widget/nr_markdown_config.dart';
import 'md_widget/nr_search_highlight_builder.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/l10n.dart';

/// 全屏搜索遮罩层
///
/// 用户输入搜索词并确认后，以段落为单位展示匹配结果。
/// 搜索结果使用与阅读器正文相同的 Markdown 渲染管线（LaTeX、高亮等）。
class SearchOverlay extends StatefulWidget {
  final ReaderSettingsState readerSettings;
  final void Function(List<SearchResult> results, int tappedIndex, String query)
  onResultTap;
  final VoidCallback onDismiss;
  final MarkdownSearchSnapshot searchSnapshot;
  final String? initialQuery;

  const SearchOverlay({
    super.key,
    required this.readerSettings,
    required this.onResultTap,
    required this.onDismiss,
    required this.searchSnapshot,
    this.initialQuery,
  });

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<SearchResult> _results = [];
  bool _hasSearched = false;

  // 搜索结果渲染资源（与正文共用同一套管线）
  MarkdownConfig? _mdConfig;
  MarkdownGenerator? _mdGenerator;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(widget.initialQuery!);
        _focusNode.requestFocus();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _mdConfig = null;
        _mdGenerator = null;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = widget.searchSnapshot.blocks
        .where((block) => block.plainText.toLowerCase().contains(lowerQuery))
        .map(
          (block) => SearchResult(
            heading: block.heading,
            plainText: block.plainText,
            charOffset: block.charOffset,
          ),
        )
        .toList(growable: false);

    // 构建与正文相同的渲染管线，附加搜索高亮
    final cs = Theme.of(context).colorScheme;
    final searchBuilder = SearchHighlightBuilder(searchQuery: query, cs: cs);

    _mdConfig = buildReaderMarkdownConfig(
      settings: widget.readerSettings,
      colorScheme: cs,
      highlightQuery: query,
    );
    _mdGenerator = buildReaderMarkdownGenerator(
      settings: widget.readerSettings,
      searchRichTextBuilder: searchBuilder.hasHighlights
          ? searchBuilder.call
          : null,
    );

    setState(() {
      _results = results;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.readerSettings;
    final cs = Theme.of(context).colorScheme;
    final safePadding = MediaQuery.of(context).padding;

    return Container(
      color: resolveReaderPalette(settings.theme, cs).background,
      padding: EdgeInsets.only(top: safePadding.top),
      child: Column(
        children: [
          _buildSearchBar(cs),
          Expanded(child: _buildResults(cs)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Symbols.chevron_left_rounded,
                size: 28,
                color: cs.onSurface,
              ),
              tooltip: context.l10n.back,
              onPressed: () {
                Haptics.soft();
                widget.onDismiss();
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(color: cs.onSurface, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchContent,
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant.withAlpha(160),
                      fontSize: 15,
                    ),
                    prefixIcon: Icon(
                      Symbols.search_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Symbols.cancel_rounded,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
                            onPressed: () {
                              Haptics.soft();
                              _controller.clear();
                              setState(() {
                                _results = [];
                                _hasSearched = false;
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: cs.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: _performSearch,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Symbols.close_rounded,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
              tooltip: context.l10n.exitSearch,
              onPressed: () {
                Haptics.soft();
                widget.onDismiss();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme cs) {
    if (!_hasSearched) return const SizedBox.shrink();

    if (_results.isEmpty) {
      return Center(
        child: Text(
          context.l10n.noMatchFound,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.searchMatchesFound(_results.length),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }

        final result = _results[index - 1];
        final showHeading =
            index == 1 || _results[index - 2].heading != result.heading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeading && result.heading.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  result.heading.toUpperCase(),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            _ResultCard(
              markdownText: result.plainText,
              config: _mdConfig!,
              generator: _mdGenerator!,
              cs: cs,
              onTap: () =>
                  widget.onResultTap(_results, index - 1, _controller.text),
            ),
          ],
        );
      },
    );
  }
}

// ─── 搜索结果卡片（复用正文 Markdown 渲染管线） ───

class _ResultCard extends StatelessWidget {
  final String markdownText;
  final MarkdownConfig config;
  final MarkdownGenerator generator;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _ResultCard({
    required this.markdownText,
    required this.config,
    required this.generator,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 与正文相同的预处理：裸 LaTeX 包裹 $...$、上标转 Unicode 等
    final processed = MarkdownPreprocessor.process(markdownText);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Haptics.soft();
            onTap();
          },
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            height: 120,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: ClipRect(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: MarkdownBlock(
                    data: processed,
                    selectable: false,
                    config: config,
                    generator: generator,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
