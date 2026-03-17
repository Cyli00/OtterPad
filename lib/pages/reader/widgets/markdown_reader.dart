import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart'
    show LatexBlockSyntax;
import 'package:markdown/markdown.dart' as md;

import '../../../data/models/book/highlight.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../utils/latex_syntax.dart';

/// 可配置外观的 Markdown 渲染组件，专用于阅读器。
///
/// 支持两种渲染模式：
/// - **普通模式**：单个 [MarkdownBody] 渲染全部内容（性能最优）
/// - **高亮模式**：按段落拆分为独立 block，目标 block 挂载 [GlobalKey]，
///   用 [Scrollable.ensureVisible] 精准滚动到段落顶部，搜索词通过
///   [_HighlightInlineSyntax] 在解析阶段自动高亮。
class ReaderMarkdownBody extends StatefulWidget {
  final String data;
  final ReaderSettingsState settings;
  final ScrollController? scrollController;

  /// 需要高亮的搜索词（null 则普通模式）
  final String? highlightQuery;

  /// 目标段落在原始 Markdown 中的字符偏移
  final int? targetCharOffset;

  /// 用户划线列表
  final List<Highlight> highlights;

  /// 单击已划线文本时回调（传递 Highlight 对象和点击全局坐标）
  final void Function(Highlight highlight, Offset globalPosition)?
      onHighlightTap;

  const ReaderMarkdownBody({
    super.key,
    required this.data,
    required this.settings,
    this.scrollController,
    this.highlightQuery,
    this.targetCharOffset,
    this.highlights = const [],
    this.onHighlightTap,
  });

  @override
  State<ReaderMarkdownBody> createState() => _ReaderMarkdownBodyState();
}

class _ReaderMarkdownBodyState extends State<ReaderMarkdownBody> {
  final _targetKey = GlobalKey();
  bool _hasScrolled = false;

  /// 进入高亮模式后锁定 block-based 渲染，避免取消高亮时切换 widget 树导致闪屏
  bool _useBlockMode = false;

  /// 管理用户划线的 TapGestureRecognizer，在 dispose 时统一释放
  _UserHighlightBuilder? _highlightBuilder;

