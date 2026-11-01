import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../reader/widgets/reader_icon_button.dart';
import '../reader/widgets/reader_search_bars.dart';
import 'reader_controller.dart';
import 'reader_surface.dart';

/// 新阅读器页面外壳：顶栏（搜索、阅读方式）+ 正文 + 搜索结果导航。
class Reader2Page extends StatefulWidget {
  const Reader2Page({super.key, required this.controller});

  final ReaderController controller;

  @override
  State<Reader2Page> createState() => _Reader2PageState();
}

class _Reader2PageState extends State<Reader2Page> {
  final _surface = GlobalKey<ReaderSurfaceState>();
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  final _focus = FocusNode();
  bool _searching = false;

  ReaderController get _controller => widget.controller;

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queryFocus.requestFocus();
      _query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _query.text.length,
      );
    });
  }

  void _closeSearch() {
    _query.clear();
    _controller.clearSearch();
    setState(() => _searching = false);
    _focus.requestFocus();
  }

  void _toggleMode() {
    _controller.clearSelection();
    _controller.mode = _controller.mode == ReaderMode.scroll
        ? ReaderMode.paged
        : ReaderMode.scroll;
  }

  void _copySelection() {
    if (!_controller.hasSelection) return;
    Clipboard.setData(ClipboardData(text: _controller.selectedText));
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openSearch,
    const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copySelection,
    const SingleActivator(LogicalKeyboardKey.keyC, control: true):
        _copySelection,
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (_searching) {
        _closeSearch();
      } else {
        _controller.clearSelection();
      }
    },
  };

  /// 翻页键只在正文获得焦点时生效，避免搜索框里的空格、方向键被截走。
  Map<ShortcutActivator, VoidCallback> get _pageKeys => {
    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
        _surface.currentState?.turnPage(1),
    const SingleActivator(LogicalKeyboardKey.pageDown): () =>
        _surface.currentState?.turnPage(1),
    const SingleActivator(LogicalKeyboardKey.space): () =>
        _surface.currentState?.turnPage(1),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
        _surface.currentState?.turnPage(-1),
    const SingleActivator(LogicalKeyboardKey.pageUp): () =>
        _surface.currentState?.turnPage(-1),
  };

  Widget _toolbar(BuildContext context) {
    if (_searching) {
      return ReaderPdfSearchBar(
        controller: _query,
        focusNode: _queryFocus,
        hintText: context.l10n.searchContent,
        onBack: _closeSearch,
        onClear: _closeSearch,
        onChanged: _controller.search,
        onSubmitted: (_) => _controller.stepHit(1),
        trailing: _query.text.trim().isEmpty ? null : _searchResults(context),
      );
    }
    final paged = _controller.mode == ReaderMode.paged;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const Spacer(),
          ReaderIconButton(
            icon: Symbols.search_rounded,
            tooltip: context.l10n.searchContent,
            onPressed: _openSearch,
          ),
          ReaderIconButton(
            // 图标表示切换后的方式。
            icon: paged
                ? Symbols.view_day_rounded
                : Symbols.auto_stories_rounded,
            tooltip: paged
                ? context.l10n.verticalPagination
                : context.l10n.horizontalPagination,
            onPressed: _toggleMode,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Column(
              children: [
                _toolbar(context),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: _pageKeys,
                    child: Focus(
                      focusNode: _focus,
                      autofocus: true,
                      child: Listener(
                        onPointerDown: (_) => _focus.requestFocus(),
                        child: ReaderSurface(
                          key: _surface,
                          controller: _controller,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 命中计数与上下跳转，放在搜索栏内，不遮挡正文；无命中时计数标红、按钮禁用。
  Widget _searchResults(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _controller.hits.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '${total == 0 ? 0 : _controller.currentHit + 1}/$total',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: total == 0 ? cs.error : cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Symbols.keyboard_arrow_up_rounded, size: 22),
          tooltip: context.l10n.previousResult,
          onPressed: total == 0 ? null : () => _controller.stepHit(-1),
        ),
        IconButton(
          icon: const Icon(Symbols.keyboard_arrow_down_rounded, size: 22),
          tooltip: context.l10n.nextResult,
          onPressed: total == 0 ? null : () => _controller.stepHit(1),
        ),
      ],
    );
  }
}
