import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/app_logger.dart';
import '../../../core/elevation.dart';
import '../../../core/rust_backend.dart';
import '../../../src/rust/api.dart';
import '../../../src/rust/pdf.dart';
import '../../../src/rust/pdf/geometry.dart' as geo;
import '../../../utils/pdf_bitmap.dart';

/// 分块边长（渲染像素）。
const _tile = 512;

/// 渲染倍率按 1/4 倍频取整，缩放过程中不会每帧都换一套分块。
double _quantize(double scale) {
  final steps = (math.log(scale) / math.ln2 * 4).ceil();
  final quantized = math.pow(2, steps / 4).toDouble().clamp(0.25, 16.0);
  // 与 Rust 一致取 1/64，保证两边算出的页面像素尺寸相同。
  return (quantized * 64).round() / 64;
}

typedef _TileKey = ({int scale64, int x, int y});

/// 一页 PDF：只渲染 [visible] 覆盖的分块，换倍率时旧分块继续顶着显示直到新分块到齐。
class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.handle,
    required this.page,
    required this.size,
    required this.visible,
    required this.overlays,
  });

  final BigInt handle;
  final PageInfo page;

  /// 页面显示尺寸（逻辑像素）。
  final Size size;

  /// 当前可见区域（页内逻辑坐标）；返回 null 表示不可见。视口变化时由 [Listenable] 通知。
  final ValueListenable<Rect?> visible;

  /// 叠加的矩形（PDF 点），按顺序绘制。
  final List<({List<geo.Rect> rects, Color color})> overlays;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  final _images = <_TileKey, ui.Image>{};
  final _pending = <_TileKey, String>{};
  bool _scheduled = false;
  Set<_TileKey> _needed = const {};
  int _scale64 = 0;

  double get _logicalPerPoint => widget.size.width / widget.page.width;

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(PdfPageView old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) {
      old.visible.removeListener(_schedule);
      widget.visible.addListener(_schedule);
    }
    if (old.size != widget.size) _schedule();
  }

  @override
  void dispose() {
    widget.visible.removeListener(_schedule);
    for (final id in _pending.values) {
      cancelTask(taskId: id);
    }
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  /// 同一帧内的多次视口变化只算一次。
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _update();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _update() {
    final visible = widget.visible.value;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final scale = _quantize(_logicalPerPoint * dpr);
    final scale64 = (scale * 64).round();
    final width = (widget.page.width * scale).floor();
    final height = (widget.page.height * scale).floor();
    final needed = <_TileKey>{};
    if (visible != null && width > 0 && height > 0) {
      final pxPerLogical = scale / _logicalPerPoint;
      final region = visible.inflate(256 / dpr);
      final left = math.max(0, (region.left * pxPerLogical) ~/ _tile);
      final top = math.max(0, (region.top * pxPerLogical) ~/ _tile);
      final right = math.min(width - 1, region.right * pxPerLogical) ~/ _tile;
      final bottom =
          math.min(height - 1, region.bottom * pxPerLogical) ~/ _tile;
      for (var y = top; y <= bottom; y++) {
        for (var x = left; x <= right; x++) {
          needed.add((scale64: scale64, x: x, y: y));
        }
      }
    }
    for (final key
        in _pending.keys.where((k) => !needed.contains(k)).toList()) {
      cancelTask(taskId: _pending.remove(key)!);
    }
    for (final key in needed) {
      if (_images.containsKey(key) || _pending.containsKey(key)) continue;
      _request(key, scale, width, height);
    }
    _needed = needed;
    _scale64 = scale64;
    _prune();
  }

  void _request(_TileKey key, double scale, int width, int height) {
    final x = key.x * _tile;
    final y = key.y * _tile;
    final id = rustTaskId('pdf-tile');
    _pending[key] = id;
    RustBackend.instance
        .renderPdfTile(
          request: RenderRequest(
            document: widget.handle,
            page: widget.page.index,
            scale: scale,
            tile: PixelRect(
              x: x,
              y: y,
              width: math.min(_tile, width - x),
              height: math.min(_tile, height - y),
            ),
            annotations: true,
          ),
          taskId: id,
        )
        .then((bitmap) async {
          if (_pending[key] != id) return;
          final image = await decodePdfBitmap(bitmap);
          if (!mounted || _pending[key] != id) {
            image.dispose();
            return;
          }
          _pending.remove(key);
          _images[key] = image;
          setState(() {});
          _prune();
        })
        .catchError((Object e) {
          if (_pending[key] == id) _pending.remove(key);
          if (!isCancellation(e)) log.d('[PdfView] 渲染分块失败：$e');
        });
  }

  /// 当前倍率只保留 [_needed] 内的分块；其他倍率等当前倍率到齐后再释放。
  /// 有释放就重建，画笔不会拿到已释放的图片。
  void _prune() {
    final complete = _needed.every(_images.containsKey);
    var removed = false;
    _images.removeWhere((key, image) {
      final drop = key.scale64 == _scale64 ? !_needed.contains(key) : complete;
      if (drop) {
        image.dispose();
        removed = true;
      }
      return drop;
    });
    if (removed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: AppShadows.card,
      ),
      child: CustomPaint(
        size: widget.size,
        painter: _PagePainter(
          images: _images,
          logicalPerPoint: _logicalPerPoint,
          overlays: widget.overlays,
        ),
      ),
    );
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter({
    required Map<_TileKey, ui.Image> images,
    required this.logicalPerPoint,
    required this.overlays,
  }) : images = Map.of(images);

  final Map<_TileKey, ui.Image> images;
  final double logicalPerPoint;
  final List<({List<geo.Rect> rects, Color color})> overlays;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    // 低倍率先画，高倍率覆盖在上面。
    final keys = images.keys.toList()
      ..sort((a, b) => a.scale64.compareTo(b.scale64));
    for (final key in keys) {
      final image = images[key]!;
      final perLogical = key.scale64 / 64 / logicalPerPoint;
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        key.x * _tile / perLogical,
        key.y * _tile / perLogical,
        image.width / perLogical,
        image.height / perLogical,
      );
      canvas.drawImageRect(image, src, dst, paint);
    }
    for (final overlay in overlays) {
      final fill = Paint()..color = overlay.color;
      for (final r in overlay.rects) {
        canvas.drawRect(
          Rect.fromLTRB(
            r.left * logicalPerPoint,
            r.top * logicalPerPoint,
            r.right * logicalPerPoint,
            r.bottom * logicalPerPoint,
          ),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PagePainter old) =>
      old.logicalPerPoint != logicalPerPoint ||
      old.overlays != overlays ||
      old.images.length != images.length ||
      old.images.keys.any((k) => !identical(old.images[k], images[k]));
}
