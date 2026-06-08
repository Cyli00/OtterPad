import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../providers/api_provider.dart';
import '../../services/agent_model_capability.dart';
import '../../services/builtin_tools.dart';

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
  Set<String> initialBuiltInTools = const {},
  ValueChanged<Set<String>>? onBuiltInToolsChanged,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => _ModelCapabilitySheet(
      modelId: modelId,
      protocol: protocol,
      initial: initial,
      inferred: inferred,
      onSave: onSave,
      onReset: onReset,
      initialThinkingLevel: initialThinkingLevel,
      onThinkingLevelChanged: onThinkingLevelChanged,
      initialBuiltInTools: initialBuiltInTools,
      onBuiltInToolsChanged: onBuiltInToolsChanged,
    ),
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
  final Set<String> initialBuiltInTools;
  final ValueChanged<Set<String>>? onBuiltInToolsChanged;

  const _ModelCapabilitySheet({
    required this.modelId,
    required this.protocol,
    required this.initial,
    required this.inferred,
    required this.onSave,
    required this.onReset,
    this.initialThinkingLevel,
    this.onThinkingLevelChanged,
    this.initialBuiltInTools = const {},
    this.onBuiltInToolsChanged,
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
  late Set<String> _builtInTools;

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
    _builtInTools = Set<String>.from(widget.initialBuiltInTools);
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

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            ),
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
                      const SizedBox(height: 18),
                      _toolsSection(theme, cs),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
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
                        _builtInTools = {};
                      });
                      widget.onBuiltInToolsChanged?.call({});
                      widget.onReset();
                    },
                    child: Text(context.l10n.resetToAuto),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.done),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleTool(String tool) {
    setState(() {
      if (_builtInTools.contains(tool)) {
        _builtInTools.remove(tool);
      } else {
        _builtInTools.add(tool);
      }
    });
    widget.onBuiltInToolsChanged?.call(Set.from(_builtInTools));
  }

  Widget _toolsSection(ThemeData theme, ColorScheme cs) {
    final tools = BuiltInToolNames.forProvider(widget.protocol);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.builtInTools,
          style: theme.textTheme.titleSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        ...tools.map((tool) => _toolToggle(
              theme,
              cs,
              tool: tool,
              value: _builtInTools.contains(tool),
              supported: BuiltInToolsHelper.isSupported(
                provider: widget.protocol,
                modelId: widget.modelId,
                tool: tool,
              ),
            )),
      ],
    );
  }

  Widget _toolToggle(
    ThemeData theme,
    ColorScheme cs, {
    required String tool,
    required bool value,
    required bool supported,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  BuiltInToolNames.label(tool, context.l10n),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (supported) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      context.l10n.official,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: FittedBox(
              child: Switch.adaptive(
                value: value,
                onChanged: (_) => _toggleTool(tool),
              ),
            ),
          ),
        ],
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
      _Seg(l10n.off, _thinkingLevel == ThinkingLevel.off,
          () => _setThinking(ThinkingLevel.off)),
      _Seg(l10n.low, _thinkingLevel == ThinkingLevel.low,
          () => _setThinking(ThinkingLevel.low)),
      _Seg(l10n.medium, _thinkingLevel == ThinkingLevel.medium,
          () => _setThinking(ThinkingLevel.medium)),
      _Seg(l10n.high, _thinkingLevel == ThinkingLevel.high,
          () => _setThinking(ThinkingLevel.high)),
      _Seg(l10n.ultraHigh, _thinkingLevel == ThinkingLevel.xhigh,
          () => _setThinking(ThinkingLevel.xhigh)),
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
    return Material(
      color: selected ? cs.primaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
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
