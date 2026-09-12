import '../providers/reader_settings_provider.dart';
import 'app_localizations.dart';

extension ReaderThemeLabels on ReaderTheme {
  String localizedLabel(AppLocalizations l10n, {bool short = false}) =>
      switch (this) {
        ReaderTheme.themed =>
          short ? l10n.readerThemeWhiteShort : l10n.readerThemeWhite,
        ReaderTheme.sepia =>
          short ? l10n.readerThemeSepiaShort : l10n.readerThemeSepia,
        ReaderTheme.green =>
          short ? l10n.readerThemeGreenShort : l10n.readerThemeGreen,
        ReaderTheme.night =>
          short ? l10n.readerThemeNightShort : l10n.readerThemeNight,
        ReaderTheme.dark =>
          short ? l10n.readerThemeDarkShort : l10n.readerThemeDark,
      };
}

extension ReaderFontLabels on ReaderFont {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    ReaderFont.serif => l10n.readerFontSerif,
    ReaderFont.sans => l10n.readerFontSans,
  };
}

extension ReaderPaginationLabels on ReaderPaginationMode {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    ReaderPaginationMode.vertical => l10n.verticalPagination,
    ReaderPaginationMode.horizontal => l10n.horizontalPagination,
  };
}

String translationStyleLabel(AppLocalizations l10n, String id) => switch (id) {
  'bold' => l10n.translationStyleBold,
  'italic' => l10n.translationStyleItalic,
  'weakened' => l10n.translationStyleWeakened,
  'dashed' => l10n.translationStyleDashed,
  'highlight' => l10n.translationStyleHighlight,
  'blur' => l10n.translationStyleBlur,
  'quote' => l10n.translationStyleQuote,
  _ => l10n.translationStyleThemed,
};
