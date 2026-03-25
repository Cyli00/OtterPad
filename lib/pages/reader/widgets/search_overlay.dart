import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../providers/reader_settings_provider.dart';
import '../../../services/reader/markdown_document_cache_service.dart';

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
  final ReaderSettingsState readerSettings;
  final void Function(List<SearchResult> results, int tappedIndex, String query)
  onResultTap;
  final VoidCallback onDismiss;
  final Future<MarkdownSearchSnapshot> searchSnapshotFuture;

  /// 从高亮模式重新搜索时，预填上次查询词
  final String? initialQuery;

  const SearchOverlay({
    super.key,
    required this.readerSettings,
    required this.onResultTap,
    required this.onDismiss,
    required this.searchSnapshotFuture,
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
  bool _loading = false;

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

  // ─── 搜索逻辑 ───

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    final snapshot = await widget.searchSnapshotFuture;
    if (!mounted) return;

    final lowerQuery = query.toLowerCase();
    final results = snapshot.blocks
        .where((block) => block.plainText.toLowerCase().contains(lowerQuery))
        .map(
          (block) => SearchResult(
            heading: block.heading,
            plainText: block.plainText,
            charOffset: block.charOffset,
          ),
        )
        .toList(growable: false);

    setState(() {
      _results = results;
      _hasSearched = true;
      _loading = false;
    });
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 28,
                color: cs.onSurface,
              ),
              tooltip: '返回',
              onPressed: widget.onDismiss,
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
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
              tooltip: '退出搜索',
              onPressed: widget.onDismiss,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme cs) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: cs.primary,
        ),
      );
    }

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
