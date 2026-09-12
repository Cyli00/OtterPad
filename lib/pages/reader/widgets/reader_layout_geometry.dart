import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../services/reader/reader_document_index.dart';

final _whitespace = RegExp(r'\s+');
final _ignoredGlyph = RegExp(r'[\s\u00ad\-]');
final _inlineFormula = RegExp(r'\$[^$\n]+\$|\\\([\s\S]*?\\\)');

Rect readerBoxRect(List<double> box, Size source, Size target, int rotation) {
  var rect = Rect.fromLTRB(
    box[0] / source.width,
    box[1] / source.height,
    box[2] / source.width,
    box[3] / source.height,
  );
  final ratio = target.width / target.height;
  if (rotation.isOdd &&
      (source.height / source.width - ratio).abs() <
          (source.width / source.height - ratio).abs()) {
    rect = rotation == 1
        ? Rect.fromLTRB(1 - rect.bottom, rect.left, 1 - rect.top, rect.right)
        : Rect.fromLTRB(rect.top, 1 - rect.right, rect.bottom, 1 - rect.left);
  }
  return Rect.fromLTRB(
    rect.left * target.width,
    rect.top * target.height,
    rect.right * target.width,
    rect.bottom * target.height,
  );
}

class ReaderLayoutGeometry {
  final PdfPageRawText? text;
  final String compactText;
  final List<int> offsets;
  ReaderLayoutGeometry(this.text)
    : compactText = (text?.fullText ?? '').replaceAll(_whitespace, ''),
      offsets = [
        for (var i = 0; i < (text?.fullText.length ?? 0); i++)
          if (!_whitespace.hasMatch(text!.fullText[i])) i,
      ];

  List<Rect> textRects(String quote, PdfPage page, Size size, {Rect? within}) {
    final needle = quote.replaceAll(_whitespace, '');
    if (needle.isEmpty || text == null) return const [];
    final matches = <List<Rect>>[];
    var start = 0;
    while (start < compactText.length) {
      final at = compactText.indexOf(needle, start);
      if (at < 0) break;
      start = at + needle.length;
      final boxes = <Rect>[];
      for (var i = at; i < start; i++) {
        final offset = offsets[i];
        if (offset < text!.charRects.length &&
            text!.charRects[offset].isNotEmpty) {
          boxes.add(
            text!.charRects[offset].toRect(page: page, scaledPageSize: size),
          );
        }
      }
      if (boxes.isNotEmpty &&
          (within == null ||
              boxes.every((r) => within.inflate(2).contains(r.center)))) {
        matches.add(boxes);
      }
    }
    return matches.length == 1 ? matches.single : const [];
  }

  List<Rect> alignedCharRects(
    String value,
    PdfPage page,
    Size size, {
    required Rect within,
    List<Rect>? regions,
  }) {
    if (text == null) return [];
    final native = StringBuffer();
    final nativeBoxes = <Rect>[];
    final bounds = (regions ?? [within]).map((box) => box.inflate(1)).toList();
    for (
      var i = 0;
      i < text!.fullText.length && i < text!.charRects.length;
      i++
    ) {
      final r = text!.charRects[i].toRect(page: page, scaledPageSize: size);
      if (r.isEmpty || !bounds.any((box) => box.contains(r.center))) {
        continue;
      }
      final c = _readerPdfGlyph(text!.fullText[i]);
      native.write(c);
      nativeBoxes.addAll(List.filled(c.length, r));
    }
    final compact = native.toString();
    final formulas = _inlineFormula.allMatches(value).toList();
    final formulaOffsets = <int>{
      for (final f in formulas)
        for (var i = f.start; i < f.end; i++) i,
    };
    final source = StringBuffer();
    final offsets = <int>[];
    for (var i = 0; i < value.length; i++) {
      if (formulaOffsets.contains(i)) continue;
      final c = _readerPdfGlyph(value[i]);
      source.write(c);
      offsets.addAll(List.filled(c.length, i));
    }
    final needle = source.toString();
    if (needle.isEmpty || compact.isEmpty) return [];
    final result = List<Rect>.filled(value.length, Rect.zero);
    final pairs = <({int source, int native})>[];
    final exact = compact.indexOf(needle);
    if (exact >= 0) {
      for (var i = 0; i < needle.length; i++) {
        pairs.add((source: i, native: exact + i));
      }
    } else {
      // OCR 与 PDF 的断词、脚注和连字并不总相同；仅在已定位的段落框内对齐字符。
      // 用最长公共子序列保留原顺序，低相似度不生成精确锚点。
      final stride = compact.length + 1;
      if ((needle.length + 1) * stride > 9000000) return [];
      final scores = Uint16List((needle.length + 1) * stride);
      for (var i = needle.length - 1; i >= 0; i--) {
        for (var j = compact.length - 1; j >= 0; j--) {
          final down = scores[(i + 1) * stride + j];
          final right = scores[i * stride + j + 1];
          scores[i * stride + j] = needle.codeUnitAt(i) == compact.codeUnitAt(j)
              ? scores[(i + 1) * stride + j + 1] + 1
              : (down > right ? down : right);
        }
      }
      if (scores[0] /
              (needle.length < compact.length
                  ? needle.length
                  : compact.length) <
          .7) {
        return [];
      }
      var i = 0;
      var j = 0;
      while (i < needle.length && j < compact.length) {
        if (needle.codeUnitAt(i) == compact.codeUnitAt(j)) {
          pairs.add((source: i, native: j));
          i++;
          j++;
        } else if (scores[(i + 1) * stride + j] >= scores[i * stride + j + 1]) {
          i++;
        } else {
          j++;
        }
      }
    }
    for (final pair in pairs) {
      result[offsets[pair.source]] = nativeBoxes[pair.native];
    }
    for (final formula in formulas) {
      final before = pairs
          .where((p) => offsets[p.source] < formula.start)
          .lastOrNull;
      final after = pairs
          .where((p) => offsets[p.source] >= formula.end)
          .firstOrNull;
      final start = before == null ? 0 : before.native + 1;
      final end = after == null ? nativeBoxes.length : after.native;
      if (start >= end) continue;
      final bounds = nativeBoxes
          .sublist(start, end)
          .reduce((a, b) => a.expandToInclude(b));
      for (var i = formula.start; i < formula.end; i++) {
        result[i] = bounds;
      }
    }
    return result;
  }

  Rect? paragraphRect(ReaderParagraph paragraph, PdfPage page, Size size) {
    final boxes = textRects(paragraph.plainText, page, size);
    if (boxes.isEmpty) return null;
    return boxes.reduce((a, b) => a.expandToInclude(b));
  }
}

String _readerPdfGlyph(String c) {
  if (_ignoredGlyph.hasMatch(c)) return '';
  return const {
        'ﬁ': 'fi',
        'ﬂ': 'fl',
        'ﬀ': 'ff',
        'ﬃ': 'ffi',
        'ﬄ': 'ffl',
        '’': "'",
        '‘': "'",
        '“': '"',
        '”': '"',
      }[c] ??
      c;
}
