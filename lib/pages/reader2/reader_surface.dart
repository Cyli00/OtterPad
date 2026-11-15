import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/book/highlight.dart';
import '../../services/haptics.dart';
import '../../src/rust/api/document.dart';
import '../../src/rust/document.dart';
import '../../utils/desktop.dart';
import '../reader/widgets/figure_viewer.dart';
import '../reader/widgets/reader_typography.dart';
import '../reader/widgets/selection_toolbar.dart';
import 'reader_controller.dart';
import 'reader_layout.dart';

/// 新阅读器正文：Flutter 原生排版，滚动与分页两种模式共用一次测量。
class ReaderSurface extends StatefulWidget {
  const ReaderSurface({
    super.key,
    required this.controller,
    this.fontSize = 17,
    this.maxColumnWidth = 720,
    this.onTranslate,
    this.onAskAi,
    this.onCopy,
    this.onFigureTap,
    this.onTapBlank,
    this.onLocationChanged,
    this.textStyle,
    this.translationStyle = 'themed',
  });

  final ReaderController controller;

  /// 叠加在正文样式上的字体与颜色（阅读器主题）。
  final TextStyle? textStyle;

  /// 译文显示样式 id；`blur` 时译文模糊，点击切换显示。
  final String translationStyle;
  final double fontSize;
  final double maxColumnWidth;

  /// 选区菜单的「翻译」：选中文字、选区外接矩形（全局坐标），以及把译文存为笔记的回调
  /// （点开的标注更新该标注，否则按选区新建）。
  final void Function(
    String text,
    Rect anchor,
    void Function(String color, String note) addNote,
  )?
  onTranslate;

  /// 选区菜单的「问 AI」：文字与其锚点。
  final void Function(String text, List<AnchorRange> anchor)? onAskAi;

  /// 选区菜单的「复制」；为 null 时直接写入剪贴板。
  final void Function(String text)? onCopy;

  /// 点击图块。
  final void Function(Block block)? onFigureTap;

  /// 点击没有标注的正文或空白处，供页面切换工具栏。
  final VoidCallback? onTapBlank;

  /// 阅读位置变化：位置与 0–1 的进度。
  final void Function(ReaderLocation location, double progress)?
  onLocationChanged;

  @override
  State<ReaderSurface> createState() => ReaderSurfaceState();
}

class ReaderSurfaceState extends State<ReaderSurface> {
  static const _highlightAlpha = 77;
  static const _scrollPadding = 24.0;
  static const _pagePadding = 28.0;

  final _typesetter = ReaderTypesetter();
  final _targets = <_HitWindowState>{};
  ReaderLayout? _layout;

  /// 模糊样式下已点开的译文块 id；换样式时清空。
  final _revealed = <String>{};
  ReaderMode? _builtMode;
  ScrollController? _scroll;
  PageController? _pages;
  ReaderContextMenuHandle? _menu;

  /// 菜单针对的已有标注；为 null 时菜单针对选区。
  ReaderHighlight? _menuHighlight;
  SearchHit? _revealedHit;
  bool _restorePending = false;

  /// 滚动模式下视口顶部那一行已滚过的比例，见 [ReaderLayout.anchorAtScroll]。
  double _lineFraction = 0;
  DateTime _lastWheelTurn = DateTime(0);

