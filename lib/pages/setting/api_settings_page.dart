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
    _docUrlCtrl = TextEditingController(text: docState.baseUrl);
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

  // ── 提取选项开关列表 ──────────────────────────────────────────────────────

  static const _optionDefs = <(String, String, String)>[
    ('useLayoutDetection', '版面检测', '识别文档区域并排序'),
    ('useChartRecognition', '图表识别', '将图表解析为表格'),
    ('useDocOrientationClassify', '方向校正', '自动纠正 0°/90°/180°/270° 旋转'),
    ('useDocUnwarping', '弯曲校正', '校正弯曲或褶皱的文档'),
    ('useSealRecognition', '印章识别', '识别文档中的印章'),
    ('useOcrForImageBlock', '图片区 OCR', '对图片区域执行文字识别'),
    ('mergeTables', '跨页合并表格', '自动合并跨页表格'),
    ('relevelTitles', '标题层级重排', '重新识别段落标题层级'),
    ('restructurePages', '多页重构', '重构多页文档结构'),
    ('layoutNms', '去重叠检测框', '移除重叠的版面检测框'),
  ];

  bool _getOptionValue(DocExtractApiState s, String field) => switch (field) {
    'useLayoutDetection' => s.useLayoutDetection,
    'useChartRecognition' => s.useChartRecognition,
    'useDocOrientationClassify' => s.useDocOrientationClassify,
    'useDocUnwarping' => s.useDocUnwarping,
    'useSealRecognition' => s.useSealRecognition,
    'useOcrForImageBlock' => s.useOcrForImageBlock,
    'mergeTables' => s.mergeTables,
    'relevelTitles' => s.relevelTitles,
    'restructurePages' => s.restructurePages,
    'layoutNms' => s.layoutNms,
    _ => false,
  };

  List<Widget> _buildOptionTiles(BuildContext context) {
    final docState = ref.watch(docExtractApiProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final tiles = <Widget>[];
    for (int i = 0; i < _optionDefs.length; i++) {
      final (field, title, subtitle) = _optionDefs[i];
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
          onChanged: (v) =>
              ref.read(docExtractApiProvider.notifier).setBool(field, v),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
        ),
      );
      if (i < _optionDefs.length - 1) {
        tiles.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: 20,
            endIndent: 20,
            color: cs.outlineVariant.withAlpha(40),
          ),
        );
      }
    }
    return tiles;
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

  Widget _buildIgnoreLabelChips(BuildContext context) {
    final docState = ref.watch(docExtractApiProvider);
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
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
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
                      onSelectionChanged: (set) => ref
                          .read(agentApiProvider.notifier)
                          .setProvider(set.first),
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

          // ── 文档提取 API ────────────────────────────────────────────────────
          _buildGroup(
            context,
            title: '文档提取 API',
            child: Padding(
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
                  Text(
                    'API URL',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
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
                              .setBaseUrl(v.trim());
                        },
                      );
                    },
                    decoration: fieldDeco(hint: 'https://xxx.aistudio-app.com'),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Access Token',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
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
                        onPressed: () =>
                            setState(() => _docKeyObscured = !_docKeyObscured),
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

          // ── 提取选项 ────────────────────────────────────────────────────────
          _buildGroup(
            context,
            title: '提取选项',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: _buildOptionTiles(context)),
            ),
          ),

          // ── Markdown 忽略标签 ───────────────────────────────────────────────
          _buildGroup(
            context,
            title: '提取过滤',
            child: Padding(
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
                  _buildIgnoreLabelChips(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
