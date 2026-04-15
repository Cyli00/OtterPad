import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_provider.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 文档提取 API 配置区块
class ExtractApiSection extends ConsumerStatefulWidget {
  const ExtractApiSection({super.key});

  @override
  ConsumerState<ExtractApiSection> createState() => _ExtractApiSectionState();
}

class _ExtractApiSectionState extends ConsumerState<ExtractApiSection> {
  static const _layoutShapeModes = <(String, String)>[
    ('auto', '自动'),
    ('rect', '矩形'),
    ('quad', '四边形'),
    ('poly', '多边形'),
  ];

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

  static const _labelNames = <String, String>{
    'header': '页眉',
    'header_image': '页眉图片',
    'footer': '页脚',
    'footer_image': '页脚图片',
    'number': '页码',
    'footnote': '脚注',
    'aside_text': '旁注',
  };

  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;

  bool _keyObscured = true;
  Timer? _urlTimer;
  Timer? _keyTimer;

  @override
  void initState() {
    super.initState();
    final s = ref.read(docExtractApiProvider);
    _urlCtrl = TextEditingController(text: s.syncBaseUrl);
    _keyCtrl = TextEditingController(text: s.apiKey);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _urlTimer?.cancel();
    _keyTimer?.cancel();
    super.dispose();
  }

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

  // ── 通用构建器 ──

  Widget _helpIcon(String message) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
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
        child: Icon(
          Symbols.help_rounded,
          size: 16,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

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

  List<Widget> _switchGroup(DocExtractApiState docState,
      List<(String, String, String)> defs) {
    final theme = Theme.of(context);
    final tiles = <Widget>[];
    for (final def in defs) {
      final (field, title, subtitle) = def;
      final value = _getOptionValue(docState, field);
      tiles.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 4),
                    _helpIcon(subtitle),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: value,
                  onChanged: (v) {
                    if (value != v) {
                      ref
                          .read(docExtractApiProvider.notifier)
                          .setBool(field, v);
                    }
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return tiles;
  }

  Widget _sliderTile({
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 4),
                    _helpIcon(subtitle),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 16),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: value, min: min, max: max,
                    divisions: divisions, onChanged: onChanged,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (onReset != null)
                IconButton(
                  onPressed: onReset,
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

  Widget _ignoreLabelChips(DocExtractApiState docState) {
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
              borderRadius: BorderRadius.circular(12)),
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

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: cs.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
          isDense: true,
          suffixIcon: suffix,
        );

    return Column(
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
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withAlpha(150),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Symbols.auto_awesome_rounded,
                        size: 20, color: cs.secondary),
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

              // ── Access Token ──
              Row(
                children: [
              Text('API Key',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(width: 8),
              Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('必填',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),]
              ),
              const SizedBox(height: 4),
              Text('用于异步 Job API 认证',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextField(
                controller: _keyCtrl,
                onChanged: (v) {
                  _keyTimer?.cancel();
                  _keyTimer = Timer(const Duration(milliseconds: 600), () {
                    ref
                        .read(docExtractApiProvider.notifier)
                        .setApiKey(v.trim());
                  });
                },
                obscureText: _keyObscured,
                decoration: fieldDeco(
                  hint: 'token ...',
                  suffix: IconButton(
                    icon: Icon(
                      _keyObscured
                          ? Symbols.visibility_off
                          : Symbols.visibility,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _keyObscured = !_keyObscured),
                  ),
                ),
                autocorrect: false,
                enableSuggestions: false,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),

              // ── 同步 API URL ──
              Row(
                children: [
                  Text('同步 Base URL',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('可选',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('异步提取失败时回退到同步接口',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextField(
                controller: _urlCtrl,
                onChanged: (v) {
                  _urlTimer?.cancel();
                  _urlTimer = Timer(const Duration(milliseconds: 600), () {
                    ref
                        .read(docExtractApiProvider.notifier)
                        .setSyncBaseUrl(v.trim());
                  });
                },
                decoration: fieldDeco(
                    hint: 'https://xxx.aistudio-app.com'),
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        // ── 版面分析 ──
        _subHeader('版面分析'),
        ..._switchGroup(docState, _layoutDefs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('版面几何形状',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  _helpIcon('版面检测框的几何形状表示'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: _layoutShapeModes
                      .map((m) => ButtonSegment(
                            value: m.$1,
                            label: Text(m.$2),
                          ))
                      .toList(),
                  selected: {docState.layoutShapeMode},
                  onSelectionChanged: (set) {
                    final v = set.first;
                    if (docState.layoutShapeMode != v) {
                      ref
                          .read(docExtractApiProvider.notifier)
                          .setString('layoutShapeMode', v);
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
            ],
          ),
        ),
        _sliderTile(
          title: '版面检测阈值',
          subtitle: '区域过滤的阈值，值越高保留的区域越少',
          value: docState.layoutThreshold,
          min: 0.0, max: 1.0, divisions: 20, defaultValue: 0.5,
          onChanged: (v) => ref
              .read(docExtractApiProvider.notifier)
              .setDouble('layoutThreshold', v),
          onReset: () => ref
              .read(docExtractApiProvider.notifier)
              .setDouble('layoutThreshold', 0.5),
        ),

        // ── 输出控制 ──
        _subHeader('输出控制'),
        ..._switchGroup(docState, _outputDefs),
        _sliderTile(
          title: '重复惩罚',
          subtitle: '出现重复文字或表格内容时适当调高',
          value: docState.repetitionPenalty,
          min: 1.0, max: 2.0, divisions: 20, defaultValue: 1.0,
          onChanged: (v) => ref
              .read(docExtractApiProvider.notifier)
              .setDouble('repetitionPenalty', v),
          onReset: () => ref
              .read(docExtractApiProvider.notifier)
              .setDouble('repetitionPenalty', 1.0),
        ),

        // ── 识别增强 ──
        _subHeader('识别增强'),
        ..._switchGroup(docState, _recognitionDefs),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Markdown 忽略标签',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      )),
                  const SizedBox(width: 4),
                  _helpIcon('勾选的标签区域将不会输出到 Markdown 结果中，默认全忽略。'),
                ],
              ),
              const SizedBox(height: 12),
              _ignoreLabelChips(docState),
            ],
          ),
        ),

        // ── 文档校正 ──
        _subHeader('文档校正'),
        ..._switchGroup(docState, _correctionDefs),
        const SizedBox(height: 8),
      ],
    );
  }
}
