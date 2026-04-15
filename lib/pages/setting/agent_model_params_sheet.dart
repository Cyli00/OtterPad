import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../providers/api_provider.dart';
import 'agent_role_widgets.dart';

/// 打开"模型参数调节"底部弹窗。
///
/// 防抖自动保存（600ms），与 api_settings_agent 的 Key/URL 输入框节奏一致。
///
/// 行格式与 [api_settings_extract.dart] 里的 `_sliderTile` / `_subHeader`
/// 对齐：标题行右侧显示当前值胶囊，滑块下方保留较宽的垂直呼吸空间。
///
/// 注意：此处的 maxTokens 仅用于正式请求；模型连通性检测走独立的
/// 硬编码上限（见 agent_model_tester.dart），两者互不干扰。
Future<void> showAgentModelParamsSheet({
  required BuildContext context,
  required AgentApiProvider provider,
  required String providerLabel,
  required String modelId,
  required AgentModelParams initialParams,
  required ValueChanged<AgentModelParams> onSave,
  required VoidCallback onReset,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AgentModelParamsSheet(
      provider: provider,
      providerLabel: providerLabel,
      modelId: modelId,
      initialParams: initialParams,
      onSave: onSave,
      onReset: onReset,
    ),
  );
}

class _AgentModelParamsSheet extends StatefulWidget {
  final AgentApiProvider provider;
  final String providerLabel;
  final String modelId;
  final AgentModelParams initialParams;
  final ValueChanged<AgentModelParams> onSave;
  final VoidCallback onReset;

  const _AgentModelParamsSheet({
    required this.provider,
    required this.providerLabel,
    required this.modelId,
    required this.initialParams,
    required this.onSave,
    required this.onReset,
  });

  @override
  State<_AgentModelParamsSheet> createState() => _AgentModelParamsSheetState();
}

class _AgentModelParamsSheetState extends State<_AgentModelParamsSheet> {
  late AgentModelParams _draft;
  Timer? _saveTimer;

  late final TextEditingController _maxTokensCtrl;
  late final TextEditingController _systemPromptCtrl;
  late final TextEditingController _thinkingBudgetCtrl;

  // ── provider-aware 常量 ───────────────────────────────────────────────

  /// Anthropic 的 temperature 上限是 1.0；其它两家都是 2.0
  double get _temperatureMax =>
      widget.provider == AgentApiProvider.anthropic ? 1.0 : 2.0;

  int get _temperatureDivisions =>
      widget.provider == AgentApiProvider.anthropic ? 20 : 40;

  double get _temperatureFallback => 1.0;

