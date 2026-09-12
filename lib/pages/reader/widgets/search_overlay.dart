import 'dart:async';

import 'package:flutter/material.dart';

import '../../../providers/reader_settings_provider.dart';
import '../../../services/haptics.dart';
import '../../../widgets/tactile_press.dart';
import '../../../core/l10n.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'reader_background.dart';
import 'reader_js_bridge.dart';

/// 全屏搜索遮罩层
///
/// 搜索在 WebView JS 端执行（TreeWalker + mark 元素），结果通过 channel
/// 返回到 Dart 端做 UI 展示。点击第 N 条结果时直接调用
/// `scrollToSearchResult(N)` 精确定位。
class SearchOverlay extends StatefulWidget {
  final ReaderSettingsState readerSettings;
  final Future<List<SearchHit>> Function(
    String query, {
    bool caseSensitive,
    bool wholeWord,
  }) onSearch;
  final void Function(int hitIndex, String query) onResultTap;
  final VoidCallback onDismiss;
  final String? initialQuery;

  const SearchOverlay({
    super.key,
    required this.readerSettings,
    required this.onSearch,
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
  List<SearchHit> _results = [];
  bool _hasSearched = false;
  bool _searching = false;

  bool _matchCase = false;
  bool _wholeWord = false;

  Timer? _debounce;

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
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  RegExp _buildHighlightRegex(String query) {
    final escaped = RegExp.escape(query);
    final pattern = _wholeWord
        ? '(?<![A-Za-z0-9])$escaped(?![A-Za-z0-9])'
        : escaped;
    return RegExp(pattern, caseSensitive: _matchCase, unicode: true);
  }

  void _onQueryChanged(String query) {
    setState(() {});
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    final results = await widget.onSearch(
      query,
      caseSensitive: _matchCase,
      wholeWord: _wholeWord,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _hasSearched = true;
      _searching = false;
    });
  }

  void _toggleOption(void Function() flip) {
    Haptics.soft();
    setState(flip);
    if (_controller.text.isNotEmpty) {
      _performSearch(_controller.text);
    }
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
                fill: 1,
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
                      fill: 1,
                      color: cs.onSurfaceVariant,
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Symbols.cancel_rounded,
                              size: 18,
                              fill: 1,
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
                  onChanged: _onQueryChanged,
                ),
              ),
            ),
            const SizedBox(width: 2),
            _OptionToggle(
              icon: Symbols.match_case_rounded,
              tooltip: context.l10n.matchCase,
              active: _matchCase,
              cs: cs,
              onTap: () => _toggleOption(() => _matchCase = !_matchCase),
            ),
            _OptionToggle(
              icon: Symbols.match_word_rounded,
              tooltip: context.l10n.matchWholeWord,
              active: _wholeWord,
              cs: cs,
              onTap: () => _toggleOption(() => _wholeWord = !_wholeWord),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme cs) {
    if (_searching) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: cs.primary,
          ),
        ),
      );
    }

    if (!_hasSearched) return const SizedBox.shrink();

    if (_results.isEmpty) {
      return Center(
        child: Text(
          context.l10n.noMatchFound,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
        ),
      );
    }

    final highlightRegex = _buildHighlightRegex(_controller.text);

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

        final hit = _results[index - 1];
        final showHeading =
            index == 1 || _results[index - 2].heading != hit.heading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeading && hit.heading.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  hit.heading.toUpperCase(),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            _ResultCard(
              hit: hit,
              highlightRegex: highlightRegex,
              cs: cs,
              onTap: () => widget.onResultTap(hit.hitIndex, _controller.text),
            ),
          ],
        );
      },
    );
  }
}

// ─── 搜索选项开关钮 ───

class _OptionToggle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _OptionToggle({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        size: 22,
        fill: 1,
        color: active ? cs.primary : cs.onSurfaceVariant,
      ),
      tooltip: tooltip,
      isSelected: active,
      style: IconButton.styleFrom(
        backgroundColor: active
            ? cs.primaryContainer.withAlpha(120)
            : Colors.transparent,
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
      onPressed: onTap,
    );
  }
}

// ─── 搜索结果卡片 ───

class _ResultCard extends StatelessWidget {
  final SearchHit hit;
  final RegExp highlightRegex;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _ResultCard({
    required this.hit,
    required this.highlightRegex,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final snippet = hit.snippet;
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in highlightRegex.allMatches(snippet)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: snippet.substring(cursor, m.start)));
      }
      spans.add(
        TextSpan(
          text: snippet.substring(m.start, m.end),
          style: TextStyle(
            backgroundColor: cs.primary.withAlpha(70),
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = m.end;
    }
    if (cursor < snippet.length) {
      spans.add(TextSpan(text: snippet.substring(cursor)));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TactilePress(
        baseColor: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text.rich(
              TextSpan(children: spans),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14.5,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
