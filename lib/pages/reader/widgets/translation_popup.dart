import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../../core/animation_constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/models/book/highlight.dart';
import '../../../providers/api_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../services/ai_settings_prompt.dart';
import '../../../services/haptics.dart';
import '../../../services/snackbar_service.dart';
import '../../../core/l10n.dart';
import '../../../services/translation_highlight_parser.dart';
import '../../../services/translation_service.dart';
import '../../../widgets/tactile_press.dart';

/// 打开一个流式翻译小窗口展示 [sourceText] 的译文。
///
/// 走 [TranslationService.translateStream]——每次 token 增量都会实时
/// 更新 UI，直到流结束。缓存命中时瞬时出完整译文。
Future<void> showTranslationPopup(
  BuildContext context, {
  required String sourceText,
  String? fullText,
  void Function(String colorHex, String note)? onAddNote,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final agentState = container.read(effectiveAgentApiProvider);

  if (!await AiSettingsPrompt.ensureTextModelConfigured(
    context: context,
    agentState: agentState,
  )) {
    return;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    builder: (_) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: _TranslationPopup(
        sourceText: sourceText,
        fullText: fullText,
        onAddNote: onAddNote,
      ),
    ),
  );
}

class _TranslationPopup extends ConsumerStatefulWidget {
  final String sourceText;
  final String? fullText;

  /// 「添加到注释」回调：把选取段落按 [colorHex] 高亮并以 [note]（译文）
  /// 作为注解。null = 不显示该按钮。
  final void Function(String colorHex, String note)? onAddNote;

  const _TranslationPopup({
    required this.sourceText,
    this.fullText,
    this.onAddNote,
  });

  @override
  ConsumerState<_TranslationPopup> createState() => _TranslationPopupState();
}

class _TranslationPopupState extends ConsumerState<_TranslationPopup> {
  StreamSubscription<String>? _sub;
  String _latest = '';
  Object? _error;
  bool _done = false;
  bool _noteAdded = false;

  final _sourceAnchorKey = GlobalKey();
  final _bodyAnchorKey = GlobalKey();

