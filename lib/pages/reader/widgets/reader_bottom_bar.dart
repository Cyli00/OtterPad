import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../providers/document_translation_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../utils/markdown_translation_weaver.dart';

enum ReaderSheetType { outline, notes, theme, text }

class ReaderBottomBar extends StatelessWidget {
  final ReaderSettingsState readerSettings;
  final DocumentTranslationState translation;
  final ReaderSheetType? activeSheet;
  final VoidCallback onOpenOutline;
  final VoidCallback onTranslate;
  final VoidCallback onCycleTranslationMode;
  final VoidCallback onOpenNotes;
  final VoidCallback onOpenTheme;
  final VoidCallback onOpenText;

  const ReaderBottomBar({
    super.key,
    required this.readerSettings,
    required this.translation,
    this.activeSheet,
    required this.onOpenOutline,
    required this.onTranslate,
    required this.onCycleTranslationMode,
    required this.onOpenNotes,
    required this.onOpenTheme,
    required this.onOpenText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(
          alpha: readerSettings.toolbarOpacity.value,
        ),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withAlpha(80), width: 0.5),
        ),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: SizedBox(
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _bottomButton(
              cs,
              icon: Symbols.menu_rounded,
              tooltip: l10n.outline,
              active: activeSheet == ReaderSheetType.outline,
              onTap: onOpenOutline,
            ),
            _buildTranslationBottomButton(context, cs),
            _bottomButton(
              cs,
              icon: Symbols.stylus_note_rounded,
              tooltip: l10n.notes,
              active: activeSheet == ReaderSheetType.notes,
              onTap: onOpenNotes,
            ),
            _bottomButton(
              cs,
              icon: Symbols.palette_rounded,
              tooltip: l10n.appearance,
              active: activeSheet == ReaderSheetType.theme,
              onTap: onOpenTheme,
            ),
            _bottomButton(
              cs,
              icon: Symbols.custom_typography_rounded,
              tooltip: l10n.font,
              active: activeSheet == ReaderSheetType.text,
              onTap: onOpenText,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslationBottomButton(BuildContext context, ColorScheme cs) {
    final l10n = context.l10n;
    if (translation.status == DocTranslationStatus.loading) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (translation.hasResult) {
      final next = _nextMode(translation.mode);
      return _bottomButton(
        cs,
        icon: _modeIcon(next),
        tooltip: _modeLabel(l10n, next),
        onTap: onCycleTranslationMode,
      );
    }

    return _bottomButton(
      cs,
      icon: Symbols.translate_rounded,
      tooltip: translation.status == DocTranslationStatus.failed
          ? l10n.retryTranslation
          : l10n.translate,
      onTap: onTranslate,
    );
  }

  static Widget _bottomButton(
    ColorScheme cs, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return IconButton(
      icon: Icon(
        icon,
        size: 24,
        fill: 1,
        color: active ? cs.primary : cs.onSurfaceVariant,
      ),
      tooltip: tooltip,
      onPressed: () {
        Haptics.soft();
        onTap();
      },
    );
  }

  // 必须与 DocumentTranslationNotifier.cycleMode 的顺序一致：
  // 双语 → 译文 → 原文 → 双语
  static DocTranslationMode _nextMode(DocTranslationMode mode) =>
      switch (mode) {
        DocTranslationMode.bilingual => DocTranslationMode.translated,
        DocTranslationMode.translated => DocTranslationMode.off,
        DocTranslationMode.off => DocTranslationMode.bilingual,
      };

  static IconData _modeIcon(DocTranslationMode mode) => switch (mode) {
    DocTranslationMode.bilingual => Symbols.text_compare_rounded,
    DocTranslationMode.off => Symbols.raw_on_rounded,
    DocTranslationMode.translated => Symbols.language_rounded,
  };

  static String _modeLabel(AppLocalizations l10n, DocTranslationMode mode) =>
      switch (mode) {
        DocTranslationMode.bilingual => l10n.bilingual,
        DocTranslationMode.off => l10n.original,
        DocTranslationMode.translated => l10n.translated,
      };
}
