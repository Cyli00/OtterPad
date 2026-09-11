import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../providers/api_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/doc_extract_usage_service.dart';
import '../../services/haptics.dart';
import '../../services/mineru_parse_options.dart';
import '../../services/snackbar_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/onboarding_spotlight.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'setting_group.dart';
import 'setting_picker.dart';

/// OCR 设置页 — 独立顶级设置入口
class OcrSettingsPage extends ConsumerStatefulWidget {
  const OcrSettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<OcrSettingsPage> createState() => _OcrSettingsPageState();
}

class _OcrSettingsPageState extends ConsumerState<OcrSettingsPage> {
  // ── PaddleOCR 参数分组（提供商切换后整组显隐）──

  List<(String, String)> _layoutShapeModes(AppLocalizations l10n) => [
    ('auto', l10n.ocrAuto),
    ('rect', l10n.ocrRectangle),
    ('quad', l10n.ocrQuadrilateral),
    ('poly', l10n.ocrPolygon),
  ];

  List<(String, String, String)> _recognitionDefs(AppLocalizations l10n) => [
    (
      'useChartRecognition',
      l10n.chartRecognition,
      l10n.ocrChartRecognitionDesc,
    ),
    ('useSealRecognition', l10n.stampRecognition, l10n.ocrStampRecognitionDesc),
    ('useOcrForImageBlock', l10n.imageAreaOcr, l10n.ocrImageAreaDesc),
  ];

  List<(String, String, String)> _correctionDefs(AppLocalizations l10n) => [
    (
      'useDocOrientationClassify',
      l10n.orientationCorrection,
      l10n.ocrOrientationDesc,
    ),
    ('useDocUnwarping', l10n.curvatureCorrection, l10n.ocrCurvatureDesc),
  ];

  List<(String, String, String)> _layoutDefs(AppLocalizations l10n) => [
    ('layoutNms', l10n.deduplicateBoxes, l10n.ocrDeduplicateDesc),
  ];

  List<(String, String, String)> _outputDefs(AppLocalizations l10n) => [
    ('restructurePages', l10n.multiPageReconstruction, l10n.ocrMultiPageDesc),
    ('mergeTables', l10n.crossPageTableMerge, l10n.crossPageTableMergeDesc),
  ];

  // ── MinerU 参数分组 ──

  List<(String, String, String)> _mineruDefs(AppLocalizations l10n) => [
    ('mineruIsOcr', l10n.mineruScannedOcr, l10n.mineruScannedOcrDesc),
    (
      'mineruEnableFormula',
      l10n.mineruFormulaRecognition,
      l10n.mineruFormulaRecognitionDesc,
    ),
    (
      'mineruEnableTable',
      l10n.mineruTableRecognition,
      l10n.mineruTableRecognitionDesc,
    ),
  ];

