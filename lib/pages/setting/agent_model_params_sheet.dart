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
    ),
  );
}

class _AgentModelParamsSheet extends StatefulWidget {
  final AgentApiProvider provider;
  final String providerLabel;
  final String modelId;
  final AgentModelParams initialParams;
  final ValueChanged<AgentModelParams> onSave;

  const _AgentModelParamsSheet({
    required this.provider,
    required this.providerLabel,
    required this.modelId,
    required this.initialParams,
    required this.onSave,
  });

  @override
  State<_AgentModelParamsSheet> createState() => _AgentModelParamsSheetState();
}

class _AgentModelParamsSheetState extends State<_AgentModelParamsSheet> {
  late AgentModelParams _draft;
  Timer? _saveTimer;

  late final TextEditingController _maxTokensCtrl;
  late final TextEditingController _thinkingBudgetCtrl;

  // ── 生命周期 ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _draft = widget.initialParams;
    _maxTokensCtrl = TextEditingController(
      text: _draft.maxTokens?.toString() ?? '',
    );
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
    // 对齐 toolbar_bottom_sheet 的 header 节奏：
    // 左侧主标题 + 副标题（模型信息），右侧操作按钮。
    // 去掉原来的 primary 竖色装饰条，减少视觉噪点。
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '模型参数',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    RoleBadge(
                      label: widget.providerLabel,
                      bg: cs.primaryContainer,
                      fg: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.modelId,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBody(ThemeData theme, ColorScheme cs) {
    return [
      _subHeader('通用参数'),
      _intFieldRow(
        title: '最大输出长度',
        subtitle: '单次回复的长度上限，留空跟随服务商默认',
        controller: _maxTokensCtrl,
        hint: '如 4096',
        onChanged: (v) =>
            _patch(_draft.copyWith(maxTokens: v == null || v <= 0 ? null : v)),
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
      title: '推理强度',
      subtitle: '推理模型专用，控制思考深度',
      options: const [
        (null, '默认'),
        ('minimal', '最低'),
        ('low', '低'),
        ('medium', '中'),
        ('high', '高'),
      ],
      selected: _draft.reasoningEffort,
      onChanged: (v) => _patch(_draft.copyWith(reasoningEffort: v)),
    ),
    _segmentedRow<String?>(
      title: '详略程度',
      subtitle: '回答的啰嗦程度',
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
      title: '并行工具',
      subtitle: '是否允许模型同时调用多个工具',
      options: const [(null, '默认'), (true, '允许'), (false, '串行')],
      selected: _draft.parallelToolCalls,
      onChanged: (v) => _patch(_draft.copyWith(parallelToolCalls: v)),
    ),
    _segmentedRow<String?>(
      title: '上下文截断',
      subtitle: '超长对话是否自动截断',
      options: const [(null, '默认'), ('auto', '自动'), ('disabled', '关闭')],
      selected: _draft.truncation,
      onChanged: (v) => _patch(_draft.copyWith(truncation: v)),
    ),
    _segmentedRow<bool?>(
      title: '联网搜索',
      subtitle: '让模型可以上网查资料',
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
              title: '搜索信息量',
              subtitle: '检索结果拼入对话的详略',
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
        title: '候选词数',
        subtitle: '每步从多少个候选词里挑选，0 表示不限',
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
        title: '深度思考',
        subtitle: '自适应让模型自行决定是否思考',
        options: const [
          (null, '默认'),
          ('disabled', '关闭'),
          ('enabled', '开启'),
          ('adaptive', '自适应'),
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
                title: '思考预算',
                subtitle: '思考环节能花多少 token，最少 1024',
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
      title: '候选词数',
      subtitle: '每步从多少个候选词里挑选，上限随模型',
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
      title: '话题新鲜度',
      subtitle: '正值鼓励换新话题，负值偏好重复',
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
      title: '用词多样度',
      subtitle: '正值鼓励词汇丰富，负值允许重复用词',
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
      title: '思考预算',
      subtitle: '思考能花多少 token，0 表示关闭',
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
    final chipText = formatter(displayValue);

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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
