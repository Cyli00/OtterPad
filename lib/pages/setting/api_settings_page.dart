import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_provider.dart';

class ApiSettingsPage extends ConsumerStatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  ConsumerState<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends ConsumerState<ApiSettingsPage> {
  static const _layoutShapeModes = <(String, String)>[
    ('auto', '自动'),
    ('rect', '矩形'),
    ('quad', '四边形'),
    ('poly', '多边形'),
  ];

  late final TextEditingController _agentUrlCtrl;
  late final TextEditingController _agentKeyCtrl;
  late final TextEditingController _docUrlCtrl;
  late final TextEditingController _docKeyCtrl;

  bool _agentKeyObscured = true;
  bool _docKeyObscured = true;

  Timer? _agentUrlTimer;
  Timer? _agentKeyTimer;
  Timer? _docUrlTimer;
  Timer? _docKeyTimer;

  @override
  void initState() {
    super.initState();
    final agentState = ref.read(agentApiProvider);
    final docState = ref.read(docExtractApiProvider);
    _agentUrlCtrl = TextEditingController(text: agentState.baseUrl);
    _agentKeyCtrl = TextEditingController(text: agentState.apiKey);
    _docUrlCtrl = TextEditingController(text: docState.syncBaseUrl);
    _docKeyCtrl = TextEditingController(text: docState.apiKey);
  }

  @override
  void dispose() {
    _agentUrlCtrl.dispose();
    _agentKeyCtrl.dispose();
    _docUrlCtrl.dispose();
    _docKeyCtrl.dispose();
    _agentUrlTimer?.cancel();
    _agentKeyTimer?.cancel();
    _docUrlTimer?.cancel();
    _docKeyTimer?.cancel();
    super.dispose();
  }

  // ── 提取选项开关分组 ────────────────────────────────────────────────────────

  static const _recognitionDefs = <(String, String, String)>[
    ('useChartRecognition', '图表识别', '将图表解析为表格'),
    ('useSealRecognition', '印章识别', '识别文档中的印章'),
    ('useOcrForImageBlock', '图片区 OCR', '对图片区域执行文字识别'),
  ];

  static const _correctionDefs = <(String, String, String)>[
    ('useDocOrientationClassify', '方向校正', '自动纠正 0°/90°/180°/270° 旋转'),
    ('useDocUnwarping', '弯曲校正', '校正弯曲或褶皱的文档'),
  ];

  static const _layoutDefs = <(String, String, String)>[
    ('layoutNms', '去重叠检测框', '移除重叠的版面检测框'),
  ];

  static const _outputDefs = <(String, String, String)>[
    ('restructurePages', '多页重构', '重构多页文档结构'),
  ];

  bool _getOptionValue(DocExtractApiState s, String field) => switch (field) {
    'useChartRecognition' => s.useChartRecognition,
    'useDocOrientationClassify' => s.useDocOrientationClassify,
    'useDocUnwarping' => s.useDocUnwarping,
    'useSealRecognition' => s.useSealRecognition,
    'useOcrForImageBlock' => s.useOcrForImageBlock,
    'restructurePages' => s.restructurePages,
    'layoutNms' => s.layoutNms,
    _ => false,
  };

  // ── 通用组件 ────────────────────────────────────────────────────────────────