  List<(String, String)> _mineruLanguages(AppLocalizations l10n) => [
    ('ch', l10n.ocrLangChinese),
    ('en', l10n.ocrLangEnglish),
    ('ch_server', l10n.mineruLangChServer),
    ('japan', l10n.mineruLangJapan),
    ('korean', l10n.mineruLangKorean),
    ('chinese_cht', l10n.mineruLangChineseCht),
    ('ta', l10n.mineruLangTa),
    ('te', l10n.mineruLangTe),
    ('ka', l10n.mineruLangKa),
    ('el', l10n.mineruLangEl),
    ('th', l10n.mineruLangTh),
    ('latin', l10n.mineruLangLatin),
    ('arabic', l10n.mineruLangArabic),
    ('cyrillic', l10n.mineruLangCyrillic),
    ('east_slavic', l10n.mineruLangEastSlavic),
    ('devanagari', l10n.mineruLangDevanagari),
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

  // ── API Key 输入框（每个提供商一个 controller，切换互不清空）──

  late final Map<DocExtractProvider, TextEditingController> _keyCtrls;

  late final TextEditingController _mineruPageRangesCtrl;

  bool _keyObscured = true;
  Timer? _keyTimer;

  @override
  void initState() {
    super.initState();
    final s = ref.read(docExtractApiProvider);
    _mineruPageRangesCtrl = TextEditingController(text: s.mineruPageRanges);
    _keyCtrls = {
      DocExtractProvider.paddle: TextEditingController(text: s.paddleApiKey),
      DocExtractProvider.mineru: TextEditingController(text: s.mineruApiKey),
    };
  }

  @override
  void dispose() {
    for (final c in _keyCtrls.values) {
      c.dispose();
    }
    _keyTimer?.cancel();
    _mineruPageRangesCtrl.dispose();
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
    'mergeTables' => s.mergeTables,
    'mineruIsOcr' => s.mineruIsOcr,
    'mineruEnableFormula' => s.mineruEnableFormula,
    'mineruEnableTable' => s.mineruEnableTable,
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
        child: Icon(Symbols.help_rounded, size: 16, color: cs.onSurfaceVariant),
      ),
    );
  }

  List<Widget> _switchGroup(
    DocExtractApiState docState,
    List<(String, String, String)> defs,
  ) {
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
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: value,
                  onChanged: (v) {
                    Haptics.soft();
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
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: (v) {
                      Haptics.soft();
                      onChanged(v);
                    },
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              IconButton(
                onPressed: isSet
                    ? () {
                        Haptics.soft();
                        onReset();
                      }
                    : null,
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
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (v) {
            Haptics.soft();
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

  // ── OCR 接口（提供商 + Token + 用量）──

  Widget _buildProviderSection(
    ThemeData theme,
    ColorScheme cs,
    DocExtractApiState docState,
    InputDecoration Function({
      required String hint,
      String? label,
      Widget? suffix,
    })
    fieldDeco,
  ) {
    final step = ref.watch(onboardingProvider);
    final provider = docState.provider;

    final picker = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<DocExtractProvider>(
          segments: [
            for (final p in DocExtractProvider.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {provider},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: cs.surface,
            selectedBackgroundColor: cs.primaryContainer,
            foregroundColor: cs.onSurfaceVariant,
            selectedForegroundColor: cs.onPrimaryContainer,
            side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          onSelectionChanged: (selection) {
            Haptics.soft();
            final next = selection.first;
            if (next != provider) {
              ref.read(docExtractApiProvider.notifier).setProvider(next);
            }
          },
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题 + 获取 Token 入口（URL 跟随当前提供商）
        Padding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 4,
            top: 24,
            bottom: 12,
          ),
          child: Row(
            children: [
              Text(
                context.l10n.ocrInterface,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              _helpIcon(context.l10n.ocrProviderHelp),
              const Spacer(),
              _buildGetTokenButton(cs, provider, step),
            ],
          ),
        ),
        picker,
        _buildApiKeyField(theme, cs, provider, fieldDeco, step),
        const SizedBox(height: 16),
        _buildUsageCard(theme, cs, provider),
      ],
    );
  }

  /// 今日额度卡片：本地记账估算（两提供商均无额度查询 API）。
  Widget _buildUsageCard(
    ThemeData theme,
    ColorScheme cs,
    DocExtractProvider provider,
  ) {
    final usage = ref.watch(docExtractUsageProvider);
    final used = switch (provider) {
      DocExtractProvider.paddle => usage.paddle,
      DocExtractProvider.mineru => usage.mineru,
    };
    final limit = provider.dailyPages;
    final ratio = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final exhausted =
        provider.dailyPagesIsHardLimit && limit > 0 && used >= limit;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        context.l10n.ocrUsageTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _helpIcon(
                      provider.dailyPagesIsHardLimit
                          ? context.l10n.ocrUsageHardLimitNote
                          : context.l10n.ocrUsagePriorityNote,
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: exhausted ? cs.errorContainer : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    context.l10n.ocrUsagePages(used, limit),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: exhausted
                          ? cs.onErrorContainer
                          : cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  exhausted ? cs.error : cs.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.ocrUsageLimitsLine(
                provider.maxFileSizeMB,
                provider.maxPagesPerFile,
                provider.maxBatchFiles,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final docState = ref.watch(docExtractApiProvider);
    final isPaddle = docState.provider == DocExtractProvider.paddle;

    InputDecoration fieldDeco({
      required String hint,
      String? label,
      Widget? suffix,
    }) => InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant.withAlpha(120),
      ),
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: cs.outlineVariant.withAlpha(100),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
    );

    final onboardingStep = ref.watch(onboardingProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: widget.embedded
          ? null
          : AppBar(
              leading: _buildBackButton(onboardingStep),
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
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ).copyWith(bottom: 40),
          children: [
            // ── OCR 接口（提供商 + Token + 今日额度）──
            _buildProviderSection(theme, cs, docState, fieldDeco),

            if (isPaddle) ...[
              // ── 输出控制（PaddleOCR）──
              SettingGroup(
                title: context.l10n.outputControl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    ..._switchGroup(docState, _layoutDefs(context.l10n)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10n.layoutGeometry,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              _helpIcon(context.l10n.layoutGeometryHelp),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SettingPicker<String>(
                            current: docState.layoutShapeMode,
                            options: _layoutShapeModes(
                              context.l10n,
                            ).map((m) => m.$1).toList(),
                            labelFor: (id) => _layoutShapeModes(
                              context.l10n,
                            ).firstWhere((m) => m.$1 == id).$2,
                            sheetTitle: context.l10n.layoutGeometry,
                            onChanged: (v) {
                              Haptics.soft();
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
                    ..._switchGroup(docState, _outputDefs(context.l10n)),
                    _sliderTile(
                      title: context.l10n.repetitionPenalty,
                      subtitle: context.l10n.repetitionPenaltyHint,
                      value: docState.repetitionPenalty,
                      min: 1.0,
                      max: 1.2,
                      divisions: 20,
                      defaultValue: 1.0,
                      formatter: (v) => v.toStringAsFixed(2),
                      onChanged: (v) => ref
                          .read(docExtractApiProvider.notifier)
                          .setDouble('repetitionPenalty', v),
                      onReset: () => ref
                          .read(docExtractApiProvider.notifier)
                          .setDouble('repetitionPenalty', 1.0),
                    ),
                    _sliderTile(
                      title: context.l10n.recognitionStability,
                      subtitle: context.l10n.recognitionStabilityHint,
                      value: docState.temperature,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      defaultValue: 0.0,
                      formatter: (v) => v.toStringAsFixed(2),
                      onChanged: (v) => ref
                          .read(docExtractApiProvider.notifier)
                          .setDouble('temperature', v),
                      onReset: () => ref
                          .read(docExtractApiProvider.notifier)
                          .setDouble('temperature', 0.0),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // ── 识别增强（PaddleOCR）──
              SettingGroup(
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
                              Text(
                                context.l10n.markdownIgnoreLabels,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4),
                              _helpIcon(context.l10n.ocrFilterHelp),
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

              // ── 文档校正（PaddleOCR）──
              SettingGroup(
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
            ] else ...[
              ..._buildMineruGroups(
                docState,
                fieldDeco(hint: context.l10n.mineruPageRangesHint),
              ),
            ],

            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: _confirmReset,
                icon: const Icon(Symbols.restart_alt_rounded, size: 20),
                label: Text(context.l10n.resetOcrSettings),
                style: TextButton.styleFrom(foregroundColor: cs.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mineruField(String title, String help, Widget child) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              _helpIcon(help),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  List<Widget> _buildMineruGroups(
    DocExtractApiState state,
    InputDecoration pageRangeDecoration,
  ) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(docExtractApiProvider.notifier);
    final languages = Map.fromEntries(
      _mineruLanguages(l10n).map((e) => MapEntry(e.$1, e.$2)),
    );
    return [
      SettingGroup(
        title: l10n.outputControl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _mineruField(
              l10n.mineruModel,
              l10n.mineruModelHelp,
              SettingPicker<String>(
                current: state.mineruModelVersion,
                options: MinerUParseOptions.models,
                labelFor: (v) =>
                    v == 'vlm' ? l10n.mineruModelVlm : l10n.mineruModelPipeline,
                sheetTitle: l10n.mineruModel,
                onChanged: (v) => notifier.setString('mineruModelVersion', v),
              ),
            ),
            _mineruField(
              l10n.mineruPageRanges,
              l10n.mineruPageRangesHelp,
              TextFormField(
                controller: _mineruPageRangesCtrl,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => MinerUParseOptions.isValidPageRanges(v ?? '')
                    ? null
                    : l10n.mineruPageRangesInvalid,
                onChanged: (v) {
                  if (MinerUParseOptions.isValidPageRanges(v)) {
                    notifier.setString(
                      'mineruPageRanges',
                      MinerUParseOptions.normalizePageRanges(v),
                    );
                  }
                },
                decoration: pageRangeDecoration.copyWith(errorMaxLines: 2),
              ),
            ),
            _mineruField(
              l10n.mineruExtraFormats,
              l10n.mineruExtraFormatsHelp,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final format in MinerUParseOptions.extraFormats)
                    FilterChip(
                      label: Text(
                        format == 'latex' ? 'LaTeX' : format.toUpperCase(),
                      ),
                      showCheckmark: false,
                      selected: state.mineruExtraFormats.contains(format),
                      color: WidgetStateProperty.resolveWith((states) {
                        return states.contains(WidgetState.selected)
                            ? cs.primaryContainer
                            : cs.surface;
                      }),
                      side: BorderSide(
                        color: state.mineruExtraFormats.contains(format)
                            ? Colors.transparent
                            : cs.outlineVariant.withAlpha(100),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (selected) {
                        Haptics.soft();
                        notifier.setMineruExtraFormats([
                          for (final f in MinerUParseOptions.extraFormats)
                            if (f == format
                                ? selected
                                : state.mineruExtraFormats.contains(f))
                              f,
                        ]);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      SettingGroup(
        title: l10n.recognitionEnhancement,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            ..._switchGroup(state, _mineruDefs(l10n)),
            _mineruField(
              l10n.ocrLanguage,
              l10n.ocrLanguageHelp,
              SettingPicker<String>(
                current: state.mineruLanguage,
                options: MinerUParseOptions.languages,
                labelFor: (v) => languages[v] ?? v,
                sheetTitle: l10n.ocrLanguage,
                onChanged: (v) => notifier.setString('mineruLanguage', v),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ];
  }

  Future<void> _confirmReset() async {
    final cs = Theme.of(context).colorScheme;
    Haptics.soft();
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        title: Text(context.l10n.resetOcrSettings),
        content: Text(context.l10n.resetOcrSettingsConfirm),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, false);
            },
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, true);
            },
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(context.l10n.reset),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await ref.read(docExtractApiProvider.notifier).resetExceptApiKey();
    if (!mounted) return;
    _mineruPageRangesCtrl.text = ref
        .read(docExtractApiProvider)
        .mineruPageRanges;
    ref
        .read(snackBarServiceProvider)
        .showResult(message: context.l10n.ocrSettingsReset);
  }

  Widget _buildGetTokenButton(
    ColorScheme cs,
    DocExtractProvider provider,
    OnboardingStep step,
  ) {
    final button = IconButton(
      onPressed: () {
        Haptics.soft();
        launchUrl(
          Uri.parse(provider.tokenPageUrl),
          mode: LaunchMode.externalApplication,
        );
        if (step == OnboardingStep.ocrGetToken) {
          ref.read(onboardingProvider.notifier).advance();
        }
      },
      icon: Icon(
        Symbols.arrow_outward_rounded,
        size: 16,
        color: cs.onSurfaceVariant,
      ),
      tooltip: context.l10n.getToken,
      visualDensity: VisualDensity.compact,
    );
    if (step != OnboardingStep.ocrGetToken) return button;
    return OnboardingPulse(borderRadius: 20, child: button);
  }

  Widget _buildApiKeyField(
    ThemeData theme,
    ColorScheme cs,
    DocExtractProvider provider,
    InputDecoration Function({
      required String hint,
      String? label,
      Widget? suffix,
    })
    fieldDeco,
    OnboardingStep step,
  ) {
    final ctrl = _keyCtrls[provider]!;

    final field = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        key: ValueKey(provider),
        controller: ctrl,
        onChanged: (v) {
          _keyTimer?.cancel();
          _keyTimer = Timer(const Duration(milliseconds: 600), () {
            ref
                .read(docExtractApiProvider.notifier)
                .setApiKey(provider, v.trim());
          });
          if (step == OnboardingStep.ocrApiKey && v.trim().isNotEmpty) {
            ref.read(onboardingProvider.notifier).advance();
          }
        },
        obscureText: _keyObscured,
        decoration: fieldDeco(
          hint: 'token ...',
          label: 'API Key',
          suffix: IconButton(
            icon: Icon(
              _keyObscured
                  ? Symbols.visibility_off_rounded
                  : Symbols.visibility_rounded,
              size: 20,
            ),
            onPressed: () {
              Haptics.soft();
              setState(() => _keyObscured = !_keyObscured);
            },
          ),
        ),
        autocorrect: false,
        enableSuggestions: false,
        style: theme.textTheme.bodyMedium,
      ),
    );
    if (step != OnboardingStep.ocrApiKey) return field;
    return OnboardingPulse(borderRadius: 12, child: field);
  }

  Widget _buildBackButton(OnboardingStep step) {
    final button = IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Symbols.arrow_back_rounded),
    );
    if (step != OnboardingStep.ocrGoBack) return button;
    return OnboardingPulse(borderRadius: 20, child: button);
  }
}
