import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'OtterPad'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @outline.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outline;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @font.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// No description provided for @translate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translate;

  /// No description provided for @retryTranslation.
  ///
  /// In en, this message translates to:
  /// **'Retry Translation'**
  String get retryTranslation;

  /// No description provided for @bilingual.
  ///
  /// In en, this message translates to:
  /// **'Bilingual'**
  String get bilingual;

  /// No description provided for @original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get original;

  /// No description provided for @translated.
  ///
  /// In en, this message translates to:
  /// **'Translated'**
  String get translated;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get test;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processing;

  /// No description provided for @cancelAll.
  ///
  /// In en, this message translates to:
  /// **'Cancel All'**
  String get cancelAll;

  /// No description provided for @goToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get goToSettings;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @networkSettings.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkSettings;

  /// No description provided for @networkSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy · Connectivity Test'**
  String get networkSettingsSubtitle;

  /// No description provided for @aiSettings.
  ///
  /// In en, this message translates to:
  /// **'AI Settings'**
  String get aiSettings;

  /// No description provided for @aiSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Model API · Translation · Image Gen'**
  String get aiSettingsSubtitle;

  /// No description provided for @ocrSettings.
  ///
  /// In en, this message translates to:
  /// **'OCR Settings'**
  String get ocrSettings;

  /// No description provided for @ocrSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'OCR API · Recognition Settings'**
  String get ocrSettingsSubtitle;

  /// No description provided for @appearanceSettings.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSettings;

  /// No description provided for @appearanceSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme · Colors · Reading · Text Size'**
  String get appearanceSettingsSubtitle;

  /// No description provided for @dataManagement.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get dataManagement;

  /// No description provided for @dataManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remote Backup · Local Backup · Zotero Sync'**
  String get dataManagementSubtitle;

  /// No description provided for @systemSettings.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemSettings;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// No description provided for @autoMode.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get autoMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightMode;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkMode;

  /// No description provided for @systemMode.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemMode;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @readingSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get readingSettings;

  /// No description provided for @defaultReadingMode.
  ///
  /// In en, this message translates to:
  /// **'Default Reading Mode'**
  String get defaultReadingMode;

  /// No description provided for @defaultReadingModeHint.
  ///
  /// In en, this message translates to:
  /// **'When Markdown is selected, documents without extraction results will fall back to PDF view'**
  String get defaultReadingModeHint;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text Size'**
  String get textSize;

  /// No description provided for @systemTextScale.
  ///
  /// In en, this message translates to:
  /// **'System Text Scale'**
  String get systemTextScale;

  /// No description provided for @textSizeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get textSizeStandard;

  /// No description provided for @textSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get textSizeLarge;

  /// No description provided for @textSizeExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra Large'**
  String get textSizeExtraLarge;

  /// No description provided for @textSizeHint.
  ///
  /// In en, this message translates to:
  /// **'Affects text size throughout the app, persists after restart'**
  String get textSizeHint;

  /// No description provided for @readerThemeWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get readerThemeWhite;

  /// No description provided for @readerThemeSepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get readerThemeSepia;

  /// No description provided for @readerThemeGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get readerThemeGreen;

  /// No description provided for @readerThemeNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get readerThemeNight;

  /// No description provided for @readerThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get readerThemeDark;

  /// No description provided for @readerThemeWhiteShort.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get readerThemeWhiteShort;

  /// No description provided for @readerThemeSepiaShort.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get readerThemeSepiaShort;

  /// No description provided for @readerThemeGreenShort.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get readerThemeGreenShort;

  /// No description provided for @readerThemeNightShort.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get readerThemeNightShort;

  /// No description provided for @readerThemeDarkShort.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get readerThemeDarkShort;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSize;

  /// No description provided for @fontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get fontFamily;

  /// No description provided for @paginationMode.
  ///
  /// In en, this message translates to:
  /// **'Pagination'**
  String get paginationMode;

  /// No description provided for @verticalPagination.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get verticalPagination;

  /// No description provided for @horizontalPagination.
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get horizontalPagination;

  /// No description provided for @translationStyle.
  ///
  /// In en, this message translates to:
  /// **'Translation Style'**
  String get translationStyle;

  /// No description provided for @toolbarOpacityOpaque.
  ///
  /// In en, this message translates to:
  /// **'Opaque'**
  String get toolbarOpacityOpaque;

  /// No description provided for @toolbarOpacitySlight.
  ///
  /// In en, this message translates to:
  /// **'Slight'**
  String get toolbarOpacitySlight;

  /// No description provided for @toolbarOpacityGlass.
  ///
  /// In en, this message translates to:
  /// **'Glass'**
  String get toolbarOpacityGlass;

  /// No description provided for @toolbarOpacityHalf.
  ///
  /// In en, this message translates to:
  /// **'Half'**
  String get toolbarOpacityHalf;

  /// No description provided for @highlightsAndNotes.
  ///
  /// In en, this message translates to:
  /// **'Highlights & Notes'**
  String get highlightsAndNotes;

  /// No description provided for @noHighlights.
  ///
  /// In en, this message translates to:
  /// **'No highlights yet'**
  String get noHighlights;

  /// No description provided for @noHighlightsHint.
  ///
  /// In en, this message translates to:
  /// **'Select text and tap a color dot to create one'**
  String get noHighlightsHint;

  /// No description provided for @editNote.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get editNote;

  /// No description provided for @editNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get editNoteTitle;

  /// No description provided for @writeYourThoughts.
  ///
  /// In en, this message translates to:
  /// **'Write your thoughts...'**
  String get writeYourThoughts;

  /// No description provided for @highlightCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String highlightCount(int count);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hr ago'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgo(int count);

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @toolbarOpacity.
  ///
  /// In en, this message translates to:
  /// **'Toolbar Opacity'**
  String get toolbarOpacity;

  /// No description provided for @translationDone.
  ///
  /// In en, this message translates to:
  /// **'Translation done'**
  String get translationDone;

  /// No description provided for @translationCacheUsed.
  ///
  /// In en, this message translates to:
  /// **'Used cached translation. To re-translate, tap the overflow menu'**
  String get translationCacheUsed;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @recommend.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get recommend;

  /// No description provided for @documentLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get documentLibrary;

  /// No description provided for @recommendContent.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get recommendContent;

  /// No description provided for @batchDelete.
  ///
  /// In en, this message translates to:
  /// **'Batch Delete'**
  String get batchDelete;

  /// No description provided for @searchDocumentsHint.
  ///
  /// In en, this message translates to:
  /// **'Search documents...'**
  String get searchDocumentsHint;

  /// No description provided for @searchDocumentsHintDesktop.
  ///
  /// In en, this message translates to:
  /// **'Search documents, authors, keywords...'**
  String get searchDocumentsHintDesktop;

  /// No description provided for @enterKeywordToSearch.
  ///
  /// In en, this message translates to:
  /// **'Enter keywords to search'**
  String get enterKeywordToSearch;

  /// No description provided for @noDocumentsFound.
  ///
  /// In en, this message translates to:
  /// **'No matching documents'**
  String get noDocumentsFound;

  /// No description provided for @noDocuments.
  ///
  /// In en, this message translates to:
  /// **'No documents'**
  String get noDocuments;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @tools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tools;

  /// No description provided for @addFiles.
  ///
  /// In en, this message translates to:
  /// **'Add Files'**
  String get addFiles;

  /// No description provided for @addByIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Add by Identifier'**
  String get addByIdentifier;

  /// No description provided for @rebuildLibrary.
  ///
  /// In en, this message translates to:
  /// **'Rebuild Library'**
  String get rebuildLibrary;

  /// No description provided for @addByIdentifierTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Entry by Identifier'**
  String get addByIdentifierTitle;

  /// No description provided for @batchExtracting.
  ///
  /// In en, this message translates to:
  /// **'Batch extracting'**
  String get batchExtracting;

  /// No description provided for @extractionDone.
  ///
  /// In en, this message translates to:
  /// **'Extraction done'**
  String get extractionDone;

  /// No description provided for @cancelExtraction.
  ///
  /// In en, this message translates to:
  /// **'Cancel Extraction'**
  String get cancelExtraction;

  /// No description provided for @waitingSubmit.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waitingSubmit;

  /// No description provided for @extractionComplete.
  ///
  /// In en, this message translates to:
  /// **'Extraction complete'**
  String get extractionComplete;

  /// No description provided for @extractionCompletePages.
  ///
  /// In en, this message translates to:
  /// **'Done ({totalPages} pages)'**
  String extractionCompletePages(int totalPages);

  /// No description provided for @extractionFailed.
  ///
  /// In en, this message translates to:
  /// **'Extraction failed'**
  String get extractionFailed;

  /// No description provided for @extractionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Extraction cancelled'**
  String get extractionCancelled;

  /// No description provided for @failedCount.
  ///
  /// In en, this message translates to:
  /// **'Done ({failed} failed)'**
  String failedCount(int failed);

  /// No description provided for @exitMultiSelect.
  ///
  /// In en, this message translates to:
  /// **'Exit selection'**
  String get exitMultiSelect;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @textExtraction.
  ///
  /// In en, this message translates to:
  /// **'Text Extraction'**
  String get textExtraction;

  /// No description provided for @addToFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorite'**
  String get addToFavorite;

  /// No description provided for @removeFromFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorite'**
  String get removeFromFavorite;

  /// No description provided for @deleteFavorite.
  ///
  /// In en, this message translates to:
  /// **'Delete Favorite'**
  String get deleteFavorite;

  /// No description provided for @myLibrary.
  ///
  /// In en, this message translates to:
  /// **'My Library'**
  String get myLibrary;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get synced;

  /// No description provided for @readingHistory.
  ///
  /// In en, this message translates to:
  /// **'Reading History'**
  String get readingHistory;

  /// No description provided for @noFileEntries.
  ///
  /// In en, this message translates to:
  /// **'No File Entries'**
  String get noFileEntries;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @addDocument.
  ///
  /// In en, this message translates to:
  /// **'Add Document'**
  String get addDocument;

  /// No description provided for @addDocuments.
  ///
  /// In en, this message translates to:
  /// **'Add Documents'**
  String get addDocuments;

  /// No description provided for @allDocumentsHaveFiles.
  ///
  /// In en, this message translates to:
  /// **'All documents have files'**
  String get allDocumentsHaveFiles;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach File'**
  String get attachFile;

  /// No description provided for @viewInBrowser.
  ///
  /// In en, this message translates to:
  /// **'View in Browser'**
  String get viewInBrowser;

  /// No description provided for @redownload.
  ///
  /// In en, this message translates to:
  /// **'Redownload'**
  String get redownload;

  /// No description provided for @entryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Entry deleted'**
  String get entryDeleted;

  /// No description provided for @fileAttached.
  ///
  /// In en, this message translates to:
  /// **'File attached'**
  String get fileAttached;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// No description provided for @noReadingHistory.
  ///
  /// In en, this message translates to:
  /// **'No reading history'**
  String get noReadingHistory;

  /// No description provided for @removedFromHistory.
  ///
  /// In en, this message translates to:
  /// **'Removed from history'**
  String get removedFromHistory;

  /// No description provided for @clearReadingHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear Reading History'**
  String get clearReadingHistory;

  /// No description provided for @readingHistoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Reading history cleared'**
  String get readingHistoryCleared;

  /// No description provided for @alreadyInFavorite.
  ///
  /// In en, this message translates to:
  /// **'Already in favorite'**
  String get alreadyInFavorite;

  /// No description provided for @createFavorite.
  ///
  /// In en, this message translates to:
  /// **'Create Favorite'**
  String get createFavorite;

  /// No description provided for @createThenSelect.
  ///
  /// In en, this message translates to:
  /// **'Create, then select below'**
  String get createThenSelect;

  /// No description provided for @editFavorite.
  ///
  /// In en, this message translates to:
  /// **'Edit Favorite'**
  String get editFavorite;

  /// No description provided for @selectIcon.
  ///
  /// In en, this message translates to:
  /// **'Select Icon'**
  String get selectIcon;

  /// No description provided for @favoriteName.
  ///
  /// In en, this message translates to:
  /// **'Favorite name'**
  String get favoriteName;

  /// No description provided for @unnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed'**
  String get unnamed;

  /// No description provided for @enterFavoriteName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get enterFavoriteName;

  /// No description provided for @documentNotInFavorite.
  ///
  /// In en, this message translates to:
  /// **'Document not in any favorite'**
  String get documentNotInFavorite;

  /// No description provided for @moveToFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorite'**
  String get moveToFavorite;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Library is empty'**
  String get libraryEmpty;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'Confirm ({count})'**
  String selectedCount(int count);

  /// No description provided for @alreadyInThisFavorite.
  ///
  /// In en, this message translates to:
  /// **'Already in this favorite'**
  String get alreadyInThisFavorite;

  /// No description provided for @reformatDone.
  ///
  /// In en, this message translates to:
  /// **'Reformat done'**
  String get reformatDone;

  /// No description provided for @viewPdf.
  ///
  /// In en, this message translates to:
  /// **'View PDF'**
  String get viewPdf;

  /// No description provided for @viewExtractResult.
  ///
  /// In en, this message translates to:
  /// **'View Extract Result'**
  String get viewExtractResult;

  /// No description provided for @documentExtract.
  ///
  /// In en, this message translates to:
  /// **'Extract'**
  String get documentExtract;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load Failed'**
  String get loadFailed;

  /// No description provided for @extractResultEmpty.
  ///
  /// In en, this message translates to:
  /// **'No extraction result'**
  String get extractResultEmpty;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get copyAll;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @generateSummary.
  ///
  /// In en, this message translates to:
  /// **'Generate Summary'**
  String get generateSummary;

  /// No description provided for @reExtract.
  ///
  /// In en, this message translates to:
  /// **'Re-extract'**
  String get reExtract;

  /// No description provided for @documentInfo.
  ///
  /// In en, this message translates to:
  /// **'Document Info'**
  String get documentInfo;

  /// No description provided for @viewSummary.
  ///
  /// In en, this message translates to:
  /// **'View Summary'**
  String get viewSummary;

  /// No description provided for @reformat.
  ///
  /// In en, this message translates to:
  /// **'Reformat'**
  String get reformat;

  /// No description provided for @reTranslate.
  ///
  /// In en, this message translates to:
  /// **'Re-translate'**
  String get reTranslate;

  /// No description provided for @searchContent.
  ///
  /// In en, this message translates to:
  /// **'Search content'**
  String get searchContent;

  /// No description provided for @exitSearch.
  ///
  /// In en, this message translates to:
  /// **'Exit search'**
  String get exitSearch;

  /// No description provided for @noMatchFound.
  ///
  /// In en, this message translates to:
  /// **'No matches found'**
  String get noMatchFound;

  /// No description provided for @previousResult.
  ///
  /// In en, this message translates to:
  /// **'Previous result'**
  String get previousResult;

  /// No description provided for @nextResult.
  ///
  /// In en, this message translates to:
  /// **'Next result'**
  String get nextResult;

  /// No description provided for @translateText.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translateText;

  /// No description provided for @deleteHighlight.
  ///
  /// In en, this message translates to:
  /// **'Delete Highlight'**
  String get deleteHighlight;

  /// No description provided for @saveNote.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveNote;

  /// No description provided for @streaming.
  ///
  /// In en, this message translates to:
  /// **'Receiving...'**
  String get streaming;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @copyTranslation.
  ///
  /// In en, this message translates to:
  /// **'Copy translation'**
  String get copyTranslation;

  /// No description provided for @copyOriginal.
  ///
  /// In en, this message translates to:
  /// **'Copy original'**
  String get copyOriginal;

  /// No description provided for @closeImage.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeImage;

  /// No description provided for @copyImage.
  ///
  /// In en, this message translates to:
  /// **'Copy Image'**
  String get copyImage;

  /// No description provided for @saveImage.
  ///
  /// In en, this message translates to:
  /// **'Save Image'**
  String get saveImage;

  /// No description provided for @imageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Image file not found'**
  String get imageNotFound;

  /// No description provided for @saveImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Image'**
  String get saveImageTitle;

  /// No description provided for @showOriginal.
  ///
  /// In en, this message translates to:
  /// **'Show original'**
  String get showOriginal;

  /// No description provided for @showTranslation.
  ///
  /// In en, this message translates to:
  /// **'Show translation'**
  String get showTranslation;

  /// No description provided for @viewInDocument.
  ///
  /// In en, this message translates to:
  /// **'View in document'**
  String get viewInDocument;

  /// No description provided for @viewOriginalImage.
  ///
  /// In en, this message translates to:
  /// **'View original'**
  String get viewOriginalImage;

  /// No description provided for @generatingSummary.
  ///
  /// In en, this message translates to:
  /// **'Generating summary...'**
  String get generatingSummary;

  /// No description provided for @noSummary.
  ///
  /// In en, this message translates to:
  /// **'No summary'**
  String get noSummary;

  /// No description provided for @referencesNotFound.
  ///
  /// In en, this message translates to:
  /// **'No references found'**
  String get referencesNotFound;

  /// No description provided for @author.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// No description provided for @journal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journal;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @modelApi.
  ///
  /// In en, this message translates to:
  /// **'Model API'**
  String get modelApi;

  /// No description provided for @translationSettings.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translationSettings;

  /// No description provided for @imageGenSettings.
  ///
  /// In en, this message translates to:
  /// **'Image Gen'**
  String get imageGenSettings;

  /// No description provided for @deleteProvider.
  ///
  /// In en, this message translates to:
  /// **'Delete Provider'**
  String get deleteProvider;

  /// No description provided for @providers.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get providers;

  /// No description provided for @addProvider.
  ///
  /// In en, this message translates to:
  /// **'Add Provider'**
  String get addProvider;

  /// No description provided for @selectProtocol.
  ///
  /// In en, this message translates to:
  /// **'Select Protocol'**
  String get selectProtocol;

  /// No description provided for @manageModels.
  ///
  /// In en, this message translates to:
  /// **'Manage Models'**
  String get manageModels;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// No description provided for @globalModelRoles.
  ///
  /// In en, this message translates to:
  /// **'Global Model Roles'**
  String get globalModelRoles;

  /// No description provided for @expertModel.
  ///
  /// In en, this message translates to:
  /// **'Expert Model'**
  String get expertModel;

  /// No description provided for @fastModel.
  ///
  /// In en, this message translates to:
  /// **'Fast Model'**
  String get fastModel;

  /// No description provided for @imageModel.
  ///
  /// In en, this message translates to:
  /// **'Image Model'**
  String get imageModel;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @pleaseAddImageModel.
  ///
  /// In en, this message translates to:
  /// **'Please add a model that supports image output first'**
  String get pleaseAddImageModel;

  /// No description provided for @pleaseAddModels.
  ///
  /// In en, this message translates to:
  /// **'Please add models under providers first'**
  String get pleaseAddModels;

  /// No description provided for @providerName.
  ///
  /// In en, this message translates to:
  /// **'Provider name'**
  String get providerName;

  /// No description provided for @nameField.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameField;

  /// No description provided for @detectModel.
  ///
  /// In en, this message translates to:
  /// **'Detect model'**
  String get detectModel;

  /// No description provided for @modelType.
  ///
  /// In en, this message translates to:
  /// **'Model Type'**
  String get modelType;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @embedding.
  ///
  /// In en, this message translates to:
  /// **'Embedding'**
  String get embedding;

  /// No description provided for @inputMode.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get inputMode;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get image;

  /// No description provided for @outputMode.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get outputMode;

  /// No description provided for @capabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get capabilities;

  /// No description provided for @reasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get reasoning;

  /// No description provided for @resetToAuto.
  ///
  /// In en, this message translates to:
  /// **'Reset to auto-detect'**
  String get resetToAuto;

  /// No description provided for @builtInTools.
  ///
  /// In en, this message translates to:
  /// **'Built-in Tools'**
  String get builtInTools;

  /// No description provided for @official.
  ///
  /// In en, this message translates to:
  /// **'Official'**
  String get official;

  /// No description provided for @defaultLevel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLevel;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @ultraHigh.
  ///
  /// In en, this message translates to:
  /// **'Ultra High'**
  String get ultraHigh;

  /// No description provided for @thinkingIntensity.
  ///
  /// In en, this message translates to:
  /// **'Thinking Intensity'**
  String get thinkingIntensity;

  /// No description provided for @fetchModelsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch models'**
  String get fetchModelsFailed;

  /// No description provided for @showAllModels.
  ///
  /// In en, this message translates to:
  /// **'Show all models'**
  String get showAllModels;

  /// No description provided for @showImageModels.
  ///
  /// In en, this message translates to:
  /// **'Show image models only'**
  String get showImageModels;

  /// No description provided for @noImageModels.
  ///
  /// In en, this message translates to:
  /// **'No models with image output detected'**
  String get noImageModels;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @expert.
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get expert;

  /// No description provided for @fast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get fast;

  /// No description provided for @imageGen.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get imageGen;

  /// No description provided for @addModel.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addModel;

  /// No description provided for @removeModel.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeModel;

  /// No description provided for @addModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Model'**
  String get addModelTitle;

  /// No description provided for @restoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get restoreDefaults;

  /// No description provided for @targetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target Language'**
  String get targetLanguage;

  /// No description provided for @translationStyleSetting.
  ///
  /// In en, this message translates to:
  /// **'Translation Style'**
  String get translationStyleSetting;

  /// No description provided for @translationIgnore.
  ///
  /// In en, this message translates to:
  /// **'Translation Ignore'**
  String get translationIgnore;

  /// No description provided for @temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// No description provided for @systemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get systemPrompt;

  /// No description provided for @userPrompt.
  ///
  /// In en, this message translates to:
  /// **'User Prompt'**
  String get userPrompt;

  /// No description provided for @classicPhotography.
  ///
  /// In en, this message translates to:
  /// **'Classic Photography'**
  String get classicPhotography;

  /// No description provided for @referenceImageCount.
  ///
  /// In en, this message translates to:
  /// **'Reference Image Count'**
  String get referenceImageCount;

  /// No description provided for @aspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect Ratio'**
  String get aspectRatio;

  /// No description provided for @resolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get resolution;

  /// No description provided for @proxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get proxy;

  /// No description provided for @customProxy.
  ///
  /// In en, this message translates to:
  /// **'Custom Proxy'**
  String get customProxy;

  /// No description provided for @customProxySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manually specify proxy address'**
  String get customProxySubtitle;

  /// No description provided for @hostAddress.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get hostAddress;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @systemProxy.
  ///
  /// In en, this message translates to:
  /// **'System Proxy'**
  String get systemProxy;

  /// No description provided for @systemProxySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use system environment proxy settings'**
  String get systemProxySubtitle;

  /// No description provided for @noProxy.
  ///
  /// In en, this message translates to:
  /// **'No Proxy'**
  String get noProxy;

  /// No description provided for @noProxySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect directly'**
  String get noProxySubtitle;

  /// No description provided for @connectivityTest.
  ///
  /// In en, this message translates to:
  /// **'Connectivity Test'**
  String get connectivityTest;

  /// No description provided for @testAddress.
  ///
  /// In en, this message translates to:
  /// **'Test Address'**
  String get testAddress;

  /// No description provided for @connectionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timeout'**
  String get connectionTimeout;

  /// No description provided for @connectionOk.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionOk;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get connectionFailed;

  /// No description provided for @remoteBackup.
  ///
  /// In en, this message translates to:
  /// **'Remote Backup'**
  String get remoteBackup;

  /// No description provided for @backupMethod.
  ///
  /// In en, this message translates to:
  /// **'Backup Method'**
  String get backupMethod;

  /// No description provided for @localBackup.
  ///
  /// In en, this message translates to:
  /// **'Local Backup'**
  String get localBackup;

  /// No description provided for @exportBackup.
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get exportBackup;

  /// No description provided for @restoreFromBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from Backup'**
  String get restoreFromBackup;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get clearCache;

  /// No description provided for @clearAllData.
  ///
  /// In en, this message translates to:
  /// **'Clear All Data'**
  String get clearAllData;

  /// No description provided for @resetAndReimport.
  ///
  /// In en, this message translates to:
  /// **'Reset and Re-import'**
  String get resetAndReimport;

  /// No description provided for @reimport.
  ///
  /// In en, this message translates to:
  /// **'Re-import'**
  String get reimport;

  /// No description provided for @detecting.
  ///
  /// In en, this message translates to:
  /// **'Detecting...'**
  String get detecting;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared'**
  String get cacheCleared;

  /// No description provided for @allDataCleared.
  ///
  /// In en, this message translates to:
  /// **'All data cleared'**
  String get allDataCleared;

  /// No description provided for @saveBackupFile.
  ///
  /// In en, this message translates to:
  /// **'Save Backup File'**
  String get saveBackupFile;

  /// No description provided for @selectBackupFile.
  ///
  /// In en, this message translates to:
  /// **'Select Backup File'**
  String get selectBackupFile;

  /// No description provided for @restoreSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Settings'**
  String get restoreSettingsTitle;

  /// No description provided for @restoreMethod.
  ///
  /// In en, this message translates to:
  /// **'Restore Method'**
  String get restoreMethod;

  /// No description provided for @restoreScope.
  ///
  /// In en, this message translates to:
  /// **'Restore Scope'**
  String get restoreScope;

  /// No description provided for @startMerge.
  ///
  /// In en, this message translates to:
  /// **'Start Merge'**
  String get startMerge;

  /// No description provided for @startRestore.
  ///
  /// In en, this message translates to:
  /// **'Start Restore'**
  String get startRestore;

  /// No description provided for @clearField.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearField;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @region.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get region;

  /// No description provided for @objectPath.
  ///
  /// In en, this message translates to:
  /// **'Object Path'**
  String get objectPath;

  /// No description provided for @usePathStyle.
  ///
  /// In en, this message translates to:
  /// **'Use path-style URL'**
  String get usePathStyle;

  /// No description provided for @remote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get remote;

  /// No description provided for @zoteroSync.
  ///
  /// In en, this message translates to:
  /// **'Zotero Sync'**
  String get zoteroSync;

  /// No description provided for @fullResync.
  ///
  /// In en, this message translates to:
  /// **'Full Resync'**
  String get fullResync;

  /// No description provided for @layoutAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Layout Analysis'**
  String get layoutAnalysis;

  /// No description provided for @layoutGeometry.
  ///
  /// In en, this message translates to:
  /// **'Layout Geometry'**
  String get layoutGeometry;

  /// No description provided for @layoutGeometryHelp.
  ///
  /// In en, this message translates to:
  /// **'Geometry for layout detection boxes'**
  String get layoutGeometryHelp;

  /// No description provided for @layoutDetectionThreshold.
  ///
  /// In en, this message translates to:
  /// **'Layout Detection Threshold'**
  String get layoutDetectionThreshold;

  /// No description provided for @outputControl.
  ///
  /// In en, this message translates to:
  /// **'Output Control'**
  String get outputControl;

  /// No description provided for @repetitionPenalty.
  ///
  /// In en, this message translates to:
  /// **'Repetition Penalty'**
  String get repetitionPenalty;

  /// No description provided for @repetitionPenaltyHint.
  ///
  /// In en, this message translates to:
  /// **'Increase when text or table content is duplicated'**
  String get repetitionPenaltyHint;

  /// No description provided for @recognitionEnhancement.
  ///
  /// In en, this message translates to:
  /// **'Recognition Enhancement'**
  String get recognitionEnhancement;

  /// No description provided for @documentCorrection.
  ///
  /// In en, this message translates to:
  /// **'Document Correction'**
  String get documentCorrection;

  /// No description provided for @ocrAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get ocrAuto;

  /// No description provided for @ocrRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get ocrRectangle;

  /// No description provided for @ocrQuadrilateral.
  ///
  /// In en, this message translates to:
  /// **'Quadrilateral'**
  String get ocrQuadrilateral;

  /// No description provided for @ocrPolygon.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get ocrPolygon;

  /// No description provided for @chartRecognition.
  ///
  /// In en, this message translates to:
  /// **'Chart Recognition'**
  String get chartRecognition;

  /// No description provided for @stampRecognition.
  ///
  /// In en, this message translates to:
  /// **'Stamp Recognition'**
  String get stampRecognition;

  /// No description provided for @imageAreaOcr.
  ///
  /// In en, this message translates to:
  /// **'Image Area OCR'**
  String get imageAreaOcr;

  /// No description provided for @orientationCorrection.
  ///
  /// In en, this message translates to:
  /// **'Orientation Correction'**
  String get orientationCorrection;

  /// No description provided for @curvatureCorrection.
  ///
  /// In en, this message translates to:
  /// **'Curvature Correction'**
  String get curvatureCorrection;

  /// No description provided for @deduplicateBoxes.
  ///
  /// In en, this message translates to:
  /// **'Deduplicate Boxes'**
  String get deduplicateBoxes;

  /// No description provided for @multiPageReconstruction.
  ///
  /// In en, this message translates to:
  /// **'Multi-page Reconstruction'**
  String get multiPageReconstruction;

  /// No description provided for @ocrHeader.
  ///
  /// In en, this message translates to:
  /// **'Header'**
  String get ocrHeader;

  /// No description provided for @ocrHeaderImage.
  ///
  /// In en, this message translates to:
  /// **'Header Image'**
  String get ocrHeaderImage;

  /// No description provided for @ocrFooter.
  ///
  /// In en, this message translates to:
  /// **'Footer'**
  String get ocrFooter;

  /// No description provided for @ocrFooterImage.
  ///
  /// In en, this message translates to:
  /// **'Footer Image'**
  String get ocrFooterImage;

  /// No description provided for @ocrPageNumber.
  ///
  /// In en, this message translates to:
  /// **'Page Number'**
  String get ocrPageNumber;

  /// No description provided for @ocrFootnote.
  ///
  /// In en, this message translates to:
  /// **'Footnote'**
  String get ocrFootnote;

  /// No description provided for @ocrSideNote.
  ///
  /// In en, this message translates to:
  /// **'Side Note'**
  String get ocrSideNote;

  /// No description provided for @searchToolLabel.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchToolLabel;

  /// No description provided for @codeExecutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Code Execution'**
  String get codeExecutionLabel;

  /// No description provided for @urlContextLabel.
  ///
  /// In en, this message translates to:
  /// **'URL Context'**
  String get urlContextLabel;

  /// No description provided for @youtubeLabel.
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get youtubeLabel;

  /// No description provided for @codeInterpreterLabel.
  ///
  /// In en, this message translates to:
  /// **'Code Interpreter'**
  String get codeInterpreterLabel;

  /// No description provided for @imageGenerationLabel.
  ///
  /// In en, this message translates to:
  /// **'Image Generation'**
  String get imageGenerationLabel;

  /// No description provided for @searchToolDesc.
  ///
  /// In en, this message translates to:
  /// **'Search the web for latest information'**
  String get searchToolDesc;

  /// No description provided for @codeExecutionDesc.
  ///
  /// In en, this message translates to:
  /// **'Execute code in sandbox and return results'**
  String get codeExecutionDesc;

  /// No description provided for @urlContextDesc.
  ///
  /// In en, this message translates to:
  /// **'Read URL content as context'**
  String get urlContextDesc;

  /// No description provided for @youtubeDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect and extract YouTube video info'**
  String get youtubeDesc;

  /// No description provided for @codeInterpreterDesc.
  ///
  /// In en, this message translates to:
  /// **'Run code and process files in sandbox'**
  String get codeInterpreterDesc;

  /// No description provided for @imageGenerationDesc.
  ///
  /// In en, this message translates to:
  /// **'Generate images in conversation'**
  String get imageGenerationDesc;

  /// No description provided for @taskInProgress.
  ///
  /// In en, this message translates to:
  /// **'This document already has a task running'**
  String get taskInProgress;

  /// No description provided for @savingResult.
  ///
  /// In en, this message translates to:
  /// **'Saving result'**
  String get savingResult;

  /// No description provided for @saveResultFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save result'**
  String get saveResultFailed;

  /// No description provided for @summaryCancelled.
  ///
  /// In en, this message translates to:
  /// **'Summary generation cancelled'**
  String get summaryCancelled;

  /// No description provided for @preparingContent.
  ///
  /// In en, this message translates to:
  /// **'Preparing content'**
  String get preparingContent;

  /// No description provided for @requestingImageModel.
  ///
  /// In en, this message translates to:
  /// **'Requesting image model'**
  String get requestingImageModel;

  /// No description provided for @summaryGenerated.
  ///
  /// In en, this message translates to:
  /// **'Summary generated'**
  String get summaryGenerated;

  /// No description provided for @downloadCancelled.
  ///
  /// In en, this message translates to:
  /// **'Download cancelled'**
  String get downloadCancelled;

  /// No description provided for @summaryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Summary image not found'**
  String get summaryNotFound;

  /// No description provided for @generateSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate Summary'**
  String get generateSummaryTitle;

  /// No description provided for @exportAll.
  ///
  /// In en, this message translates to:
  /// **'Export All'**
  String get exportAll;

  /// No description provided for @roleBadgeEmbedding.
  ///
  /// In en, this message translates to:
  /// **'Embed'**
  String get roleBadgeEmbedding;

  /// No description provided for @roleBadgeVision.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get roleBadgeVision;

  /// No description provided for @roleBadgeImageGen.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get roleBadgeImageGen;

  /// No description provided for @roleBadgeTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get roleBadgeTools;

  /// No description provided for @roleBadgeReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get roleBadgeReasoning;

  /// No description provided for @storageUsage.
  ///
  /// In en, this message translates to:
  /// **'Using {size}'**
  String storageUsage(String size);

  /// No description provided for @backupTo.
  ///
  /// In en, this message translates to:
  /// **'Backup to {target}'**
  String backupTo(String target);

  /// No description provided for @uploadBackupTo.
  ///
  /// In en, this message translates to:
  /// **'Upload full backup to {target}'**
  String uploadBackupTo(String target);

  /// No description provided for @pleaseConfigureFirst.
  ///
  /// In en, this message translates to:
  /// **'Please configure {target} connection first'**
  String pleaseConfigureFirst(String target);

  /// No description provided for @restoreFromRemote.
  ///
  /// In en, this message translates to:
  /// **'Restore from {target}'**
  String restoreFromRemote(String target);

  /// No description provided for @downloadAndRestore.
  ///
  /// In en, this message translates to:
  /// **'Download from {target} and restore'**
  String downloadAndRestore(String target);

  /// No description provided for @generateZipAndSave.
  ///
  /// In en, this message translates to:
  /// **'Generate zip backup and save locally'**
  String get generateZipAndSave;

  /// No description provided for @selectLocalZipRestore.
  ///
  /// In en, this message translates to:
  /// **'Select local zip backup file to restore'**
  String get selectLocalZipRestore;

  /// No description provided for @thumbnailsAndTemp.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails, temp files, etc.'**
  String get thumbnailsAndTemp;

  /// No description provided for @allDataWillBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Library and databases will be deleted'**
  String get allDataWillBeDeleted;

  /// No description provided for @getToken.
  ///
  /// In en, this message translates to:
  /// **'Get Token'**
  String get getToken;

  /// No description provided for @syncZoteroLibrary.
  ///
  /// In en, this message translates to:
  /// **'Sync Zotero Library'**
  String get syncZoteroLibrary;

  /// No description provided for @zoteroImportedPull.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} · Pull new entries'**
  String zoteroImportedPull(int count);

  /// No description provided for @pleaseFillApiKey.
  ///
  /// In en, this message translates to:
  /// **'Please fill in API Key first'**
  String get pleaseFillApiKey;

  /// No description provided for @zoteroImportHint.
  ///
  /// In en, this message translates to:
  /// **'Import documents from Zotero personal library'**
  String get zoteroImportHint;

  /// No description provided for @zoteroResetHint.
  ///
  /// In en, this message translates to:
  /// **'Clear import records and re-pull from library (recover deleted entries)'**
  String get zoteroResetHint;

  /// No description provided for @resetZoteroSync.
  ///
  /// In en, this message translates to:
  /// **'Reset Zotero Sync'**
  String get resetZoteroSync;

  /// No description provided for @resetZoteroConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will clear local Zotero import records and re-pull from library: deleted entries will reappear, existing ones won\'t duplicate. Continue?'**
  String get resetZoteroConfirm;

  /// No description provided for @s3Config.
  ///
  /// In en, this message translates to:
  /// **'S3 Configuration'**
  String get s3Config;

  /// No description provided for @webDavConfig.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Configuration'**
  String get webDavConfig;

  /// No description provided for @remoteNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'{target} remote backup not configured'**
  String remoteNotConfigured(String target);

  /// No description provided for @s3BucketInfo.
  ///
  /// In en, this message translates to:
  /// **'Bucket: {bucket}  ·  Region: {region}'**
  String s3BucketInfo(String bucket, String region);

  /// No description provided for @s3ObjectInfo.
  ///
  /// In en, this message translates to:
  /// **'Object: {key}'**
  String s3ObjectInfo(String key);

  /// No description provided for @webDavAccountInfo.
  ///
  /// In en, this message translates to:
  /// **'Account: {username}'**
  String webDavAccountInfo(String username);

  /// No description provided for @webDavPathInfo.
  ///
  /// In en, this message translates to:
  /// **'Path: {path}'**
  String webDavPathInfo(String path);

  /// No description provided for @clearingCache.
  ///
  /// In en, this message translates to:
  /// **'Clearing cache...'**
  String get clearingCache;

  /// No description provided for @confirmDeleteAllDataBody.
  ///
  /// In en, this message translates to:
  /// **'This will delete all document files and databases irreversibly. Continue?'**
  String get confirmDeleteAllDataBody;

  /// No description provided for @clearingData.
  ///
  /// In en, this message translates to:
  /// **'Clearing data...'**
  String get clearingData;

  /// No description provided for @generatingLocalBackup.
  ///
  /// In en, this message translates to:
  /// **'Generating local backup...'**
  String get generatingLocalBackup;

  /// No description provided for @backupExportedTo.
  ///
  /// In en, this message translates to:
  /// **'Backup exported to {path}'**
  String backupExportedTo(String path);

  /// No description provided for @exportBackupFailed.
  ///
  /// In en, this message translates to:
  /// **'Export backup failed: {error}'**
  String exportBackupFailed(String error);

  /// No description provided for @mergingBackup.
  ///
  /// In en, this message translates to:
  /// **'Merging backup...'**
  String get mergingBackup;

  /// No description provided for @restoringBackup.
  ///
  /// In en, this message translates to:
  /// **'Restoring backup...'**
  String get restoringBackup;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// No description provided for @generatingAndUploading.
  ///
  /// In en, this message translates to:
  /// **'Generating and uploading remote backup...'**
  String get generatingAndUploading;

  /// No description provided for @remoteBackupUploaded.
  ///
  /// In en, this message translates to:
  /// **'Remote backup uploaded to {target}'**
  String remoteBackupUploaded(String target);

  /// No description provided for @uploadRemoteFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload remote backup failed: {error}'**
  String uploadRemoteFailed(String error);

  /// No description provided for @downloadingRemoteBackup.
  ///
  /// In en, this message translates to:
  /// **'Downloading remote backup...'**
  String get downloadingRemoteBackup;

  /// No description provided for @mergingRemoteBackup.
  ///
  /// In en, this message translates to:
  /// **'Merging remote backup...'**
  String get mergingRemoteBackup;

  /// No description provided for @restoringRemoteBackup.
  ///
  /// In en, this message translates to:
  /// **'Restoring remote backup...'**
  String get restoringRemoteBackup;

  /// No description provided for @remoteRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Remote restore failed: {error}'**
  String remoteRestoreFailed(String error);

  /// No description provided for @restoreCompleteRefreshed.
  ///
  /// In en, this message translates to:
  /// **'{prefix}Restore complete, page state synced'**
  String restoreCompleteRefreshed(String prefix);

  /// No description provided for @mergeCompleteUpToDate.
  ///
  /// In en, this message translates to:
  /// **'{prefix}Merge complete, local data is up to date'**
  String mergeCompleteUpToDate(String prefix);

  /// No description provided for @mergeDocumentsAdded.
  ///
  /// In en, this message translates to:
  /// **'Added {count} documents'**
  String mergeDocumentsAdded(int count);

  /// No description provided for @mergeHighlightsAdded.
  ///
  /// In en, this message translates to:
  /// **'Added {count} highlights'**
  String mergeHighlightsAdded(int count);

  /// No description provided for @mergeFilesCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} files'**
  String mergeFilesCopied(int count);

  /// No description provided for @mergeSettingsAdded.
  ///
  /// In en, this message translates to:
  /// **'Added {count} settings'**
  String mergeSettingsAdded(int count);

  /// No description provided for @mergeCompleteSummary.
  ///
  /// In en, this message translates to:
  /// **'{prefix}Merge complete: {details}'**
  String mergeCompleteSummary(String prefix, String details);

  /// No description provided for @webDavServerAddress.
  ///
  /// In en, this message translates to:
  /// **'WebDAV server address'**
  String get webDavServerAddress;

  /// No description provided for @s3Endpoint.
  ///
  /// In en, this message translates to:
  /// **'S3 / R2 / MinIO Endpoint'**
  String get s3Endpoint;

  /// No description provided for @s3ObjectPathDefault.
  ///
  /// In en, this message translates to:
  /// **'Default: otter-pad/otter_pad_backup.zip'**
  String get s3ObjectPathDefault;

  /// No description provided for @s3PathStyleHint.
  ///
  /// In en, this message translates to:
  /// **'MinIO / R2 / S3-compatible usually recommended'**
  String get s3PathStyleHint;

  /// No description provided for @selectImageModelFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select an image model in AI Settings first'**
  String get selectImageModelFirst;

  /// No description provided for @summaryApiCostHint.
  ///
  /// In en, this message translates to:
  /// **'Summary images are generated by a third-party model, which may incur API costs.'**
  String get summaryApiCostHint;

  /// No description provided for @estimatedCost.
  ///
  /// In en, this message translates to:
  /// **'Estimated cost ~\${dollar}{cost} per image'**
  String estimatedCost(String dollar, String cost);

  /// No description provided for @useAppImageGen.
  ///
  /// In en, this message translates to:
  /// **'To use App image gen, tap App Image Gen and upload manually.'**
  String get useAppImageGen;

  /// No description provided for @appImageGen.
  ///
  /// In en, this message translates to:
  /// **'App Image Gen'**
  String get appImageGen;

  /// No description provided for @markdownNotFound.
  ///
  /// In en, this message translates to:
  /// **'Markdown file not found, please extract first'**
  String get markdownNotFound;

  /// No description provided for @promptGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Prompt generation failed: {error}'**
  String promptGenerationFailed(String error);

  /// No description provided for @saveExportZip.
  ///
  /// In en, this message translates to:
  /// **'Save export ZIP'**
  String get saveExportZip;

  /// No description provided for @exportedWithPromptCopied.
  ///
  /// In en, this message translates to:
  /// **'Exported to {name}, prompt copied'**
  String exportedWithPromptCopied(String name);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @exportToAppImageGen.
  ///
  /// In en, this message translates to:
  /// **'Export to App Image Gen'**
  String get exportToAppImageGen;

  /// No description provided for @exportToAppImageGenHint.
  ///
  /// In en, this message translates to:
  /// **'Export document materials, then upload manually in ChatGPT / Gemini etc.'**
  String get exportToAppImageGenHint;

  /// No description provided for @exportShareHint.
  ///
  /// In en, this message translates to:
  /// **'Share figures + Markdown, prompt auto-copied to clipboard'**
  String get exportShareHint;

  /// No description provided for @exportZipHint.
  ///
  /// In en, this message translates to:
  /// **'Pack figures + article.md + prompt.md into ZIP, prompt auto-copied to clipboard'**
  String get exportZipHint;

  /// No description provided for @ocrChartRecognitionDesc.
  ///
  /// In en, this message translates to:
  /// **'Parse charts into tables'**
  String get ocrChartRecognitionDesc;

  /// No description provided for @ocrStampRecognitionDesc.
  ///
  /// In en, this message translates to:
  /// **'Recognize stamps in documents'**
  String get ocrStampRecognitionDesc;

  /// No description provided for @ocrImageAreaDesc.
  ///
  /// In en, this message translates to:
  /// **'Perform OCR on image areas'**
  String get ocrImageAreaDesc;

  /// No description provided for @ocrOrientationDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-correct 0°/90°/180°/270° rotation'**
  String get ocrOrientationDesc;

  /// No description provided for @ocrCurvatureDesc.
  ///
  /// In en, this message translates to:
  /// **'Correct curved or wrinkled documents'**
  String get ocrCurvatureDesc;

  /// No description provided for @ocrDeduplicateDesc.
  ///
  /// In en, this message translates to:
  /// **'Remove overlapping layout detection boxes'**
  String get ocrDeduplicateDesc;

  /// No description provided for @ocrMultiPageDesc.
  ///
  /// In en, this message translates to:
  /// **'Reconstruct multi-page document structure'**
  String get ocrMultiPageDesc;

  /// No description provided for @ocrThresholdHelp.
  ///
  /// In en, this message translates to:
  /// **'Higher values retain fewer regions'**
  String get ocrThresholdHelp;

  /// No description provided for @ocrFilterHelp.
  ///
  /// In en, this message translates to:
  /// **'Checked label regions will not appear in Markdown output. All ignored by default.'**
  String get ocrFilterHelp;

  /// No description provided for @ocrInterface.
  ///
  /// In en, this message translates to:
  /// **'OCR Interface'**
  String get ocrInterface;

  /// No description provided for @aspectSquare.
  ///
  /// In en, this message translates to:
  /// **'Square · Social media'**
  String get aspectSquare;

  /// No description provided for @aspectClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic print · Document layout'**
  String get aspectClassic;

  /// No description provided for @aspectWide.
  ///
  /// In en, this message translates to:
  /// **'Landscape · Desktop wallpaper'**
  String get aspectWide;

  /// No description provided for @aspectUltraWide.
  ///
  /// In en, this message translates to:
  /// **'Ultra-wide · Cinema'**
  String get aspectUltraWide;

  /// No description provided for @aspectTall.
  ///
  /// In en, this message translates to:
  /// **'Portrait · Phone wallpaper'**
  String get aspectTall;

  /// No description provided for @imageRefCountHint.
  ///
  /// In en, this message translates to:
  /// **'Select reference images from extracted figures in order; models will auto-crop to their limit.'**
  String get imageRefCountHint;

  /// No description provided for @aspectRatioHint.
  ///
  /// In en, this message translates to:
  /// **'OpenAI maps to the nearest output size, preserving aspect ratio in the prompt.'**
  String get aspectRatioHint;

  /// No description provided for @summaryPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Controls the visual style and information layout; title, metadata, Markdown and figures are appended at runtime.'**
  String get summaryPromptHint;

  /// No description provided for @summaryPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Summary Prompt'**
  String get summaryPromptLabel;

  /// No description provided for @summaryPromptFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Describe layout, colors, density and style for the summary image'**
  String get summaryPromptFieldHint;

  /// No description provided for @estimatedCostShort.
  ///
  /// In en, this message translates to:
  /// **'Est. \${dollar}{cost}'**
  String estimatedCostShort(String dollar, String cost);

  /// No description provided for @translationTargetLangDesc.
  ///
  /// In en, this message translates to:
  /// **'Actual value of the targetLanguage variable in prompts'**
  String get translationTargetLangDesc;

  /// No description provided for @translationStyleDesc.
  ///
  /// In en, this message translates to:
  /// **'Visual style for translations in full-document translation'**
  String get translationStyleDesc;

  /// No description provided for @translationIgnoreDesc.
  ///
  /// In en, this message translates to:
  /// **'Checked sections are skipped during translation; unchecked sections merge into full paragraphs'**
  String get translationIgnoreDesc;

  /// No description provided for @temperatureDesc.
  ///
  /// In en, this message translates to:
  /// **'Lower is more conservative, higher is more creative'**
  String get temperatureDesc;

  /// No description provided for @systemPromptDesc.
  ///
  /// In en, this message translates to:
  /// **'Translation system prompt, supports targetLanguage placeholder'**
  String get systemPromptDesc;

  /// No description provided for @systemPromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g.: You are a professional translator...'**
  String get systemPromptHint;

  /// No description provided for @userPromptDesc.
  ///
  /// In en, this message translates to:
  /// **'Translation user prompt, supports targetLanguage and input placeholders'**
  String get userPromptDesc;

  /// No description provided for @documentsAddedCount.
  ///
  /// In en, this message translates to:
  /// **'Added {added} documents'**
  String documentsAddedCount(int added);

  /// No description provided for @documentsAddedSkipped.
  ///
  /// In en, this message translates to:
  /// **'Added {added} documents, {skipped} already existed'**
  String documentsAddedSkipped(int added, int skipped);

  /// No description provided for @confirmDeleteDocuments.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} documents? This cannot be undone.'**
  String confirmDeleteDocuments(int count);

  /// No description provided for @deletedDocuments.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} documents'**
  String deletedDocuments(int count);

  /// No description provided for @configureExtractToken.
  ///
  /// In en, this message translates to:
  /// **'Please configure document extraction Access Token in Settings'**
  String get configureExtractToken;

  /// No description provided for @noPdfFilesSelected.
  ///
  /// In en, this message translates to:
  /// **'No local PDF files in selection, cannot extract'**
  String get noPdfFilesSelected;

  /// No description provided for @pdfNotFound.
  ///
  /// In en, this message translates to:
  /// **'PDF file not found'**
  String get pdfNotFound;

  /// No description provided for @reformatting.
  ///
  /// In en, this message translates to:
  /// **'Reformatting...'**
  String get reformatting;

  /// No description provided for @reformatFailed.
  ///
  /// In en, this message translates to:
  /// **'Reformat failed: {error}'**
  String reformatFailed(String error);

  /// No description provided for @addedToFavorite.
  ///
  /// In en, this message translates to:
  /// **'Added to \"{name}\"'**
  String addedToFavorite(String name);

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added to {count} favorites'**
  String addedToFavorites(int count);

  /// No description provided for @removedFromFavoriteSingle.
  ///
  /// In en, this message translates to:
  /// **'Removed from \"{name}\"'**
  String removedFromFavoriteSingle(String name);

  /// No description provided for @removedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Removed from {count} favorites'**
  String removedFromFavorites(int count);

  /// No description provided for @translationFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed: {error}'**
  String translationFailed(String error);

  /// No description provided for @pdfFileNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'PDF file not found for this document'**
  String get pdfFileNotFoundTitle;

  /// No description provided for @removedFromFavoriteCount.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} documents from favorite'**
  String removedFromFavoriteCount(int count);

  /// No description provided for @confirmDeleteEntries.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} entries without files?'**
  String confirmDeleteEntries(int count);

  /// No description provided for @deletedEntries.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} entries'**
  String deletedEntries(int count);

  /// No description provided for @attachFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Attach file failed: {error}'**
  String attachFileFailed(String error);

  /// No description provided for @addingDocumentsTo.
  ///
  /// In en, this message translates to:
  /// **'Adding {total} documents to...'**
  String addingDocumentsTo(int total);

  /// No description provided for @allSelectedAlreadyHere.
  ///
  /// In en, this message translates to:
  /// **'All {count} selected already in this favorite'**
  String allSelectedAlreadyHere(int count);

  /// No description provided for @currentDocumentCount.
  ///
  /// In en, this message translates to:
  /// **'Currently {count} documents'**
  String currentDocumentCount(int count);

  /// No description provided for @overlapAndNew.
  ///
  /// In en, this message translates to:
  /// **'Contains {overlap} · Will add {newCount}'**
  String overlapAndNew(int overlap, int newCount);

  /// No description provided for @confirmDeleteFavorite.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Documents inside will not be deleted.'**
  String confirmDeleteFavorite(String name);

  /// No description provided for @favoriteDocumentCount.
  ///
  /// In en, this message translates to:
  /// **'{count} documents'**
  String favoriteDocumentCount(int count);

  /// No description provided for @clearReadingHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will clear all reading history. Documents will not be deleted. This cannot be undone.'**
  String get clearReadingHistoryConfirm;

  /// No description provided for @noReadingHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Open any document and it will appear here by date'**
  String get noReadingHistoryHint;

  /// No description provided for @identifierInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter ISBN, DOI, PMID, arXiv ID or ADS bibcode to add entries:'**
  String get identifierInputHint;

  /// No description provided for @identifierExample.
  ///
  /// In en, this message translates to:
  /// **'e.g.: 10.1038/s41586-021-03811-w'**
  String get identifierExample;

  /// No description provided for @addFilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import local PDFs, extract title, author, journal, year and DOI'**
  String get addFilesSubtitle;

  /// No description provided for @addByIdentifierSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter DOI, PMID, arXiv ID or ISBN to create entries directly'**
  String get addByIdentifierSubtitle;

  /// No description provided for @rebuildLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rescan directory, recover PDFs and retry core metadata extraction'**
  String get rebuildLibrarySubtitle;

  /// No description provided for @downloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get downloadPdf;

  /// No description provided for @viewLibraryTotal.
  ///
  /// In en, this message translates to:
  /// **'View library · {count} items'**
  String viewLibraryTotal(int count);

  /// No description provided for @addedDocumentsToFavorite.
  ///
  /// In en, this message translates to:
  /// **'Added {count} documents'**
  String addedDocumentsToFavorite(int count);

  /// No description provided for @searchDocumentHint.
  ///
  /// In en, this message translates to:
  /// **'Search title / author / journal'**
  String get searchDocumentHint;

  /// No description provided for @noDocumentsInLibrary.
  ///
  /// In en, this message translates to:
  /// **'No documents, please add PDF files to library'**
  String get noDocumentsInLibrary;

  /// No description provided for @providerDescOpenai.
  ///
  /// In en, this message translates to:
  /// **'gpt / o series · Image gen via gpt-image'**
  String get providerDescOpenai;

  /// No description provided for @providerDescAnthropic.
  ///
  /// In en, this message translates to:
  /// **'Claude series'**
  String get providerDescAnthropic;

  /// No description provided for @providerDescGemini.
  ///
  /// In en, this message translates to:
  /// **'Google AI · Multimodal'**
  String get providerDescGemini;

  /// No description provided for @providerDescOpenaiCompatible.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek / self-hosted OpenAI-compatible API'**
  String get providerDescOpenaiCompatible;

  /// No description provided for @confirmDeleteProvider.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? API Key, URL and models will be cleared.'**
  String confirmDeleteProvider(String name);

  /// No description provided for @modelConnected.
  ///
  /// In en, this message translates to:
  /// **'{modelId} connected'**
  String modelConnected(String modelId);

  /// No description provided for @apiAddress.
  ///
  /// In en, this message translates to:
  /// **'API Address'**
  String get apiAddress;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @previewUrl.
  ///
  /// In en, this message translates to:
  /// **'Preview: {url}'**
  String previewUrl(String url);

  /// No description provided for @selectRole.
  ///
  /// In en, this message translates to:
  /// **'Select {role}'**
  String selectRole(String role);

  /// No description provided for @addProtocol.
  ///
  /// In en, this message translates to:
  /// **'Add {protocol}'**
  String addProtocol(String protocol);

  /// No description provided for @assignRoleHint.
  ///
  /// In en, this message translates to:
  /// **'Assign a scene role for this model (optional)'**
  String get assignRoleHint;

  /// No description provided for @willReplace.
  ///
  /// In en, this message translates to:
  /// **'Will replace {current}'**
  String willReplace(String current);

  /// No description provided for @providerModels.
  ///
  /// In en, this message translates to:
  /// **'{provider} Models'**
  String providerModels(String provider);

  /// No description provided for @searchModelHint.
  ///
  /// In en, this message translates to:
  /// **'Search model ID or name'**
  String get searchModelHint;

  /// No description provided for @connectionOkMs.
  ///
  /// In en, this message translates to:
  /// **'Connected, {ms} ms'**
  String connectionOkMs(String ms);

  /// No description provided for @cannotConnectCheckProxy.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect, check proxy settings'**
  String get cannotConnectCheckProxy;

  /// No description provided for @requestFailed.
  ///
  /// In en, this message translates to:
  /// **'Request failed: {error}'**
  String requestFailed(String error);

  /// No description provided for @testFailed.
  ///
  /// In en, this message translates to:
  /// **'Test failed: {error}'**
  String testFailed(String error);

  /// No description provided for @copyFailed.
  ///
  /// In en, this message translates to:
  /// **'Copy failed: {error}'**
  String copyFailed(String error);

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(String error);

  /// No description provided for @savedToPath.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String savedToPath(String path);

  /// No description provided for @figuresNotFoundHint.
  ///
  /// In en, this message translates to:
  /// **'No figures found\nPlease extract first'**
  String get figuresNotFoundHint;

  /// No description provided for @copiedReferenceNumber.
  ///
  /// In en, this message translates to:
  /// **'Copied reference {number}'**
  String copiedReferenceNumber(int number);

  /// No description provided for @searchMatchesFound.
  ///
  /// In en, this message translates to:
  /// **'Found {count} matches'**
  String searchMatchesFound(int count);

  /// No description provided for @searchPdfContentHint.
  ///
  /// In en, this message translates to:
  /// **'Search PDF content'**
  String get searchPdfContentHint;

  /// No description provided for @markdownIgnoreLabels.
  ///
  /// In en, this message translates to:
  /// **'Markdown Ignore Labels'**
  String get markdownIgnoreLabels;

  /// No description provided for @resolutionHint.
  ///
  /// In en, this message translates to:
  /// **'OpenAI maps to quality; Gemini maps to imageSize.'**
  String get resolutionHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
