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
    return _optionDefs.map((def) {
      final (field, title, subtitle) = def;
      return SwitchListTile(
        title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
        subtitle: Text(subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
        value: _getOptionValue(docState, field),
        onChanged: (v) =>
            ref.read(docExtractApiProvider.notifier).setBool(field, v),
        dense: true,
        visualDensity: VisualDensity.compact,
      );
    }).toList();
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

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: kAllIgnoreLabels.map((label) {
        final isSelected = selected.contains(label);
        return FilterChip(
          label: Text(_labelNames[label] ?? label),
          selected: isSelected,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final agentState = ref.watch(agentApiProvider);

    InputDecoration fieldDeco({required String hint, Widget? suffix}) =>
        InputDecoration(
          hintText: hint,
          hintStyle: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant.withAlpha(130)),
          filled: true,
          fillColor: cs.surfaceContainer,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
          suffixIcon: suffix,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('API 服务商设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Agent API ──────────────────────────────────────────────────────
          _SectionTitle('Agent API'),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 服务商选择
                  Text(
                    '服务商',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AgentApiProvider>(
                      segments: AgentApiProvider.values
                          .map((p) =>
                              ButtonSegment(value: p, label: Text(p.label)))
                          .toList(),
                      selected: {agentState.provider},
                      onSelectionChanged: (set) => ref
                          .read(agentApiProvider.notifier)
                          .setProvider(set.first),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Base URL
                  Text(
                    'Base URL',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _agentUrlCtrl,
                    onChanged: (v) {
                      _agentUrlTimer?.cancel();
                      _agentUrlTimer =
                          Timer(const Duration(milliseconds: 600), () {
                        ref
                            .read(agentApiProvider.notifier)
                            .setBaseUrl(v.trim());
                      });
                    },
                    decoration:
                        fieldDeco(hint: agentState.provider.defaultBaseUrl),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  // API Key
                  Text(
                    'API Key',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _agentKeyCtrl,
                    onChanged: (v) {
                      _agentKeyTimer?.cancel();
                      _agentKeyTimer =
                          Timer(const Duration(milliseconds: 600), () {
                        ref
                            .read(agentApiProvider.notifier)
                            .setApiKey(v.trim());
                      });
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
                            () => _agentKeyObscured = !_agentKeyObscured),
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

          const SizedBox(height: 16),

          // ── 文档提取 API ────────────────────────────────────────────────────
          _SectionTitle('文档提取 API'),
          const SizedBox(height: 8),
          // 连接信息卡片
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '百度 AI Studio 文档版面解析 (PaddleOCR-VL)',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // API URL
                  Text(
                    'API URL',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _docUrlCtrl,
                    onChanged: (v) {
                      _docUrlTimer?.cancel();
                      _docUrlTimer =
                          Timer(const Duration(milliseconds: 600), () {
                        ref
                            .read(docExtractApiProvider.notifier)
                            .setBaseUrl(v.trim());
                      });
                    },
                    decoration: fieldDeco(
                        hint: 'https://xxx.aistudio-app.com'),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  // Access Token
                  Text(
                    'Access Token',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _docKeyCtrl,
                    onChanged: (v) {
                      _docKeyTimer?.cancel();
                      _docKeyTimer =
                          Timer(const Duration(milliseconds: 600), () {
                        ref
                            .read(docExtractApiProvider.notifier)
                            .setApiKey(v.trim());
                      });
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

          const SizedBox(height: 12),

          // 提取选项卡片
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      '提取选项',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ..._buildOptionTiles(context),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Markdown 忽略标签卡片
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Markdown 忽略标签',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '勾选的标签区域将不会输出到 Markdown 中',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  _buildIgnoreLabelChips(context),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
