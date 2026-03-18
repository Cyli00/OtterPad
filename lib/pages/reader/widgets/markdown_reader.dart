import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../data/models/book/highlight.dart';
import '../../../providers/reader_settings_provider.dart';
import 'markdown_rendering.dart';

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

  List<_MdBlock>? _cachedBlocks;
  String? _cachedBlockSource;
  _ReaderMarkdownRenderResources? _renderResources;

  bool _isHighlightModeFor(ReaderMarkdownBody widget) {
    return widget.highlightQuery != null &&
        widget.highlightQuery!.isNotEmpty &&
        widget.targetCharOffset != null;
  }

  @override
  void didUpdateWidget(covariant ReaderMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldHighlightMode = _isHighlightModeFor(oldWidget);
    if (widget.targetCharOffset != oldWidget.targetCharOffset ||
        widget.highlightQuery != oldWidget.highlightQuery) {
      _hasScrolled = false;
      if (_isHighlightMode) _useBlockMode = true;
      if (!_isHighlightMode && oldHighlightMode && _useBlockMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isHighlightMode || !_useBlockMode) return;
          setState(() => _useBlockMode = false);
        });
      }
    }
    if (widget.data != oldWidget.data) {
      _cachedBlockSource = null;
      _cachedBlocks = null;
    }
    if (widget.settings != oldWidget.settings ||
        widget.highlightQuery != oldWidget.highlightQuery ||
        widget.highlights != oldWidget.highlights ||
        widget.onHighlightTap != oldWidget.onHighlightTap) {
      _disposeRenderResources();
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
    _disposeRenderResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resources = _resolveRenderResources(context);
    final useBlockMode = _useBlockMode || _isHighlightMode;
    if (useBlockMode) {
      return _buildBlockBased(resources);
    }
    return _buildSingleBody(resources);
  }

  // ─── 普通模式：单 MarkdownBody ───

  Widget _buildSingleBody(_ReaderMarkdownRenderResources resources) {
    resources.prepareForBuild();
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: _markdownBody(
        data: widget.data,
        keySuffix: 'full_${resources.renderKeySalt}',
        resources: resources,
      ),
    );
  }

  // ─── 高亮模式：按段落拆分 + 精准跳转 ───

  Widget _buildBlockBased(_ReaderMarkdownRenderResources resources) {
    resources.prepareForBuild();
    final blocks = _getBlocks();
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
          Widget child = _markdownBody(
            data: block.text,
            keySuffix: '${block.charOffset}_${resources.renderKeySalt}',
            resources: resources,
          );
          if (i == targetIndex) {
            child = Container(key: _targetKey, child: child);
          }
          return child;
        }),
      ),
    );
  }

  // ─── 共享的 MarkdownBody 构造 ───

  Widget _markdownBody({
    required String data,
    required String keySuffix,
    required _ReaderMarkdownRenderResources resources,
  }) {
    return MarkdownBody(
      key: ValueKey('md_$keySuffix'),
      data: data,
      styleSheet: resources.styleSheet,
      builders: resources.builders,
      extensionSet: resources.extensionSet,
      imageBuilder: buildMarkdownImage,
    );
  }

  List<_MdBlock> _getBlocks() {
    if (_cachedBlockSource != widget.data || _cachedBlocks == null) {
      _cachedBlockSource = widget.data;
      _cachedBlocks = _splitIntoBlocks(widget.data);
    }
    return _cachedBlocks!;
  }

  _ReaderMarkdownRenderResources _resolveRenderResources(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resources = _renderResources;
    if (resources != null &&
        resources.primary == colorScheme.primary &&
        resources.primaryContainer == colorScheme.primaryContainer &&
        resources.onPrimaryContainer == colorScheme.onPrimaryContainer) {
      return resources;
    }
    _disposeRenderResources();
    final next = _ReaderMarkdownRenderResources.create(
      settings: widget.settings,
      colorScheme: colorScheme,
      highlightQuery: _isHighlightMode ? widget.highlightQuery : null,
      highlights: widget.highlights,
      onHighlightTap: widget.onHighlightTap,
    );
    _renderResources = next;
    return next;
  }

  void _disposeRenderResources() {
    _renderResources?.dispose();
    _renderResources = null;
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
  var low = 0;
  var high = blocks.length - 1;
  var result = 0;

  while (low <= high) {
    final mid = low + ((high - low) >> 1);
    final offset = blocks[mid].charOffset;
    if (offset <= charOffset) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  return result;
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
  _UserHighlightSyntax(super.pattern);

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
  final Map<String, Highlight> highlightByFragment;
  final Color highlightColor;
  final void Function(Highlight highlight, Offset globalPosition) onTap;
  final List<TapGestureRecognizer> _recognizers = [];

  _UserHighlightBuilder({
    required this.highlightByFragment,
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
    final highlight = highlightByFragment[text];

    // 无匹配时仅渲染高亮背景，不绑定手势
    if (highlight == null) {
      return RichText(
        text: TextSpan(
          text: text,
          style: style.copyWith(backgroundColor: highlightColor),
        ),
      );
    }

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

class _ReaderMarkdownRenderResources {
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final md.ExtensionSet extensionSet;
  final String renderKeySalt;
  final Color primary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final _UserHighlightBuilder? highlightBuilder;

  const _ReaderMarkdownRenderResources({
    required this.styleSheet,
    required this.builders,
    required this.extensionSet,
    required this.renderKeySalt,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.highlightBuilder,
  });

  factory _ReaderMarkdownRenderResources.create({
    required ReaderSettingsState settings,
    required ColorScheme colorScheme,
    required String? highlightQuery,
    required List<Highlight> highlights,
    required void Function(Highlight highlight, Offset globalPosition)?
    onHighlightTap,
  }) {
    final baseStyle = TextStyle(
      color: settings.textColor,
      fontSize: settings.fontSize,
      fontFamily: settings.font.fontFamily,
      fontFamilyFallback: settings.font.fontFamilyFallback,
      height: 1.7,
    );

    final extraBuilders = <String, MarkdownElementBuilder>{};
    final prefixSyntaxes = <md.InlineSyntax>[];
    final suffixSyntaxes = <md.InlineSyntax>[];

    _UserHighlightBuilder? highlightBuilder;
    if (highlights.isNotEmpty) {
      final fragmentIndex = _UserHighlightFragmentIndex.fromHighlights(
        highlights,
      );
      prefixSyntaxes.add(_UserHighlightSyntax(fragmentIndex.pattern));
      highlightBuilder = _UserHighlightBuilder(
        highlightByFragment: fragmentIndex.highlightByFragment,
        highlightColor: colorScheme.primary.withAlpha(50),
        onTap: (highlight, position) {
          onHighlightTap?.call(highlight, position);
        },
      );
      extraBuilders['user_highlight'] = highlightBuilder;
    }

    if (highlightQuery != null && highlightQuery.isNotEmpty) {
      suffixSyntaxes.add(_HighlightInlineSyntax(highlightQuery));
      extraBuilders['highlight'] = _HighlightElementBuilder(
        backgroundColor: colorScheme.primaryContainer,
        textColor: colorScheme.onPrimaryContainer,
      );
    }

    final inlineSyntaxes = buildMarkdownInlineSyntaxes(
      prefix: prefixSyntaxes,
      suffix: suffixSyntaxes,
    );

    return _ReaderMarkdownRenderResources(
      styleSheet: _buildStyleSheet(settings, baseStyle),
      builders: buildMarkdownBuilders(
        latexTextStyle: TextStyle(
          color: settings.textColor,
          fontFamily: settings.font.fontFamily,
          fontFamilyFallback: settings.font.fontFamilyFallback,
        ),
        extraBuilders: extraBuilders,
      ),
      extensionSet: buildMarkdownExtensionSet(inlineSyntaxes),
      renderKeySalt: Object.hash(
        highlightQuery,
        Object.hashAll(
          highlights.map((h) => Object.hash(h.id, h.text, h.groupId)),
        ),
      ).toString(),
      primary: colorScheme.primary,
      primaryContainer: colorScheme.primaryContainer,
      onPrimaryContainer: colorScheme.onPrimaryContainer,
      highlightBuilder: highlightBuilder,
    );
  }

  void dispose() {
    highlightBuilder?.dispose();
  }

  void prepareForBuild() {
    highlightBuilder?.dispose();
  }
}

class _UserHighlightFragmentIndex {
  final String pattern;
  final Map<String, Highlight> highlightByFragment;

  const _UserHighlightFragmentIndex({
    required this.pattern,
    required this.highlightByFragment,
  });

  factory _UserHighlightFragmentIndex.fromHighlights(
    List<Highlight> highlights,
  ) {
    if (highlights.isEmpty) {
      return const _UserHighlightFragmentIndex(
        pattern: r'(?!)',
        highlightByFragment: {},
      );
    }

    final highlightByFragment = <String, Highlight>{};
    for (final highlight in highlights) {
      for (final line in highlight.text.split(RegExp(r'\n+'))) {
        final fragment = line.trim();
        if (fragment.isEmpty) continue;
        highlightByFragment.putIfAbsent(fragment, () => highlight);
      }
    }

    if (highlightByFragment.isEmpty) {
      return const _UserHighlightFragmentIndex(
        pattern: r'(?!)',
        highlightByFragment: {},
      );
    }

    final escapedFragments =
        highlightByFragment.keys.map(RegExp.escape).toList()
          ..sort((a, b) => b.length.compareTo(a.length));

    return _UserHighlightFragmentIndex(
      pattern: '(${escapedFragments.join('|')})',
      highlightByFragment: highlightByFragment,
    );
  }
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
      border: Border(left: BorderSide(color: settings.dividerColor, width: 3)),
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
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: settings.dividerColor, width: 1)),
    ),
    blockSpacing: settings.fontSize * 0.8,
  );
}
