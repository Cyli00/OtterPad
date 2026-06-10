import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../../core/animation_constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../providers/api_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../router/app_router.dart';
import '../../../router/app_routes.dart';
import '../../../services/ai_settings_prompt.dart';
import '../../../services/haptics.dart';
import '../../../services/snackbar_service.dart';
import '../../../core/l10n.dart';
import '../../../services/translation_service.dart';

/// 打开一个流式翻译小窗口展示 [sourceText] 的译文。
///
/// 走 [TranslationService.translateStream]——每次 token 增量都会实时
/// 更新 UI，直到流结束。缓存命中时瞬时出完整译文。
Future<void> showTranslationPopup(
  BuildContext context, {
  required String sourceText,
  String? fullText,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final agentState = container.read(effectiveAgentApiProvider);
  final snackBar = container.read(snackBarServiceProvider);
  void openSettings() {
    container.read(routerProvider).push(AppRoutes.settingsApi);
  }

  if (!AiSettingsPrompt.ensureTextModelConfigured(
    agentState: agentState,
    snackBar: snackBar,
    onOpenSettings: openSettings,
  )) {
    return;
  }

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    builder: (_) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: _TranslationPopup(sourceText: sourceText, fullText: fullText),
    ),
  );
}

class _TranslationPopup extends ConsumerStatefulWidget {
  final String sourceText;
  final String? fullText;
  const _TranslationPopup({required this.sourceText, this.fullText});

  @override
  ConsumerState<_TranslationPopup> createState() => _TranslationPopupState();
}

class _TranslationPopupState extends ConsumerState<_TranslationPopup> {
  StreamSubscription<String>? _sub;
  String _latest = '';
  Object? _error;
  bool _done = false;

  final _sourceAnchorKey = GlobalKey();
  final _bodyAnchorKey = GlobalKey();

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

  static const _hlOpen = '⟪';
  static const _hlClose = '⟫';

  bool get _hasHighlight =>
      widget.fullText != null && widget.fullText != widget.sourceText;

  String get _effectiveFullText => widget.fullText ?? widget.sourceText;

  String get _errorText => '$_error'.replaceFirst('Exception: ', '');

  /// 在 [haystack] 中定位 [needle]，返回原始坐标 (start, end)。
  /// 先尝试直接匹配，失败后完全剥离空白再匹配——处理跨段落选择
  /// 丢失 `\n\n` 分隔符甚至连空格都没有的情况。
  static (int, int)? _findInFullText(String haystack, String needle) {
    final direct = haystack.indexOf(needle);
    if (direct >= 0) return (direct, direct + needle.length);

    // 完全剥离空白后做匹配，通过位置映射回溯到原文坐标
    final origPos = <int>[];
    final normBuf = StringBuffer();
    for (int i = 0; i < haystack.length; i++) {
      final c = haystack.codeUnitAt(i);
      if (c != 0x20 && c != 0x0A && c != 0x0D && c != 0x09) {
        normBuf.writeCharCode(c);
        origPos.add(i);
      }
    }

    final normH = normBuf.toString();
    final normN = needle.replaceAll(RegExp(r'\s+'), '');
    final idx = normH.indexOf(normN);
    if (idx < 0 || idx + normN.length > origPos.length) return null;

    final start = origPos[idx];
    final end = origPos[idx + normN.length - 1] + 1;
    return (start, end);
  }

  ({String text, int? hlStart, int? hlEnd}) _parseTranslationHighlight() {
    final raw = _latest;
    final s = raw.indexOf(_hlOpen);
    if (s < 0) return (text: raw, hlStart: null, hlEnd: null);

    final e = raw.indexOf(_hlClose);
    final clean = raw.replaceAll(_hlOpen, '').replaceAll(_hlClose, '');
    return (text: clean, hlStart: s, hlEnd: e >= 0 ? e - 1 : clean.length);
  }

  void _start() {
    final agentState = ref.read(effectiveAgentApiProvider);
    final config = ref.read(translationConfigProvider);

    String textToTranslate = _effectiveFullText;
    String? extraInstruction;

    if (_hasHighlight) {
      final range = _findInFullText(_effectiveFullText, widget.sourceText);
      if (range != null) {
        final (s, e) = range;
        textToTranslate =
            '${_effectiveFullText.substring(0, s)}$_hlOpen${_effectiveFullText.substring(s, e)}$_hlClose${_effectiveFullText.substring(e)}';
        extraInstruction =
            '原文中 $_hlOpen$_hlClose 标记包裹的是用户重点关注的部分。在译文中，用相同的 $_hlOpen$_hlClose 标记包裹对应的译文部分。不要翻译或省略标记本身。';
      }
    }

    final stream = TranslationService.translateStream(
      text: textToTranslate,
      agentState: agentState,
      translationConfig: config,
      extraSystemInstruction: extraInstruction,
    );

    _sub = stream.listen(
      (value) {
        if (!mounted) return;
        setState(() => _latest = value);
      },
      onError: (e) {
        if (!mounted) return;
        final handled = AiSettingsPrompt.showForConfigError(
          error: e,
          snackBar: ref.read(snackBarServiceProvider),
          onOpenSettings: () =>
              ref.read(routerProvider).push(AppRoutes.settingsApi),
        );
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
      final range = _findInFullText(fullText, widget.sourceText);
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
          thumbVisibility: true,
          child: SingleChildScrollView(
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
      thumbVisibility: true,
      child: SingleChildScrollView(
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
