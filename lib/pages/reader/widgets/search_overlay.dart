import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../providers/reader_settings_provider.dart';
import '../../../services/reader/search_heading_pattern_service.dart';

/// Markdown 内容搜索结果
class SearchResult {
  final String heading;
  final String plainText;
  final int charOffset;

  const SearchResult({
    required this.heading,
    required this.plainText,
    required this.charOffset,
  });
}

/// 全屏搜索遮罩层
///
/// 覆盖在阅读器内容之上，高斯模糊底层视图。
/// 用户输入搜索词并确认后，以段落为单位展示匹配结果。
/// 所有 UI 色调从 MD3 [ColorScheme] 获取。
class SearchOverlay extends StatefulWidget {
  final String markdownContent;
  final ReaderSettingsState readerSettings;
  final void Function(List<SearchResult> results, int tappedIndex, String query)
  onResultTap;
  final VoidCallback onDismiss;

  /// 从高亮模式重新搜索时，预填上次查询词
  final String? initialQuery;

  const SearchOverlay({
    super.key,
    required this.markdownContent,
    required this.readerSettings,
    required this.onResultTap,
    required this.onDismiss,
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
  SearchHeadingPatternConfig? _headingPatternConfig;

  @override
  void initState() {
    super.initState();
    _warmUpHeadingPatterns();
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

  // ─── 搜索逻辑 ───

  Future<void> _warmUpHeadingPatterns() async {
    _headingPatternConfig ??= await SearchHeadingPatternService.load();
  }

  Future<SearchHeadingPatternConfig> _loadHeadingPatternConfig() async {
    final config = _headingPatternConfig;
    if (config != null) return config;
    final loaded = await SearchHeadingPatternService.load();
    _headingPatternConfig = loaded;
    return loaded;
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    final patternConfig = await _loadHeadingPatternConfig();
    if (!mounted) return;
    final blocks = _parseBlocks(widget.markdownContent, patternConfig);
    final lowerQuery = query.toLowerCase();
    final results = <SearchResult>[];

    for (final block in blocks) {
      if (block.plainText.toLowerCase().contains(lowerQuery)) {
        results.add(
          SearchResult(
            heading: block.heading,
            plainText: block.plainText,
            charOffset: block.charOffset,
          ),
        );
      }
    }

    setState(() {
      _results = results;
      _hasSearched = true;
    });
  }

  List<_TextBlock> _parseBlocks(
    String markdown,
    SearchHeadingPatternConfig patternConfig,
  ) {
    final blocks = <_TextBlock>[];
    final lines = markdown.split('\n');
    var currentHeading = '';
    var blockBuffer = StringBuffer();
    var blockStartOffset = 0;
    var currentOffset = 0;

    void flushBlock() {
      if (blockBuffer.isEmpty) return;
      final rawText = blockBuffer.toString().trim();
      if (rawText.isNotEmpty) {
        blocks.add(
          _TextBlock(
            heading: currentHeading,
            plainText: _stripMarkdown(rawText),
            charOffset: blockStartOffset,
          ),
        );
      }
      blockBuffer = StringBuffer();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineLength = line.length + 1;

      if (line.trim().isEmpty) {
        flushBlock();
        currentOffset += lineLength;
        blockStartOffset = currentOffset;
        continue;
      }

      final sectionMarker = _resolveSectionMarker(lines, i, patternConfig);
      if (sectionMarker != null) {
        flushBlock();
        currentHeading = sectionMarker.heading ?? '';
        blockStartOffset = currentOffset;
      }

      if (blockBuffer.isEmpty) {
        blockStartOffset = currentOffset;
      }
      blockBuffer.writeln(line);
      currentOffset += lineLength;
    }

    flushBlock();

    return blocks;
  }

  _SectionMarker? _resolveSectionMarker(
    List<String> lines,
    int index,
    SearchHeadingPatternConfig patternConfig,
  ) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    final candidates = <String>{};
    final atxHeading = patternConfig.atxHeadingPattern.firstMatch(line);
    if (atxHeading != null) {
      candidates.add(atxHeading.group(1)!.trim());
    }

    final nextLine = index + 1 < lines.length ? lines[index + 1].trim() : null;
    if (nextLine != null &&
        patternConfig.setextUnderlinePattern.hasMatch(nextLine)) {
      candidates.add(trimmed);
    }

    if (_canBeStandaloneSectionHeading(trimmed)) {
      candidates.add(trimmed);
    }

    for (final candidate in candidates) {
      final normalized = _normalizeSectionCandidate(candidate, patternConfig);
      if (normalized.isEmpty) continue;

      for (final pattern in patternConfig.headingPatterns) {
        if (pattern.pattern.hasMatch(normalized)) {
          return _SectionMarker.heading(pattern.display);
        }
      }

      if (patternConfig.resetPatterns.any(
        (pattern) => pattern.hasMatch(normalized),
      )) {
        return const _SectionMarker.reset();
      }
    }

    return null;
  }

  bool _canBeStandaloneSectionHeading(String text) {
    if (text.length > 80) return false;
    return !text.contains(RegExp(r'[.!?]'));
  }

  String _normalizeSectionCandidate(
    String raw,
    SearchHeadingPatternConfig patternConfig,
  ) {
    var text = raw.trim();
    text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*'), '');
    text = text.replaceAll(RegExp(r'\s*#*\s*$'), '');
    text = text.replaceAll(RegExp(r'^(?:\*\*?|__?)\s*'), '');
    text = text.replaceAll(RegExp(r'\s*(?:\*\*?|__?)$'), '');
    text = text.replaceAll(RegExp(r'^`+|`+$'), '');
    text = text.replaceAll(patternConfig.numberingPrefixPattern, '');
    text = text.replaceAll(RegExp(r'\s*[:.-]\s*$'), '');
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
    return text.trim();
  }

  static String _stripMarkdown(String text) {
    var result = text;
    result = result.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^[=-]{3,}\s*$', multiLine: true), '');
    result = result.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
      (m) => m.group(1) ?? '',
    );
    result = result.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m.group(1) ?? '',
    );
    result = result.replaceAll(RegExp(r'\*{1,3}([^*]+)\*{1,3}'), r'$1');
    result = result.replaceAll(RegExp(r'_{1,3}([^_]+)_{1,3}'), r'$1');
    result = result.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    result = result.replaceAll(RegExp(r'<[^>]+>'), '');
    result = result.replaceAllMapped(
      RegExp(r'\$([^\$\n]+?)\$'),
      (m) => m.group(1) ?? '',
    );
    result = result.replaceAll(RegExp(r'\n+'), ' ');
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ');
    return result.trim();
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final settings = widget.readerSettings;
    final cs = Theme.of(context).colorScheme;
    final safePadding = MediaQuery.of(context).padding;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        color: settings.backgroundColor.withAlpha(210),
        padding: EdgeInsets.only(top: safePadding.top),
        child: Column(
          children: [
            _buildSearchBar(cs),
            Expanded(child: _buildResults(cs)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(color: cs.onSurface, fontSize: 15),
                decoration: InputDecoration(
                  hintText: '搜索正文内容',
                  hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withAlpha(160),
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.cancel_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () {
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
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onDismiss,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Text(
                '取消',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ColorScheme cs) {
    if (!_hasSearched) return const SizedBox.shrink();

    if (_results.isEmpty) {
      return Center(
        child: Text(
          '未找到匹配内容',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
        ),
      );
    }

    final query = _controller.text;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '找到 ${_results.length} 条匹配',
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
            _ResultListItem(
              text: result.plainText,
              query: query,
              cs: cs,
              onTap: () => widget.onResultTap(_results, index - 1, query),
            ),
          ],
        );
      },
    );
  }
}

// ─── 内部模型 ───

class _TextBlock {
  final String heading;
  final String plainText;
  final int charOffset;

  const _TextBlock({
    required this.heading,
    required this.plainText,
    required this.charOffset,
  });
}

// ─── 搜索结果条目（MD3 列表样式） ───

class _ResultListItem extends StatelessWidget {
  final String text;
  final String query;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _ResultListItem({
    required this.text,
    required this.query,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final snippet = _buildSnippet(text, query, maxLength: 150);
    final textColor = cs.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return cs.primary.withAlpha(20);
            }
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withAlpha(12);
            }
            if (states.contains(WidgetState.focused)) {
              return cs.primary.withAlpha(16);
            }
            return null;
          }),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: _buildHighlightedText(snippet, query, textColor),
          ),
        ),
      ),
    );
  }

  String _buildSnippet(String text, String query, {int maxLength = 150}) {
    if (text.length <= maxLength) return text;

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);

    if (matchIndex < 0) return '${text.substring(0, maxLength)}…';

    var start = (matchIndex - maxLength ~/ 4).clamp(0, text.length);
    var end = (start + maxLength).clamp(0, text.length);

    if (start > 0) {
      final spaceIdx = text.indexOf(' ', start);
      if (spaceIdx > 0 && spaceIdx - start < 20) start = spaceIdx + 1;
    }

    var snippet = text.substring(start, end);
    if (start > 0) snippet = '…$snippet';
    if (end < text.length) snippet = '$snippet…';
    return snippet;
  }

  Widget _buildHighlightedText(String snippet, String query, Color textColor) {
    if (query.isEmpty) {
      return Text(
        snippet,
        style: TextStyle(color: textColor, fontSize: 14, height: 1.6),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    final lowerSnippet = snippet.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var start = 0;

    while (start < snippet.length) {
      final matchIndex = lowerSnippet.indexOf(lowerQuery, start);
      if (matchIndex < 0) {
        spans.add(TextSpan(text: snippet.substring(start)));
        break;
      }
      if (matchIndex > start) {
        spans.add(TextSpan(text: snippet.substring(start, matchIndex)));
      }
      spans.add(
        TextSpan(
          text: snippet.substring(matchIndex, matchIndex + query.length),
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w600,
            backgroundColor: cs.primaryContainer.withAlpha(100),
          ),
        ),
      );
      start = matchIndex + query.length;
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(color: textColor, fontSize: 14, height: 1.6),
        children: spans,
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SectionMarker {
  final String? heading;

  const _SectionMarker._(this.heading);

  const _SectionMarker.heading(String heading) : this._(heading);

  const _SectionMarker.reset() : this._(null);
}
