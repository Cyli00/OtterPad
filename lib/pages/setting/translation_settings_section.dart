import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../../providers/translation_config_provider.dart';
import '../../services/haptics.dart';
import '../../services/translation_skip_sections.dart';
import '../../services/translation_style.dart';

/// 翻译设置区块——嵌入 api_settings_page 的 _buildGroup 内。
class TranslationSettingsSection extends ConsumerStatefulWidget {
  const TranslationSettingsSection({super.key});

  @override
  ConsumerState<TranslationSettingsSection> createState() =>
      _TranslationSettingsSectionState();
}

class _TranslationSettingsSectionState
    extends ConsumerState<TranslationSettingsSection> {
  late final TextEditingController _systemPromptCtrl;
  late final TextEditingController _userPromptCtrl;
  Timer? _systemTimer;
  Timer? _userTimer;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(translationConfigProvider);
    _systemPromptCtrl = TextEditingController(text: cfg.systemPrompt);
    _userPromptCtrl = TextEditingController(text: cfg.userPrompt);
  }

  @override
  void dispose() {
    _systemTimer?.cancel();
    _userTimer?.cancel();
    _systemPromptCtrl.dispose();
    _userPromptCtrl.dispose();
    super.dispose();
  }

  void _debounceSaveSystem(String value) {
    _systemTimer?.cancel();
    _systemTimer = Timer(const Duration(milliseconds: 600), () {
      ref.read(translationConfigProvider.notifier).setSystemPrompt(value);
    });
  }

  void _debounceSaveUser(String value) {
    _userTimer?.cancel();
    _userTimer = Timer(const Duration(milliseconds: 600), () {
      ref.read(translationConfigProvider.notifier).setUserPrompt(value);
    });
  }

  // ── 通用 helpers（镜像 ocr_settings_page 风格）─────────────────────────

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

  InputDecoration _fieldDeco(ThemeData theme, ColorScheme cs,
      {required String hint}) {
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

  /// 镜像 agent_model_params_sheet 的 _sliderRow 视觉
  Widget _sliderRow({
    required ThemeData theme,
    required ColorScheme cs,
    required String title,
    required String tooltip,
    required double? value,
    required double fallback,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) formatter,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    final isSet = value != null;
    final displayValue = value ?? fallback;
    return Column(
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
                  _helpIcon(tooltip),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                formatter(displayValue),
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
                  value: displayValue.clamp(min, max),
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
              onPressed: isSet ? onReset : null,
              icon: const Icon(Symbols.refresh_rounded, size: 20),
              tooltip: context.l10n.restoreDefaults,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cfg = ref.watch(translationConfigProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 目标语言 ──
          _buildTitleRow(context.l10n.targetLanguage, context.l10n.translationTargetLangDesc),
          const SizedBox(height: 12),
          _buildLanguagePicker(theme, cs, cfg.targetLanguage),

          const SizedBox(height: 24),

          // ── 译文样式 ──
          _buildTitleRow(context.l10n.translationStyleSetting, context.l10n.translationStyleDesc),
          const SizedBox(height: 12),
          _buildStylePicker(theme, cs, cfg.displayStyleId),

          const SizedBox(height: 24),

          // ── 翻译忽略内容 ──
          _buildTitleRow(context.l10n.translationIgnore, context.l10n.translationIgnoreDesc),
          const SizedBox(height: 12),
          _buildIgnoreSectionChips(cs, cfg.ignoreSections),

          const SizedBox(height: 24),

          // ── 温度 ──
          _sliderRow(
            theme: theme,
            cs: cs,
            title: context.l10n.temperature,
            tooltip: context.l10n.temperatureDesc,
            value: cfg.temperature,
            fallback: 0.0,
            min: 0.0,
            max: 2.0,
            divisions: 40,
            formatter: (v) => v.toStringAsFixed(2),
            onChanged: (v) {
              Haptics.soft();
              ref.read(translationConfigProvider.notifier).setTemperature(v);
            },
            onReset: () {
              Haptics.soft();
              ref.read(translationConfigProvider.notifier).setTemperature(null);
            },
          ),

          const SizedBox(height: 24),

          // ── 系统提示词 ──
          Row(
            children: [
              Expanded(child: _buildTitleRow(
                context.l10n.systemPrompt,
                context.l10n.systemPromptDesc,
              )),
              if (!cfg.isSystemPromptDefault)
                _resetButton(onPressed: () {
                  Haptics.soft();
                  ref
                      .read(translationConfigProvider.notifier)
                      .resetSystemPrompt();
                  _systemPromptCtrl.text = kDefaultTranslationSystemPrompt;
                }),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _systemPromptCtrl,
            minLines: 3,
            maxLines: 8,
            style: theme.textTheme.bodyMedium,
            decoration: _fieldDeco(theme, cs,
                hint: context.l10n.systemPromptHint),
            onChanged: (v) => _debounceSaveSystem(v.trim()),
          ),

          const SizedBox(height: 24),

          // ── 用户提示词 ──
          Row(
            children: [
              Expanded(child: _buildTitleRow(
                context.l10n.userPrompt,
                context.l10n.userPromptDesc,
              )),
              if (!cfg.isUserPromptDefault)
                _resetButton(onPressed: () {
                  Haptics.soft();
                  ref
                      .read(translationConfigProvider.notifier)
                      .resetUserPrompt();
                  _userPromptCtrl.text = kDefaultTranslationUserPrompt;
                }),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userPromptCtrl,
            minLines: 2,
            maxLines: 6,
            style: theme.textTheme.bodyMedium,
            decoration: _fieldDeco(theme, cs,
                hint: 'Translate to {{targetLanguage}}:\n\n{{input}}'),
            onChanged: (v) => _debounceSaveUser(v.trim()),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleRow(String title, String tooltip) {
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

  /// 翻译忽略区域：FilterChip 镜像 OCR 忽略标签视觉。
  Widget _buildIgnoreSectionChips(ColorScheme cs, List<String> selected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kAllTranslationSkipSections.map((section) {
        final isSelected = selected.contains(section.id);
        return FilterChip(
          label: Text(_skipSectionLabel(context.l10n, section.id)),
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
              if (!updated.contains(section.id)) updated.add(section.id);
            } else {
              updated.remove(section.id);
            }
            ref
                .read(translationConfigProvider.notifier)
                .setIgnoreSections(updated);
          },
        );
      }).toList(),
    );
  }

  /// 译文样式选择：自描述 chip，label 即预览——文本用自身样式渲染。
  Widget _buildStylePicker(ThemeData theme, ColorScheme cs, String currentId) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kTranslationStyles
          .map((s) => _buildStyleChip(s, theme, cs, currentId))
          .toList(),
    );
  }

  Widget _buildStyleChip(
    TranslationStyleStrategy style,
    ThemeData theme,
    ColorScheme cs,
    String currentId,
  ) {
    final isSelected = style.id == currentId;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isSelected ? cs.primaryContainer : cs.surfaceContainerLow,
        border: Border.all(
          color: isSelected
              ? Colors.transparent
              : cs.outlineVariant.withAlpha(100),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Haptics.soft();
            ref
                .read(translationConfigProvider.notifier)
                .setDisplayStyleId(style.id);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: _buildStyledLabel(style.id, _translationStyleLabel(context.l10n, style.id), cs, theme),
          ),
        ),
      ),
    );
  }

  Widget _buildStyledLabel(
    String styleId,
    String label,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final base = theme.textTheme.bodyMedium!;

    return switch (styleId) {
      'themed' => Text(label, style: base.copyWith(color: cs.primary)),
      'bold' => Text(label,
          style: base.copyWith(fontWeight: FontWeight.bold)),
      'italic' => Text(label,
          style: base.copyWith(fontStyle: FontStyle.italic)),
      'weakened' => Text(label,
          style: base.copyWith(color: cs.onSurface.withAlpha(120))),
      'dashed' => Text(label,
          style: base.copyWith(
            color: cs.primary,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dashed,
            decorationColor: cs.primary.withAlpha(140),
          )),
      'highlight' => Text(label,
          style: base.copyWith(backgroundColor: cs.primaryContainer)),
      'blur' => ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Text(label, style: base),
          ),
        ),
      'quote' => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: base.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      _ => Text(label, style: base),
    };
  }

  /// 点击后弹出底部语言选择面板（视觉参照 toolbar_bottom_sheet）
  Widget _buildLanguagePicker(
      ThemeData theme, ColorScheme cs, String current) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Haptics.soft();
        _showLanguageSheet(current);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withAlpha(100)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Symbols.expand_more_rounded,
                size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _showLanguageSheet(String current) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final maxH = MediaQuery.sizeOf(ctx).height * 0.7;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.l10n.targetLanguage,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.of(ctx).padding.bottom + 16),
                    children: kTargetLanguages.map((lang) {
                      final isSelected = lang == current;
                      return InkWell(
                        onTap: () {
                          Haptics.soft();
                          Navigator.pop(ctx, lang);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  lang,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurface,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Symbols.check_rounded,
                                    color: cs.primary, size: 22),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && selected != current && mounted) {
      ref.read(translationConfigProvider.notifier).setTargetLanguage(selected);
    }
  }
}

String _translationStyleLabel(AppLocalizations l10n, String id) => switch (id) {
  'themed' => l10n.translationStyleThemed,
  'bold' => l10n.translationStyleBold,
  'italic' => l10n.translationStyleItalic,
  'weakened' => l10n.translationStyleWeakened,
  'dashed' => l10n.translationStyleDashed,
  'highlight' => l10n.translationStyleHighlight,
  'blur' => l10n.translationStyleBlur,
  'quote' => l10n.translationStyleQuote,
  _ => id,
};

String _skipSectionLabel(AppLocalizations l10n, String id) => switch (id) {
  'references' => l10n.skipSectionReferences,
  'acknowledgments' => l10n.skipSectionAcknowledgments,
  'authors_contributions' => l10n.skipSectionAuthorsContributions,
  'funding_data' => l10n.skipSectionFundingData,
  'supplementary_appendix' => l10n.skipSectionSupplementaryAppendix,
  'ethics_legends' => l10n.skipSectionEthicsLegends,
  _ => id,
};
