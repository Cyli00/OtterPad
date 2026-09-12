import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/elevation.dart';
import '../../core/l10n.dart';
import '../../data/models/ai/agent_config.dart';
import '../../services/haptics.dart';
import '../../utils/desktop.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/tactile_press.dart';

/// 打开「模型能力」编辑 sheet（照搬 kelivo 基础页：类型 + 模态 + 能力）。
///
/// 改动即时通过 [onSave] 写入；[onReset] 删除覆盖、回落自动推断。
Future<void> showAgentModelCapabilitySheet({
  required BuildContext context,
  required String modelId,
  required AgentApiProvider protocol,
  required AgentModelCapability initial,
  required AgentModelCapability inferred,
  required ValueChanged<AgentModelCapability> onSave,
  required VoidCallback onReset,
  ThinkingLevel? initialThinkingLevel,
  ValueChanged<ThinkingLevel?>? onThinkingLevelChanged,
}) {
  final content = _ModelCapabilitySheet(
    modelId: modelId,
    protocol: protocol,
    initial: initial,
    inferred: inferred,
    onSave: onSave,
    onReset: onReset,
    initialThinkingLevel: initialThinkingLevel,
    onThinkingLevelChanged: onThinkingLevelChanged,
    asDialog: isDesktopOs,
  );
  if (isDesktopOs) {
    return showAppDialog<void>(context: context, builder: (_) => content);
  }
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => content,
  );
}

class _ModelCapabilitySheet extends StatefulWidget {
  final String modelId;
  final AgentApiProvider protocol;
  final AgentModelCapability initial;
  final AgentModelCapability inferred;
  final ValueChanged<AgentModelCapability> onSave;
  final VoidCallback onReset;
  final ThinkingLevel? initialThinkingLevel;
  final ValueChanged<ThinkingLevel?>? onThinkingLevelChanged;
  final bool asDialog;

  const _ModelCapabilitySheet({
    required this.modelId,
    required this.protocol,
    required this.initial,
    required this.inferred,
    required this.onSave,
    required this.onReset,
    this.initialThinkingLevel,
    this.onThinkingLevelChanged,
    this.asDialog = false,
  });

  @override
  State<_ModelCapabilitySheet> createState() => _ModelCapabilitySheetState();
}