  Widget _buildDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 20,
      endIndent: 20,
      color: cs.outlineVariant.withAlpha(40),
    );
  }

  Widget _buildSectionDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 20,
      endIndent: 20,
      color: cs.outlineVariant.withAlpha(80),
    );
  }

  Widget _buildSubHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  List<Widget> _buildSwitchGroup(
    BuildContext context,
    DocExtractApiState docState,
    List<(String, String, String)> defs,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final tiles = <Widget>[];
    for (int i = 0; i < defs.length; i++) {
      final (field, title, subtitle) = defs[i];
      tiles.add(
        SwitchListTile(
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          value: _getOptionValue(docState, field),
          onChanged: (v) {
            if (_getOptionValue(docState, field) != v) {
              ref.read(docExtractApiProvider.notifier).setBool(field, v);
            }
          },
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
        ),
      );
      if (i < defs.length - 1) tiles.add(_buildDivider(context));
    }
    return tiles;
  }

  // ── 参数卡片与滑动条 ────────────────────────────────────────────────────────

  Widget _buildSplitParameterItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        );

        final selector = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
          child: Align(alignment: Alignment.centerRight, child: child),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: header),
              const SizedBox(width: 24),
              selector,
            ],
          ),
        );
      },
    );
  }

  Widget _buildSingleSelectChips(
    BuildContext context, {
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
    WrapAlignment alignment = WrapAlignment.start,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Wrap(
      alignment: alignment,
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final selected = item.$1 == value;
        return FilterChip(
          label: Text(item.$2),
          selected: selected,
          showCheckmark: false,
          color: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return cs.primaryContainer;
            }
            return cs.surface;
          }),
          side: BorderSide(
            color: selected
                ? Colors.transparent
                : cs.outlineVariant.withAlpha(100),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: selected ? cs.onPrimaryContainer : cs.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          onSelected: (_) => onChanged(item.$1),
        );
      }).toList(),
    );
  }

  Widget _buildSliderTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required double defaultValue,
    required ValueChanged<double> onChanged,
    VoidCallback? onReset,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
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
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  value.toStringAsFixed(2),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
              if (onReset != null)
                IconButton(
                  onPressed: onReset,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: '恢复默认',
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 忽略标签 Chips ─────────────────────────────────────────────────────────

  static const _labelNames = <String, String>{
    'header': '页眉',
    'header_image': '页眉图片',
    'footer': '页脚',
    'footer_image': '页脚图片',
    'number': '页码',
    'footnote': '脚注',
    'aside_text': '旁注',
  };

  Widget _buildIgnoreLabelChips(BuildContext context, DocExtractApiState docState) {
    final selected = docState.markdownIgnoreLabels;
    final cs = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kAllIgnoreLabels.map((label) {
        final isSelected = selected.contains(label);
        return FilterChip(
          label: Text(_labelNames[label] ?? label),
          selected: isSelected,
          showCheckmark: false,
          color: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return cs.primaryContainer;
            }
            return cs.surface;
          }),
          side: BorderSide(
            color: isSelected
                ? Colors.transparent
                : cs.outlineVariant.withAlpha(100),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (v) {
            final updated = List<String>.from(selected);
            if (v) {
              if (!updated.contains(label)) updated.add(label);
            } else {
              updated.remove(label);
            }
            ref.read(docExtractApiProvider.notifier).setIgnoreLabels(updated);
          },
        );
      }).toList(),
    );
  }

  Widget _buildGroup(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12, top: 24),
          child: Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final agentState = ref.watch(agentApiProvider);
    final docState = ref.watch(docExtractApiProvider);

    InputDecoration fieldDeco({required String hint, Widget? suffix}) =>
        InputDecoration(
          hintText: hint,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant.withAlpha(120),
          ),
          filled: true,
          fillColor: cs.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: cs.outlineVariant.withAlpha(100),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: cs.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          isDense: true,
          suffixIcon: suffix,
        );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          '模型服务',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ).copyWith(bottom: 40),
        children: [
          // ── Agent API ──────────────────────────────────────────────────────
          _buildGroup(
            context,
            title: 'Agent API',
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '服务商',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AgentApiProvider>(
                      segments: AgentApiProvider.values
                          .map(
                            (p) =>
                                ButtonSegment(value: p, label: Text(p.label)),
                          )
                          .toList(),
                      selected: {agentState.provider},
                      onSelectionChanged: (set) {
                        if (agentState.provider != set.first) {
                          ref
                              .read(agentApiProvider.notifier)
                              .setProvider(set.first);
                        }
                      },
                      style: SegmentedButton.styleFrom(
                        backgroundColor: cs.surface,
                        selectedBackgroundColor: cs.primaryContainer,
                        side: BorderSide(
                          color: cs.outlineVariant.withAlpha(100),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Base URL',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _agentUrlCtrl,
                    onChanged: (v) {
                      _agentUrlTimer?.cancel();
                      _agentUrlTimer = Timer(
                        const Duration(milliseconds: 600),
                        () {
                          ref
                              .read(agentApiProvider.notifier)
                              .setBaseUrl(v.trim());
                        },
                      );
                    },
                    decoration: fieldDeco(
                      hint: agentState.provider.defaultBaseUrl,
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'API Key',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _agentKeyCtrl,
                    onChanged: (v) {
                      _agentKeyTimer?.cancel();
                      _agentKeyTimer = Timer(
                        const Duration(milliseconds: 600),
                        () {
                          ref
                              .read(agentApiProvider.notifier)
                              .setApiKey(v.trim());
                        },
                      );
                    },
                    obscureText: _agentKeyObscured,
                    decoration: fieldDeco(
                      hint: agentState.provider.apiKeyHint,
                      suffix: IconButton(
                        icon: Icon(
                          _agentKeyObscured
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _agentKeyObscured = !_agentKeyObscured,
                        ),
                      ),
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          // ── 文档提取 ──────────────────────────────────────────────────────
          _buildGroup(
            context,
            title: '文档提取',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 认证配置 ──
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer.withAlpha(150),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 20,
                              color: cs.secondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '百度 AI Studio 文档 (PaddleOCR-VL-1.5)',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSecondaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Access Token（必填） ──
                      Text(
                        'Access Token',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '用于异步 Job API 认证，必填。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _docKeyCtrl,
                        onChanged: (v) {
                          _docKeyTimer?.cancel();
                          _docKeyTimer = Timer(
                            const Duration(milliseconds: 600),
                            () {
                              ref
                                  .read(docExtractApiProvider.notifier)
                                  .setApiKey(v.trim());
                            },
                          );
                        },
                        obscureText: _docKeyObscured,
                        decoration: fieldDeco(
                          hint: 'token ...',
                          suffix: IconButton(
                            icon: Icon(
                              _docKeyObscured
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _docKeyObscured = !_docKeyObscured,
                            ),
                          ),
                        ),
                        autocorrect: false,
                        enableSuggestions: false,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),

                      // ── 同步 API URL（可选 fallback） ──
                      Row(
                        children: [
                          Text(
                            '同步 API',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '可选',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '配置后在异步提取失败时自动回退到同步接口。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _docUrlCtrl,
                        onChanged: (v) {
                          _docUrlTimer?.cancel();
                          _docUrlTimer = Timer(
                            const Duration(milliseconds: 600),
                            () {
                              ref
                                  .read(docExtractApiProvider.notifier)
                                  .setSyncBaseUrl(v.trim());
                            },
                          );
                        },
                        decoration: fieldDeco(
                          hint: 'https://xxx.aistudio-app.com',
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                _buildSectionDivider(context),

                // ── 识别增强 ──
                _buildSubHeader(context, '识别增强'),
                ..._buildSwitchGroup(context, docState, _recognitionDefs),
                _buildSectionDivider(context),

                // ── 文档校正 ──
                _buildSubHeader(context, '文档校正'),
                ..._buildSwitchGroup(context, docState, _correctionDefs),
                _buildSectionDivider(context),

                // ── 版面分析 ──
                _buildSubHeader(context, '版面分析'),
                ..._buildSwitchGroup(context, docState, _layoutDefs),
                _buildDivider(context),
                _buildSplitParameterItem(
                  context,
                  title: '版面几何形状',
                  subtitle: '版面检测框的几何形状表示',
                  child: _buildSingleSelectChips(
                    context,
                    value: docState.layoutShapeMode,
                    items: _layoutShapeModes,
                    onChanged: (v) {
                      if (docState.layoutShapeMode != v) {
                        ref
                            .read(docExtractApiProvider.notifier)
                            .setString('layoutShapeMode', v);
                      }
                    },
                    alignment: WrapAlignment.end,
                  ),
                ),
                _buildDivider(context),
                _buildSliderTile(
                  context,
                  title: '版面检测阈值',
                  subtitle: '区域过滤的阈值，值越高保留的区域越少',
                  value: docState.layoutThreshold,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  defaultValue: 0.5,
                  onChanged: (v) => ref
                      .read(docExtractApiProvider.notifier)
                      .setDouble('layoutThreshold', v),
                  onReset: () => ref
                      .read(docExtractApiProvider.notifier)
                      .setDouble('layoutThreshold', 0.5),
                ),
                _buildSectionDivider(context),

                // ── 输出控制 ──
                _buildSubHeader(context, '输出控制'),
                ..._buildSwitchGroup(context, docState, _outputDefs),
                _buildDivider(context),
                _buildSliderTile(
                  context,
                  title: '重复惩罚',
                  subtitle: '出现重复文字或表格内容时适当调高',
                  value: docState.repetitionPenalty,
                  min: 1.0,
                  max: 2.0,
                  divisions: 20,
                  defaultValue: 1.0,
                  onChanged: (v) => ref
                      .read(docExtractApiProvider.notifier)
                      .setDouble('repetitionPenalty', v),
                  onReset: () => ref
                      .read(docExtractApiProvider.notifier)
                      .setDouble('repetitionPenalty', 1.0),
                ),
                _buildDivider(context),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Markdown 忽略标签',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '勾选的标签区域将不会输出到 Markdown 结果中，默认全忽略。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildIgnoreLabelChips(context, docState),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
