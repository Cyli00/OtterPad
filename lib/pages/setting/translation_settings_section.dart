import '../../widgets/setting_controls.dart';
import '../../l10n/reader_labels.dart';
import '../../widgets/translation_style_label.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/elevation.dart';
import '../../core/l10n.dart';
import '../../providers/translation_config_provider.dart';
import '../../services/haptics.dart';
import '../../services/prompts.dart';
import '../../services/translation_skip_sections.dart';
import '../../services/translation_style.dart';
import '../../widgets/tactile_press.dart';

/// 翻译设置区块——嵌入 api_settings_page 的 SettingGroup 内。
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

  /// user prompt 缺必需占位符时的即时错误提示。非 null 期间存储层
  /// （PromptStore.set）同样会拒绝保存——红字 = 当前文本无效未保存。
  String? _userPromptError;

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
    // 即时校验：缺必需占位符立即红字（空白除外——空白 = 重置为默认）。
    // 防抖落点的 setUserPrompt 校验不过会拒绝写入，红字即"未保存"。
    final missing = Prompts.translationUser.missingPlaceholders(value);
    final error = (missing.isEmpty || value.trim().isEmpty)
        ? null
        : context.l10n.promptMissingPlaceholders(
            missing.map((p) => '{{$p}}').join(', '),
          );
    if (error != _userPromptError) {
      setState(() => _userPromptError = error);
    }
    _userTimer?.cancel();
    _userTimer = Timer(const Duration(milliseconds: 600), () {
      ref.read(translationConfigProvider.notifier).setUserPrompt(value);
    });
  }

  /// 设置项说明 + 该 prompt 的可用占位符清单（清单从 registry 渲染，
  /// ARB 文案不再手写占位符名）。
  String _promptDesc(String desc, PromptDef def) =>
      '$desc · ${context.l10n.promptPlaceholdersAvailable(def.placeholdersLabel)}';

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
          SettingTitle(
            context.l10n.targetLanguage,
            context.l10n.translationTargetLangDesc,
          ),
          const SizedBox(height: 12),
          _buildLanguagePicker(theme, cs, cfg.targetLanguage),

          const SizedBox(height: 24),

          // ── 译文样式 ──
          SettingTitle(
            context.l10n.translationStyleSetting,
            context.l10n.translationStyleDesc,
          ),
          const SizedBox(height: 12),
          _buildStylePicker(theme, cs, cfg.displayStyleId),

          const SizedBox(height: 24),

          // ── 翻译忽略内容 ──
          SettingTitle(
            context.l10n.translationIgnore,
            context.l10n.translationIgnoreDesc,
          ),
          const SizedBox(height: 12),
          _buildIgnoreSectionChips(cs, cfg.ignoreSections),

          const SizedBox(height: 24),

          // ── 温度 ──
          SettingSlider(
            padding: EdgeInsets.zero,
            title: context.l10n.temperature,
            tooltip: context.l10n.temperatureDesc,
            value: cfg.temperature,
            fallback: 0.0,
            min: 0.0,
            max: 2.0,
            divisions: 40,
            formatter: (v) => v.toStringAsFixed(2),
            onChanged: (v) {
              ref.read(translationConfigProvider.notifier).setTemperature(v);
            },
            onReset: () {
              ref.read(translationConfigProvider.notifier).setTemperature(null);
            },
          ),

          const SizedBox(height: 24),

          // ── 系统提示词 ──
          Row(
            children: [
              Expanded(
                child: SettingTitle(
                  context.l10n.systemPrompt,
                  _promptDesc(
                    context.l10n.systemPromptDesc,
                    Prompts.translationSystem,
                  ),
                ),
              ),
              if (!cfg.isSystemPromptDefault)
                SettingResetButton(
                  onPressed: () {
                    ref
                        .read(translationConfigProvider.notifier)
                        .resetSystemPrompt();
                    _systemPromptCtrl.text = kDefaultTranslationSystemPrompt;
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _systemPromptCtrl,
            minLines: 3,
            maxLines: 8,
            style: theme.textTheme.bodyMedium,
            decoration: _fieldDeco(
              theme,
              cs,
              hint: context.l10n.systemPromptHint,
            ),
            onChanged: (v) => _debounceSaveSystem(v.trim()),
          ),

          const SizedBox(height: 24),

          // ── 用户提示词 ──
          Row(
            children: [
              Expanded(
                child: SettingTitle(
                  context.l10n.userPrompt,
                  _promptDesc(
                    context.l10n.userPromptDesc,
                    Prompts.translationUser,
                  ),
                ),
              ),
              if (!cfg.isUserPromptDefault)
                SettingResetButton(
                  onPressed: () {
                    ref
                        .read(translationConfigProvider.notifier)
                        .resetUserPrompt();
                    _userPromptCtrl.text = kDefaultTranslationUserPrompt;
                    setState(() => _userPromptError = null);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userPromptCtrl,
            minLines: 2,
            maxLines: 6,
            style: theme.textTheme.bodyMedium,
            decoration: _fieldDeco(
              theme,
              cs,
              hint: 'Translate to {{targetLanguage}}:\n\n{{input}}',
            ).copyWith(errorText: _userPromptError),
            onChanged: (v) => _debounceSaveUser(v.trim()),
          ),
        ],
      ),
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
    TranslationStyle style,
    ThemeData theme,
    ColorScheme cs,
    String currentId,
  ) {
    final isSelected = style.id == currentId;
    return TactilePress(
      borderRadius: BorderRadius.circular(12),
      baseColor: isSelected ? cs.primaryContainer : cs.surfaceContainerLow,
      border: Border.all(
        color: isSelected
            ? Colors.transparent
            : cs.outlineVariant.withAlpha(100),
      ),
      onTap: () {
        ref
            .read(translationConfigProvider.notifier)
            .setDisplayStyleId(style.id);
      },
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: TranslationStyleLabel(
        styleId: style.id,
        label: translationStyleLabel(context.l10n, style.id),
      ),
    );
  }

  /// 点击后弹出底部语言选择面板（视觉参照 toolbar_bottom_sheet）
  Widget _buildLanguagePicker(ThemeData theme, ColorScheme cs, String current) {
    return TactilePress(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showLanguageSheet(current),
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
            Icon(
              Symbols.expand_more_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: AppShadows.sheet,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
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
                      bottom: MediaQuery.of(ctx).padding.bottom + 16,
                    ),
                    children: kTargetLanguages.map((lang) {
                      final isSelected = lang == current;
                      return TactilePress(
                        baseColor: Colors.transparent,
                        onTap: () => Navigator.pop(ctx, lang),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                lang,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected ? cs.primary : cs.onSurface,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Symbols.check_rounded,
                                color: cs.primary,
                                size: 22,
                              ),
                          ],
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

String _skipSectionLabel(AppLocalizations l10n, String id) => switch (id) {
  'references' => l10n.skipSectionReferences,
  'acknowledgments' => l10n.skipSectionAcknowledgments,
  'authors_contributions' => l10n.skipSectionAuthorsContributions,
  'funding_data' => l10n.skipSectionFundingData,
  'supplementary_appendix' => l10n.skipSectionSupplementaryAppendix,
  'ethics_legends' => l10n.skipSectionEthicsLegends,
  _ => id,
};
