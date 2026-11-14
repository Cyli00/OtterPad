import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../core/app_logger.dart';
import '../../../core/rust_backend.dart';
import '../../../src/rust/pdf.dart';
import '../../../src/rust/pdf/geometry.dart' as geo;

/// 选区端点：页码与该页字符列表下标。
typedef PdfTextPosition = ({int page, int index});

int _compare(PdfTextPosition a, PdfTextPosition b) =>
    a.page != b.page ? a.page - b.page : a.index - b.index;

/// PDF 文字选择：按页缓存字符（最多 [_cachePages] 页），命中与选区矩形在 Dart 计算，
/// 拖动时不必每次把整页字符跨 FFI 传给 Rust。
class PdfTextSelection {
  PdfTextSelection(this.handle);

  final BigInt handle;
  static const _cachePages = 8;
  final _chars = <int, List<PdfChar>>{};
  final _loading = <int>{};

  PdfTextPosition? _anchor;
  PdfTextPosition? _extent;

  bool get isEmpty => _anchor == null || _extent == null;

  PdfTextPosition get _start =>
      _compare(_anchor!, _extent!) <= 0 ? _anchor! : _extent!;
  PdfTextPosition get _end =>
      _compare(_anchor!, _extent!) <= 0 ? _extent! : _anchor!;

  /// 已缓存则同步返回；否则开始加载并返回 null，加载完成后调用 [onLoaded]。
  List<PdfChar>? characters(int page, void Function() onLoaded) {
    final cached = _chars.remove(page);
    if (cached != null) {
      _chars[page] = cached;
      return cached;
    }
    if (_loading.add(page)) {
      unawaited(
        RustBackend.instance
            .pdfCharacters(
              handle: handle,
              page: page,
              taskId: rustTaskId('pdf-chars'),
            )
            .then((chars) {
              _chars[page] = chars;
              while (_chars.length > _cachePages) {
                // 正在选择的页不淘汰。
                final victim = _chars.keys.firstWhere(
                  (p) => p != _anchor?.page && p != _extent?.page,
                  orElse: () => -1,
                );
                if (victim < 0) break;
                _chars.remove(victim);
              }
              onLoaded();
            })
            .catchError((Object e) {
              log.d('[PdfView] 读取第 ${page + 1} 页字符失败：$e');
            })
            .whenComplete(() => _loading.remove(page)),
      );
    }
    return null;
  }

  /// 距 [point]（PDF 点）最近的字符；同一行优先。[tolerance] 为 null 时不限距离。
  static int? hitTest(List<PdfChar> chars, Offset point, {double? tolerance}) {
    int? best;
    var bestScore = double.infinity;
    for (var i = 0; i < chars.length; i++) {
      final b = chars[i].bounds;
      if (b.right <= b.left || b.bottom <= b.top) continue;
      final dx = math.max(0, math.max(b.left - point.dx, point.dx - b.right));
      final dy = math.max(0, math.max(b.top - point.dy, point.dy - b.bottom));
      if (tolerance != null && math.sqrt(dx * dx + dy * dy) > tolerance) {
        continue;
      }
      final score = dy * 4 + dx;
      if (score < bestScore) {
        bestScore = score.toDouble();
        best = i;
      }
    }
    return best;
  }

  void start(PdfTextPosition position) {
    _anchor = position;
    _extent = position;
  }

  void extend(PdfTextPosition position) {
    if (_anchor != null) _extent = position;
  }

  void clear() {
    _anchor = null;
    _extent = null;
  }

  /// [page] 上的选区矩形（PDF 点）：同一行相邻字符合并成一块。
  List<geo.Rect> rects(int page) {
    if (isEmpty) return const [];
    final start = _start;
    final end = _end;
    if (page < start.page || page > end.page) return const [];
    final chars = _chars[page];
    if (chars == null || chars.isEmpty) return const [];
    final from = page == start.page ? start.index : 0;
    final to = page == end.page ? end.index : chars.length - 1;
    final result = <geo.Rect>[];
    for (var i = from; i <= to && i < chars.length; i++) {
      final b = chars[i].bounds;
      if (b.right <= b.left || b.bottom <= b.top) continue;
      final last = result.isEmpty ? null : result.last;
      final sameLine =
          last != null &&
          last.top < b.bottom &&
          b.top < last.bottom &&
          b.left >= last.left - 1;
      if (sameLine) {
        result[result.length - 1] = geo.Rect(
          left: math.min(last.left, b.left),
          top: math.min(last.top, b.top),
          right: math.max(last.right, b.right),
          bottom: math.max(last.bottom, b.bottom),
        );
      } else {
        result.add(b);
      }
    }
    return result;
  }

  /// 选中的文字；跨页时中间页的字符若已被淘汰会重新读取。
  Future<String> text() async {
    if (isEmpty) return '';
    final start = _start;
    final end = _end;
    final buffer = StringBuffer();
    for (var page = start.page; page <= end.page; page++) {
      final chars =
          _chars[page] ??
          await RustBackend.instance.pdfCharacters(
            handle: handle,
            page: page,
            taskId: rustTaskId('pdf-chars'),
          );
      final from = page == start.page ? start.index : 0;
      final to = page == end.page ? end.index : chars.length - 1;
      if (buffer.isNotEmpty) buffer.writeln();
      for (var i = from; i <= to && i < chars.length; i++) {
        buffer.write(chars[i].text);
      }
    }
    return buffer.toString().replaceAll('\r\n', '\n');
  }
}
