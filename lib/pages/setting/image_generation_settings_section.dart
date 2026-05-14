import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../providers/api_provider.dart';
import '../../providers/image_generation_config_provider.dart';
import 'setting_picker.dart';

/// 画幅比例用户场景副标题——帮用户从"数字"映射到"使用场景"。
const _kAspectRatioHints = <String, String>{
  '1:1': '方形 · 社交配图',
  '4:3': '传统打印 · 文档版面',
  '3:2': '经典摄影',
  '16:9': '横屏视频 · 桌面壁纸',
  '21:9': '超宽屏 · 电影',
  '9:16': '竖屏 · 手机壁纸',
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
      tooltip: '恢复默认',
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
                '参考图数量',
                '从文献提取的 figure 中按顺序选择参考图；不同模型会按自身上限自动裁剪。',
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
            min: 1,
            max: 14,
            divisions: 13,
            onChanged: (v) => onChanged(v.round()),
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
            '画幅比例',
            'Gemini 映射为 imageConfig.aspectRatio；OpenAI 会映射到最接近的输出尺寸，并在 prompt 中保留比例要求。',
          ),
          const SizedBox(height: 12),
          SettingPicker<String>(
            current: cfg.aspectRatio,
            options: kSummaryAspectRatios,
            labelFor: (v) => v,
            subtitleFor: (v) => _kAspectRatioHints[v] ?? '',
            sheetTitle: '画幅比例',
            onChanged: notifier.setAspectRatio,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _titleRow(
                  '清晰度',
                  'OpenAI 映射为 quality；Gemini 映射为 imageSize。gpt-image-2 的输入图保真度由模型自动高保真处理。',
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
            values: kSummaryFidelityOptions.keys.toList(),
            selected: cfg.fidelity,
            labelFor: (v) => kSummaryFidelityOptions[v] ?? v,
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
                  '总结图 Prompt',
                  '用于控制文献总结图的视觉风格和信息组织方式；运行时会自动追加文献标题、元数据、Markdown 和参考 figure。',
                ),
              ),
              if (!cfg.isPromptDefault)
                _resetButton(
                  onPressed: () {
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
            decoration: _fieldDeco(theme, cs, hint: '描述文献总结图的版式、颜色、信息密度和风格要求'),
            onChanged: (v) => _debounceSavePrompt(v.trim()),
          ),
        ],
      ),
    );
  }

  String? _costLabel(ImageGenerationConfig cfg) {
    final role = AgentApiNotifier.globalImageRole;
    if (role.provider != AgentApiProvider.openai) return null;
    final cost = estimateOpenAICost(
      aspectRatio: cfg.aspectRatio,
      fidelity: cfg.fidelity,
    );
    if (cost == null) return null;
    return '预估 \$${cost.toStringAsFixed(3)}';
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
        onSelectionChanged: (set) => onSelected(set.first),
      ),
    );
  }
}