  // ── 生命周期 ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _draft = widget.initialParams;
    _maxTokensCtrl = TextEditingController(
      text: _draft.maxTokens?.toString() ?? '',
    );
    _systemPromptCtrl = TextEditingController(text: _draft.systemPrompt ?? '');
    _thinkingBudgetCtrl = TextEditingController(
      text: _draft.thinkingBudget?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    // 关闭前刷掉任何尚未到时的 pending save
    _saveTimer?.cancel();
    if (_draft != widget.initialParams) {
      widget.onSave(_draft);
    }
    _maxTokensCtrl.dispose();
    _systemPromptCtrl.dispose();
    _thinkingBudgetCtrl.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      widget.onSave(_draft);
    });
  }

  void _patch(AgentModelParams next) {
    setState(() => _draft = next);
    _scheduleSave();
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置参数'),
        content: Text('将 ${widget.modelId} 的所有参数恢复为服务商默认？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _saveTimer?.cancel();
    setState(() {
      _draft = const AgentModelParams();
      _maxTokensCtrl.text = '';
      _systemPromptCtrl.text = '';
      _thinkingBudgetCtrl.text = '';
    });
    widget.onReset();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            _buildHeader(theme, cs),
            Divider(height: 1, color: cs.outlineVariant.withAlpha(60)),
            Flexible(
              child: ListView(
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: MediaQuery.of(context).padding.bottom + 24,
                ),
                children: _buildBody(theme, cs),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.modelId,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    RoleBadge(
                      label: widget.providerLabel,
                      bg: cs.primaryContainer,
                      fg: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '参数调节',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Symbols.restart_alt_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            tooltip: '重置全部',
            onPressed: _draft.isDefault ? null : _confirmReset,
          ),
          IconButton(
            icon: Icon(
              Symbols.close_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBody(ThemeData theme, ColorScheme cs) {
    return [
      _subHeader('通用参数'),
      _sliderRow(
        title: '温度 (temperature)',
        subtitle: widget.provider == AgentApiProvider.anthropic
            ? 'Anthropic 范围 0.0 – 1.0；越低越确定，越高越发散'
            : '范围 0.0 – 2.0；越低越确定，越高越发散',
        value: _draft.temperature,
        fallback: _temperatureFallback.clamp(0.0, _temperatureMax),
        min: 0.0,
        max: _temperatureMax,
        divisions: _temperatureDivisions,
        formatter: (v) => v.toStringAsFixed(2),
        onChanged: (v) => _patch(_draft.copyWith(temperature: v)),
        onReset: () => _patch(_draft.copyWith(temperature: null)),
      ),
      _sliderRow(
        title: 'Top P',
        subtitle: '核采样阈值（0.0 – 1.0）；建议与温度二选一调节',
        value: _draft.topP,
        fallback: 1.0,
        min: 0.0,
        max: 1.0,
        divisions: 20,
        formatter: (v) => v.toStringAsFixed(2),
        onChanged: (v) => _patch(_draft.copyWith(topP: v)),
        onReset: () => _patch(_draft.copyWith(topP: null)),
      ),
      _intFieldRow(
        title: '最大输出 Tokens',
        subtitle:
            'OpenAI: max_output_tokens；Anthropic: max_tokens；Gemini: maxOutputTokens。留空使用服务商默认上限',
        controller: _maxTokensCtrl,
        hint: '如 4096',
        onChanged: (v) =>
            _patch(_draft.copyWith(maxTokens: v == null || v <= 0 ? null : v)),
      ),
      _multilineFieldRow(
        title: 'System Prompt',
        subtitle:
            'OpenAI 映射到 instructions；Anthropic 写入顶层 system；Gemini 写入 systemInstruction',
        controller: _systemPromptCtrl,
        hint: '例如：你是一位严谨的学术助手，回答时优先引用原文…',
        onChanged: (v) =>
            _patch(_draft.copyWith(systemPrompt: v.isEmpty ? null : v)),
      ),
      _subHeader('${widget.providerLabel} 专属'),
      ...switch (widget.provider) {
        AgentApiProvider.openai => _openaiRows(),
        AgentApiProvider.anthropic => _anthropicRows(),
        AgentApiProvider.gemini => _geminiRows(),
      },
      const SizedBox(height: 12),
    ];
  }

  // ── Provider-specific rows ────────────────────────────────────────────

  List<Widget> _openaiRows() => [
    _segmentedRow<String?>(
      title: 'Reasoning Effort',
      subtitle: 'reasoning.effort：仅对 o-series / GPT-5 推理模型生效',
      options: const [
        (null, '默认'),
        ('minimal', 'minimal'),
        ('low', '低'),
        ('medium', '中'),
        ('high', '高'),
      ],
      selected: _draft.reasoningEffort,
      onChanged: (v) => _patch(_draft.copyWith(reasoningEffort: v)),
    ),
    _segmentedRow<String?>(
      title: 'Verbosity',
      subtitle: 'text.verbosity：控制回答的详略程度，默认 medium',
      options: const [
        (null, '默认'),
        ('low', '简'),
        ('medium', '中'),
        ('high', '详'),
      ],
      selected: _draft.verbosity,
      onChanged: (v) => _patch(_draft.copyWith(verbosity: v)),
    ),
    _segmentedRow<bool?>(
      title: 'Parallel Tool Calls',
      subtitle: 'parallel_tool_calls：是否允许模型单轮并行调用多个工具',
      options: const [(null, '默认'), (true, '允许'), (false, '串行')],
      selected: _draft.parallelToolCalls,
      onChanged: (v) => _patch(_draft.copyWith(parallelToolCalls: v)),
    ),
    _segmentedRow<String?>(
      title: 'Truncation',
      subtitle: 'truncation：上下文超限时是否自动截断，默认 disabled',
      options: const [(null, '默认'), ('auto', 'auto'), ('disabled', 'disabled')],
      selected: _draft.truncation,
      onChanged: (v) => _patch(_draft.copyWith(truncation: v)),
    ),
    _segmentedRow<bool?>(
      title: 'Web Search 工具',
      subtitle: 'tools 中注入内置 web_search 工具，允许模型联网检索',
      options: const [(null, '默认'), (true, '开启'), (false, '关闭')],
      selected: _draft.webSearchEnabled,
      onChanged: (v) => _patch(
        _draft.copyWith(
          webSearchEnabled: v,
          webSearchContextSize: v == true ? _draft.webSearchContextSize : null,
        ),
      ),
    ),
    AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: _draft.webSearchEnabled == true
          ? _segmentedRow<String?>(
              title: '搜索上下文大小',
              subtitle: 'search_context_size：检索结果拼入上下文的信息量',
              options: const [
                (null, '默认'),
                ('low', '低'),
                ('medium', '中'),
                ('high', '高'),
              ],
              selected: _draft.webSearchContextSize,
              onChanged: (v) =>
                  _patch(_draft.copyWith(webSearchContextSize: v)),
            )
          : const SizedBox.shrink(),
    ),
  ];

  List<Widget> _anthropicRows() {
    final mode = _draft.thinkingMode;
    final showBudget = mode == 'enabled' || mode == 'adaptive';
    return [
      _sliderRow(
        title: 'Top K',
        subtitle: 'top_k：每步候选 token 数；0 表示不限制',
        value: _draft.topK?.toDouble(),
        fallback: 40,
        min: 0,
        max: 500,
        divisions: 50,
        formatter: (v) => v.round().toString(),
        onChanged: (v) => _patch(_draft.copyWith(topK: v.round())),
        onReset: () => _patch(_draft.copyWith(topK: null)),
      ),
      _segmentedRow<String?>(
        title: '深度思考 (thinking)',
        subtitle: 'thinking.type：adaptive 由模型自行决定是否思考',
        options: const [
          (null, '默认'),
          ('disabled', 'disabled'),
          ('enabled', 'enabled'),
          ('adaptive', 'adaptive'),
        ],
        selected: _draft.thinkingMode,
        onChanged: (v) => _patch(
          _draft.copyWith(
            thinkingMode: v,
            // disabled / default 时同步清除 budget
            thinkingBudget: (v == 'enabled' || v == 'adaptive')
                ? _draft.thinkingBudget
                : null,
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: showBudget
            ? _intFieldRow(
                title: 'Thinking Budget',
                subtitle: 'thinking.budget_tokens：最少 1024，必须小于 max_tokens',
                controller: _thinkingBudgetCtrl,
                hint: '如 4096',
                onChanged: (v) {
                  if (v == null || v <= 0) {
                    _patch(_draft.copyWith(thinkingBudget: null));
                  } else {
                    _patch(
                      _draft.copyWith(thinkingBudget: v.clamp(1024, 65536)),
                    );
                  }
                },
              )
            : const SizedBox.shrink(),
      ),
    ];
  }

  List<Widget> _geminiRows() => [
    _sliderRow(
      title: 'Top K',
      subtitle: 'topK：gemini-2.5 Pro 上限 64，Flash 上限 40',
      value: _draft.topK?.toDouble(),
      fallback: 40,
      min: 0,
      max: 64,
      divisions: 32,
      formatter: (v) => v.round().toString(),
      onChanged: (v) => _patch(_draft.copyWith(topK: v.round())),
      onReset: () => _patch(_draft.copyWith(topK: null)),
    ),
    _sliderRow(
      title: 'Presence Penalty',
      subtitle: 'presencePenalty：范围 -2.0 ~ 2.0；正值抑制重复出现的主题',
      value: _draft.presencePenalty,
      fallback: 0,
      min: -2,
      max: 2,
      divisions: 40,
      formatter: (v) => v.toStringAsFixed(2),
      onChanged: (v) => _patch(_draft.copyWith(presencePenalty: v)),
      onReset: () => _patch(_draft.copyWith(presencePenalty: null)),
    ),
    _sliderRow(
      title: 'Frequency Penalty',
      subtitle: 'frequencyPenalty：范围 -2.0 ~ 2.0；正值降低高频 token 概率',
      value: _draft.frequencyPenalty,
      fallback: 0,
      min: -2,
      max: 2,
      divisions: 40,
      formatter: (v) => v.toStringAsFixed(2),
      onChanged: (v) => _patch(_draft.copyWith(frequencyPenalty: v)),
      onReset: () => _patch(_draft.copyWith(frequencyPenalty: null)),
    ),
    _intFieldRow(
      title: 'Thinking Budget',
      subtitle: 'thinkingConfig.thinkingBudget：0 关闭思考，Flash 最大 24576',
      controller: _thinkingBudgetCtrl,
      hint: '如 4096',
      onChanged: (v) => _patch(
        _draft.copyWith(thinkingBudget: v == null || v < 0 ? null : v),
      ),
    ),
  ];

  // ── Reusable row helpers (镜像 api_settings_extract.dart) ─────────────

  Widget _subHeader(String title) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 28, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _helpIcon(String message) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 5),
      preferBelow: true,
      verticalOffset: 16,
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Symbols.help_rounded, size: 16, color: cs.onSurfaceVariant),
      ),
    );
  }

  /// 复刻 api_settings_extract.dart 中的 `_sliderTile`：
  /// 标题行（title + 帮助 tooltip + 数值胶囊），32px 大间隔，滑块 + 重置。
  /// 唯一差异：value 允许为 null（表示"使用服务商默认"），此时胶囊显示为灰色。
  Widget _sliderRow({
    required String title,
    required String subtitle,
    required double? value,
    required double fallback,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) formatter,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSet = value != null;
    final displayValue = value ?? fallback;
    final chipText = isSet ? formatter(displayValue) : '默认';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _helpIcon(subtitle),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSet
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest.withAlpha(160),
                  borderRadius: BorderRadius.circular(12),
                  border: isSet
                      ? null
                      : Border.all(color: cs.outlineVariant.withAlpha(80)),
                ),
                child: Text(
                  chipText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isSet ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: displayValue.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onChanged,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              IconButton(
                onPressed: isSet ? onReset : null,
                icon: const Icon(Symbols.refresh_rounded, size: 20),
                tooltip: '恢复默认',
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 分段选择行；T? 形式允许包含一个 null 段表示"默认/不设置"
  Widget _segmentedRow<T>({
    required String title,
    required String subtitle,
    required List<(T?, String)> options,
    required T? selected,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _helpIcon(subtitle),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T?>(
              segments: options
                  .map((o) => ButtonSegment<T?>(value: o.$1, label: Text(o.$2)))
                  .toList(),
              selected: {selected},
              showSelectedIcon: false,
              emptySelectionAllowed: false,
              onSelectionChanged: (set) => onChanged(set.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: cs.surface,
                selectedBackgroundColor: cs.primaryContainer,
                side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intFieldRow({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<int?> onChanged,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _helpIcon(subtitle),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: theme.textTheme.bodyMedium,
            decoration: _fieldDeco(theme, cs, hint: hint),
            onChanged: (v) {
              final trimmed = v.trim();
              if (trimmed.isEmpty) {
                onChanged(null);
              } else {
                onChanged(int.tryParse(trimmed));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _multilineFieldRow({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _helpIcon(subtitle),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 6,
            style: theme.textTheme.bodyMedium,
            decoration: _fieldDeco(theme, cs, hint: hint),
            onChanged: (v) => onChanged(v.trim()),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(
    ThemeData theme,
    ColorScheme cs, {
    required String hint,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant.withAlpha(120),
      ),
      filled: true,
      fillColor: cs.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant.withAlpha(100)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );
  }
}