  ReaderController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(ReaderSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.translationStyle != widget.translationStyle) {
      _revealed.clear();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _menu?.remove();
    _scroll?.dispose();
    _pages?.dispose();
    _typesetter.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final hit = _controller.activeHit;
    if (hit != null && hit != _revealedHit) {
      _revealedHit = hit;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => reveal(ReaderLocation(hit.blockIndex, hit.start)),
      );
    } else if (hit == null) {
      _revealedHit = null;
    }
    if (!_controller.hasSelection && _menuHighlight == null) _closeMenu();
    setState(() {});
  }

  // ── 排版与定位 ──

  ReaderLayoutSpec _spec(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final horizontal = isDesktopOs ? 32.0 : 20.0;
    final width = math.max(
      120.0,
      math.min(widget.maxColumnWidth, constraints.maxWidth - horizontal * 2),
    );
    final body = (theme.textTheme.bodyLarge ?? const TextStyle())
        .copyWith(
          fontSize: MediaQuery.textScalerOf(context).scale(widget.fontSize),
          height: ReaderTypography.bodyHeight,
          letterSpacing: 0,
          color: cs.onSurface,
        )
        .merge(widget.textStyle);
    return ReaderLayoutSpec(
      width: width.floorToDouble(),
      pageHeight: math.max(
        body.fontSize! * 3,
        constraints.maxHeight - _pagePadding * 2,
      ),
      body: body,
      mutedColor: cs.onSurfaceVariant,
      linkColor: cs.primary,
      ruleColor: cs.outlineVariant,
      rtlTranslations: _controller.rtlTranslations,
      translationStyle: widget.translationStyle,
    );
  }

  ReaderLayout _layoutFor(ReaderLayoutSpec spec) {
    final current = _layout;
    if (current != null &&
        current.spec == spec &&
        identical(current.model, _controller.model)) {
      return current;
    }
    final watch = Stopwatch()..start();
    final layout = _typesetter.layout(_controller.model, spec);
    if (kDebugMode || kProfileMode) {
      debugPrint(
        '[reader2] layout ${layout.items.length} items, '
        '${layout.pages.length} pages in ${watch.elapsedMilliseconds}ms',
      );
    }
    _layout = layout;
    _restorePending = current != null;
    return layout;
  }

  /// 把 [location] 移入可视区域；滚动模式下已可见则不动。
  void reveal(ReaderLocation location) {
    final layout = _layout;
    if (layout == null) return;
    switch (_controller.mode) {
      case ReaderMode.scroll:
        final scroll = _scroll;
        if (scroll == null || !scroll.hasClients) return;
        final position = scroll.position;
        final y = _scrollPadding + layout.scrollOf(location);
        final viewport = position.viewportDimension;
        if (y >= position.pixels + viewport * .1 &&
            y <= position.pixels + viewport * .8) {
          return;
        }
        scroll.jumpTo((y - viewport * .3).clamp(0, position.maxScrollExtent));
      case ReaderMode.paged:
        final pages = _pages;
        if (pages == null || !pages.hasClients) return;
        pages.jumpToPage(layout.pageOf(location));
    }
  }

  void _restore() {
    if (!_restorePending || !mounted) return;
    _restorePending = false;
    final layout = _layout!;
    final location = _controller.location;
    switch (_controller.mode) {
      case ReaderMode.scroll:
        final scroll = _scroll;
        if (scroll == null || !scroll.hasClients) return;
        scroll.jumpTo(
          (_scrollPadding + layout.scrollOf(location, fraction: _lineFraction))
              .clamp(0, scroll.position.maxScrollExtent),
        );
      case ReaderMode.paged:
        final pages = _pages;
        if (pages == null || !pages.hasClients) return;
        pages.jumpToPage(layout.pageOf(location));
    }
  }

  /// 换模式时按当前阅读位置新建控制器，使新视图首帧即落在原位置。
  void _syncControllers(ReaderLayout layout) {
    final mode = _controller.mode;
    if (mode == _builtMode) return;
    _builtMode = mode;
    final location = _controller.location;
    final oldScroll = _scroll;
    final oldPages = _pages;
    _scroll = null;
    _pages = null;
    switch (mode) {
      case ReaderMode.scroll:
        _scroll = ScrollController(
          initialScrollOffset:
              _scrollPadding +
              layout.scrollOf(location, fraction: _lineFraction),
        );
      case ReaderMode.paged:
        _pages = PageController(initialPage: layout.pageOf(location));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldScroll?.dispose();
      oldPages?.dispose();
    });
  }

  void turnPage(int delta) {
    final pages = _pages;
    if (pages == null || !pages.hasClients) return;
    final target = (pages.page?.round() ?? 0) + delta;
    if (target < 0 || target >= (_layout?.pages.length ?? 0)) return;
    pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  // ── 命中与选区 ──

  /// 全局坐标对应的文本位置；落在文本项之间或之外时取最近的可见文本项。
  ReaderLocation? _locate(Offset global) {
    _HitWindowState? best;
    var bestDistance = double.infinity;
    Rect? bestRect;
    for (final target in _targets) {
      final rect = target.globalRect;
      if (rect == null) continue;
      final dy = global.dy < rect.top
          ? rect.top - global.dy
          : (global.dy > rect.bottom ? global.dy - rect.bottom : 0.0);
      final dx = global.dx < rect.left
          ? rect.left - global.dx
          : (global.dx > rect.right ? global.dx - rect.right : 0.0);
      final distance = dy * 10000 + dx;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = target;
        bestRect = rect;
      }
    }
    final paragraph = best?.paragraph;
    if (best == null || paragraph == null || bestRect == null) return null;
    final item = best.widget.item;
    var local = paragraph.globalToLocal(global);
    final top = best.widget.windowTop;
    final bottom = top + bestRect.height;
    if (global.dy < bestRect.top) {
      local = Offset(0, top + 1);
    } else if (global.dy > bestRect.bottom) {
      local = Offset(paragraph.size.width, bottom - 1);
    }
    final position = paragraph.getPositionForOffset(local);
    return ReaderLocation(item.blockIndex, item.map!.toText(position.offset));
  }

  (ReaderLocation, ReaderLocation)? _wordAt(Offset global) {
    final location = _locate(global);
    if (location == null) return null;
    for (final target in _targets) {
      final item = target.widget.item;
      final paragraph = target.paragraph;
      if (item.blockIndex != location.blockIndex || paragraph == null) continue;
      final map = item.map!;
      final range = paragraph.getWordBoundary(
        TextPosition(offset: map.toPainter(location.offset)),
      );
      final start = map.toText(range.start);
      final end = map.toText(range.end);
      if (end <= start) break;
      return (
        ReaderLocation(item.blockIndex, start),
        ReaderLocation(item.blockIndex, end),
      );
    }
    return (location, location);
  }

  /// 块内区间 (块序号, 起, 止) 在屏幕上的外接矩形（全局坐标），供菜单定位。
  Rect? _rangesRect(Iterable<(int, int, int)> spans) {
    final ranges = <int, List<(int, int)>>{};
    for (final (i, s, e) in spans) {
      ranges.putIfAbsent(i, () => []).add((s, e));
    }
    Rect? rect;
    for (final target in _targets) {
      final item = target.widget.item;
      final paragraph = target.paragraph;
      final window = target.globalRect;
      if (paragraph == null || window == null) continue;
      for (final range in ranges[item.blockIndex] ?? const <(int, int)>[]) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: item.map!.toPainter(range.$1),
            extentOffset: item.map!.toPainter(range.$2),
          ),
        );
        for (final box in boxes) {
          final global = MatrixUtils.transformRect(
            paragraph.getTransformTo(null),
            box.toRect(),
          ).intersect(window);
          if (global.height <= 0 || global.width <= 0) continue;
          rect = rect == null ? global : rect.expandToInclude(global);
        }
      }
    }
    return rect;
  }

  /// 菜单锚点：点开的标注，否则为当前选区。
  Rect? _menuRect() {
    final highlight = _menuHighlight;
    return _rangesRect(
      highlight == null
          ? _controller.selectedRanges
          : _controller.highlightRanges(highlight.id),
    );
  }

  void _closeMenu() {
    final menu = _menu;
    _menu = null;
    _menuHighlight = null;
    menu?.remove();
  }

  Highlight _legacy(ReaderHighlight h) => Highlight(
    id: h.id,
    documentId: '',
    text: h.text,
    note: h.note,
    color: h.color,
    createdAt: h.createdAt,
  );

  /// [existing] 为点开的已有标注：与 0.1.x 一致不进入选区，菜单锚定在标注上。
  void _showMenu({ReaderHighlight? existing}) {
    _closeMenu();
    _menuHighlight = existing;
    final rect = _menuRect();
    if (rect == null) {
      _menuHighlight = null;
      return;
    }
    final controller = _controller;
    final text = existing?.text ?? controller.selectedText;
    // 关闭菜单会清除选区；翻译弹窗稍后「加入笔记」时按这里取出的锚点建标注。
    final anchors = existing?.ranges ?? controller.selectionAnchors;
    _menu = showReaderContextMenu(
      context: context,
      selectionRect: rect,
      selectedText: text,
      existingHighlight: existing == null ? null : _legacy(existing),
      onHighlight: (color) {
        if (existing != null) {
          controller.updateHighlight(existing.copyWith(color: color));
        } else {
          controller.highlightSelection(color);
        }
      },
      onCopy: () {
        controller.clearSelection();
        final copy = widget.onCopy;
        if (copy != null) {
          copy(text);
        } else {
          Clipboard.setData(ClipboardData(text: text));
        }
      },
      onTranslate: () => widget.onTranslate?.call(text, rect, (color, note) {
        final current = existing == null
            ? null
            : controller.highlights
                  .where((h) => h.id == existing.id)
                  .firstOrNull;
        if (current != null) {
          controller.updateHighlight(
            current.copyWith(color: color, note: note),
          );
        } else if (existing == null) {
          controller.addHighlight(anchors, color, note: note);
        }
      }),
      onAskAi: () {
        controller.clearSelection();
        widget.onAskAi?.call(text, anchors);
      },
      onCreateForNote: () {
        final created =
            existing ?? controller.highlightSelection(kDefaultHighlightColor);
        return created == null ? null : _legacy(created);
      },
      onNoteChanged: (id, note) {
        final h = controller.highlights.where((h) => h.id == id).firstOrNull;
        if (h != null) controller.updateHighlight(h.copyWith(note: note));
      },
      onDelete: existing == null
          ? null
          : () => controller.removeHighlight(existing.id),
      onDismiss: () {
        _menu = null;
        _menuHighlight = null;
        controller.clearSelection();
      },
    );
  }

  void _onTapUp(TapUpDetails details) {
    if (_menu != null || _controller.hasSelection) {
      _closeMenu();
      _controller.clearSelection();
      return;
    }
    final location = _locate(details.globalPosition);
    if (location != null && widget.translationStyle == 'blur') {
      final block = _controller.model.blocks[location.blockIndex];
      if (isTranslationBlock(block)) {
        setState(() {
          if (!_revealed.remove(block.id)) _revealed.add(block.id);
        });
        return;
      }
    }
    final highlight = location == null
        ? null
        : _controller.highlightAt(location);
    if (highlight == null) {
      widget.onTapBlank?.call();
      return;
    }
    _showMenu(existing: highlight);
  }

  Map<Type, GestureRecognizerFactory> get _gestures => {
    TapGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (r) => r.onTapUp = _onTapUp,
        ),
    // 鼠标拖选；触摸拖动仍交给滚动或翻页。
    PanGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
          () => PanGestureRecognizer(
            supportedDevices: const {PointerDeviceKind.mouse},
          )..dragStartBehavior = DragStartBehavior.down,
          (r) => r
            ..onStart = (d) {
              _closeMenu();
              final at = _locate(d.globalPosition);
              if (at != null) _controller.select(at, at);
            }
            ..onUpdate = (d) {
              final at = _locate(d.globalPosition);
              if (at != null) _controller.extendSelection(at);
            }
            ..onEnd = (_) {
              if (_controller.hasSelection) _showMenu();
            },
        ),
    // 触摸长按选词，按住拖动扩展。
    LongPressGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
            },
          ),
          (r) => r
            ..onLongPressStart = (d) {
              _closeMenu();
              final word = _wordAt(d.globalPosition);
              if (word == null) return;
              Haptics.light();
              _controller.select(word.$1, word.$2);
            }
            ..onLongPressMoveUpdate = (d) {
              final at = _locate(d.globalPosition);
              if (at != null) _controller.extendSelection(at);
            }
            ..onLongPressEnd = (_) {
              if (_controller.hasSelection) _showMenu();
            },
        ),
  };

  // ── 构建 ──

  List<TextMark> _marks(int blockIndex) {
    final cs = Theme.of(context).colorScheme;
    return _controller.marksFor(
      blockIndex,
      highlight: (hex) => Color(
        int.parse(hex, radix: 16) | 0xFF000000,
      ).withAlpha(_highlightAlpha),
      hit: cs.tertiaryContainer,
      activeHit: cs.tertiary.withAlpha(110),
      selection: cs.primary.withAlpha(56),
    );
  }

  Widget _item(ReaderLayout layout, int index, {double windowTop = 0}) {
    final item = layout.items[index];
    final block = _controller.model.blocks[item.blockIndex];
    final spec = layout.spec;
    switch (item.kind) {
      case ItemKind.text:
        return _HitWindow(
          key: ValueKey(('hit', index, windowTop)),
          item: item,
          windowTop: windowTop,
          registry: _targets,
          builder: (key) => _TextItem(
            paragraphKey: key,
            block: block,
            item: item,
            spec: spec,
            typesetter: _typesetter,
            marks: _marks(item.blockIndex),
            blurred:
                widget.translationStyle == 'blur' &&
                isTranslationBlock(block) &&
                !_revealed.contains(block.id),
          ),
        );
      case ItemKind.figure:
        final figure = _Figure(size: item.mediaSize!, image: item.image);
        final onTap = widget.onFigureTap;
        if (onTap == null) return figure;
        return MouseRegion(
          cursor: SystemMouseCursors.zoomIn,
          child: GestureDetector(onTap: () => onTap(block), child: figure),
        );
      case ItemKind.equation:
        return SizedBox(
          height: item.height,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _typesetter.mathWidget(
                block.runs.first.math!,
                display: true,
                style: spec.body,
              ),
            ),
          ),
        );
      case ItemKind.table:
        return _typesetter.table(block, spec);
    }
  }

  Widget _scrollView(ReaderLayout layout) {
    final items = layout.items;
    final spec = layout.spec;
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.depth == 0) {
          final (location, fraction) = layout.anchorAtScroll(
            n.metrics.pixels - _scrollPadding,
          );
          _controller.location = location;
          _lineFraction = fraction;
          final max = n.metrics.maxScrollExtent;
          widget.onLocationChanged?.call(
            location,
            max <= 0 ? 1 : (n.metrics.pixels / max).clamp(0.0, 1.0),
          );
          final rect = _menu == null ? null : _menuRect();
          if (rect != null) _menu?.updateVerticalAnchor(rect);
        }
        return false;
      },
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: _scrollPadding),
            sliver: SliverVariedExtentList.builder(
              itemCount: items.length,
              itemExtentBuilder: (i, _) => i < items.length
                  ? items[i].gapBefore + items[i].height
                  : null,
              itemBuilder: (context, i) => Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: spec.width,
                  child: Padding(
                    padding: EdgeInsets.only(top: items[i].gapBefore),
                    child: _item(layout, i),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pagedView(ReaderLayout layout) {
    final spec = layout.spec;
    return Listener(
      // 鼠标滚轮翻页；触控板横扫由 PageView 自身处理。
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final now = DateTime.now();
        if (now.difference(_lastWheelTurn) <
            const Duration(milliseconds: 300)) {
          return;
        }
        final delta = event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()
            ? event.scrollDelta.dy
            : event.scrollDelta.dx;
        if (delta.abs() < 4) return;
        _lastWheelTurn = now;
        turnPage(delta > 0 ? 1 : -1);
      },
      child: PageView.builder(
        controller: _pages,
        itemCount: layout.pages.length,
        onPageChanged: (p) {
          _controller.location = layout.locationOfPage(p);
          _lineFraction = 0;
          _closeMenu();
          final last = layout.pages.length - 1;
          widget.onLocationChanged?.call(
            _controller.location,
            last <= 0 ? 1 : p / last,
          );
        },
        itemBuilder: (context, p) {
          final page = layout.pages[p];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: _pagePadding),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: spec.width,
                height: spec.pageHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final f in page.fragments) _fragment(layout, f),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -_pagePadding + 6,
                      child: Text(
                        '${p + 1} / ${layout.pages.length}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 分页片段：整块绘制，按片段的行范围裁切并上移，避免截断重排改变断行。
  Widget _fragment(ReaderLayout layout, PageFragment f) {
    final item = layout.items[f.itemIndex];
    final top = item.lines[f.firstLine].top;
    final height = item.lines[f.lastLine].bottom - top;
    return Positioned(
      top: f.top,
      left: 0,
      right: 0,
      height: height,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: item.height,
          maxHeight: item.height,
          child: Transform.translate(
            offset: Offset(0, -top),
            child: _item(layout, f.itemIndex, windowTop: top),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layoutFor(_spec(context, constraints));
        _syncControllers(layout);
        if (_restorePending) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
        }
        return RawGestureDetector(
          gestures: _gestures,
          behavior: HitTestBehavior.translucent,
          child: switch (_controller.mode) {
            ReaderMode.scroll => _scrollView(layout),
            ReaderMode.paged => _pagedView(layout),
          },
        );
      },
    );
  }
}

/// 文本项的可见窗口；登记到 [registry] 供指针命中，分页时窗口只是整块的一段。
class _HitWindow extends StatefulWidget {
  const _HitWindow({
    super.key,
    required this.item,
    required this.windowTop,
    required this.registry,
    required this.builder,
  });

  final LayoutItem item;

  /// 窗口顶端在整块坐标系中的位置（分页片段的首行行顶）。
  final double windowTop;
  final Set<_HitWindowState> registry;
  final Widget Function(GlobalKey paragraphKey) builder;

  @override
  State<_HitWindow> createState() => _HitWindowState();
}

class _HitWindowState extends State<_HitWindow> {
  final _paragraphKey = GlobalKey();

  RenderParagraph? get paragraph {
    final object = _paragraphKey.currentContext?.findRenderObject();
    return object is RenderParagraph && object.attached ? object : null;
  }

  /// 可见窗口的全局矩形：分页时是外层裁切框，滚动时是段落本身。
  Rect? get globalRect {
    final paragraph = this.paragraph;
    if (paragraph == null || !paragraph.hasSize) return null;
    RenderObject? clip = paragraph;
    while (clip != null && clip is! RenderClipRect) {
      clip = clip.parent;
      if (clip is RenderSliver) {
        clip = null;
        break;
      }
    }
    final box = clip is RenderClipRect ? clip : paragraph;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.registry.add(this);
  }

  @override
  void dispose() {
    widget.registry.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_paragraphKey);
}

/// 只在着色区间、版式或块变化时重建 span；公式 widget 随 span 复用，不重复解析。
class _TextItem extends StatefulWidget {
  const _TextItem({
    required this.paragraphKey,
    required this.block,
    required this.item,
    required this.spec,
    required this.typesetter,
    required this.marks,
    this.blurred = false,
  });

  final GlobalKey paragraphKey;
  final bool blurred;
  final Block block;
  final LayoutItem item;
  final ReaderLayoutSpec spec;
  final ReaderTypesetter typesetter;
  final List<TextMark> marks;

  @override
  State<_TextItem> createState() => _TextItemState();
}

class _TextItemState extends State<_TextItem> {
  InlineSpan? _span;

  @override
  void didUpdateWidget(_TextItem old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item ||
        old.spec != widget.spec ||
        !listEquals(old.marks, widget.marks)) {
      _span = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final span = _span ??= widget.typesetter.span(
      widget.block,
      widget.item,
      widget.spec,
      marks: widget.marks,
    );
    Widget text = RichText(
      key: widget.paragraphKey,
      textScaler: TextScaler.noScaling,
      textDirection: widget.item.direction,
      text: span,
    );
    // 始终包一层滤镜，切换模糊时不改变树结构，段落 GlobalKey 不必重新挂载。
    text = ImageFiltered(
      enabled: widget.blurred,
      imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: text,
    );
    if (widget.item.indent == 0) return text;
    return Container(
      padding: EdgeInsets.only(left: ReaderTypography.blockquotePadLeft),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: widget.item.ruleColor ?? widget.spec.ruleColor,
            width: ReaderTypography.blockquoteSideWidth,
          ),
        ),
      ),
      child: text,
    );
  }
}

/// 图块位图；按显示尺寸解码以限制内存，读取失败或没有图片时显示比例一致的占位。
class _Figure extends StatelessWidget {
  const _Figure({required this.size, this.image});

  final Size size;
  final ReaderFigureImage? image;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Symbols.image_rounded, color: cs.onSurfaceVariant),
    );
    final image = this.image;
    return Align(
      alignment: Alignment.topCenter,
      child: image == null
          ? placeholder
          : Hero(
              tag: figureHeroTag(FigureHeroSource.reader, image.path),
              child: Image.file(
                File(image.path),
                width: size.width,
                height: size.height,
                fit: BoxFit.contain,
                cacheWidth:
                    (size.width * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                errorBuilder: (_, _, _) => placeholder,
              ),
            ),
    );
  }
}
