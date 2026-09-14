// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aiSettings => 'AI settings';

  @override
  String get subtitle =>
      'Configure model connections, translation preferences, and summary images.';

  @override
  String get demoNote => 'Interactive preview · Changes stay on this page';

  @override
  String get darkMode => 'Toggle light and dark';

  @override
  String get language => 'Switch language';

  @override
  String get fontScale => 'Adjust text size';

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get modelApi => 'Model connections';

  @override
  String get modelApiHelp =>
      'Connect a provider for reading, translation and images.';

  @override
  String get provider => 'Provider';

  @override
  String get providerHint => 'Choose the service that hosts your models.';

  @override
  String get apiKey => 'API key';

  @override
  String get getApiKey => 'Get API key';

  @override
  String get apiKeyActionMessage =>
      'This preview does not connect to providers. Get an API key from the provider console.';

  @override
  String get keyHint => 'No real key is needed. Input stays in this preview.';

  @override
  String get keyPlaceholder => 'Enter a demo key';

  @override
  String get showKey => 'Show API key';

  @override
  String get hideKey => 'Hide API key';

  @override
  String get endpoint => 'API address';

  @override
  String get endpointHint => 'Enter the base address for the API.';

  @override
  String get endpointError => 'Enter a valid HTTPS address.';

  @override
  String get models => 'Models';

  @override
  String get modelHint =>
      'Choose a model and inspect its capabilities. Fetch models loads a local demo catalog without contacting a provider.';

  @override
  String get vision => 'Vision';

  @override
  String get tools => 'Tools';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get roles => 'Global model roles';

  @override
  String get expert => 'Expert model';

  @override
  String get expertHint =>
      'For careful reasoning, complex analysis and detailed answers.';

  @override
  String get fast => 'Fast model';

  @override
  String get fastHint => 'For everyday questions and quick responses.';

  @override
  String get imageModel => 'Image model';

  @override
  String get imageModelHint => 'For creating illustrated paper summaries.';

  @override
  String get search => 'Web search';

  @override
  String get searchHint => 'Give the reading assistant access to web sources.';

  @override
  String get searchKey => 'Search API key';

  @override
  String get clear => 'Not assigned';

  @override
  String get translation => 'Translation';

  @override
  String get translationHelp => 'Choose how translations read and appear.';

  @override
  String get targetLanguage => 'Target language';

  @override
  String get simplifiedChinese => 'Chinese (Simplified)';

  @override
  String get english => 'English';

  @override
  String get japanese => 'Japanese';

  @override
  String get korean => 'Korean';

  @override
  String get french => 'French';

  @override
  String get german => 'German';

  @override
  String get styles => 'Translation style';

  @override
  String get styleHint => 'Choose one translation style at a time.';

  @override
  String get normal => 'Default';

  @override
  String get accent => 'Accent';

  @override
  String get bold => 'Bold';

  @override
  String get italic => 'Italic';

  @override
  String get muted => 'Muted';

  @override
  String get underline => 'Dashed underline';

  @override
  String get background => 'Background';

  @override
  String get blur => 'Blur';

  @override
  String get quote => 'Quote';

  @override
  String get ignore => 'Exclude from translation';

  @override
  String get references => 'References';

  @override
  String get acknowledgments => 'Acknowledgments';

  @override
  String get contributions => 'Contributions / competing interests';

  @override
  String get funding => 'Funding / data statements';

  @override
  String get supplement => 'Appendices / supplements';

  @override
  String get ethics => 'Ethics / figure captions';

  @override
  String get ignoreHint => 'Selected sections are excluded from translation.';

  @override
  String get temperature => 'Temperature';

  @override
  String get temperatureHelp =>
      'Steps of 0.05. Lower values are steadier; higher values allow more variation.';

  @override
  String get resetTemperature => 'Reset temperature';

  @override
  String get systemPrompt => 'System prompt';

  @override
  String get userPrompt => 'User prompt';

  @override
  String get promptHint =>
      'Keep template variables intact while editing the instructions.';

  @override
  String get promptError =>
      'Keep both text and targetLanguage variables. This draft is not active.';

  @override
  String get resetPrompt => 'Restore the default prompt';

  @override
  String get imageSettings => 'Image generation';

  @override
  String get imageHelp =>
      'Choose the proportions, quality and references for summary images.';

  @override
  String get aspectRatio => 'Aspect ratio';

  @override
  String get aspectHint => 'Choose the proportions of the generated image.';

  @override
  String get quality => 'Image quality';

  @override
  String get auto => 'Automatic';

  @override
  String get standard => 'Standard';

  @override
  String get high => 'High';

  @override
  String get referenceImages => 'Reference images';

  @override
  String get referenceImagesHelp =>
      'Use 1–10 paper figures as references. The default is 10.';

  @override
  String get resetReferences => 'Reset reference image count';

  @override
  String get imagePrompt => 'Summary image prompt';

  @override
  String get imagePromptHint =>
      'Describe the focus, structure and style of the image.';

  @override
  String get fetchModels => 'Fetch models';

  @override
  String get retryModels => 'Retry fetch';

  @override
  String get fetchingModels => 'Loading demo models…';

  @override
  String modelsFetched(int count) {
    return 'Fetched $count demo models';
  }

  @override
  String get modelsDemoHint => 'Local demo catalog · No network request';

  @override
  String get fetchModelsError =>
      'Could not fetch models. Correct the API endpoint, then retry.';

  @override
  String get account => 'Account';

  @override
  String get address => 'Address';

  @override
  String get author => 'Author';

  @override
  String get autoBackup => 'Auto Backup';

  @override
  String get autoBackupDaily => 'Daily';

  @override
  String get autoBackupHint =>
      'Backs up to the remote in the background when due, only if content has changed';

  @override
  String get autoBackupOff => 'Off';

  @override
  String get autoBackupWeekly => 'Weekly';

  @override
  String get backupMethod => 'Backup Method';

  @override
  String get backupScopeData => 'Data only';

  @override
  String get backupScopeDataDesc =>
      'Settings, metadata, highlights, translations and chats; excludes PDFs and extracted files';

  @override
  String get backupScopeFull => 'Full backup';

  @override
  String get backupScopeFullDesc =>
      'Includes PDFs and extracted files; archive can be large';

  @override
  String get backupScopeTitle => 'Backup Scope';

  @override
  String backupTo(String target) {
    return 'Backup to $target';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get clearField => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get configure => 'Configure';

  @override
  String get dataManagement => 'Data Management';

  @override
  String get delete => 'Delete';

  @override
  String downloadAndRestore(String target) {
    return 'Download from $target and restore';
  }

  @override
  String get edit => 'Edit';

  @override
  String get editFavorite => 'Edit Favorite';

  @override
  String get enterFavoriteName => 'Enter a name';

  @override
  String get exportBackup => 'Export Backup';

  @override
  String get favoriteName => 'Favorite name';

  @override
  String get fullResync => 'Full Resync';

  @override
  String get generateZipAndSave => 'Generate zip backup and save locally';

  @override
  String get getToken => 'Get Token';

  @override
  String get journal => 'Journal';

  @override
  String get localBackup => 'Local Backup';

  @override
  String get objectPath => 'Object Path';

  @override
  String get password => 'Password';

  @override
  String pleaseConfigureFirst(String target) {
    return 'Please configure $target connection first';
  }

  @override
  String get pleaseFillApiKey => 'Please fill in API Key first';

  @override
  String get region => 'Region';

  @override
  String get reimport => 'Re-import';

  @override
  String get remoteBackup => 'Remote Backup';

  @override
  String remoteNotConfigured(String target) {
    return '$target remote backup not configured';
  }

  @override
  String get resetZoteroConfirm =>
      'This will clear local Zotero import records and re-pull from library: deleted entries will reappear, existing ones won\'t duplicate. Continue?';

  @override
  String get resetZoteroSync => 'Reset Zotero Sync';

  @override
  String get restoreFromBackup => 'Restore from Backup';

  @override
  String restoreFromRemote(String target) {
    return 'Restore from $target';
  }

  @override
  String get restoreMethod => 'Restore Method';

  @override
  String get restoreModeMerge => 'Merge';

  @override
  String get restoreModeMergeDescription =>
      'Keep local data and add missing content from the backup';

  @override
  String get restoreModeOverwrite => 'Overwrite';

  @override
  String get restoreModeOverwriteDescription =>
      'Replace local data with the backup';

  @override
  String get restoreScope => 'Restore Scope';

  @override
  String get restoreScopeFull => 'Full restore';

  @override
  String get restoreScopeFullDescription => 'Restore the library and settings';

  @override
  String get restoreScopeLibrary => 'Library only';

  @override
  String get restoreScopeLibraryDescription =>
      'Restore documents, collections, annotations and document files';

  @override
  String get restoreScopeSettings => 'Settings only';

  @override
  String get restoreScopeSettingsDescription => 'Restore application settings';

  @override
  String get restoreSettingsTitle => 'Restore Settings';

  @override
  String get s3Config => 'S3 Configuration';

  @override
  String get s3Endpoint => 'S3 / R2 / MinIO Endpoint';

  @override
  String get s3ObjectPathDefault => 'Default: otter-pad/otter_pad_backup.zip';

  @override
  String get s3PathStyleHint =>
      'MinIO / R2 / S3-compatible usually recommended';

  @override
  String get save => 'Save';

  @override
  String get selectIcon => 'Select Icon';

  @override
  String get selectLocalZipRestore => 'Select local zip backup file to restore';

  @override
  String get startBackup => 'Start Backup';

  @override
  String get startMerge => 'Start Merge';

  @override
  String get startRestore => 'Start Restore';

  @override
  String get storage => 'Storage';

  @override
  String get storageSpace => 'Storage Space';

  @override
  String get syncZoteroLibrary => 'Sync Zotero Library';

  @override
  String get thumbnailsAndTemp => 'Thumbnails, temp files, etc';

  @override
  String get unnamed => 'Unnamed';

  @override
  String uploadBackupTo(String target) {
    return 'Upload full backup to $target';
  }

  @override
  String get usePathStyle => 'Use path-style URL';

  @override
  String viewLibraryTotal(int count) {
    return 'Library · $count items';
  }

  @override
  String get webDavConfig => 'WebDAV Configuration';

  @override
  String get webDavServerAddress => 'WebDAV server address';

  @override
  String get year => 'Year';

  @override
  String get zoteroImportHint =>
      'Import documents from Zotero personal library';

  @override
  String zoteroImportedPull(int count) {
    return 'Imported $count · Pull new entries';
  }

  @override
  String get zoteroLocalDirectory => 'Choose Zotero data folder';

  @override
  String get zoteroLocalEntryHint =>
      'Import metadata and PDFs from Zotero on this computer';

  @override
  String get zoteroLocalMetadataOnly => 'Metadata only';

  @override
  String get zoteroLocalTitle => 'Local Zotero';

  @override
  String get zoteroResetHint =>
      'Clear import records and re-pull from library (recover deleted entries)';

  @override
  String get zoteroSync => 'Zotero Sync';

  @override
  String get demoBackupHelp =>
      'Manage remote backups, Zotero papers, and local data.';

  @override
  String get demoWidgetTitle => 'Component library';

  @override
  String get demoWidgetHelp =>
      'One paper and graphite language for content, overlays, and feedback.';

  @override
  String get demoOperationDone =>
      'Demo complete. No real data was read or written.';

  @override
  String get demoOperationRunning => 'Running demo…';

  @override
  String get demoArchiveHint =>
      'Sample archive only. This preview does not create or select real files.';

  @override
  String get demoRemoteHelp =>
      'Configure S3 or WebDAV, schedule backups, and back up or restore.';

  @override
  String get demoZoteroHelp =>
      'Import Zotero papers. Local import is available on desktop only.';

  @override
  String get demoLocalHelp =>
      'Export a ZIP backup, or restore and merge an existing archive.';

  @override
  String get demoLocalSource => 'Sample library';

  @override
  String get demoLocalSourceHint =>
      'Preview the import flow with fixtures, without scanning a local Zotero library.';

  @override
  String get demoLocalPapers => '3 sample papers selected';

  @override
  String get demoImport => 'Import samples';

  @override
  String get demoStorageHint => 'The following usage figures are sample data.';

  @override
  String get demoDocuments => 'Document files';

  @override
  String get demoThumbnails => 'Thumbnails';

  @override
  String get demoTemporary => 'Temporary files';

  @override
  String get demoStorageSummary => '896 MB · Sample usage';

  @override
  String get demoConfigured =>
      'Configured for this preview · No remote connection';

  @override
  String get demoTokenHint =>
      'The product opens this address; the preview displays the entry only.';

  @override
  String get demoConfiguration => 'Local configuration preview';

  @override
  String get demoConfigurationHint =>
      'Use sample values to preview the configured state. No real credentials needed.';

  @override
  String get demoFill => 'Fill sample configuration';

  @override
  String get demoInvalidConfig => 'Complete the configuration';

  @override
  String get demoInvalidConfigHint =>
      'Enter an HTTPS address and required fields. The object path is optional.';

  @override
  String get demoResult => 'Demo result';

  @override
  String get demoDialogs => 'Dialogs and panels';

  @override
  String get demoDialogsHelp =>
      'Open an overlay. Escape or Cancel dismisses it; form drafts apply only after confirmation.';

  @override
  String get demoDocumentInfo => 'Document information';

  @override
  String get demoDocumentInfoHelp =>
      'Title, authors, journal, year, DOI, and keywords support selection and copying.';

  @override
  String get demoEditFavoriteHelp =>
      'Choose an icon, edit the name, and preview it. An empty name cannot be saved.';

  @override
  String get demoDeleteFavorite => 'Delete collection';

  @override
  String get demoDeleteHint =>
      'Remove this demo collection only, leaving papers intact. You can undo this action.';

  @override
  String get demoFavoriteSaved => 'Collection updated in this preview';

  @override
  String get demoFavoriteRemoved => 'Demo collection removed';

  @override
  String get demoUndo => 'Undo';

  @override
  String get demoUndoHint => 'Restore the demo collection you just removed.';

  @override
  String get demoFavoriteTitle => 'My collection';

  @override
  String get demoFavoriteMenu => 'Collection actions';

  @override
  String get demoFavoriteCards => 'Collection cards';

  @override
  String get demoFavoriteCardsHelp =>
      'Empty cover for 0 papers; centered for 1; paired for 2; one large and two small for 3; a grid for 4; one large and four small for 5 or more. Right-click, hold the cover, or use More for actions.';

  @override
  String get demoCoverCount => 'Paper count in the first card';

  @override
  String get demoMethodsCollection => 'Research methods';

  @override
  String get demoVisualCollection => 'Visual interaction';

  @override
  String get demoEmptyLibrary => 'This collection is empty';

  @override
  String get demoEmptyLibraryHint =>
      'Add papers and the cover layout will adapt to their count.';

  @override
  String get demoPaperTitle => 'Organizing knowledge for deep reading';

  @override
  String get demoKeywords => 'Keywords';

  @override
  String get demoKeywordValues =>
      'Deep reading, knowledge organization, interaction design';

  @override
  String get demoCopied => 'Copied to clipboard';

  @override
  String get demoCopyFailed =>
      'Could not copy. Select the text and copy it manually.';

  @override
  String get demoDocumentActions => 'Document action sheet';

  @override
  String get demoSheetHelp =>
      'A scrollable sheet with a drag handle and safe-area padding, without blur.';

  @override
  String get demoAddFavorite => 'Add to collection';

  @override
  String get demoExportCitation => 'Export citation';

  @override
  String get demoFeedback => 'Feedback and notices';

  @override
  String get demoFeedbackHelp =>
      'Use transient snackbars for results, progress for tasks, and inline alerts for issues requiring action.';

  @override
  String get demoResultSnack => 'Result snackbar';

  @override
  String get demoErrorSnack => 'Error and retry';

  @override
  String get demoProgressSnack => 'Single task';

  @override
  String get demoAggregateSnack => 'Multiple tasks';

  @override
  String get demoResultMessage => 'Demo settings updated';

  @override
  String get demoNetworkError => 'Demo connection interrupted. You can retry.';

  @override
  String get demoRetry => 'Retry';

  @override
  String get demoRetryReady =>
      'Demo retry complete. No network request was sent.';

  @override
  String get demoTaskCanceled => 'Demo task canceled';

  @override
  String get demoAlertTitle => 'Backup cannot continue';

  @override
  String get demoAlertMessage =>
      'This is a connection-failure example. Your configuration and content are preserved. Check the address and retry.';

  @override
  String get demoAlertResolved => 'Demo issue resolved';

  @override
  String get demoResetExample => 'Reset example';

  @override
  String get demoBasicControls => 'Selection and actions';

  @override
  String get demoBasicControlsHelp =>
      'Choices, switches, and buttons share consistent borders, focus, and target sizes.';

  @override
  String get demoNotifications => 'Task notifications';

  @override
  String get demoNotificationsHelp =>
      'Show a result when a task ends. This switch previews its state only.';

  @override
  String get demoSort => 'Sort papers';

  @override
  String get demoRecent => 'Recently added';

  @override
  String get demoSortTitle => 'Title';

  @override
  String get demoFileTypes => 'File types';

  @override
  String get demoFileTypesHelp => 'Select multiple file types.';

  @override
  String get demoPrimaryAction => 'Primary action';

  @override
  String get demoSecondaryAction => 'Secondary action';

  @override
  String get demoTextAction => 'Text action';

  @override
  String get demoDisabledAction => 'Unavailable';

  @override
  String get demoUsage => 'Usage and progress';

  @override
  String get demoUsageHelp =>
      'Keep over-quota values visible while clamping the progress bar to 0–100%. Label local estimates.';

  @override
  String get demoQuota => 'Sample usage ratio';

  @override
  String get demoQuotaHelp => 'Drag above 1.0 to preview the over-quota state.';

  @override
  String get demoEstimatedUsage => 'Local estimate';

  @override
  String get demoOverQuota => 'Usage exceeds quota';

  @override
  String get demoOverQuotaHint =>
      'The full value stays visible; the progress bar remains inside its track.';

  @override
  String get demoIconBook => 'Book';

  @override
  String get demoIconScience => 'Science';

  @override
  String get demoIconSchool => 'Academic';

  @override
  String get demoIconFolder => 'Folder';

  @override
  String get demoIconStar => 'Star';

  @override
  String get demoIconReading => 'Reading';

  @override
  String get demoIconGroupReading => 'Reading and study';

  @override
  String get demoIconGroupMark => 'Organize and mark';

  @override
  String get demoIconGroupIdea => 'Ideas and themes';

  @override
  String get demoIconBookmark => 'Bookmark';

  @override
  String get demoIconHeart => 'Heart';

  @override
  String get demoIconIdea => 'Idea';

  @override
  String get demoIconPalette => 'Palette';

  @override
  String get demoIconMusic => 'Music';

  @override
  String get demoIconExplore => 'Explore';

  @override
  String get demoNameRequired => 'Enter a collection name';

  @override
  String get demoLivePreview => 'Live preview';

  @override
  String demoPaperCount(int count) {
    return '$count papers';
  }

  @override
  String demoTasks(int count) {
    return '$count demo tasks running';
  }

  @override
  String demoCopyField(String field) {
    return 'Copy $field';
  }

  @override
  String get demoSelection => 'Segmented selection';

  @override
  String get demoSelectionHelp =>
      'Fixed choices share one equal-width single-selection control. Fill and a check mark indicate selection. Narrow layouts stack the segments to keep every option visible.';

  @override
  String get generalLogLevel => 'Minimum log level';

  @override
  String get demoLogInfo => 'Info';

  @override
  String get demoLogWarning => 'Warning';

  @override
  String get demoLogError => 'Error';

  @override
  String get appearanceTitle => 'Appearance, in context';

  @override
  String get appearanceHelp =>
      'Compare app brightness and reading paper in graphite with system sans. Each device keeps independent preview settings.';

  @override
  String get appearanceScope =>
      'APPEARANCE LAB / Content and reading samples · Product navigation unchanged';

  @override
  String get appearanceMode => 'App brightness';

  @override
  String get appearanceModeHelp =>
      'System follows the browser’s color preference. A pinned reading paper stays unchanged.';

  @override
  String get appearanceSystem => 'Auto';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get appearancePaper => 'Reading paper';

  @override
  String get appearancePaperHelp =>
      'Controls the reading area only. Pinned white, sepia, green, night, or black paper stays fixed when the app changes brightness.';

  @override
  String get appearanceFollow => 'Follow app';

  @override
  String get appearanceWhite => 'White';

  @override
  String get appearanceSepia => 'Sepia';

  @override
  String get appearancePaleGreen => 'Pale green';

  @override
  String get appearanceNight => 'Night';

  @override
  String get appearanceBlack => 'Black';

  @override
  String get appearanceFollowing => 'Reading paper follows app brightness';

  @override
  String get appearancePinned => 'Reading paper is pinned independently';

  @override
  String get appearanceComponents => 'Controls & feedback';

  @override
  String get appearanceComponentsHelp =>
      'Check focus, disabled controls, dialogs, scrims, snackbars, and errors. Brightness and font changes preserve your draft.';

  @override
  String get appearanceDraft => 'Reading note';

  @override
  String get appearanceDraftHint => 'Type, then change the theme';

  @override
  String get appearanceShowSnack => 'Show snackbar';

  @override
  String get appearanceSnack =>
      'Preview notification; your reading position is preserved';

  @override
  String get appearanceShowError => 'Error example';

  @override
  String get appearanceDisabled => 'Unavailable';

  @override
  String get appearanceErrorTitle => 'Connection error sample';

  @override
  String get appearanceErrorMessage =>
      'A simulated error. Your note and appearance choices are preserved.';

  @override
  String get appearanceRetryDone => 'Error preview recovered';

  @override
  String get appearanceReader => 'Reading preview';

  @override
  String get appearanceReaderHelp =>
      'Markdown previews themed text. PDF uses an illustrative fixed layout with original page and figure colors. Neither is a real document.';

  @override
  String get appearanceOriginal => 'PDF / Original-page sample';

  @override
  String get appearanceReadingPreview => 'TEXT / Translation & figures';

  @override
  String get appearancePdfNote =>
      'Illustrative layout: page and figures keep their original colors; the surrounding canvas follows reading paper.';

  @override
  String get appearanceMarkdownNote =>
      'Text follows reading paper; figures keep original colors. Scroll the reading area independently.';

  @override
  String get appearanceContrast => 'Live contrast';

  @override
  String get appearanceContrastHelp =>
      'Computed from current foreground and background colors, with a 4.5:1 text threshold. These three pairs do not constitute a full accessibility audit. PDF pages keep their original colors.';

  @override
  String get appearanceUiText => 'UI text';

  @override
  String get appearanceReadingText => 'Reading text';

  @override
  String get appearanceLink => 'Reading link';

  @override
  String get appearancePass => 'Pass';

  @override
  String get appearanceFail => 'Adjust';

  @override
  String get appearanceArticleKicker => 'READING NOTES / 01';

  @override
  String get appearanceArticleTitle => 'Room to think between the lines';

  @override
  String get appearanceArticleByline =>
      'Lin Zhou · Notes on reading & cognition · 2026';

  @override
  String get appearanceArticleIntro =>
      'Reading a paper means moving between text, figures, and our own ideas. The interface should make these transitions quiet enough for attention to remain on the content.';

  @override
  String get appearanceArticleHeading =>
      '01  Clear hierarchy, considered color';

  @override
  String get appearanceArticleBody =>
      'Type size, spacing, and contrast establish a clear hierarchy. Links should be discoverable and selections unmistakable, while the paper remains steady through color changes. This order should carry into the night.';

  @override
  String get appearanceQuote =>
      'A considered reading environment lets the content hold our attention.';

  @override
  String get appearanceFigureTitle => 'Figure 1 / Reading activities (sample)';

  @override
  String get appearanceFigureA => 'Reading text';

  @override
  String get appearanceFigureB => 'Exploring figures';

  @override
  String get appearanceFigureC => 'Taking notes';

  @override
  String get appearanceFigureCaption =>
      'Illustrative data. Figure colors remain unchanged on every reading paper.';

  @override
  String get appearanceArticleEnd =>
      'When we return, the chosen paper, the note we typed, and the paragraph we were reading should still be there.';

  @override
  String get appearanceReference => 'View sample reference ↗';

  @override
  String get appearanceSample => 'Sample document';

  @override
  String get appearanceSampleHelp =>
      'The document, author, and chart are fictional content for appearance validation. No external services are connected.';

  @override
  String get displaySettings => 'Display settings';

  @override
  String get interfaceFont => 'Interface font';

  @override
  String get interfaceFontHelp =>
      'System sans is the default; serif is optional. Applies to this preview without downloading fonts.';

  @override
  String get fontSans => 'Sans';

  @override
  String get fontSerif => 'Serif';
}
