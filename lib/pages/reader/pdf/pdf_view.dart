import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_logger.dart';
import '../../../core/rust_backend.dart';
import '../../../src/rust/pdf.dart';
import '../../../src/rust/pdf/geometry.dart' as geo;
import 'pdf_controller.dart';
import 'pdf_page.dart';

const _padding = 8.0;
const _minZoom = 1.0;
const _maxZoom = 6.0;

/// 基于 Rust 分块渲染的 PDF 视图：纵向连续滚动，按窗口宽度适配，
/// Ctrl/⌘+滚轮、触控板与双指捏合缩放，放大后可横向滚动。
class RustPdfView extends StatefulWidget {
  const RustPdfView({
    super.key,
    required this.documentId,
    required this.controller,
    required this.initialProgress,
    required this.onPageChanged,
    required this.matchColor,
    required this.activeMatchColor,
    required this.errorBuilder,
  });

  final String documentId;
  final PdfViewController controller;

  /// 0–1，按页数换算初始页（与 0.1.x 相同：`round(progress * total)`）。
  final double initialProgress;

  /// 1 起的页码与总页数。
  final void Function(int page, int total) onPageChanged;
  final Color matchColor;
  final Color activeMatchColor;
  final Widget Function(BuildContext context, Object error) errorBuilder;

  @override
  State<RustPdfView> createState() => _RustPdfViewState();
}

class _RustPdfViewState extends State<RustPdfView> {
  DocumentInfo? _info;
  Object? _error;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  double _zoom = 1;
  Size _viewport = Size.zero;
  List<double> _offsets = const [];
  double _layoutWidth = 0;
  double _layoutZoom = 0;
  int _page = -1;
  bool _positioned = false;

  /// 每页一个可见区域通知，按页内逻辑坐标。
  final _visible = <int, ValueNotifier<Rect?>>{};

