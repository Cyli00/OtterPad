import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../../providers/api_provider.dart';
import '../../providers/image_generation_config_provider.dart';
import '../../services/haptics.dart';
import '../../services/prompts.dart';
import 'setting_picker.dart';

/// 画幅比例用户场景副标题——帮用户从"数字"映射到"使用场景"。
/// 含中文的 hint 在 build 内通过 l10n 解析，其余技术描述保持原样。
Map<String, String> _kAspectRatioHints(AppLocalizations l10n) => <String, String>{
  '1:1': l10n.aspectSquare,
  '4:3': l10n.aspectClassic,
  '16:9': l10n.aspectWide,
  '21:9': l10n.aspectUltraWide,
  '9:16': l10n.aspectTall,
};

class ImageGenerationSettingsSection extends ConsumerStatefulWidget {
  const ImageGenerationSettingsSection({super.key});

  @override
  ConsumerState<ImageGenerationSettingsSection> createState() =>
      _ImageGenerationSettingsSectionState();
}

class _ImageGenerationSettingsSectionState
    extends ConsumerState<ImageGenerationSettingsSection> {
  late final TextEditingController _promptCtrl;
  Timer? _promptTimer;

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController(
      text: ref.read(imageGenerationConfigProvider).prompt,
    );
  }

  @override
  void dispose() {
    _promptTimer?.cancel();
    _promptCtrl.dispose();
    super.dispose();
  }

  void _debounceSavePrompt(String value) {
    _promptTimer?.cancel();
    _promptTimer = Timer(const Duration(milliseconds: 600), () {
      ref.read(imageGenerationConfigProvider.notifier).setPrompt(value);
    });
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
      fillColor: cs.surfaceContainerLow,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant.withAlpha(100)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );
  }

  Widget _titleRow(String title, String tooltip) {
    final theme = Theme.of(context);
    return Row(
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
        _helpIcon(tooltip),
      ],
    );
  }

  Widget _resetButton({required VoidCallback onPressed}) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(Symbols.refresh_rounded, size: 18, color: cs.onSurfaceVariant),
      tooltip: context.l10n.restoreDefaults,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _sliderRow({
    required ThemeData theme,
    required ColorScheme cs,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _titleRow(
                context.l10n.referenceImageCount,
                context.l10n.imageRefCountHint,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$value',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.toDouble(),
            min: kSummaryReferenceImageMin.toDouble(),
            max: kSummaryReferenceImageMax.toDouble(),
            divisions: kSummaryReferenceImageMax - kSummaryReferenceImageMin,
            onChanged: (v) {
              Haptics.soft();
              onChanged(v.round());
            },
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cfg = ref.watch(imageGenerationConfigProvider);
    final notifier = ref.read(imageGenerationConfigProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleRow(
            context.l10n.aspectRatio,
            context.l10n.aspectRatioHint,
          ),
          const SizedBox(height: 12),
          SettingPicker<String>(
            current: cfg.aspectRatio,
            options: kSummaryAspectRatios,
            labelFor: (v) => v,
            subtitleFor: (v) => v == '3:2' ? context.l10n.classicPhotography : (_kAspectRatioHints(context.l10n)[v] ?? ''),
            sheetTitle: context.l10n.aspectRatio,
            onChanged: (v) {
              Haptics.soft();
              notifier.setAspectRatio(v);
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _titleRow(
                  context.l10n.resolution,
                  context.l10n.resolutionHint,
                ),
              ),
              if (_costLabel(cfg) case final label?)
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _segmented<String>(
            theme: theme,
            cs: cs,
            values: kSummaryFidelityKeys,
            selected: cfg.fidelity,
            labelFor: (v) => _fidelityLabel(context.l10n, v),
            onSelected: notifier.setFidelity,
          ),
          const SizedBox(height: 24),
          _sliderRow(
            theme: theme,
            cs: cs,
            value: cfg.maxReferenceImages,
            onChanged: notifier.setMaxReferenceImages,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _titleRow(
                  context.l10n.summaryPromptLabel,
                  context.l10n.summaryPromptHint,
                ),
              ),
              if (!cfg.isPromptDefault)
                _resetButton(
                  onPressed: () {
                    Haptics.soft();
                    notifier.resetPrompt();
                    _promptCtrl.text = kDefaultSummaryImagePrompt;
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptCtrl,
            minLines: 5,
            maxLines: 12,
            style: theme.textTheme.bodyMedium,
            decoration: _fieldDeco(theme, cs, hint: context.l10n.summaryPromptFieldHint),
            onChanged: (v) => _debounceSavePrompt(v.trim()),
          ),
        ],
      ),
    );
  }

  String? _costLabel(ImageGenerationConfig cfg) {
    final role = AgentApiNotifier.globalImageRole;
    final protocol = role.id == null
        ? null
        : AgentApiNotifier.loadInstance(role.id!)?.provider;
    if (protocol != AgentApiProvider.openai) return null;
    final cost = estimateOpenAICost(
      aspectRatio: cfg.aspectRatio,
      fidelity: cfg.fidelity,
    );
    if (cost == null) return null;
    return context.l10n.estimatedCostShort('\$', cost.toStringAsFixed(3));
  }

  Widget _segmented<T>({
    required ThemeData theme,
    required ColorScheme cs,
    required List<T> values,
    required T selected,
    required String Function(T) labelFor,
    required ValueChanged<T> onSelected,
  }) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        style: SegmentedButton.styleFrom(
          backgroundColor: cs.surface,
          selectedBackgroundColor: cs.primaryContainer,
          foregroundColor: cs.onSurfaceVariant,
          selectedForegroundColor: cs.onPrimaryContainer,
          side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: theme.textTheme.bodyMedium,
        ),
        showSelectedIcon: false,
        segments: values
            .map(
              (v) => ButtonSegment<T>(
                value: v,
                label: Text(labelFor(v), overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        selected: {selected},
        onSelectionChanged: (set) {
          Haptics.soft();
          onSelected(set.first);
        },
      ),
    );
  }
}

String _fidelityLabel(AppLocalizations l10n, String key) => switch (key) {
  'auto' => l10n.fidelityAuto,
  'standard' => l10n.fidelityStandard,
  'high' => l10n.fidelityHigh,
  _ => key,
};