class _ModelCapabilitySheetState extends State<_ModelCapabilitySheet> {
  late bool _embedding;
  late bool _textInput;
  late bool _imageInput;
  late bool _textOutput;
  late bool _imageOutput;
  late bool _tool;
  late bool _reasoning;
  late ThinkingLevel? _thinkingLevel;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _embedding = c.embedding;
    _textInput = c.textInput;
    _imageInput = c.imageInput;
    _textOutput = c.textOutput;
    _imageOutput = c.imageOutput;
    _tool = c.tool;
    _reasoning = c.reasoning;
    _thinkingLevel = widget.initialThinkingLevel;
  }

  AgentModelCapability get _current => _embedding
      ? AgentModelCapability(
          embedding: true,
          textInput: _textInput,
          imageInput: _imageInput,
        )
      : AgentModelCapability(
          textInput: _textInput,
          imageInput: _imageInput,
          textOutput: _textOutput,
          imageOutput: _imageOutput,
          tool: _tool,
          reasoning: _reasoning,
        );

  void _set(VoidCallback change) {
    setState(change);
    widget.onSave(_current);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bottomPad =
        (widget.asDialog ? 16.0 : MediaQuery.of(context).padding.bottom) + 12;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.asDialog)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )
        else
          const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            widget.modelId,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _segRow(theme, cs, context.l10n.modelType, [
                  _Seg(context.l10n.chat, !_embedding, () {
                    if (_embedding) _set(() => _embedding = false);
                  }),
                  _Seg(context.l10n.embedding, _embedding, () {
                    if (!_embedding) _set(() => _embedding = true);
                  }),
                ]),
                const SizedBox(height: 18),
                _segRow(theme, cs, context.l10n.inputMode, [
                  _Seg(context.l10n.text, _textInput, () {
                    _set(() => _textInput = !_textInput);
                  }),
                  _Seg(context.l10n.image, _imageInput, () {
                    _set(() => _imageInput = !_imageInput);
                  }),
                ]),
                if (!_embedding) ...[
                  const SizedBox(height: 18),
                  _segRow(theme, cs, context.l10n.outputMode, [
                    _Seg(context.l10n.text, _textOutput, () {
                      _set(() => _textOutput = !_textOutput);
                    }),
                    _Seg(context.l10n.image, _imageOutput, () {
                      _set(() => _imageOutput = !_imageOutput);
                    }),
                  ]),
                  const SizedBox(height: 18),
                  _segRow(theme, cs, context.l10n.capabilities, [
                    _Seg(context.l10n.roleBadgeTools, _tool, () {
                      _set(() => _tool = !_tool);
                    }),
                    _Seg(context.l10n.reasoning, _reasoning, () {
                      _set(() => _reasoning = !_reasoning);
                    }),
                  ]),
                  if (_reasoning) ...[
                    const SizedBox(height: 18),
                    _thinkingSection(theme, cs),
                  ],
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Haptics.soft();
                  final c = widget.inferred;
                  setState(() {
                    _embedding = c.embedding;
                    _textInput = c.textInput;
                    _imageInput = c.imageInput;
                    _textOutput = c.textOutput;
                    _imageOutput = c.imageOutput;
                    _tool = c.tool;
                    _reasoning = c.reasoning;
                    _thinkingLevel = null;
                  });
                  widget.onReset();
                },
                child: Text(context.l10n.resetToAuto),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  Haptics.soft();
                  Navigator.pop(context);
                },
                child: Text(context.l10n.done),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.asDialog) {
      final lo = 320.0;
      final computed = MediaQuery.sizeOf(context).width * 0.85;
      final hi = math.max(lo, math.min(540.0, computed));
      final width = computed.clamp(lo, hi);
      final maxH = MediaQuery.sizeOf(context).height * 0.75;
      return Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: column,
          ),
        ),
      );
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: AppShadows.sheet,
        ),
        child: column,
      ),
    );
  }

  void _setThinking(ThinkingLevel? level) {
    setState(() => _thinkingLevel = level);
    widget.onThinkingLevelChanged?.call(level);
  }

  /// 思考强度：6 个选项（默认 + 5 档），分两行每行 3 个。
  Widget _thinkingSection(ThemeData theme, ColorScheme cs) {
    final l10n = context.l10n;
    final segs = [
      _Seg(l10n.defaultLevel, _thinkingLevel == null, () => _setThinking(null)),
      _Seg(
        l10n.off,
        _thinkingLevel == ThinkingLevel.off,
        () => _setThinking(ThinkingLevel.off),
      ),
      _Seg(
        l10n.low,
        _thinkingLevel == ThinkingLevel.low,
        () => _setThinking(ThinkingLevel.low),
      ),
      _Seg(
        l10n.medium,
        _thinkingLevel == ThinkingLevel.medium,
        () => _setThinking(ThinkingLevel.medium),
      ),
      _Seg(
        l10n.high,
        _thinkingLevel == ThinkingLevel.high,
        () => _setThinking(ThinkingLevel.high),
      ),
      _Seg(
        l10n.ultraHigh,
        _thinkingLevel == ThinkingLevel.xhigh,
        () => _setThinking(ThinkingLevel.xhigh),
      ),
    ];
    Widget row(int from, int to) => Row(
      children: [
        for (int i = from; i < to; i++) ...[
          if (i > from) const SizedBox(width: 12),
          Expanded(child: _segButton(theme, cs, segs[i])),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.thinkingIntensity,
          style: theme.textTheme.titleSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        row(0, 3),
        const SizedBox(height: 8),
        row(3, 6),
      ],
    );
  }

  /// 一组「分节标题 + 整行等宽按钮」。
  Widget _segRow(
    ThemeData theme,
    ColorScheme cs,
    String label,
    List<_Seg> segs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 0; i < segs.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: _segButton(theme, cs, segs[i])),
            ],
          ],
        ),
      ],
    );
  }

  Widget _segButton(ThemeData theme, ColorScheme cs, _Seg seg) {
    final selected = seg.selected;
    return TactilePress(
      baseColor: selected ? cs.primaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(12),
      onTap: seg.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : cs.outlineVariant.withAlpha(80),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Text(
          seg.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _Seg {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Seg(this.label, this.selected, this.onTap);
}