  // 原文框与译文区各自独立的 controller——两个 thumbVisibility 滚动条
  // 若都回退到 PrimaryScrollController 会触发多 ScrollPosition 断言。
  final _sourceScrollCtrl = ScrollController();
  final _bodyScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _start();
    if (_hasHighlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _sourceAnchorKey.currentContext;
        if (ctx != null && mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.3,
            duration: const Duration(milliseconds: 300),
            curve: kAnimCurve,
          );
        }
      });
    }
  }

  /// %%%% 分隔符模式下，选区对应的段索引（-1 = 无分隔）
  int _hlSegmentIndex = -1;

  bool get _hasHighlight =>
      widget.fullText != null && widget.fullText != widget.sourceText;

  String get _effectiveFullText => widget.fullText ?? widget.sourceText;

  String get _errorText => '$_error'.replaceFirst('Exception: ', '');

  ({String text, int? hlStart, int? hlEnd}) _parseTranslationHighlight() {
    return TranslationHighlightParser.parse(_latest, _hlSegmentIndex);
  }

  void _start() {
    final agentState = ref.read(effectiveAgentApiProvider);
    final config = ref.read(translationConfigProvider);

    String textToTranslate = _effectiveFullText;

    if (_hasHighlight) {
      final segmented = TranslationHighlightParser.buildSegmentedInput(
        _effectiveFullText,
        widget.sourceText,
      );
      textToTranslate = segmented.text;
      _hlSegmentIndex = segmented.hlSegmentIndex;
    }

    final stream = TranslationService.translateStream(
      text: textToTranslate,
      agentState: agentState,
      translationConfig: config,
    );

    _sub = stream.listen(
      (value) {
        if (!mounted) return;
        setState(() => _latest = value);
      },
      onError: (e) async {
        if (!mounted) return;
        final handled = await AiSettingsPrompt.showForConfigError(
          context: context,
          error: e,
        );
        if (!mounted) return;
        if (handled) {
          Navigator.of(context, rootNavigator: true).pop();
          return;
        }
        setState(() {
          _error = e;
          _done = true;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _done = true);
        if (_hasHighlight) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _bodyAnchorKey.currentContext;
            if (ctx != null && mounted) {
              Scrollable.ensureVisible(
                ctx,
                alignment: 0.3,
                duration: const Duration(milliseconds: 300),
                curve: kAnimCurve,
              );
            }
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sourceScrollCtrl.dispose();
    _bodyScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(theme, cs),
              const SizedBox(height: 12),
              _buildSource(theme, cs),
              const SizedBox(height: 12),
              Flexible(child: _buildBody(theme, cs)),
              const SizedBox(height: 8),
              _buildFooter(theme, cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    return Row(
      children: [
        Icon(
          Symbols.translate_rounded,
          color: cs.primary,
          size: 22,
          weight: 600,
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.translateText,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Symbols.close_rounded, size: 20),
          color: cs.onSurfaceVariant,
          tooltip: context.l10n.close,
          onPressed: () {
            Haptics.soft();
            Navigator.of(context).pop();
          },
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildSource(ThemeData theme, ColorScheme cs) {
    final readerFont = ref.watch(readerSettingsProvider).font;
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      height: 1.5,
      fontFamily: readerFont.fontFamily,
      fontFamilyFallback: readerFont.fontFamilyFallback,
    );

    final fullText = _effectiveFullText;
    TextSpan sourceSpan;
    if (_hasHighlight) {
      final range = TranslationHighlightParser.findInFullText(fullText, widget.sourceText);
      if (range != null) {
        final (s, e) = range;
        sourceSpan = TextSpan(
          style: baseStyle,
          children: [
            if (s > 0) TextSpan(text: fullText.substring(0, s)),
            WidgetSpan(child: SizedBox.shrink(key: _sourceAnchorKey)),
            TextSpan(
              text: fullText.substring(s, e),
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
            ),
            if (e < fullText.length) TextSpan(text: fullText.substring(e)),
          ],
        );
      } else {
        sourceSpan = TextSpan(text: fullText, style: baseStyle);
      }
    } else {
      sourceSpan = TextSpan(text: fullText, style: baseStyle);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 140),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withAlpha(80)),
        ),
        child: Scrollbar(
          controller: _sourceScrollCtrl,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _sourceScrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text.rich(sourceSpan),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs) {
    final parsed = _parseTranslationHighlight();

    if (_error != null && parsed.text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Symbols.error_rounded, color: cs.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.translationFailed(_errorText),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (parsed.text.isEmpty && !_done) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final readerFont = ref.watch(readerSettingsProvider).font;
    final displayText = parsed.text;

    final List<InlineSpan> spans;
    if (parsed.hlStart != null && _hasHighlight) {
      final s = parsed.hlStart!.clamp(0, displayText.length);
      final e = parsed.hlEnd!.clamp(s, displayText.length);
      spans = [
        if (s > 0) TextSpan(text: displayText.substring(0, s)),
        WidgetSpan(child: SizedBox.shrink(key: _bodyAnchorKey)),
        TextSpan(
          text: displayText.substring(s, e),
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
        ),
        if (e < displayText.length) TextSpan(text: displayText.substring(e)),
        if (!_done)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _BlinkingCursor(color: cs.primary),
          ),
      ];
    } else {
      spans = [
        TextSpan(text: displayText),
        if (!_done)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _BlinkingCursor(color: cs.primary),
          ),
      ];
    }

    return Scrollbar(
      controller: _bodyScrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _bodyScrollCtrl,
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: SelectableText.rich(
          TextSpan(children: spans),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: cs.onSurface,
            height: 1.65,
            fontFamily: readerFont.fontFamily,
            fontFamilyFallback: readerFont.fontFamilyFallback,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, ColorScheme cs) {
    final parsed = _parseTranslationHighlight();
    if (parsed.text.isEmpty) return const SizedBox.shrink();

    // 有高亮时只复制高亮区段，无高亮时复制全文
    final String copyTranslation;
    final String copySource;
    if (_hasHighlight && parsed.hlStart != null) {
      final s = parsed.hlStart!.clamp(0, parsed.text.length);
      final e = parsed.hlEnd!.clamp(s, parsed.text.length);
      copyTranslation = parsed.text.substring(s, e);
      copySource = widget.sourceText;
    } else {
      copyTranslation = parsed.text;
      copySource = _effectiveFullText;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          if (!_done)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: cs.primary.withAlpha(160),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.streaming,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const Spacer(),
          // 添加到注释：选颜色 → 高亮选取段落 + 译文作注解。流结束后才可用
          // （注解内容是完整译文）。
          if (widget.onAddNote != null && _done)
            PopupMenuButton<String>(
              enabled: !_noteAdded,
              icon: Icon(
                _noteAdded
                    ? Symbols.check_circle_rounded
                    : Symbols.bookmark_add_rounded,
                size: 20,
                color: _noteAdded ? cs.primary : cs.onSurfaceVariant,
              ),
              tooltip: context.l10n.addToNote,
              // 与 toolbar 色盘同款横排圆点，配色随对话框主题
              color: cs.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              // 成功反馈靠按钮自身（图标变 ✓ + 触觉）：snackbar 渲染在
              // 页面 Scaffold 层，会被对话框的模糊 barrier 盖住，看不见。
              onSelected: (color) {
                Haptics.soft();
                widget.onAddNote!(color, copyTranslation);
                setState(() => _noteAdded = true);
              },
              itemBuilder: (menuContext) => [
                PopupMenuItem<String>(
                  enabled: false,
                  height: 36,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final color in kHighlightColors)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: TactilePress(
                            onTap: () =>
                                Navigator.pop(menuContext, color),
                            baseColor: Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(int.parse('0xFF$color'))
                                    .withAlpha(200),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          PopupMenuButton<String>(
            icon: Icon(
              Symbols.content_copy_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            tooltip: context.l10n.copy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              Haptics.soft();
              final text = switch (value) {
                'translation' => copyTranslation,
                'source' => copySource,
                'all' => '$copySource\n\n$copyTranslation',
                _ => copyTranslation,
              };
              Clipboard.setData(ClipboardData(text: text));
              ref
                  .read(snackBarServiceProvider)
                  .showResult(
                    message: context.l10n.copied,
                    duration: const Duration(seconds: 1),
                  );
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'translation',
                child: Text(context.l10n.copyTranslation, style: theme.textTheme.bodyMedium),
              ),
              PopupMenuItem(
                value: 'source',
                child: Text(context.l10n.copyOriginal, style: theme.textTheme.bodyMedium),
              ),
              PopupMenuItem(
                value: 'all',
                child: Text(context.l10n.copyAll, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 文本末尾的闪烁光标——纯视觉暗示"流式还在继续"。
class _BlinkingCursor extends StatefulWidget {
  final Color color;
  const _BlinkingCursor({required this.color});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        // 方波：前 50% 可见，后 50% 隐藏，符合文本光标的视觉习惯
        final visible = _ctrl.value < 0.5;
        return Opacity(
          opacity: visible ? 1.0 : 0.0,
          child: Container(
            margin: const EdgeInsets.only(left: 2),
            width: 2,
            height: 16,
            color: widget.color,
          ),
        );
      },
    );
  }
}