  // 双指捏合：活动触点与起始状态。
  final _touches = <int, Offset>{};
  double? _pinchDistance;
  double _pinchZoom = 1;
  double _panZoomBase = 1;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_onScroll);
    _horizontal.addListener(_onScroll);
    widget.controller.addListener(_onControllerChanged);
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final info = await openLibraryPdf(widget.documentId);
      if (!mounted) {
        unawaited(RustBackend.instance.closePdf(handle: info.handle));
        return;
      }
      widget.controller.attach(info.handle, info.pages.length, _reveal);
      setState(() => _info = info);
    } catch (e) {
      log.e('[PdfView] 打开 PDF 失败', error: e);
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    widget.controller
      ..removeListener(_onControllerChanged)
      ..detach();
    if (_info case final info?) {
      unawaited(RustBackend.instance.closePdf(handle: info.handle));
    }
    _vertical.dispose();
    _horizontal.dispose();
    for (final notifier in _visible.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // ── 排版 ──

  double get _pageWidth => (_viewport.width - _padding * 2) * _zoom;

  double _pageHeight(PageInfo page) => _pageWidth * page.height / page.width;

  /// 每页顶部在内容中的位置；末尾是内容总高。只在宽度或缩放变化时重算。
  void _layout() {
    final info = _info;
    if (info == null) return;
    if (_layoutWidth == _viewport.width && _layoutZoom == _zoom) return;
    _layoutWidth = _viewport.width;
    _layoutZoom = _zoom;
    final offsets = <double>[];
    var y = _padding * _zoom;
    for (final page in info.pages) {
      offsets.add(y);
      y += _pageHeight(page) + _padding * _zoom;
    }
    offsets.add(y);
    _offsets = offsets;
  }

  int _pageAt(double y) {
    var low = 0;
    var high = _offsets.length - 2;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_offsets[mid] <= y) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  ValueNotifier<Rect?> _visibleOf(int page) =>
      _visible.putIfAbsent(page, () => ValueNotifier(_visibleRect(page)));

  Rect? _visibleRect(int page) {
    final info = _info;
    if (info == null || _offsets.isEmpty || !_vertical.hasClients) return null;
    final top = _vertical.offset - _offsets[page];
    final left =
        (_horizontal.hasClients ? _horizontal.offset : 0) - _padding * _zoom;
    final view = Rect.fromLTWH(left, top, _viewport.width, _viewport.height);
    final pageRect =
        Offset.zero & Size(_pageWidth, _pageHeight(info.pages[page]));
    final visible = view.intersect(pageRect);
    return visible.isEmpty ? null : visible;
  }

  void _onScroll() {
    for (final entry in _visible.entries) {
      entry.value.value = _visibleRect(entry.key);
    }
    final info = _info;
    if (info == null || _offsets.isEmpty || !_vertical.hasClients) return;
    final page = _pageAt(_vertical.offset + _viewport.height / 3);
    if (page != _page) {
      _page = page;
      widget.onPageChanged(page + 1, info.pages.length);
    }
  }

  void _positionInitially() {
    final info = _info;
    if (_positioned || info == null || info.pages.isEmpty) return;
    _positioned = true;
    final total = info.pages.length;
    final page = (widget.initialProgress * total).round().clamp(1, total) - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      _vertical.jumpTo(
        math.min(_offsets[page] - _padding, _vertical.position.maxScrollExtent),
      );
      _onScroll();
    });
  }

  /// 命中矩形放到视口上三分之一处；放大时横向居中。
  void _reveal(PdfMatch match) {
    final info = _info;
    if (info == null || !_vertical.hasClients) return;
    final perPoint = _pageWidth / info.pages[match.page].width;
    final top = match.rects.map((r) => r.top).fold(double.infinity, math.min);
    final left = match.rects.map((r) => r.left).fold(double.infinity, math.min);
    final y = _offsets[match.page] + top * perPoint - _viewport.height / 3;
    _vertical.animateTo(
      y.clamp(0, _vertical.position.maxScrollExtent),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
    if (_horizontal.hasClients && _zoom > 1) {
      final x = _padding * _zoom + left * perPoint - _viewport.width / 2;
      _horizontal.jumpTo(x.clamp(0, _horizontal.position.maxScrollExtent));
    }
  }

  // ── 缩放 ──

  /// 以 [focal]（视口坐标）为中心缩放；内容等比放大，滚动偏移按同一比例换算。
  void _setZoom(double zoom, Offset focal) {
    final next = zoom.clamp(_minZoom, _maxZoom);
    if (next == _zoom || !_vertical.hasClients) return;
    final ratio = next / _zoom;
    final x = (_horizontal.hasClients ? _horizontal.offset : 0) + focal.dx;
    final y = _vertical.offset + focal.dy;
    setState(() => _zoom = next);
    _layout();
    // jumpTo 不按旧内容尺寸截断，下一次布局用新尺寸校正。
    _vertical.jumpTo(math.max(0, y * ratio - focal.dy));
    if (_horizontal.hasClients) {
      _horizontal.jumpTo(math.max(0, x * ratio - focal.dx));
    }
    _onScroll();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return;
    // 页面比滚动视图先注册，抢在列表滚动之前处理。
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      _setZoom(_zoom * math.exp(-dy / 400), _local(event.position));
    });
  }

  Offset _local(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touches[event.pointer] = event.position;
    if (_touches.length == 2) {
      final points = _touches.values.toList();
      _pinchDistance = (points[0] - points[1]).distance;
      _pinchZoom = _zoom;
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.position;
    final start = _pinchDistance;
    if (start == null || _touches.length < 2 || start == 0) return;
    final points = _touches.values.take(2).toList();
    final distance = (points[0] - points[1]).distance;
    _setZoom(
      _pinchZoom * distance / start,
      _local((points[0] + points[1]) / 2),
    );
  }

  void _onPointerUp(PointerEvent event) {
    if (_touches.remove(event.pointer) == null) return;
    if (_touches.length < 2 && _pinchDistance != null) {
      setState(() => _pinchDistance = null);
    }
  }

  // ── 构建 ──

  List<({List<geo.Rect> rects, Color color})> _overlays(int page) {
    final controller = widget.controller;
    if (controller.matches.isEmpty) return const [];
    final overlays = <({List<geo.Rect> rects, Color color})>[];
    for (var i = 0; i < controller.matches.length; i++) {
      final match = controller.matches[i];
      if (match.page != page) continue;
      overlays.add((
        rects: match.rects,
        color: i == controller.currentIndex
            ? widget.activeMatchColor
            : widget.matchColor,
      ));
    }
    return overlays;
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) return widget.errorBuilder(context, error);
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (viewport != _viewport) {
          _viewport = viewport;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onScroll();
          });
        }
        _layout();
        _positionInitially();
        final pinching = _pinchDistance != null;
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          onPointerPanZoomStart: (_) => _panZoomBase = _zoom,
          onPointerPanZoomUpdate: (event) {
            if (event.scale != 1) {
              _setZoom(_panZoomBase * event.scale, event.localPosition);
            }
          },
          child: Scrollbar(
            controller: _vertical,
            notificationPredicate: (n) => n.depth == 1,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              physics: pinching ? const NeverScrollableScrollPhysics() : null,
              child: SizedBox(
                width: viewport.width * _zoom,
                height: viewport.height,
                child: ListView.builder(
                  controller: _vertical,
                  physics: pinching
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: EdgeInsets.only(top: _padding * _zoom),
                  itemCount: info.pages.length,
                  itemExtentBuilder: (index, _) =>
                      _offsets[index + 1] - _offsets[index],
                  itemBuilder: (context, index) => Listener(
                    onPointerSignal: _onPointerSignal,
                    behavior: HitTestBehavior.opaque,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: PdfPageView(
                        key: ValueKey(index),
                        handle: info.handle,
                        page: info.pages[index],
                        size: Size(_pageWidth, _pageHeight(info.pages[index])),
                        visible: _visibleOf(index),
                        overlays: _overlays(index),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
