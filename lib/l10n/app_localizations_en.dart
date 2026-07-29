// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OtterPad';

  @override
  String get home => 'Home';

  @override
  String get library => 'Library';

  @override
  String get outline => 'Outline';

  @override
  String get notes => 'Notes';

  @override
  String get appearance => 'Appearance';

  @override
  String get translate => 'Translate';

  @override
  String get retryTranslation => 'Retry Translation';

  @override
  String get bilingual => 'Bilingual';

  @override
  String get original => 'Original';

  @override
  String get translated => 'Translated';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String get back => 'Back';

  @override
  String get copy => 'Copy';

  @override
  String get more => 'More';

  @override
  String get add => 'Add';

  @override
  String get edit => 'Edit';

  @override
  String get remove => 'Remove';

  @override
  String get done => 'Done';

  @override
  String get search => 'Search';

  @override
  String get test => 'Test';

  @override
  String get create => 'Create';

  @override
  String get refresh => 'Refresh';

  @override
  String get processing => 'Processing...';

  @override
  String get cancelAll => 'Cancel All';

  @override
  String get goToSettings => 'Go to Settings';

  @override
  String get configurationRequired => 'Configuration Required';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get settings => 'Settings';

  @override
  String get networkSettings => 'Network';

  @override
  String get networkSettingsSubtitle => 'Proxy · Connectivity Test';

  @override
  String get aiSettings => 'AI Settings';

  @override
  String get aiSettingsSubtitle => 'Model API · Translation · Image Gen';

  @override
  String get ocrSettings => 'OCR Settings';

  @override
  String get ocrSettingsSubtitle =>
      'OCR Interface · Output Control · Recognition · Correction';

  @override
  String get appearanceSettings => 'Display';

  @override
  String get appearanceSettingsSubtitle => 'Theme · Colors · Reading';

  @override
  String get dataManagement => 'Data Management';

  @override
  String get dataManagementSubtitle =>
      'Remote Backup · Local Backup · Zotero Sync';

  @override
  String get systemSettings => 'System';

  @override
  String get about => 'About';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get autoMode => 'Auto';

  @override
  String get lightMode => 'Light';

  @override
  String get darkMode => 'Dark';

  @override
  String get systemMode => 'System';

  @override
  String get themeColor => 'Theme Color';

  @override
  String get readingSettings => 'Reading';

  @override
  String get defaultReadingMode => 'Default Reading Mode';

  @override
  String get defaultReadingModeHint =>
      'When Markdown is selected, documents without extraction results will fall back to PDF view';

  @override
  String get textSize => 'Font';

  @override
  String get appLanguage => 'App Language';

  @override
  String get appLanguageDesc =>
      'Override the display language of the app interface';

  @override
  String get systemTextScale => 'System Text Scale';

  @override
  String get textSizeStandard => 'Standard';

  @override
  String get textSizeLarge => 'Large';

  @override
  String get textSizeExtraLarge => 'xLarge';

  @override
  String get textSizeHint =>
      'Affects text size throughout the app, persists after restart';

  @override
  String get readerThemeWhite => 'White';

  @override
  String get readerThemeSepia => 'Sepia';

  @override
  String get readerThemeGreen => 'Green';

  @override
  String get readerThemeNight => 'Night';

  @override
  String get readerThemeDark => 'Dark';

  @override
  String get readerThemeWhiteShort => 'White';

  @override
  String get readerThemeSepiaShort => 'Sepia';

  @override
  String get readerThemeGreenShort => 'Green';

  @override
  String get readerThemeNightShort => 'Night';

  @override
  String get readerThemeDarkShort => 'Dark';

  @override
  String get fontSize => 'Font Size';

  @override
  String get fontFamily => 'Font';

  @override
  String get paginationMode => 'Pagination';

  @override
  String get verticalPagination => 'Vertical';

  @override
  String get horizontalPagination => 'Horizontal';

  @override
  String get translationStyle => 'Translation Style';

  @override
  String get highlightsAndNotes => 'Highlights & Notes';

  @override
  String get noHighlights => 'No highlights yet';

  @override
  String get noHighlightsHint =>
      'Select text and tap a color dot to create one';

  @override
  String get editNote => 'Edit Note';

  @override
  String get editNoteTitle => 'Edit Note';

  @override
  String get writeYourThoughts => 'Write your thoughts...';

  @override
  String highlightCount(int count) {
    return '$count items';
  }

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(int count) {
    return '$count hr ago';
  }

  @override
  String daysAgo(int count) {
    return '$count days ago';
  }

  @override
  String get color => 'Color';

  @override
  String get background => 'Background';

  @override
  String get translationDone => 'Translation done';

  @override
  String get translationCacheUsed => 'Loaded from cache';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageChinese => 'Chinese (Simplified)';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTraditionalChinese => 'Chinese (Traditional)';

  @override
  String get recommend => 'Discover';

  @override
  String get documentLibrary => 'Library';

  @override
  String get recommendContent => 'Discover';

  @override
  String get batchDelete => 'Batch Delete';

  @override
  String get searchDocumentsHint => 'Search documents...';

  @override
  String get searchDocumentsHintDesktop =>
      'Search documents, authors, keywords...';

  @override
  String get enterKeywordToSearch => 'Enter keywords to search';

  @override
  String get noDocumentsFound => 'No matching documents';

  @override
  String get noDocuments => 'No documents';

  @override
  String get listView => 'List view';

  @override
  String get gridView => 'Grid view';

  @override
  String get tools => 'Tools';

  @override
  String get addFiles => 'Add Files';

  @override
  String get addByIdentifier => 'Add by Identifier';

  @override
  String get rebuildLibrary => 'Rebuild Library';

  @override
  String get addByIdentifierTitle => 'Add Entry by Identifier';

  @override
  String get batchExtracting => 'Batch extracting';

  @override
  String get extractionDone => 'Extraction done';

  @override
  String get cancelExtraction => 'Cancel Extraction';

  @override
  String get waitingSubmit => 'Waiting';

  @override
  String get extractionComplete => 'Extraction complete';

  @override
  String extractionCompletePages(int totalPages) {
    return 'Done ($totalPages pages)';
  }

  @override
  String get extractionFailed => 'Extraction failed';

  @override
  String get extractionCancelled => 'Extraction cancelled';

  @override
  String failedCount(int failed) {
    return 'Done ($failed failed)';
  }

  @override
  String get exitMultiSelect => 'Exit selection';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get selectAll => 'Select all';

  @override
  String get textExtraction => 'Text Extraction';

  @override
  String get addToFavorite => 'Add to Favorite';

  @override
  String get removeFromFavorite => 'Remove from Favorite';

  @override
  String get deleteFavorite => 'Delete Favorite';

  @override
  String get myLibrary => 'My Library';

  @override
  String get readingHistory => 'Reading History';

  @override
  String get noFileEntries => 'No File Entries';

  @override
  String get favorites => 'Favorites';

  @override
  String get addDocument => 'Add Document';

  @override
  String get addDocuments => 'Add Documents';

  @override
  String get allDocumentsHaveFiles => 'All documents have files';

  @override
  String get attachFile => 'Attach File';

  @override
  String get viewInBrowser => 'View in Browser';

  @override
  String get redownload => 'Redownload';

  @override
  String get entryDeleted => 'Entry deleted';

  @override
  String get fileAttached => 'File attached';

  @override
  String get clearHistory => 'Clear History';

  @override
  String get noReadingHistory => 'No reading history';

  @override
  String get removedFromHistory => 'Removed from history';

  @override
  String get clearReadingHistory => 'Clear Reading History';

  @override
  String get readingHistoryCleared => 'Reading history cleared';

  @override
  String get alreadyInFavorite => 'Already in favorite';

  @override
  String get createFavorite => 'Create Favorite';

  @override
  String get createThenSelect => 'Create, then select below';

  @override
  String get editFavorite => 'Edit Favorite';

  @override
  String get selectIcon => 'Select Icon';

  @override
  String get favoriteName => 'Favorite name';

  @override
  String get unnamed => 'Unnamed';

  @override
  String get enterFavoriteName => 'Enter a name';

  @override
  String get documentNotInFavorite => 'Document not in any favorite';

  @override
  String get moveToFavorite => 'Add to Favorite';

  @override
  String get libraryEmpty => 'Library is empty';

  @override
  String selectedCount(int count) {
    return 'Confirm ($count)';
  }

  @override
  String get alreadyInThisFavorite => 'Already in this favorite';

  @override
  String get reformatDone => 'Reformat done';

  @override
  String get viewPdf => 'View PDF';

  @override
  String get viewExtractResult => 'View Extract Result';

  @override
  String get documentExtract => 'Extract';

  @override
  String get loadFailed => 'Load Failed';

  @override
  String get extractResultEmpty => 'No extraction result';

  @override
  String get copyAll => 'Copy All';

  @override
  String get share => 'Share';

  @override
  String get generateSummary => 'Generate Summary';

  @override
  String get reExtract => 'Re-extract';

  @override
  String get aiLayoutFix => 'AI Layout Fix';

  @override
  String get documentInfo => 'Document Info';

  @override
  String get viewSummary => 'View Summary';

  @override
  String get reformat => 'Reformat';

  @override
  String get reTranslate => 'Re-translate';

  @override
  String get searchContent => 'Search content';

  @override
  String get exitSearch => 'Exit search';

  @override
  String get matchCase => 'Match case';

  @override
  String get matchWholeWord => 'Match whole word';

  @override
  String get noMatchFound => 'No matches found';

  @override
  String get previousResult => 'Previous result';

  @override
  String get nextResult => 'Next result';

  @override
  String get translateText => 'Translate';

  @override
  String get deleteHighlight => 'Delete Highlight';

  @override
  String get saveNote => 'Save';

  @override
  String get streaming => 'Receiving...';

  @override
  String get copied => 'Copied';

  @override
  String get addToNote => 'Add to notes';

  @override
  String get copyTranslation => 'Copy translation';

  @override
  String get copyOriginal => 'Copy original';

  @override
  String get closeImage => 'Close';

  @override
  String get copyImage => 'Copy Image';

  @override
  String get shareImage => 'Share Image';

  @override
  String get saveImage => 'Save Image';

  @override
  String get imageNotFound => 'Image file not found';

  @override
  String get saveImageTitle => 'Save Image';

  @override
  String get savedToGallery => 'Saved to gallery';

  @override
  String get galleryAccessDenied => 'Photo library access denied';

  @override
  String get showOriginal => 'Show original';

  @override
  String get showTranslation => 'Show translation';

  @override
  String get viewInDocument => 'View in document';

  @override
  String get viewOriginalImage => 'View original';

  @override
  String get generatingSummary => 'Generating summary...';

  @override
  String get referencesNotFound => 'No references found';

  @override
  String get author => 'Author';

  @override
  String get journal => 'Journal';

  @override
  String get year => 'Year';

  @override
  String get modelApi => 'Model API';

  @override
  String get translationSettings => 'Translation';

  @override
  String get imageGenSettings => 'Image Gen';

  @override
  String get deleteProvider => 'Delete Provider';

  @override
  String get providers => 'Providers';

  @override
  String get addProvider => 'Add Provider';

  @override
  String get selectProtocol => 'Select Protocol';

  @override
  String get manageModels => 'Manage Models';

  @override
  String get addApiKeyFirst => 'Add API key to manage models';

  @override
  String get models => 'Models';

  @override
  String get globalModelRoles => 'Global Model Roles';

  @override
  String get expertModel => 'Expert Model';

  @override
  String get fastModel => 'Fast Model';

  @override
  String get imageModel => 'Image-Gen Model';

  @override
  String get notSet => 'Not set';

  @override
  String get pleaseAddImageModel =>
      'Please add a model that supports image output first';

  @override
  String get pleaseAddMultimodalModel => 'Please add a multimodal model first';

  @override
  String get pleaseAddModels => 'Please add models under providers first';

  @override
  String get providerName => 'Provider name';

  @override
  String get nameField => 'Name';

  @override
  String get detectModel => 'Detect model';

  @override
  String get modelType => 'Model Type';

  @override
  String get chat => 'Chat';

  @override
  String get embedding => 'Embedding';

  @override
  String get inputMode => 'Input';

  @override
  String get text => 'Text';

  @override
  String get image => 'Multimodal';

  @override
  String get outputMode => 'Output';

  @override
  String get capabilities => 'Capabilities';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get resetToAuto => 'Reset to auto-detect';

  @override
  String get defaultLevel => 'Default';

  @override
  String get off => 'Off';

  @override
  String get low => 'Low';

  @override
  String get medium => 'Medium';

  @override
  String get high => 'High';

  @override
  String get ultraHigh => 'Ultra High';

  @override
  String get thinkingIntensity => 'Thinking Intensity';

  @override
  String get fetchModelsFailed => 'Failed to fetch models';

  @override
  String get showAllModels => 'Show all models';

  @override
  String get showImageGenModels => 'Show image-gen models only';

  @override
  String get showMultimodalModels => 'Show multimodal models only';

  @override
  String get noImageGenModels => 'No models with image output detected';

  @override
  String get noMultimodalModels => 'No multimodal models detected';

  @override
  String get noResults => 'No results';

  @override
  String get expert => 'Expert';

  @override
  String get fast => 'Fast';

  @override
  String get imageGen => 'Image';

  @override
  String get addModel => 'Add';

  @override
  String addModelById(String id) {
    return 'Add \"$id\"';
  }

  @override
  String get removeModel => 'Remove';

  @override
  String get addModelTitle => 'Add Model';

  @override
  String get restoreDefaults => 'Restore defaults';

  @override
  String get targetLanguage => 'Target Language';

  @override
  String get translationStyleSetting => 'Translation Style';

  @override
  String get translationIgnore => 'Translation Ignore';

  @override
  String get temperature => 'Temperature';

  @override
  String get systemPrompt => 'System Prompt';

  @override
  String get userPrompt => 'User Prompt';

  @override
  String get classicPhotography => 'Classic Photography';

  @override
  String get referenceImageCount => 'Reference Image Count';

  @override
  String get aspectRatio => 'Aspect Ratio';

  @override
  String get resolution => 'Resolution';

  @override
  String get proxy => 'Proxy';

  @override
  String get customProxy => 'Custom Proxy';

  @override
  String get customProxySubtitle => 'Manually specify proxy address';

  @override
  String get hostAddress => 'Host';

  @override
  String get port => 'Port';

  @override
  String get systemProxy => 'System Proxy';

  @override
  String get systemProxySubtitle => 'Use system environment proxy settings';

  @override
  String get noProxy => 'No Proxy';

  @override
  String get noProxySubtitle => 'Connect directly';

  @override
  String get connectivityTest => 'Connectivity Test';

  @override
  String get testAddress => 'Test Address';

  @override
  String get connectionTimeout => 'Connection timeout';

  @override
  String get connectionOk => 'Connected';

  @override
  String get connectionFailed => 'Connection failed';

  @override
  String get remoteBackup => 'Remote Backup';

  @override
  String get backupMethod => 'Backup Method';

  @override
  String get localBackup => 'Local Backup';

  @override
  String get exportBackup => 'Export Backup';

  @override
  String get restoreFromBackup => 'Restore from Backup';

  @override
  String get storage => 'Storage';

  @override
  String get clearCache => 'Clear Cache';

  @override
  String get clearAllData => 'Clear All Data';

  @override
  String get clearAllDataConfirm =>
      'This will delete all documents, databases, and cache. This action cannot be undone';

  @override
  String get storageSpace => 'Storage Space';

  @override
  String get storageSpaceTotal => 'Total';

  @override
  String get storageSpaceDetails => 'Details';

  @override
  String get storageSpaceLoadFailed => 'Failed to load storage info';

  @override
  String storageSpaceClearable(String size) {
    return 'Clearable: $size';
  }

  @override
  String storageSpaceFilesCount(int count) {
    return '$count files';
  }

  @override
  String get storageGroupPapers => 'Papers';

  @override
  String get storageCategoryImages => 'Images';

  @override
  String get storageCategoryFiles => 'Files';

  @override
  String get storageCategoryChat => 'Chat History';

  @override
  String get storageCategoryCache => 'Cache';

  @override
  String get storageCategoryLogs => 'Logs';

  @override
  String get storageCategoryDatabase => 'Database';

  @override
  String get storageSpaceSelected => 'Selected';

  @override
  String get storageSpaceCleared => 'Selected data cleared';

  @override
  String get clearData => 'Clear Data';

  @override
  String clearDataConfirm(String names) {
    return 'The following data will be permanently deleted: $names';
  }

  @override
  String get listSeparator => ', ';

  @override
  String get resetAndReimport => 'Reset and Re-import';

  @override
  String get reimport => 'Re-import';

  @override
  String get detecting => 'Detecting...';

  @override
  String get configure => 'Configure';

  @override
  String get cacheCleared => 'Cache cleared';

  @override
  String get allDataCleared => 'All data cleared';

  @override
  String get saveBackupFile => 'Save Backup File';

  @override
  String get selectBackupFile => 'Select Backup File';

  @override
  String get restoreSettingsTitle => 'Restore Settings';

  @override
  String get restoreMethod => 'Restore Method';

  @override
  String get restoreScope => 'Restore Scope';

  @override
  String get startMerge => 'Start Merge';

  @override
  String get startRestore => 'Start Restore';

  @override
  String get clearField => 'Clear';

  @override
  String get address => 'Address';

  @override
  String get account => 'Account';

  @override
  String get password => 'Password';

  @override
  String get region => 'Region';

  @override
  String get objectPath => 'Object Path';

  @override
  String get usePathStyle => 'Use path-style URL';

  @override
  String get remote => 'Remote';

  @override
  String get zoteroSync => 'Zotero Sync';

  @override
  String get fullResync => 'Full Resync';

  @override
  String get layoutAnalysis => 'Layout Analysis';

  @override
  String get layoutGeometry => 'Layout Geometry';

  @override
  String get layoutGeometryHelp => 'Geometry for layout detection boxes';

  @override
  String get outputControl => 'Output Control';

  @override
  String get repetitionPenalty => 'Repetition Suppression';

  @override
  String get repetitionPenaltyHint =>
      'Raise it when results contain repeated text or table content';

  @override
  String get crossPageTableMerge => 'Cross-page Table Merging';

  @override
  String get crossPageTableMergeDesc =>
      'Detects tables spanning pages and merges them into one';

  @override
  String get recognitionStability => 'Recognition Stability';

  @override
  String get recognitionStabilityHint =>
      'Lower it when results are unstable or show obvious hallucinations; raise slightly when there are omissions or excessive repetition';

  @override
  String get recognitionEnhancement => 'Recognition Enhancement';

  @override
  String get documentCorrection => 'Document Correction';

  @override
  String get ocrAuto => 'Auto';

  @override
  String get ocrRectangle => 'Rectangle';

  @override
  String get ocrQuadrilateral => 'Quadrilateral';

  @override
  String get ocrPolygon => 'Polygon';

  @override
  String get chartRecognition => 'Chart Recognition';

  @override
  String get stampRecognition => 'Stamp Recognition';

  @override
  String get imageAreaOcr => 'Image Text Recognition';

  @override
  String get orientationCorrection => 'Orientation Correction';

  @override
  String get curvatureCorrection => 'Curvature Correction';

  @override
  String get deduplicateBoxes => 'NMS Post-processing';

  @override
  String get multiPageReconstruction => 'Multi-page Reconstruction';

  @override
  String get ocrHeader => 'Header';

  @override
  String get ocrHeaderImage => 'Header Image';

  @override
  String get ocrFooter => 'Footer';

  @override
  String get ocrFooterImage => 'Footer Image';

  @override
  String get ocrPageNumber => 'Page Number';

  @override
  String get ocrFootnote => 'Footnote';

  @override
  String get ocrSideNote => 'Side Note';

  @override
  String get searchToolLabel => 'Search';

  @override
  String get streamOutput => 'Streaming output';

  @override
  String get tavilySearchSection => 'Web Search Fallback (Tavily)';

  @override
  String get tavilySearchDesc =>
      'Provides web search for models without native search (e.g. DeepSeek, Doubao). Once the key is set, the search toggle in chat works for these models';

  @override
  String get tavilyNotConfiguredHint =>
      'This model has no native web search. Set a Tavily API Key in AI settings to enable it';

  @override
  String get mimoSearchPluginTitle => 'Enable web search plugin';

  @override
  String get mimoSearchPluginHint =>
      'MiMo web search requires enabling the plugin in the platform console first';

  @override
  String get mimoSearchPluginOpenConsole => 'Open plugin console';

  @override
  String get taskInProgress => 'This document already has a task running';

  @override
  String get savingResult => 'Saving result';

  @override
  String get saveResultFailed => 'Failed to save result';

  @override
  String get summaryCancelled => 'Summary generation cancelled';

  @override
  String get preparingContent => 'Preparing content';

  @override
  String get requestingImageModel => 'Requesting image model';

  @override
  String get summaryGenerated => 'Summary generated';

  @override
  String get downloadCancelled => 'Download cancelled';

  @override
  String get summaryNotFound => 'Summary image not found';

  @override
  String get generateSummaryTitle => 'Generate Summary';

  @override
  String get exportAll => 'Export All';

  @override
  String get roleBadgeEmbedding => 'Embed';

  @override
  String get roleBadgeVision => 'Vision';

  @override
  String get roleBadgeImageGen => 'Image';

  @override
  String get roleBadgeTools => 'Tools';

  @override
  String get roleBadgeReasoning => 'Reason';

  @override
  String storageUsage(String size) {
    return 'Using $size';
  }

  @override
  String backupTo(String target) {
    return 'Backup to $target';
  }

  @override
  String uploadBackupTo(String target) {
    return 'Upload full backup to $target';
  }

  @override
  String pleaseConfigureFirst(String target) {
    return 'Please configure $target connection first';
  }

  @override
  String restoreFromRemote(String target) {
    return 'Restore from $target';
  }

  @override
  String downloadAndRestore(String target) {
    return 'Download from $target and restore';
  }

  @override
  String get generateZipAndSave => 'Generate zip backup and save locally';

  @override
  String get selectLocalZipRestore => 'Select local zip backup file to restore';

  @override
  String get thumbnailsAndTemp => 'Thumbnails, temp files, etc';

  @override
  String get allDataWillBeDeleted => 'Library and databases will be deleted';

  @override
  String get getToken => 'Get Token';

  @override
  String get syncZoteroLibrary => 'Sync Zotero Library';

  @override
  String zoteroImportedPull(int count) {
    return 'Imported $count · Pull new entries';
  }

  @override
  String get pleaseFillApiKey => 'Please fill in API Key first';

  @override
  String get zoteroImportHint =>
      'Import documents from Zotero personal library';

  @override
  String get zoteroResetHint =>
      'Clear import records and re-pull from library (recover deleted entries)';

  @override
  String get resetZoteroSync => 'Reset Zotero Sync';

  @override
  String get resetZoteroConfirm =>
      'This will clear local Zotero import records and re-pull from library: deleted entries will reappear, existing ones won\'t duplicate. Continue?';

  @override
  String get s3Config => 'S3 Configuration';

  @override
  String get webDavConfig => 'WebDAV Configuration';

  @override
  String remoteNotConfigured(String target) {
    return '$target remote backup not configured';
  }

  @override
  String s3BucketInfo(String bucket, String region) {
    return 'Bucket: $bucket  ·  Region: $region';
  }

  @override
  String s3ObjectInfo(String key) {
    return 'Object: $key';
  }

  @override
  String webDavAccountInfo(String username) {
    return 'Account: $username';
  }

  @override
  String webDavPathInfo(String path) {
    return 'Path: $path';
  }

  @override
  String get clearingCache => 'Clearing cache...';

  @override
  String get confirmDeleteAllDataBody =>
      'This will delete all document files and databases irreversibly. Continue?';

  @override
  String get clearingData => 'Clearing data...';

  @override
  String get generatingLocalBackup => 'Generating local backup...';

  @override
  String backupExportedTo(String path) {
    return 'Backup exported to $path';
  }

  @override
  String exportBackupFailed(String error) {
    return 'Export backup failed: $error';
  }

  @override
  String get mergingBackup => 'Merging backup...';

  @override
  String get restoringBackup => 'Restoring backup...';

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get generatingAndUploading =>
      'Generating and uploading remote backup...';

  @override
  String get backupScopeTitle => 'Backup Scope';

  @override
  String get backupScopeFull => 'Full backup';

  @override
  String get backupScopeFullDesc =>
      'Includes PDFs and extracted files; archive can be large';

  @override
  String get backupScopeData => 'Data only';

  @override
  String get backupScopeDataDesc =>
      'Settings, metadata, highlights, translations and chats; excludes PDFs and extracted files';

  @override
  String get startBackup => 'Start Backup';

  @override
  String get autoBackup => 'Auto Backup';

  @override
  String get autoBackupOff => 'Off';

  @override
  String get autoBackupDaily => 'Daily';

  @override
  String get autoBackupWeekly => 'Weekly';

  @override
  String get autoBackupHint =>
      'Backs up to the remote in the background when due, only if content has changed';

  @override
  String get cloudSync => 'Cloud Sync';

  @override
  String get syncBackupNow => 'Back Up Now';

  @override
  String syncLastBackup(String info) {
    return 'Last backup: $info';
  }

  @override
  String get syncLastBackupNever => 'No backup yet';

  @override
  String get syncRemoteNotConfigured => 'Remote backup not configured';

  @override
  String get syncRemoteNotConfiguredDesc =>
      'Configure S3 or WebDAV to back up and see sync status here';

  @override
  String get syncGroupChanged => 'Changed since last backup';

  @override
  String get syncGroupNever => 'Never backed up';

  @override
  String get syncGroupSynced => 'Backed up';

  @override
  String get syncReasonAdded => 'New';

  @override
  String get syncReasonContent => 'File changed';

  @override
  String get syncReasonMeta => 'Metadata / highlights';

  @override
  String get syncReasonFiles => 'Translations / chats';

  @override
  String remoteBackupUploaded(String target) {
    return 'Remote backup uploaded to $target';
  }

  @override
  String uploadRemoteFailed(String error) {
    return 'Upload remote backup failed: $error';
  }

  @override
  String get downloadingRemoteBackup => 'Downloading remote backup...';

  @override
  String get mergingRemoteBackup => 'Merging remote backup...';

  @override
  String get restoringRemoteBackup => 'Restoring remote backup...';

  @override
  String remoteRestoreFailed(String error) {
    return 'Remote restore failed: $error';
  }

  @override
  String restoreCompleteRefreshed(String prefix) {
    return '${prefix}Restore complete, page state synced';
  }

  @override
  String mergeCompleteUpToDate(String prefix) {
    return '${prefix}Merge complete, local data is up to date';
  }

  @override
  String mergeDocumentsAdded(int count) {
    return 'Added $count documents';
  }

  @override
  String mergeHighlightsAdded(int count) {
    return 'Added $count highlights';
  }

  @override
  String mergeFilesCopied(int count) {
    return 'Copied $count files';
  }

  @override
  String mergeSettingsAdded(int count) {
    return 'Added $count settings';
  }

  @override
  String mergeCompleteSummary(String prefix, String details) {
    return '${prefix}Merge complete: $details';
  }

  @override
  String get webDavServerAddress => 'WebDAV server address';

  @override
  String get s3Endpoint => 'S3 / R2 / MinIO Endpoint';

  @override
  String get s3ObjectPathDefault => 'Default: otter-pad/otter_pad_backup.zip';

  @override
  String get s3PathStyleHint =>
      'MinIO / R2 / S3-compatible usually recommended';

  @override
  String get selectImageModelFirst =>
      'Please select an image model in AI Settings first';

  @override
  String get summaryUploadFailed => 'Failed to upload summary image';

  @override
  String estimatedCost(String dollar, String cost) {
    return 'Estimated cost ~\$$dollar$cost per image';
  }

  @override
  String get useAppImageGen =>
      'To use App image gen, tap App Image Gen and upload manually';

  @override
  String get appImageGen => 'App Image Gen';

  @override
  String get markdownNotFound =>
      'Markdown file not found, please extract first';

  @override
  String promptGenerationFailed(String error) {
    return 'Prompt generation failed: $error';
  }

  @override
  String get saveExportZip => 'Save export ZIP';

  @override
  String exportedWithPromptCopied(String name) {
    return 'Exported to $name, prompt copied';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get exportToAppImageGen => 'Export to App Image Gen';

  @override
  String get exportToAppImageGenHint =>
      'Export document materials, then upload manually in ChatGPT / Gemini etc';

  @override
  String get exportShareHint =>
      'Share figures + Markdown, prompt auto-copied to clipboard';

  @override
  String get exportZipHint =>
      'Pack figures + article.md + prompt.md into ZIP, prompt auto-copied to clipboard';

  @override
  String get ocrChartRecognitionDesc => 'Parse charts into tables';

  @override
  String get ocrStampRecognitionDesc => 'Recognize stamps in documents';

  @override
  String get ocrImageAreaDesc => 'Recognizes text within image layout elements';

  @override
  String get ocrOrientationDesc => 'Auto-correct 0°/90°/180°/270° rotation';

  @override
  String get ocrCurvatureDesc => 'Correct curved or wrinkled documents';

  @override
  String get ocrDeduplicateDesc =>
      'Effective only when layout analysis is enabled. Automatically removes duplicate or highly overlapping region boxes';

  @override
  String get ocrMultiPageDesc => 'Reconstruct multi-page document structure';

  @override
  String get ocrFilterHelp =>
      'Checked label regions will not appear in Markdown output. All ignored by default';

  @override
  String get resetOcrSettings => 'Reset Settings';

  @override
  String get resetOcrSettingsConfirm =>
      'This resets all OCR options to their defaults except the API Key. Continue?';

  @override
  String get reset => 'Reset';

  @override
  String get ocrSettingsReset => 'OCR settings reset';

  @override
  String get ocrInterface => 'OCR Interface';

  @override
  String get aspectSquare => 'Square · Social media';

  @override
  String get aspectClassic => 'Classic print · Document layout';

  @override
  String get aspectWide => 'Landscape · Desktop wallpaper';

  @override
  String get aspectUltraWide => 'Ultra-wide · Cinema';

  @override
  String get aspectTall => 'Portrait · Phone wallpaper';

  @override
  String get imageRefCountHint =>
      'Select up to 10 reference figures in document order; supplementary figures (Supplementary / Extended Data, etc.) are dropped first when over the limit';

  @override
  String get aspectRatioHint =>
      'OpenAI maps to the nearest output size, preserving aspect ratio in the prompt';

  @override
  String get summaryPromptHint =>
      'Controls the visual style and information layout; title, metadata, Markdown and figures are appended at runtime';

  @override
  String get summaryPromptLabel => 'Summary Prompt';

  @override
  String get summaryPromptFieldHint =>
      'Describe layout, colors, density and style for the summary image';

  @override
  String estimatedCostShort(String dollar, String cost) {
    return 'Est. \$$dollar$cost';
  }

  @override
  String get translationTargetLangDesc =>
      'Actual value of the targetLanguage variable in prompts';

  @override
  String get translationStyleDesc =>
      'Visual style for translations in full-document translation';

  @override
  String get translationIgnoreDesc =>
      'Checked sections are skipped during translation; unchecked sections merge into full paragraphs';

  @override
  String get temperatureDesc =>
      'Lower is more conservative, higher is more creative';

  @override
  String get systemPromptDesc =>
      'Translation system prompt, supports targetLanguage placeholder';

  @override
  String get systemPromptHint => 'e.g.: You are a professional translator...';

  @override
  String get userPromptDesc =>
      'Translation user prompt, supports targetLanguage and input placeholders';

  @override
  String documentsAddedCount(int added) {
    return 'Added $added documents';
  }

  @override
  String documentsAddedSkipped(int added, int skipped) {
    return 'Added $added documents, $skipped already existed';
  }

  @override
  String confirmDeleteDocuments(int count) {
    return 'Delete $count documents? This cannot be undone';
  }

  @override
  String deletedDocuments(int count) {
    return 'Deleted $count documents';
  }

  @override
  String get configureExtractToken =>
      'Please configure document extraction Access Token in Settings';

  @override
  String get noPdfFilesSelected =>
      'No local PDF files in selection, cannot extract';

  @override
  String get pdfNotFound => 'PDF file not found';

  @override
  String get reformatting => 'Reformatting...';

  @override
  String reformatFailed(String error) {
    return 'Reformat failed: $error';
  }

  @override
  String addedToFavorite(String name) {
    return 'Added to \"$name\"';
  }

  @override
  String addedToFavorites(int count) {
    return 'Added to $count favorites';
  }

  @override
  String removedFromFavoriteSingle(String name) {
    return 'Removed from \"$name\"';
  }

  @override
  String removedFromFavorites(int count) {
    return 'Removed from $count favorites';
  }

  @override
  String translationFailed(String error) {
    return 'Translation failed: $error';
  }

  @override
  String get pdfFileNotFoundTitle => 'PDF file not found for this document';

  @override
  String removedFromFavoriteCount(int count) {
    return 'Removed $count documents from favorite';
  }

  @override
  String confirmDeleteEntries(int count) {
    return 'Delete $count entries without files?';
  }

  @override
  String deletedEntries(int count) {
    return 'Deleted $count entries';
  }

  @override
  String attachFileFailed(String error) {
    return 'Attach file failed: $error';
  }

  @override
  String addingDocumentsTo(int total) {
    return 'Adding $total documents to...';
  }

  @override
  String allSelectedAlreadyHere(int count) {
    return 'All $count selected already in this favorite';
  }

  @override
  String currentDocumentCount(int count) {
    return 'Currently $count documents';
  }

  @override
  String overlapAndNew(int overlap, int newCount) {
    return 'Contains $overlap · Will add $newCount';
  }

  @override
  String confirmDeleteFavorite(String name) {
    return 'Delete \"$name\"? Documents inside will not be deleted';
  }

  @override
  String favoriteDocumentCount(int count) {
    return '$count documents';
  }

  @override
  String get clearReadingHistoryConfirm =>
      'This will clear all reading history. Documents will not be deleted. This cannot be undone';

  @override
  String get noReadingHistoryHint =>
      'Open any document and it will appear here by date';

  @override
  String get identifierInputHint =>
      'Enter ISBN, DOI, PMID, arXiv ID or ADS bibcode to add entries:';

  @override
  String get identifierExample => 'e.g.: 10.1038/s41586-021-03811-w';

  @override
  String get addFilesSubtitle =>
      'Import local PDFs, extract title, author, journal, year and DOI';

  @override
  String get addByIdentifierSubtitle =>
      'Enter DOI, PMID, arXiv ID or ISBN to create entries directly';

  @override
  String get rebuildLibrarySubtitle =>
      'Rescan directory, recover PDFs and retry core metadata extraction';

  @override
  String get downloadPdf => 'Download PDF';

  @override
  String viewLibraryTotal(int count) {
    return 'Library · $count items';
  }

  @override
  String addedDocumentsToFavorite(int count) {
    return 'Added $count documents';
  }

  @override
  String get searchDocumentHint => 'Search title / author / journal';

  @override
  String get noDocumentsInLibrary =>
      'No documents, please add PDF files to library';

  @override
  String get providerDescOpenai => 'gpt / o series · Image gen via gpt-image';

  @override
  String get providerDescAnthropic => 'Claude series';

  @override
  String get providerDescGemini => 'Google AI · Multimodal';

  @override
  String get providerDescOpenaiCompatible =>
      'DeepSeek / self-hosted OpenAI-compatible API';

  @override
  String confirmDeleteProvider(String name) {
    return 'Delete \"$name\"? API Key, URL and models will be cleared';
  }

  @override
  String modelConnected(String modelId) {
    return '$modelId connected';
  }

  @override
  String get apiAddress => 'API Address';

  @override
  String get apiKey => 'API Key';

  @override
  String previewUrl(String url) {
    return 'Preview: $url';
  }

  @override
  String selectRole(String role) {
    return 'Select $role';
  }

  @override
  String addProtocol(String protocol) {
    return 'Add $protocol';
  }

  @override
  String get assignRoleHint => 'Assign a scene role for this model (optional)';

  @override
  String willReplace(String current) {
    return 'Will replace $current';
  }

  @override
  String providerModels(String provider) {
    return '$provider Models';
  }

  @override
  String get searchModelHint => 'Search model ID or name';

  @override
  String connectionOkMs(String ms) {
    return 'Connected, $ms ms';
  }

  @override
  String get cannotConnectCheckProxy => 'Cannot connect, check proxy settings';

  @override
  String requestFailed(String error) {
    return 'Request failed: $error';
  }

  @override
  String testFailed(String error) {
    return 'Test failed: $error';
  }

  @override
  String copyFailed(String error) {
    return 'Copy failed: $error';
  }

  @override
  String shareFailed(String error) {
    return 'Share failed: $error';
  }

  @override
  String saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String savedToPath(String path) {
    return 'Saved to $path';
  }

  @override
  String get figuresNotFoundHint => 'No figures found\nPlease extract first';

  @override
  String copiedReference(int number, String snippet) {
    return 'Copied [$number] $snippet';
  }

  @override
  String searchMatchesFound(int count) {
    return 'Found $count matches';
  }

  @override
  String get searchPdfContentHint => 'Search PDF content';

  @override
  String get markdownIgnoreLabels => 'Markdown Ignore Labels';

  @override
  String get resolutionHint =>
      'OpenAI maps to quality; Gemini maps to imageSize';

  @override
  String get translationStyleThemed => 'Themed';

  @override
  String get translationStyleBold => 'Bold';

  @override
  String get translationStyleItalic => 'Italic';

  @override
  String get translationStyleWeakened => 'Weakened';

  @override
  String get translationStyleDashed => 'Dashed Underline';

  @override
  String get translationStyleHighlight => 'Highlight';

  @override
  String get translationStyleBlur => 'Blur';

  @override
  String get translationStyleQuote => 'Quote';

  @override
  String get skipSectionReferences => 'References';

  @override
  String get skipSectionAcknowledgments => 'Acknowledgments';

  @override
  String get skipSectionAuthorsContributions => 'Authors / Conflicts';

  @override
  String get skipSectionFundingData => 'Funding / Data';

  @override
  String get skipSectionSupplementaryAppendix => 'Appendix / Supplements';

  @override
  String get skipSectionEthicsLegends => 'Ethics / Legends';

  @override
  String get fidelityAuto => 'Auto';

  @override
  String get fidelityStandard => 'Standard';

  @override
  String get fidelityHigh => 'High';

  @override
  String tasksInProgress(int count) {
    return '$count tasks in progress';
  }

  @override
  String get aiSettingsSelectTextModel =>
      'Please select a fast or expert model in AI Settings';

  @override
  String get aiSettingsFillApiKey => 'Please fill in API Key in AI Settings';

  @override
  String get aiSettingsFillImageApiKey =>
      'Please fill in image model API Key in AI Settings';

  @override
  String get targetLanguageChangedRetranslate =>
      'Target language changed, please re-translate';

  @override
  String get preparingTranslation => 'Preparing';

  @override
  String get noTranslatableParagraphs => 'No translatable paragraphs detected';

  @override
  String waitingExtractTitle(String title) {
    return 'Waiting to extract: $title';
  }

  @override
  String submittingTaskTitle(String title) {
    return 'Submitting task: $title';
  }

  @override
  String extractionCompleteTitle(String title) {
    return 'Extraction complete: $title';
  }

  @override
  String networkError(String message) {
    return 'Network error: $message';
  }

  @override
  String extractionFailedDetail(String error) {
    return 'Extraction failed: $error';
  }

  @override
  String waitingSubmitTitle(String title) {
    return 'Waiting to submit: $title';
  }

  @override
  String submittedWaitingTitle(String title) {
    return 'Submitted, waiting: $title';
  }

  @override
  String extractingTitle(String title) {
    return 'Extracting… · $title';
  }

  @override
  String waitingSummaryTitle(String title) {
    return 'Waiting to generate summary: $title';
  }

  @override
  String generatingSummaryTitle(String title) {
    return 'Generating summary: $title';
  }

  @override
  String summaryGenerationFailed(String error) {
    return 'Summary generation failed: $error';
  }

  @override
  String waitingDownloadTitle(String title) {
    return 'Waiting to download: $title';
  }

  @override
  String downloadingTitle(String title) {
    return 'Downloading: $title';
  }

  @override
  String downloadSuccessTitle(String title) {
    return 'Download complete: $title';
  }

  @override
  String get downloadFailedNoSource =>
      'Download failed, no available PDF source';

  @override
  String downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get downloadingPdf => 'Downloading PDF';

  @override
  String downloadCancelledPartial(int count) {
    return 'Download cancelled, $count succeeded';
  }

  @override
  String downloadCompleteAll(int count) {
    return 'Download complete, $count succeeded';
  }

  @override
  String downloadCompletePartial(int ok, int fail) {
    return 'Download complete: $ok succeeded, $fail failed';
  }

  @override
  String get preparingImport => 'Preparing to import files...';

  @override
  String get importingFilesBusy => 'Importing files, please wait';

  @override
  String importingFile(String fileName) {
    return 'Importing: $fileName';
  }

  @override
  String get documentAlreadyExists => 'This document already exists in library';

  @override
  String addedDocumentNoPdf(String title) {
    return 'Added \"$title\", but no associated PDF found';
  }

  @override
  String get goAdd => 'Go add';

  @override
  String addedDocumentTitle(String title) {
    return 'Added: $title';
  }

  @override
  String get networkRequestFailedRetry =>
      'Network request failed, please try again later';

  @override
  String addFailedError(String error) {
    return 'Add failed: $error';
  }

  @override
  String resolvingIdentifier(String identifier) {
    return 'Resolving identifier: $identifier';
  }

  @override
  String get resolvingIdentifierBusy => 'Resolving identifier, please wait';

  @override
  String get preparingRebuild => 'Preparing to rebuild library...';

  @override
  String get rebuildInProgress => 'Library rebuild in progress';

  @override
  String get rebuildCancelled => 'Library rebuild cancelled';

  @override
  String get rebuildComplete => 'Library rebuild complete';

  @override
  String rebuildAdded(int count) {
    return 'Added $count';
  }

  @override
  String rebuildRemoved(int count) {
    return 'Removed $count';
  }

  @override
  String rebuildRepaired(int count) {
    return 'Repaired metadata for $count';
  }

  @override
  String rebuildUnresolved(int count) {
    return '$count still need metadata';
  }

  @override
  String rebuildNoFile(int count) {
    return '$count entries without files';
  }

  @override
  String get rebuildNormal => ', library status normal';

  @override
  String get fetchingZoteroItems => 'Fetching Zotero items...';

  @override
  String get zoteroSyncInProgress => 'Zotero sync in progress';

  @override
  String get zoteroSyncCancelled => 'Zotero sync cancelled';

  @override
  String get fetchingZoteroProgress => 'Fetching Zotero items';

  @override
  String get importingDocuments => 'Importing documents...';

  @override
  String zoteroSyncCompleteAdded(int count) {
    return 'Zotero sync complete, added $count';
  }

  @override
  String get zoteroSyncCompleteNoNew => 'Zotero sync complete, no new items';

  @override
  String zoteroSyncFailed(String error) {
    return 'Zotero sync failed: $error';
  }

  @override
  String get zoteroSyncNetworkFailed =>
      'Zotero sync failed: network request failed';

  @override
  String existsInLibrary(String title) {
    return 'Already in library: $title';
  }

  @override
  String importedCountPart(int count) {
    return 'Imported $count';
  }

  @override
  String duplicateCountPart(int count) {
    return 'Duplicate $count';
  }

  @override
  String importedFile(String title) {
    return 'Imported: $title';
  }

  @override
  String get importCancelledLabel => 'Import cancelled';

  @override
  String get noFilesImported => 'No files imported';

  @override
  String get importCompleteLabel => 'Import complete';

  @override
  String get taskBusy => 'A task is already running';

  @override
  String aiLayoutFixConfirmMessage(String tokens) {
    return 'AI layout fix will use the expert model to audit figure crop regions (subfigure completeness, caption exclusion) and recover missed figures. Estimated token usage: ~$tokens';
  }

  @override
  String get aiLayoutFixAnalyzing => 'Analyzing document...';

  @override
  String get aiLayoutFixRendering => 'Rendering PDF pages...';

  @override
  String get aiLayoutFixCalling => 'Calling AI model...';

  @override
  String get aiLayoutFixApplying => 'Applying fixes...';

  @override
  String get aiLayoutFixCropping => 'Re-cropping figures...';

  @override
  String get aiLayoutFixComplete => 'Layout fix complete';

  @override
  String aiLayoutFixSummary(int adjusted, int added, int removed) {
    return '$adjusted adjusted · $added added · $removed removed';
  }

  @override
  String aiLayoutFixFailed(String error) {
    return 'Layout fix failed: $error';
  }

  @override
  String get aiLayoutFixNoContent => 'No figures to audit';

  @override
  String promptMissingPlaceholders(String placeholders) {
    return 'Missing required placeholder: $placeholders';
  }

  @override
  String aiLayoutFixFigureCount(int count) {
    return '$count figures';
  }

  @override
  String get aiLayoutFixRevertHint => 'Revert via \"Re-extract\" if needed';

  @override
  String get expertModelNotSet => 'Please set up the expert model first';

  @override
  String get expertRequiresVision => 'Expert model must support image input';

  @override
  String get switchedToExpertForImage =>
      'Fast model doesn\'t support images; switched to expert model';

  @override
  String get askAi => 'Ask AI';

  @override
  String get newChat => 'New chat';

  @override
  String get chatHistory => 'Chat history';

  @override
  String get chatNoHistory => 'No chats yet';

  @override
  String get chatInputHint => 'Ask about this document…';

  @override
  String get chatEmptyHint =>
      'Ask anything about this document — answers are grounded in the extracted full text and figures';

  @override
  String chatMessageCount(int count) {
    return '$count messages';
  }

  @override
  String get chatSend => 'Send';

  @override
  String get chatRemoveQuote => 'Remove quote';

  @override
  String get chatLocateSource => 'Locate in document';

  @override
  String get chatReturnToAi => 'Return to Ask AI';

  @override
  String chatNewSessionHint(String title) {
    return 'The new chat will still be grounded in the full text and figures of \"$title\"';
  }

  @override
  String get chatCopyMessage => 'Copy message';

  @override
  String get chatSelectText => 'Select text';

  @override
  String get chatEditingMessage => 'Editing message';

  @override
  String get chatEditHint =>
      'Editing will restart the conversation from this point';

  @override
  String get chatFork => 'Fork';

  @override
  String get dontRemindAgain => 'Don\'t remind me again';

  @override
  String get aboutSubtitle => 'Open Source AI Literature Reading Assistant';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutSystem => 'System';

  @override
  String get aboutSystemCopyHint => 'Tap to copy system specs';

  @override
  String get aboutReportIssue => 'Report an Issue';

  @override
  String get aboutReportIssueDesc => 'Copy specs and open the GitHub bug form';

  @override
  String get aboutSpecsCopied =>
      'System specs copied — paste into the issue form';

  @override
  String get aboutOpenIssueFailed => 'Could not open GitHub';

  @override
  String get aboutProject => 'Repository';

  @override
  String get aboutCheckUpdate => 'Check for Updates';

  @override
  String get aboutLicense => 'Open Source License';

  @override
  String get aboutDisclaimer => 'Disclaimer';

  @override
  String get aboutDisclaimerContent =>
      'This software is intended solely for non-commercial purposes such as learning, communication, and scientific research. Commercial use of this software is strictly prohibited. Any commercial activities are unrelated to this software';

  @override
  String get aboutAgree => 'Agree';

  @override
  String get aboutDisagree => 'Disagree';

  @override
  String get aboutLicenseContent =>
      'This software is released under the GNU General Public License v3.0 (GPL-3.0).\n\nYou are free to use, modify, and distribute this software, provided that modified versions are released under the same license with source code made available.\n\nSee the LICENSE file in the project repository for full terms';

  @override
  String get aboutViewFullLicense => 'View Full Text';

  @override
  String get generalSettings => 'General';

  @override
  String get generalSettingsSubtitle =>
      'Logging, cache, and system preferences';

  @override
  String get generalSystem => 'System';

  @override
  String get generalLogRecording => 'Log Recording';

  @override
  String get generalLogRecordingDesc =>
      'Record logs to local files for troubleshooting';

  @override
  String get generalLogLevel => 'Minimum Log Level';

  @override
  String get generalLogLevelInfo => 'Info';

  @override
  String get generalLogLevelWarning => 'Warning';

  @override
  String get generalLogLevelError => 'Error';

  @override
  String get generalExportTodayLog => 'Export Today\'s Log';

  @override
  String get generalExportTodayLogDesc =>
      'Share or save today\'s log file for bug reports';

  @override
  String get generalExportLogEmpty =>
      'No log file yet — enable logging, reproduce the issue, then export';

  @override
  String get generalExportLogFailed => 'Failed to export log';

  @override
  String generalExportLogSaved(String path) {
    return 'Log saved to $path';
  }

  @override
  String get generalReportIssue => 'Report an Issue';

  @override
  String get generalReportIssueDesc =>
      'Copy system specs and open the GitHub bug form';

  @override
  String get generalHapticFeedback => 'Haptic Feedback';

  @override
  String get generalHapticFeedbackDesc =>
      'Vibration feedback for taps and interactions';

  @override
  String get generalCacheAutoCleanup => 'Auto Cleanup Cache';

  @override
  String get generalCacheAutoCleanupDesc =>
      'Clean up WebView and thumbnail caches on app startup';

  @override
  String get generalAutoCheckUpdate => 'Check for Updates on Startup';

  @override
  String get generalAutoCheckUpdateDesc =>
      'Automatically check for new versions when the app launches';

  @override
  String get updateNewVersionFound => 'New Version Available';

  @override
  String get updateViewFullChangelog => 'View Full Changelog';

  @override
  String get updateNow => 'Update Now';

  @override
  String get updateIgnoreVersion => 'Ignore This Version';

  @override
  String get updateLater => 'Later';

  @override
  String get updateOpenReleasePage => 'Open Release Page';

  @override
  String get updateUpToDate => 'You\'re up to date';

  @override
  String get updateCheckFailed => 'Failed to check for updates';

  @override
  String get updateDownloading => 'Downloading update';

  @override
  String get updateDownloadFailed => 'Failed to download update';

  @override
  String get generalEnableHttp2 => 'HTTP/2';

  @override
  String get generalEnableHttp2Desc =>
      'Multiplexes concurrent API requests over a single connection, reducing overhead for parallel tasks like translation';

  @override
  String get onboardingWelcomeTitle => 'Welcome to OtterPad';

  @override
  String get onboardingWelcomeBody =>
      'Let\'s set up a few things to get started. You can always change these later in Settings';

  @override
  String get onboardingStart => 'Start Setup';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingOcrTitle => 'Set Up Document OCR';

  @override
  String get onboardingOcrBody =>
      'OtterPad uses PaddleOCR to extract text from PDF documents. You\'ll need an API token to get started';

  @override
  String get onboardingOcrGuide => 'Go to Settings';

  @override
  String get onboardingToolsHint =>
      'Use this button to add PDF files and run OCR text extraction';

  @override
  String get onboardingAiTitle => 'Set Up AI Models';

  @override
  String get onboardingAiBody =>
      'Configure AI models to unlock document chat, translation, and more. You can skip this and set up later';

  @override
  String get onboardingAiGuide => 'Set Up Models';

  @override
  String get onboardingExpertHint =>
      'Configure a multimodal model for in-document chat and OCR proofreading';

  @override
  String get onboardingFastHint =>
      'Configure a fast model for translation, quick Q&A, and title renaming';

  @override
  String get onboardingImageGenHint =>
      'Configure an image generation model for generating document summary images';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingFinish => 'Finish';

  @override
  String get onboardingGotIt => 'Got It';

  @override
  String get emptyLibraryTitle => 'Your library is empty';

  @override
  String get emptyLibraryBody =>
      'Set up OCR and AI models, then add your first PDF to start reading';

  @override
  String get emptyLibraryAction => 'Initial Setup';
}
