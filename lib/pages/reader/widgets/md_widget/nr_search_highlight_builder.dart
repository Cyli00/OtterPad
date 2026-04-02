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
      if (lf.isWidget) {
        out.add(lf.widget!);
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
      if (t != null && t.isNotEmpty) {
        out.add(_Leaf(text: t, style: st));
      }
      if (span.children != null) {
        for (final c in span.children!) {
          _flatten(c, st, out);
        }
      }
    } else if (span is WidgetSpan) {
      out.add(_Leaf.w(span));
    }
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
    for (final c in q.split('')) {
      if (RegExp(r'[a-zA-Z]').hasMatch(c)) {
        buf.write('[${c.toLowerCase()}${c.toUpperCase()}]');
      } else {
        buf.write(RegExp.escape(c));
      }
    }
    return RegExp(buf.toString());
  }
}

// ─── 数据类 ───

class _Leaf {
  final String text;
  final String visible;
  final TextStyle? style;
  final bool isWidget;
  final WidgetSpan? widget;
  int start = 0, end = 0;

  _Leaf({required this.text, this.style})
      : visible = text,
        isWidget = false,
        widget = null;
  _Leaf.w(this.widget)
      : text = '\uFFFC',
        visible = '\uFFFC',
        style = null,
        isWidget = true;
}

class _Hit {
  final int s, e;
  _Hit(this.s, this.e);
}