  @override
  void didUpdateWidget(covariant ReaderMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetCharOffset != oldWidget.targetCharOffset ||
        widget.highlightQuery != oldWidget.highlightQuery) {
      _hasScrolled = false;
      if (_isHighlightMode) _useBlockMode = true;
    }
    // 划线变化时重建 builder
    if (widget.highlights != oldWidget.highlights) {
      _highlightBuilder?.dispose();
      _highlightBuilder = null;
    }
  }

  bool get _isHighlightMode =>
      widget.highlightQuery != null &&
      widget.highlightQuery!.isNotEmpty &&
      widget.targetCharOffset != null;

  void _scheduleScrollToTarget() {
    if (_hasScrolled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasScrolled) return;
      final ctx = _targetKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        _hasScrolled = true;
      }
    });
  }

  @override
  void dispose() {
    _highlightBuilder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_useBlockMode) {
      return _buildBlockBased(context);
    }
    return _buildSingleBody(context);
  }

  // ─── 普通模式：单 MarkdownBody ───

  Widget _buildSingleBody(BuildContext context) {
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: _markdownBody(widget.data, context),
    );
  }

  // ─── 高亮模式：按段落拆分 + 精准跳转 ───

  Widget _buildBlockBased(BuildContext context) {
    final blocks = _splitIntoBlocks(widget.data);
    final targetIndex = widget.targetCharOffset != null
        ? _findTargetBlock(blocks, widget.targetCharOffset!)
        : -1;

    if (targetIndex >= 0) _scheduleScrollToTarget();

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(blocks.length, (i) {
          final block = blocks[i];
          Widget child = _markdownBody(block.text, context);
          if (i == targetIndex) {
            child = Container(key: _targetKey, child: child);
          }
          return child;
        }),
      ),
    );
  }

  // ─── 共享的 MarkdownBody 构造 ───

  Widget _markdownBody(String data, BuildContext context) {
    final settings = widget.settings;
    final cs = Theme.of(context).colorScheme;

    final baseStyle = TextStyle(
      color: settings.textColor,
      fontSize: settings.fontSize,
      fontFamily: settings.font.fontFamily,
      fontFamilyFallback: settings.font.fontFamilyFallback,
      height: 1.7,
    );

    final builders = <String, MarkdownElementBuilder>{
      'latex': NRLatexElementBuilder(
        textStyle: TextStyle(
          color: settings.textColor,
          fontFamily: settings.font.fontFamily,
          fontFamilyFallback: settings.font.fontFamilyFallback,
        ),
      ),
      'emoji': _EmojiElementBuilder(),
    };

    final inlineSyntaxes = <md.InlineSyntax>[
      NRLatexInlineSyntax(),
      ...md.ExtensionSet.gitHubWeb.inlineSyntaxes,
    ];

    // 搜索高亮模式
    if (_isHighlightMode) {
      inlineSyntaxes.add(_HighlightInlineSyntax(widget.highlightQuery!));
      builders['highlight'] = _HighlightElementBuilder(
        backgroundColor: cs.primaryContainer,
        textColor: cs.onPrimaryContainer,
      );
    }

    // 用户标记
    if (widget.highlights.isNotEmpty) {
      inlineSyntaxes.insert(
        0,
        _UserHighlightSyntax(widget.highlights),
      );
      _highlightBuilder?.dispose();
      _highlightBuilder = _UserHighlightBuilder(
        highlights: widget.highlights,
        highlightColor: cs.primary.withAlpha(50),
        onTap: (highlight, position) {
          widget.onHighlightTap?.call(highlight, position);
        },
      );
      builders['user_highlight'] = _highlightBuilder!;
    }

    final styleSheet = _buildStyleSheet(settings, baseStyle);

    // 用 ValueKey 强制 MarkdownBody 在标记变化时完整重建，
    // 因为 flutter_markdown 只在 data/styleSheet 变化时才重新解析。
    final highlightKey = widget.highlights.map((h) => h.id).join(',');

    return MarkdownBody(
      key: ValueKey('md_$highlightKey'),
      data: data,
      styleSheet: styleSheet,
      builders: builders,
      extensionSet: md.ExtensionSet(
        [LatexBlockSyntax(), ...md.ExtensionSet.gitHubWeb.blockSyntaxes],
        inlineSyntaxes,
      ),
      imageBuilder: _buildImage,
    );
  }

  MarkdownStyleSheet _buildStyleSheet(
    ReaderSettingsState settings,
    TextStyle baseStyle,
  ) {
    return MarkdownStyleSheet(
      p: baseStyle,
      h1: baseStyle.copyWith(
        fontSize: settings.fontSize * 1.6,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h2: baseStyle.copyWith(
        fontSize: settings.fontSize * 1.35,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      h3: baseStyle.copyWith(
        fontSize: settings.fontSize * 1.15,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h4: baseStyle.copyWith(
        fontSize: settings.fontSize * 1.05,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h5: baseStyle.copyWith(fontWeight: FontWeight.w600, height: 1.4),
      h6: baseStyle.copyWith(
        fontWeight: FontWeight.w500,
        color: settings.secondaryTextColor,
        height: 1.4,
      ),
      blockquote: baseStyle.copyWith(
        color: settings.secondaryTextColor,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: settings.dividerColor, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      code: TextStyle(
        fontFamily: 'Consolas',
        fontFamilyFallback: const [
          'Cascadia Mono',
          'Courier New',
          'Menlo',
          'Noto Sans Mono',
        ],
        fontSize: settings.fontSize * 0.88,
        color: settings.textColor,
        backgroundColor: settings.theme == ReaderTheme.dark
            ? const Color(0xFF2D2D3A)
            : const Color(0xFFF5F5F5),
      ),
      codeblockDecoration: BoxDecoration(
        color: settings.theme == ReaderTheme.dark
            ? const Color(0xFF2D2D3A)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      a: baseStyle.copyWith(
        color: settings.linkColor,
        decoration: TextDecoration.none,
      ),
      listBullet: baseStyle.copyWith(color: settings.secondaryTextColor),
      tableHead: baseStyle.copyWith(fontWeight: FontWeight.w600),
      tableBody: baseStyle,
      tableBorder: TableBorder.all(color: settings.dividerColor, width: 0.5),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: settings.dividerColor, width: 1),
        ),
      ),
      blockSpacing: settings.fontSize * 0.8,
    );
  }

  Widget _buildImage(Uri uri, String? title, String? alt) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget image;
        if (uri.scheme == 'file') {
          final file = File(uri.toFilePath());
          if (file.existsSync()) {
            image = Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_rounded,
                size: 48,
              ),
            );
          } else {
            image = Image.network(
              uri.toString(),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_rounded,
                size: 48,
              ),
            );
          }
        } else {
          image = Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_rounded,
              size: 48,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: image,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── 段落拆分工具 ───

class _MdBlock {
  final String text;
  final int charOffset;
  const _MdBlock({required this.text, required this.charOffset});
}

List<_MdBlock> _splitIntoBlocks(String markdown) {
  final blocks = <_MdBlock>[];
  final matches = RegExp(r'\n\n+').allMatches(markdown).toList();

  var start = 0;
  for (final match in matches) {
    final text = markdown.substring(start, match.start).trim();
    if (text.isNotEmpty) {
      blocks.add(_MdBlock(text: text, charOffset: start));
    }
    start = match.end;
  }

  if (start < markdown.length) {
    final text = markdown.substring(start).trim();
    if (text.isNotEmpty) {
      blocks.add(_MdBlock(text: text, charOffset: start));
    }
  }

  return blocks;
}

int _findTargetBlock(List<_MdBlock> blocks, int charOffset) {
  for (var i = blocks.length - 1; i >= 0; i--) {
    if (blocks[i].charOffset <= charOffset) return i;
  }
  return 0;
}

// ─── 搜索词高亮 InlineSyntax ───

class _HighlightInlineSyntax extends md.InlineSyntax {
  _HighlightInlineSyntax(String query)
      : super(_buildCaseInsensitivePattern(query));

  /// 将查询词转为大小写不敏感的正则模式
  /// "where" → "([wW][hH][eE][rR][eE])"
  static String _buildCaseInsensitivePattern(String query) {
    final buffer = StringBuffer();
    for (final char in query.split('')) {
      if (RegExp(r'[a-zA-Z]').hasMatch(char)) {
        buffer.write('[${char.toLowerCase()}${char.toUpperCase()}]');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    return '(${buffer.toString()})';
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('highlight', match.group(0)!);
    parser.addNode(el);
    return true;
  }
}

/// Emoji 渲染器：将 :shortcode: 解析后的 Unicode emoji 以文本形式输出。
class _EmojiElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style =
        parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style;
    return RichText(
      text: TextSpan(text: element.textContent, style: style),
    );
  }
}

/// 搜索词高亮渲染器，使用 MD3 primaryContainer 配色。
/// 返回 RichText 而非 Container，使 _mergeInlineChildren 可将其合并到
/// 相邻 TextSpan 中，避免单词内部断行（如 "shows" 中 "show" 与 "s" 分行）。
class _HighlightElementBuilder extends MarkdownElementBuilder {
  final Color backgroundColor;
  final Color textColor;

  _HighlightElementBuilder({
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style =
        parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style;
    return RichText(
      text: TextSpan(
        text: element.textContent,
        style: style.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
          backgroundColor: backgroundColor,
        ),
      ),
    );
  }
}

// ─── 用户标记 InlineSyntax + ElementBuilder ───

/// 匹配所有已保存标记文本的 InlineSyntax。
///
/// 将多条标记文本构建为一个正则交替模式 `(text1|text2|...)`，
/// 按长度降序排列确保长文本优先匹配。
class _UserHighlightSyntax extends md.InlineSyntax {
  _UserHighlightSyntax(List<Highlight> highlights)
      : super(_buildPattern(highlights));

  static String _buildPattern(List<Highlight> highlights) {
    if (highlights.isEmpty) return r'(?!)'; // 永不匹配
    // 跨段落标记按换行拆分为独立片段，InlineSyntax 只能匹配单段落内容
    final fragments = <String>{};
    for (final h in highlights) {
      for (final line in h.text.split(RegExp(r'\n+'))) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) fragments.add(RegExp.escape(trimmed));
      }
    }
    if (fragments.isEmpty) return r'(?!)';
    final sorted = fragments.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return '(${sorted.join('|')})';
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('user_highlight', match.group(0)!);
    parser.addNode(el);
    return true;
  }
}

