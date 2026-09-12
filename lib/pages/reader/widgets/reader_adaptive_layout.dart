import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../utils/markdown_translation_weaver.dart';

int readerSpreadColumns({
  required double availableWidth,
  required double screenWidth,
  required double fontSize,
  int previousColumns = 1,
}) {
  // 使用系统缩放后的逻辑像素；同时保证每栏能容纳约 30 个正文汉字。
  final threshold = math.max(
    (screenWidth * .62).clamp(1000.0, 1440.0),
    fontSize * 60 + 64,
  );
  return availableWidth >= threshold - (previousColumns == 2 ? 64 : 0) ? 2 : 1;
}

/// 窄屏把双语投影为译文，不改写用户保存的翻译模式，也不重新翻译。
DocTranslationMode readerEffectiveTranslationMode(
  DocTranslationMode mode, {
  required bool bilingualCapable,
}) =>
    mode == DocTranslationMode.bilingual && !bilingualCapable
    ? DocTranslationMode.translated
    : mode;

/// 下一次点击翻译按钮后的模式：宽屏三态（双语 → 译文 → 原文），
/// 窄屏只在原文与译文之间切换，与底栏 tooltip 共用同一份计算。
DocTranslationMode readerNextTranslationMode(
  DocTranslationMode mode, {
  required bool bilingualCapable,
}) {
  if (!bilingualCapable) {
    final effective = readerEffectiveTranslationMode(
      mode,
      bilingualCapable: false,
    );
    return effective == DocTranslationMode.off
        ? DocTranslationMode.translated
        : DocTranslationMode.off;
  }
  return switch (mode) {
    DocTranslationMode.bilingual => DocTranslationMode.translated,
    DocTranslationMode.translated => DocTranslationMode.off,
    DocTranslationMode.off => DocTranslationMode.bilingual,
  };
}

double readerPdfInitialZoom(
  PdfDocument document,
  PdfViewerController controller,
  double fitScale,
  double coverScale,
) => math.min(fitScale, coverScale);

PdfPageLayout readerFacingPages(List<PdfPage> pages, PdfViewerParams params) {
  final gap = params.margin;
  final rowWidths = <double>[];
  for (var i = 0; i < pages.length; i += 2) {
    rowWidths.add(
      pages[i].width + (i + 1 < pages.length ? gap + pages[i + 1].width : 0),
    );
  }
  final width = rowWidths.fold<double>(0, math.max) + gap * 2;
  final rects = <Rect>[];
  var y = gap;
  for (var i = 0; i < pages.length; i += 2) {
    var x = (width - rowWidths[i ~/ 2]) / 2;
    var height = pages[i].height;
    for (var j = i; j < math.min(i + 2, pages.length); j++) {
      rects.add(Rect.fromLTWH(x, y, pages[j].width, pages[j].height));
      x += pages[j].width + gap;
      height = math.max(height, pages[j].height);
    }
    y += height + gap;
  }
  return PdfPageLayout(pageLayouts: rects, documentSize: Size(width, y));
}
