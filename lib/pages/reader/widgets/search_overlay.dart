import 'package:flutter/material.dart';

import '../../../providers/reader_settings_provider.dart';
import '../../../services/haptics.dart';
import '../../../widgets/tactile_press.dart';
import '../../../services/reader/markdown_document_cache_service.dart';
import 'reader_background.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/l10n.dart';

/// 全屏搜索遮罩层
///
/// 以段落为单位匹配；结果卡展示**以匹配为中心的摘要窗口**（前后各取一段
/// 上下文，纯文本 + 高亮 span），保证高亮必然可见——不再渲染整段 Markdown。
/// 支持 Match Case / Match Whole Word 两个会话级开关。
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

  // 搜索选项（会话级，不持久化）
  bool _matchCase = false;
  bool _wholeWord = false;

  /// 当前结果对应的匹配正则——摘要窗口高亮与命中判定共用，
  /// 保证「搜得到的必高亮」。
  RegExp? _searchRegex;

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

  /// 按当前开关构造匹配正则。Whole word 用「两侧非字母数字」断言而非 \b
  /// ——\b 对 CJK 与重音字符不可靠。
  RegExp _buildSearchRegex(String query) {
    final escaped = RegExp.escape(query);
    final pattern = _wholeWord
        ? '(?<![A-Za-z0-9])$escaped(?![A-Za-z0-9])'
        : escaped;
    return RegExp(pattern, caseSensitive: _matchCase, unicode: true);
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _searchRegex = null;
      });
      return;
    }

    final regex = _buildSearchRegex(query);
    final results = <SearchResult>[];
    for (final block in widget.searchSnapshot.blocks) {
      final m = regex.firstMatch(block.plainText);
      if (m == null) continue;
      results.add(
        SearchResult(
          heading: block.heading,
          plainText: block.plainText,
          charOffset: block.charOffset,
          matchStart: m.start,
          matchLength: m.end - m.start,
        ),
      );
    }

    setState(() {
      _searchRegex = regex;
      _results = results;
      _hasSearched = true;
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
                                _searchRegex = null;
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
              result: result,
              regex: _searchRegex!,
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

// ─── 搜索结果卡片：以匹配为中心的摘要窗口 ───

class _ResultCard extends StatelessWidget {
  final SearchResult result;
  final RegExp regex;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _ResultCard({
    required this.result,
    required this.regex,
    required this.cs,
    required this.onTap,
  });

  /// 匹配前保留的上下文字符数 / 窗口总长上限
  static const _kLeadContext = 60;
  static const _kWindowLength = 220;

  /// 截取以首个匹配为中心的窗口；起止尽量贴到空格边界（±12 字内）。
  String _snippetWindow() {
    final text = result.plainText;
    final start = result.matchStart < 0 ? 0 : result.matchStart;

    var winStart = (start - _kLeadContext).clamp(0, text.length);
    var winEnd = (winStart + _kWindowLength).clamp(0, text.length);

    // 贴词边界：避免窗口边缘切出半个单词
    if (winStart > 0) {
      final sp = text.indexOf(' ', winStart);
      if (sp >= 0 && sp - winStart <= 12) winStart = sp + 1;
    }
    if (winEnd < text.length) {
      final sp = text.lastIndexOf(' ', winEnd);
      if (sp > winStart && winEnd - sp <= 12) winEnd = sp;
    }

    final prefix = winStart > 0 ? '…' : '';
    final suffix = winEnd < text.length ? '…' : '';
    return '$prefix${text.substring(winStart, winEnd)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final snippet = _snippetWindow();

    // 在窗口文本内高亮所有命中（与搜索共用同一 RegExp）
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in regex.allMatches(snippet)) {
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
