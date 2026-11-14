import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../src/rust/api/document.dart';
import '../../../src/rust/document.dart';
import '../../../src/rust/document/regions.dart';

/// 一块译文在页面上的位置（页面比例坐标）与要显示的行内片段。
typedef PdfTextOverlay = ({Rect area, List<InlineRun> runs});

/// 按块区域放置译文：没有区域或没有译文的块保留原页。
/// 一个块跨栏/跨页有多个区域时，按各区域原文长度切分译文。
///
/// [parsed] 按译文缓存行内解析结果，翻译逐段写入时不必重解析已有段落。
Map<int, List<PdfTextOverlay>> pdfTranslationOverlays(
  ReaderDocument document,
  Map<String, String> translations,
  Map<String, List<InlineRun>> parsed,
) {
  final result = <int, List<PdfTextOverlay>>{};
  final keys = document.translationKeys;
  for (var i = 0; i < document.blocks.length; i++) {
    final regions = i < document.blockRegions.length
        ? document.blockRegions[i]
        : const <PageRegion>[];
    final key = i < keys.length ? keys[i] : '';
    final text = key.isEmpty ? null : translations[key];
    if (regions.isEmpty || text == null || text.trim().isEmpty) continue;
    final runs = parsed[text] ??= translatedBlock(
      source: document.blocks[i],
      markdown: text,
    ).runs;
    final parts = _split(runs, [
      for (final r in regions) r.sourceLength.toInt(),
    ]);
    for (var k = 0; k < regions.length; k++) {
      final r = regions[k];
      if (parts[k].isEmpty) continue;
      (result[r.page] ??= []).add((
        area: Rect.fromLTRB(r.left, r.top, r.right, r.bottom),
        runs: parts[k],
      ));
    }
  }
  return result;
}

/// 把行内片段切成 [lengths.length] 段：切点按长度比例，就近落在空白处，
/// 不切开公式和 UTF-16 代理对。
List<List<InlineRun>> _split(List<InlineRun> runs, List<int> lengths) {
  if (lengths.length <= 1) return [runs];
  final text = runs.map((r) => r.text).join();
  final total = text.length;
  final sum = lengths.fold(0, (a, b) => a + b);
  final cuts = <int>[0];
  var cumulative = 0;
  for (var k = 0; k < lengths.length - 1; k++) {
    cumulative += sum == 0 ? 1 : lengths[k];
    var cut = (total * cumulative / (sum == 0 ? lengths.length : sum)).round();
    for (var d = 0; d <= 24; d++) {
      if (cut + d < total && text.codeUnitAt(cut + d) == 0x20) {
        cut += d + 1;
        break;
      }
      if (cut - d > 0 && text.codeUnitAt(cut - d - 1) == 0x20) {
        cut -= d;
        break;
      }
    }
    var start = 0;
    for (final run in runs) {
      final end = start + run.text.length;
      if (run.math != null && cut > start && cut < end) cut = end;
      start = end;
    }
    if (cut > 0 && cut < total && _isLowSurrogate(text.codeUnitAt(cut))) cut++;
    cuts.add(cut.clamp(cuts.last, total));
  }
  cuts.add(total);
  return [
    for (var k = 0; k + 1 < cuts.length; k++)
      _slice(runs, cuts[k], cuts[k + 1]),
  ];
}

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

List<InlineRun> _slice(List<InlineRun> runs, int from, int to) {
  final result = <InlineRun>[];
  var start = 0;
  for (final run in runs) {
    final end = start + run.text.length;
    final a = math.max(from, start);
    final b = math.min(to, end);
    if (a < b) {
      result.add(
        run.math != null || (a == start && b == end)
            ? run
            : InlineRun(
                text: run.text.substring(a - start, b - start),
                bold: run.bold,
                italic: run.italic,
                code: run.code,
                strike: run.strike,
                link: run.link,
                math: run.math,
              ),
      );
    }
    start = end;
  }
  return result;
}

/// 一页的译文层：按 PDF 点排版，再整体缩放到页面显示尺寸，缩放时不重新排版。
/// 先铺全部白底再画文字，相邻区域的白底不会盖住上一段的字脚。
class PdfTranslationLayer extends StatelessWidget {
  const PdfTranslationLayer({
    super.key,
    required this.pageWidth,
    required this.pageHeight,
    required this.overlays,
    required this.rtl,
  });

  /// 页面尺寸（PDF 点）。
  final double pageWidth;
  final double pageHeight;
  final List<PdfTextOverlay> overlays;
  final bool rtl;

  Rect _rect(PdfTextOverlay overlay) => Rect.fromLTRB(
    overlay.area.left * pageWidth,
    overlay.area.top * pageHeight,
    overlay.area.right * pageWidth,
    overlay.area.bottom * pageHeight,
  );

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(color: Colors.black87, height: 1.2);
    final rects = [for (final o in overlays) _rect(o)];
    final sizes = [
      for (var i = 0; i < overlays.length; i++)
        _fitFontSize(overlays[i].runs, rects[i].size),
    ];
    // 正文块向本页中位字号对齐，标题等明显不同的块保留自己的字号。
    final sorted = [...sizes]..sort();
    final median = sorted.isEmpty ? 0.0 : sorted[sorted.length ~/ 2];
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: pageWidth,
        height: pageHeight,
        child: Stack(
          children: [
            for (final rect in rects)
              Positioned.fromRect(
                rect: rect.inflate(1),
                child: const ColoredBox(color: Colors.white),
              ),
            for (var i = 0; i < overlays.length; i++)
              Positioned.fromRect(
                rect: rects[i],
                child: _RegionText(
                  runs: overlays[i].runs,
                  style: base.copyWith(
                    fontSize: (sizes[i] - median).abs() < median * .35
                        ? math.min(sizes[i], median)
                        : sizes[i],
                  ),
                  rtl: rtl,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 按面积估字号（中日韩字符约 1em 宽，其余约 0.5em）；放不下再由 FittedBox 缩小。
double _fitFontSize(List<InlineRun> runs, Size size) {
  var ems = 0.0;
  for (final run in runs) {
    for (final unit in run.text.codeUnits) {
      ems += unit >= 0x2E80 ? 1.0 : 0.5;
    }
  }
  if (ems == 0) return 10;
  final fitted = math.sqrt(size.width * size.height / (1.2 * ems)) * 0.95;
  return math.min(fitted, math.min(size.height / 1.2, 24));
}

class _RegionText extends StatelessWidget {
  const _RegionText({
    required this.runs,
    required this.style,
    required this.rtl,
  });

  final List<InlineRun> runs;
  final TextStyle style;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: rtl ? Alignment.topRight : Alignment.topLeft,
        child: SizedBox(
          width: constraints.maxWidth,
          child: Text.rich(
            TextSpan(
              style: style,
              children: [for (final r in runs) _span(r, style)],
            ),
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }

  InlineSpan _span(InlineRun run, TextStyle base) {
    var style = base;
    if (run.bold) style = style.copyWith(fontWeight: FontWeight.w700);
    if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (run.strike) {
      style = style.copyWith(decoration: TextDecoration.lineThrough);
    }
    final tex = run.math;
    if (tex == null) return TextSpan(text: run.text, style: style);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Math.tex(
        tex,
        options: MathOptions(fontSize: style.fontSize!, color: style.color!),
        onErrorFallback: (_) => Text('\$$tex\$', style: style),
      ),
    );
  }
}
