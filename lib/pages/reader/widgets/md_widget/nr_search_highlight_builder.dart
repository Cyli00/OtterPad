import 'package:flutter/material.dart';

/// 搜索高亮的 richTextBuilder——仅处理搜索词匹配。
///
/// 用户高亮已迁移到 [MarkNode] + [HighlightInjector] 预处理方案，
/// 此类只保留搜索关键词的背景色 + 加粗渲染。
class SearchHighlightBuilder {
  final RegExp? _pattern;
  final Color _searchBg;
  final Color _searchFg;

  SearchHighlightBuilder({
    required String searchQuery,
    required ColorScheme cs,
  })  : _pattern = searchQuery.isNotEmpty
            ? _buildCaseInsensitive(searchQuery)
            : null,
        _searchBg = cs.primaryContainer,
        _searchFg = cs.onPrimaryContainer;

  bool get hasHighlights => _pattern != null;

  /// 作为 richTextBuilder 使用（每段调用一次）。
  Widget call(InlineSpan span) {
    if (_pattern == null) return _wrap(span);

    final leaves = <_Leaf>[];
    _flatten(span, null, leaves);
    if (leaves.isEmpty) return _wrap(span);

    // 拼接可见文本
    final buf = StringBuffer();
    for (final lf in leaves) {
      lf.start = buf.length;
      buf.write(lf.visible);
      lf.end = buf.length;
    }
    final text = buf.toString();

    // 匹配搜索词
    final hits = _pattern
        .allMatches(text)
        .map((m) => _Hit(m.start, m.end))
        .toList(growable: false);
    if (hits.isEmpty) return _wrap(span);

    // 重建带高亮的 span 树
    final out = <InlineSpan>[];
    for (final lf in leaves) {
      if (lf.isOpaque) {
        out.add(lf.opaqueSpan!);
        continue;
      }
      final overlaps =
          hits.where((h) => h.s < lf.end && h.e > lf.start).toList();
      if (overlaps.isEmpty) {
        out.add(TextSpan(text: lf.text, style: lf.style));
        continue;
      }
      out.addAll(_split(lf, overlaps));
    }
    return Text.rich(TextSpan(children: out));
  }

  // ─── 内部工具 ───

  static Widget _wrap(InlineSpan s) =>
      Text.rich(s is TextSpan ? s : TextSpan(children: [s]));

  void _flatten(InlineSpan span, TextStyle? inherited, List<_Leaf> out) {
    if (span is TextSpan) {
      final st = inherited != null && span.style != null
          ? inherited.merge(span.style)
          : (span.style ?? inherited);
      final t = span.text;
      // 公式节点伴随的隐形源码 TextSpan：不参与搜索匹配，原样保留。
      if (t != null && t.isNotEmpty && _isInvisible(st)) {
        out.add(_Leaf.opaque(TextSpan(text: t, style: st)));
      } else if (t != null && t.isNotEmpty) {
        out.add(_Leaf(text: t, style: st));
      }
      if (span.children != null) {
        for (final c in span.children!) {
          _flatten(c, st, out);
        }
      }
    } else if (span is WidgetSpan) {
      out.add(_Leaf.opaque(span));
    }
  }

  /// 对应 `_invisibleSourceSpan`（nr_latex_node.dart）的哨兵样式：
  /// 字号 < 1 或完全透明色。先查 alpha（整数比较，开销最小）。
  static bool _isInvisible(TextStyle? s) {
    if (s == null) return false;
    if (s.color?.a == 0) return true;
    final fs = s.fontSize;
    return fs != null && fs < 1.0;
  }

  List<InlineSpan> _split(_Leaf lf, List<_Hit> overlaps) {
    final pts = <int>{lf.start, lf.end};
    for (final h in overlaps) {
      if (h.s > lf.start && h.s < lf.end) pts.add(h.s);
      if (h.e > lf.start && h.e < lf.end) pts.add(h.e);
    }
    final sorted = pts.toList()..sort();
    final result = <InlineSpan>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i], b = sorted[i + 1];
      final seg = lf.text.substring(a - lf.start, b - lf.start);
      if (seg.isEmpty) continue;
      final isHit = overlaps.any((h) => h.s <= a && h.e >= b);
      if (!isHit) {
        result.add(TextSpan(text: seg, style: lf.style));
      } else {
        result.add(TextSpan(
          text: seg,
          style: (lf.style ?? const TextStyle()).copyWith(
            color: _searchFg,
            fontWeight: FontWeight.w600,
            backgroundColor: _searchBg,
          ),
        ));
      }
    }
    return result;
  }

  static RegExp _buildCaseInsensitive(String q) {
    final buf = StringBuffer();
    for (final rune in q.runes) {
      final c = String.fromCharCode(rune);
      if (_asciiLetterRe.hasMatch(c)) {
        buf.write('[${c.toLowerCase()}${c.toUpperCase()}]');
      } else {
        buf.write(RegExp.escape(c));
      }
    }
    return RegExp(buf.toString());
  }
}

// ─── 库级常量 ───

final RegExp _asciiLetterRe = RegExp(r'[a-zA-Z]');

// ─── 数据类 ───

class _Leaf {
  final String text;
  final String visible;
  final TextStyle? style;
  final bool isOpaque;
  final InlineSpan? opaqueSpan;
  int start = 0, end = 0;

  _Leaf({required this.text, this.style})
      : visible = text,
        isOpaque = false,
        opaqueSpan = null;

  /// 不参与搜索扫描的原子片段（WidgetSpan 或隐形源码 TextSpan）。
  /// 以一个占位符 \uFFFC 占一个逻辑位，保持 leaf 位置与原文对齐。
  _Leaf.opaque(InlineSpan span)
      : text = '\uFFFC',
        visible = '\uFFFC',
        style = null,
        isOpaque = true,
        opaqueSpan = span;
}

class _Hit {
  final int s, e;
  _Hit(this.s, this.e);
}
