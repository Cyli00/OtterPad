import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../providers/api_provider.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'setting_picker.dart';

/// OCR 设置页 — 独立顶级设置入口
class OcrSettingsPage extends ConsumerStatefulWidget {
  const OcrSettingsPage({super.key});

  @override
  ConsumerState<OcrSettingsPage> createState() => _OcrSettingsPageState();
}

class _OcrSettingsPageState extends ConsumerState<OcrSettingsPage> {
  List<(String, String)> _layoutShapeModes(AppLocalizations l10n) => [
    ('auto', l10n.ocrAuto),
    ('rect', l10n.ocrRectangle),
    ('quad', l10n.ocrQuadrilateral),
    ('poly', l10n.ocrPolygon),
  ];

  List<(String, String, String)> _recognitionDefs(AppLocalizations l10n) => [
    ('useChartRecognition', l10n.chartRecognition, l10n.ocrChartRecognitionDesc),
    ('useSealRecognition', l10n.stampRecognition, l10n.ocrStampRecognitionDesc),
    ('useOcrForImageBlock', l10n.imageAreaOcr, l10n.ocrImageAreaDesc),
  ];

  List<(String, String, String)> _correctionDefs(AppLocalizations l10n) => [
    ('useDocOrientationClassify', l10n.orientationCorrection, l10n.ocrOrientationDesc),
    ('useDocUnwarping', l10n.curvatureCorrection, l10n.ocrCurvatureDesc),
  ];

  List<(String, String, String)> _layoutDefs(AppLocalizations l10n) => [
    ('layoutNms', l10n.deduplicateBoxes, l10n.ocrDeduplicateDesc),
  ];

  List<(String, String, String)> _outputDefs(AppLocalizations l10n) => [
    ('restructurePages', l10n.multiPageReconstruction, l10n.ocrMultiPageDesc),
  ];

  Map<String, String> _labelNames(AppLocalizations l10n) => {
    'header': l10n.ocrHeader,
    'header_image': l10n.ocrHeaderImage,
    'footer': l10n.ocrFooter,
    'footer_image': l10n.ocrFooterImage,
    'number': l10n.ocrPageNumber,
    'footnote': l10n.ocrFootnote,
    'aside_text': l10n.ocrSideNote,
  };


  late final TextEditingController _keyCtrl;

    bool _keyObscured = true;
    Timer? _keyTimer;

    @override
    void initState() {
      super.initState();
      final s = ref.read(docExtractApiProvider);
      _keyCtrl = TextEditingController(text: s.apiKey);
    }

    @override
    void dispose() {
      _keyCtrl.dispose();
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

  Widget _buildGroup({required String title, required Widget child}) {
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
    required String Function(double) formatter,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSet = value != defaultValue;
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
                  color: isSet
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest.withAlpha(160),
                  borderRadius: BorderRadius.circular(12),
                  border: isSet
                      ? null
                      : Border.all(color: cs.outlineVariant.withAlpha(80)),
                ),
                child: Text(
                  formatter(value),
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
              IconButton(
                onPressed: isSet ? onReset : null,
                icon: const Icon(Symbols.refresh_rounded, size: 20),
                tooltip: context.l10n.restoreDefaults,
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
          label: Text(_labelNames(context.l10n)[label] ?? label),
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
              width: 1,
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

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          context.l10n.ocrSettings,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: Listener(
        onPointerDown: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          ScaffoldMessenger.of(context).clearSnackBars();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              .copyWith(bottom: 40),
          children: [
            // ── OCR 接口设置 ──
            _buildGroup(
              title: context.l10n.ocrInterface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── API Key ──
                    Row(
                      children: [
                        Text('API Key',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            )),
                        const Spacer(),
                        IconButton(
                          onPressed: () => launchUrl(
                            Uri.parse(
                                'https://aistudio.baidu.com/paddleocr'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: Icon(Symbols.arrow_outward_rounded,
                              size: 16, color: cs.onSurfaceVariant),
                          tooltip: context.l10n.getToken,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyCtrl,
                      onChanged: (v) {
                        _keyTimer?.cancel();
                        _keyTimer =
                            Timer(const Duration(milliseconds: 600), () {
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
                  ],
                ),
              ),
            ),

            // ── 版面分析 ──
            _buildGroup(
              title: context.l10n.layoutAnalysis,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ..._switchGroup(docState, _layoutDefs(context.l10n)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(context.l10n.layoutGeometry,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(width: 4),
                            _helpIcon(context.l10n.layoutGeometryHelp),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SettingPicker<String>(
                          current: docState.layoutShapeMode,
                          options: _layoutShapeModes(context.l10n).map((m) => m.$1).toList(),
                          labelFor: (id) =>
                              _layoutShapeModes(context.l10n).firstWhere((m) => m.$1 == id).$2,
                          sheetTitle: context.l10n.layoutGeometry,
                          onChanged: (v) {
                            if (docState.layoutShapeMode != v) {
                              ref
                                  .read(docExtractApiProvider.notifier)
                                  .setString('layoutShapeMode', v);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  _sliderTile(
                    title: context.l10n.layoutDetectionThreshold,
                    subtitle: context.l10n.ocrThresholdHelp,
                    value: docState.layoutThreshold,
                    min: 0.0, max: 1.0, divisions: 20, defaultValue: 0.5,
                    formatter: (v) => v.toStringAsFixed(2),
                    onChanged: (v) => ref
                        .read(docExtractApiProvider.notifier)
                        .setDouble('layoutThreshold', v),
                    onReset: () => ref
                        .read(docExtractApiProvider.notifier)
                        .setDouble('layoutThreshold', 0.5),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            // ── 输出控制 ──
            _buildGroup(
              title: context.l10n.outputControl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ..._switchGroup(docState, _outputDefs(context.l10n)),
                  _sliderTile(
                    title: context.l10n.repetitionPenalty,
                    subtitle: context.l10n.repetitionPenaltyHint,
                    value: docState.repetitionPenalty,
                    min: 1.0, max: 2.0, divisions: 20, defaultValue: 1.0,
                    formatter: (v) => v.toStringAsFixed(2),
                    onChanged: (v) => ref
                        .read(docExtractApiProvider.notifier)
                        .setDouble('repetitionPenalty', v),
                    onReset: () => ref
                        .read(docExtractApiProvider.notifier)
                        .setDouble('repetitionPenalty', 1.0),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            // ── 识别增强 ──
            _buildGroup(
              title: context.l10n.recognitionEnhancement,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ..._switchGroup(docState, _recognitionDefs(context.l10n)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(context.l10n.markdownIgnoreLabels,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                )),
                            const SizedBox(width: 4),
                            _helpIcon(
                                context.l10n.ocrFilterHelp),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ignoreLabelChips(docState),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            // ── 文档校正 ──
            _buildGroup(
              title: context.l10n.documentCorrection,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ..._switchGroup(docState, _correctionDefs(context.l10n)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