/// 用户标记渲染器：MD3 主题色半透明背景 + 点击手势。
///
/// 内部维护 [TapGestureRecognizer] 列表，使用方需在 widget dispose 时
/// 调用 [dispose] 释放资源。
class _UserHighlightBuilder extends MarkdownElementBuilder {
  final List<Highlight> highlights;
  final Color highlightColor;
  final void Function(Highlight highlight, Offset globalPosition) onTap;
  final List<TapGestureRecognizer> _recognizers = [];

  _UserHighlightBuilder({
    required this.highlights,
    required this.highlightColor,
    required this.onTap,
  });

  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style =
        parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style;
    final text = element.textContent;

    // 精确匹配；历史含 \n 数据做片段回退
    var idx = highlights.indexWhere((h) => h.text == text);
    if (idx < 0) {
      idx = highlights.indexWhere(
        (h) =>
            h.text.contains('\n') &&
            h.text.split(RegExp(r'\n+')).any((l) => l.trim() == text),
      );
    }

    // 无匹配时仅渲染高亮背景，不绑定手势
    if (idx < 0) {
      return RichText(
        text: TextSpan(
          text: text,
          style: style.copyWith(backgroundColor: highlightColor),
        ),
      );
    }

    final highlight = highlights[idx];
    final recognizer = TapGestureRecognizer()
      ..onTapUp = (details) {
        onTap(highlight, details.globalPosition);
      };
    _recognizers.add(recognizer);

    return RichText(
      text: TextSpan(
        text: text,
        style: style.copyWith(backgroundColor: highlightColor),
        recognizer: recognizer,
      ),
    );
  }
}
