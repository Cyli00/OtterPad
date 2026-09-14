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

  /// No description provided for @aiSettings.
  ///
  /// In en, this message translates to:
  /// **'AI settings'**
  String get aiSettings;

  /// No description provided for @subtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure model connections, translation preferences, and summary images.'**
  String get subtitle;

  /// No description provided for @demoNote.
  ///
  /// In en, this message translates to:
  /// **'Interactive preview · Changes stay on this page'**
  String get demoNote;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Toggle light and dark'**
  String get darkMode;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Switch language'**
  String get language;

  /// No description provided for @fontScale.
  ///
  /// In en, this message translates to:
  /// **'Adjust text size'**
  String get fontScale;

  /// No description provided for @reduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// No description provided for @modelApi.
  ///
  /// In en, this message translates to:
  /// **'Model connections'**
  String get modelApi;

  /// No description provided for @modelApiHelp.
  ///
  /// In en, this message translates to:
  /// **'Connect a provider for reading, translation and images.'**
  String get modelApiHelp;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @providerHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the service that hosts your models.'**
  String get providerHint;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKey;

  /// No description provided for @getApiKey.
  ///
  /// In en, this message translates to:
  /// **'Get API key'**
  String get getApiKey;

  /// No description provided for @apiKeyActionMessage.
  ///
  /// In en, this message translates to:
  /// **'This preview does not connect to providers. Get an API key from the provider console.'**
  String get apiKeyActionMessage;

  /// No description provided for @keyHint.
  ///
  /// In en, this message translates to:
  /// **'No real key is needed. Input stays in this preview.'**
  String get keyHint;

  /// No description provided for @keyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter a demo key'**
  String get keyPlaceholder;

  /// No description provided for @showKey.
  ///
  /// In en, this message translates to:
  /// **'Show API key'**
  String get showKey;

  /// No description provided for @hideKey.
  ///
  /// In en, this message translates to:
  /// **'Hide API key'**
  String get hideKey;

  /// No description provided for @endpoint.
  ///
  /// In en, this message translates to:
  /// **'API address'**
  String get endpoint;

  /// No description provided for @endpointHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the base address for the API.'**
  String get endpointHint;

  /// No description provided for @endpointError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid HTTPS address.'**
  String get endpointError;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// No description provided for @modelHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a model and inspect its capabilities. Fetch models loads a local demo catalog without contacting a provider.'**
  String get modelHint;

  /// No description provided for @vision.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get vision;

  /// No description provided for @tools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tools;

  /// No description provided for @reasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get reasoning;

  /// No description provided for @roles.
  ///
  /// In en, this message translates to:
  /// **'Global model roles'**
  String get roles;

  /// No description provided for @expert.
  ///
  /// In en, this message translates to:
  /// **'Expert model'**
  String get expert;

  /// No description provided for @expertHint.
  ///
  /// In en, this message translates to:
  /// **'For careful reasoning, complex analysis and detailed answers.'**
  String get expertHint;

  /// No description provided for @fast.
  ///
  /// In en, this message translates to:
  /// **'Fast model'**
  String get fast;

  /// No description provided for @fastHint.
  ///
  /// In en, this message translates to:
  /// **'For everyday questions and quick responses.'**
  String get fastHint;

  /// No description provided for @imageModel.
  ///
  /// In en, this message translates to:
  /// **'Image model'**
  String get imageModel;

  /// No description provided for @imageModelHint.
  ///
  /// In en, this message translates to:
  /// **'For creating illustrated paper summaries.'**
  String get imageModelHint;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Web search'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Give the reading assistant access to web sources.'**
  String get searchHint;

  /// No description provided for @searchKey.
  ///
  /// In en, this message translates to:
  /// **'Search API key'**
  String get searchKey;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Not assigned'**
  String get clear;

  /// No description provided for @translation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translation;

  /// No description provided for @translationHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose how translations read and appear.'**
  String get translationHelp;

  /// No description provided for @targetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get targetLanguage;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get simplifiedChinese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @japanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get japanese;

  /// No description provided for @korean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get korean;

  /// No description provided for @french.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// No description provided for @styles.
  ///
  /// In en, this message translates to:
  /// **'Translation style'**
  String get styles;

  /// No description provided for @styleHint.
  ///
  /// In en, this message translates to:
  /// **'Choose one translation style at a time.'**
  String get styleHint;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get normal;

  /// No description provided for @accent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get accent;

  /// No description provided for @bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// No description provided for @italic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italic;

  /// No description provided for @muted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get muted;

  /// No description provided for @underline.
  ///
  /// In en, this message translates to:
  /// **'Dashed underline'**
  String get underline;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @blur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get blur;

  /// No description provided for @quote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get quote;

  /// No description provided for @ignore.
  ///
  /// In en, this message translates to:
  /// **'Exclude from translation'**
  String get ignore;

  /// No description provided for @references.
  ///
  /// In en, this message translates to:
  /// **'References'**
  String get references;

  /// No description provided for @acknowledgments.
  ///
  /// In en, this message translates to:
  /// **'Acknowledgments'**
  String get acknowledgments;

  /// No description provided for @contributions.
  ///
  /// In en, this message translates to:
  /// **'Contributions / competing interests'**
  String get contributions;

  /// No description provided for @funding.
  ///
  /// In en, this message translates to:
  /// **'Funding / data statements'**
  String get funding;

  /// No description provided for @supplement.
  ///
  /// In en, this message translates to:
  /// **'Appendices / supplements'**
  String get supplement;

  /// No description provided for @ethics.
  ///
  /// In en, this message translates to:
  /// **'Ethics / figure captions'**
  String get ethics;

  /// No description provided for @ignoreHint.
  ///
  /// In en, this message translates to:
  /// **'Selected sections are excluded from translation.'**
  String get ignoreHint;

  /// No description provided for @temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// No description provided for @temperatureHelp.
  ///
  /// In en, this message translates to:
  /// **'Steps of 0.05. Lower values are steadier; higher values allow more variation.'**
  String get temperatureHelp;

  /// No description provided for @resetTemperature.
  ///
  /// In en, this message translates to:
  /// **'Reset temperature'**
  String get resetTemperature;

  /// No description provided for @systemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get systemPrompt;

  /// No description provided for @userPrompt.
  ///
  /// In en, this message translates to:
  /// **'User prompt'**
  String get userPrompt;

  /// No description provided for @promptHint.
  ///
  /// In en, this message translates to:
  /// **'Keep template variables intact while editing the instructions.'**
  String get promptHint;

  /// No description provided for @promptError.
  ///
  /// In en, this message translates to:
  /// **'Keep both text and targetLanguage variables. This draft is not active.'**
  String get promptError;

  /// No description provided for @resetPrompt.
  ///
  /// In en, this message translates to:
  /// **'Restore the default prompt'**
  String get resetPrompt;

  /// No description provided for @imageSettings.
  ///
  /// In en, this message translates to:
  /// **'Image generation'**
  String get imageSettings;

  /// No description provided for @imageHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose the proportions, quality and references for summary images.'**
  String get imageHelp;

  /// No description provided for @aspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get aspectRatio;

  /// No description provided for @aspectHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the proportions of the generated image.'**
  String get aspectHint;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Image quality'**
  String get quality;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get auto;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @referenceImages.
  ///
  /// In en, this message translates to:
  /// **'Reference images'**
  String get referenceImages;

  /// No description provided for @referenceImagesHelp.
  ///
  /// In en, this message translates to:
  /// **'Use 1–10 paper figures as references. The default is 10.'**
  String get referenceImagesHelp;

  /// No description provided for @resetReferences.
  ///
  /// In en, this message translates to:
  /// **'Reset reference image count'**
  String get resetReferences;

  /// No description provided for @imagePrompt.
  ///
  /// In en, this message translates to:
  /// **'Summary image prompt'**
  String get imagePrompt;

  /// No description provided for @imagePromptHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the focus, structure and style of the image.'**
  String get imagePromptHint;

  /// No description provided for @fetchModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch models'**
  String get fetchModels;

  /// No description provided for @retryModels.
  ///
  /// In en, this message translates to:
  /// **'Retry fetch'**
  String get retryModels;

  /// No description provided for @fetchingModels.
  ///
  /// In en, this message translates to:
  /// **'Loading demo models…'**
  String get fetchingModels;

  /// No description provided for @modelsFetched.
  ///
  /// In en, this message translates to:
  /// **'Fetched {count} demo models'**
  String modelsFetched(int count);

  /// No description provided for @modelsDemoHint.
  ///
  /// In en, this message translates to:
  /// **'Local demo catalog · No network request'**
  String get modelsDemoHint;

  /// No description provided for @fetchModelsError.
  ///
  /// In en, this message translates to:
  /// **'Could not fetch models. Correct the API endpoint, then retry.'**
  String get fetchModelsError;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @author.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// No description provided for @autoBackup.
  ///
  /// In en, this message translates to:
  /// **'Auto Backup'**
  String get autoBackup;

  /// No description provided for @autoBackupDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get autoBackupDaily;

  /// No description provided for @autoBackupHint.
  ///
  /// In en, this message translates to:
  /// **'Backs up to the remote in the background when due, only if content has changed'**
  String get autoBackupHint;

  /// No description provided for @autoBackupOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get autoBackupOff;

  /// No description provided for @autoBackupWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get autoBackupWeekly;

  /// No description provided for @backupMethod.
  ///
  /// In en, this message translates to:
  /// **'Backup Method'**
  String get backupMethod;

  /// No description provided for @backupScopeData.
  ///
  /// In en, this message translates to:
  /// **'Data only'**
  String get backupScopeData;

  /// No description provided for @backupScopeDataDesc.
  ///
  /// In en, this message translates to:
  /// **'Settings, metadata, highlights, translations and chats; excludes PDFs and extracted files'**
  String get backupScopeDataDesc;

  /// No description provided for @backupScopeFull.
  ///
  /// In en, this message translates to:
  /// **'Full backup'**
  String get backupScopeFull;

  /// No description provided for @backupScopeFullDesc.
  ///
  /// In en, this message translates to:
  /// **'Includes PDFs and extracted files; archive can be large'**
  String get backupScopeFullDesc;

  /// No description provided for @backupScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup Scope'**
  String get backupScopeTitle;

  /// No description provided for @backupTo.
  ///
  /// In en, this message translates to:
  /// **'Backup to {target}'**
  String backupTo(String target);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @clearField.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearField;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @dataManagement.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get dataManagement;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @downloadAndRestore.
  ///
  /// In en, this message translates to:
  /// **'Download from {target} and restore'**
  String downloadAndRestore(String target);

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editFavorite.
  ///
  /// In en, this message translates to:
  /// **'Edit Favorite'**
  String get editFavorite;

  /// No description provided for @enterFavoriteName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get enterFavoriteName;

  /// No description provided for @exportBackup.
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get exportBackup;

  /// No description provided for @favoriteName.
  ///
  /// In en, this message translates to:
  /// **'Favorite name'**
  String get favoriteName;

  /// No description provided for @fullResync.
  ///
  /// In en, this message translates to:
  /// **'Full Resync'**
  String get fullResync;

  /// No description provided for @generateZipAndSave.
  ///
  /// In en, this message translates to:
  /// **'Generate zip backup and save locally'**
  String get generateZipAndSave;

  /// No description provided for @getToken.
  ///
  /// In en, this message translates to:
  /// **'Get Token'**
  String get getToken;

  /// No description provided for @journal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journal;

  /// No description provided for @localBackup.
  ///
  /// In en, this message translates to:
  /// **'Local Backup'**
  String get localBackup;

  /// No description provided for @objectPath.
  ///
  /// In en, this message translates to:
  /// **'Object Path'**
  String get objectPath;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @pleaseConfigureFirst.
  ///
  /// In en, this message translates to:
  /// **'Please configure {target} connection first'**
  String pleaseConfigureFirst(String target);

  /// No description provided for @pleaseFillApiKey.
  ///
  /// In en, this message translates to:
  /// **'Please fill in API Key first'**
  String get pleaseFillApiKey;

  /// No description provided for @region.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get region;

  /// No description provided for @reimport.
  ///
  /// In en, this message translates to:
  /// **'Re-import'**
  String get reimport;

  /// No description provided for @remoteBackup.
  ///
  /// In en, this message translates to:
  /// **'Remote Backup'**
  String get remoteBackup;

  /// No description provided for @remoteNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'{target} remote backup not configured'**
  String remoteNotConfigured(String target);

  /// No description provided for @resetZoteroConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will clear local Zotero import records and re-pull from library: deleted entries will reappear, existing ones won\'t duplicate. Continue?'**
  String get resetZoteroConfirm;

  /// No description provided for @resetZoteroSync.
  ///
  /// In en, this message translates to:
  /// **'Reset Zotero Sync'**
  String get resetZoteroSync;

  /// No description provided for @restoreFromBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from Backup'**
  String get restoreFromBackup;

  /// No description provided for @restoreFromRemote.
  ///
  /// In en, this message translates to:
  /// **'Restore from {target}'**
  String restoreFromRemote(String target);

  /// No description provided for @restoreMethod.
  ///
  /// In en, this message translates to:
  /// **'Restore Method'**
  String get restoreMethod;

  /// No description provided for @restoreModeMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get restoreModeMerge;

  /// No description provided for @restoreModeMergeDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep local data and add missing content from the backup'**
  String get restoreModeMergeDescription;

  /// No description provided for @restoreModeOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get restoreModeOverwrite;

  /// No description provided for @restoreModeOverwriteDescription.
  ///
  /// In en, this message translates to:
  /// **'Replace local data with the backup'**
  String get restoreModeOverwriteDescription;

  /// No description provided for @restoreScope.
  ///
  /// In en, this message translates to:
  /// **'Restore Scope'**
  String get restoreScope;

  /// No description provided for @restoreScopeFull.
  ///
  /// In en, this message translates to:
  /// **'Full restore'**
  String get restoreScopeFull;

  /// No description provided for @restoreScopeFullDescription.
  ///
  /// In en, this message translates to:
  /// **'Restore the library and settings'**
  String get restoreScopeFullDescription;

  /// No description provided for @restoreScopeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library only'**
  String get restoreScopeLibrary;

  /// No description provided for @restoreScopeLibraryDescription.
  ///
  /// In en, this message translates to:
  /// **'Restore documents, collections, annotations and document files'**
  String get restoreScopeLibraryDescription;

  /// No description provided for @restoreScopeSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings only'**
  String get restoreScopeSettings;

  /// No description provided for @restoreScopeSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Restore application settings'**
  String get restoreScopeSettingsDescription;

  /// No description provided for @restoreSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Settings'**
  String get restoreSettingsTitle;

  /// No description provided for @s3Config.
  ///
  /// In en, this message translates to:
  /// **'S3 Configuration'**
  String get s3Config;

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

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @selectIcon.
  ///
  /// In en, this message translates to:
  /// **'Select Icon'**
  String get selectIcon;

  /// No description provided for @selectLocalZipRestore.
  ///
  /// In en, this message translates to:
  /// **'Select local zip backup file to restore'**
  String get selectLocalZipRestore;

  /// No description provided for @startBackup.
  ///
  /// In en, this message translates to:
  /// **'Start Backup'**
  String get startBackup;

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

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @storageSpace.
  ///
  /// In en, this message translates to:
  /// **'Storage Space'**
  String get storageSpace;

  /// No description provided for @syncZoteroLibrary.
  ///
  /// In en, this message translates to:
  /// **'Sync Zotero Library'**
  String get syncZoteroLibrary;

  /// No description provided for @thumbnailsAndTemp.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails, temp files, etc'**
  String get thumbnailsAndTemp;

  /// No description provided for @unnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed'**
  String get unnamed;

  /// No description provided for @uploadBackupTo.
  ///
  /// In en, this message translates to:
  /// **'Upload full backup to {target}'**
  String uploadBackupTo(String target);

  /// No description provided for @usePathStyle.
  ///
  /// In en, this message translates to:
  /// **'Use path-style URL'**
  String get usePathStyle;

  /// No description provided for @viewLibraryTotal.
  ///
  /// In en, this message translates to:
  /// **'Library · {count} items'**
  String viewLibraryTotal(int count);

  /// No description provided for @webDavConfig.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Configuration'**
  String get webDavConfig;

  /// No description provided for @webDavServerAddress.
  ///
  /// In en, this message translates to:
  /// **'WebDAV server address'**
  String get webDavServerAddress;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @zoteroImportHint.
  ///
  /// In en, this message translates to:
  /// **'Import documents from Zotero personal library'**
  String get zoteroImportHint;

  /// No description provided for @zoteroImportedPull.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} · Pull new entries'**
  String zoteroImportedPull(int count);

  /// No description provided for @zoteroLocalDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose Zotero data folder'**
  String get zoteroLocalDirectory;

  /// No description provided for @zoteroLocalEntryHint.
  ///
  /// In en, this message translates to:
  /// **'Import metadata and PDFs from Zotero on this computer'**
  String get zoteroLocalEntryHint;

  /// No description provided for @zoteroLocalMetadataOnly.
  ///
  /// In en, this message translates to:
  /// **'Metadata only'**
  String get zoteroLocalMetadataOnly;

  /// No description provided for @zoteroLocalTitle.
  ///
  /// In en, this message translates to:
  /// **'Local Zotero'**
  String get zoteroLocalTitle;

  /// No description provided for @zoteroResetHint.
  ///
  /// In en, this message translates to:
  /// **'Clear import records and re-pull from library (recover deleted entries)'**
  String get zoteroResetHint;

  /// No description provided for @zoteroSync.
  ///
  /// In en, this message translates to:
  /// **'Zotero Sync'**
  String get zoteroSync;

  /// No description provided for @demoBackupHelp.
  ///
  /// In en, this message translates to:
  /// **'Manage remote backups, Zotero papers, and local data.'**
  String get demoBackupHelp;

  /// No description provided for @demoWidgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Component library'**
  String get demoWidgetTitle;

  /// No description provided for @demoWidgetHelp.
  ///
  /// In en, this message translates to:
  /// **'One paper and graphite language for content, overlays, and feedback.'**
  String get demoWidgetHelp;

  /// No description provided for @demoOperationDone.
  ///
  /// In en, this message translates to:
  /// **'Demo complete. No real data was read or written.'**
  String get demoOperationDone;

  /// No description provided for @demoOperationRunning.
  ///
  /// In en, this message translates to:
  /// **'Running demo…'**
  String get demoOperationRunning;

  /// No description provided for @demoArchiveHint.
  ///
  /// In en, this message translates to:
  /// **'Sample archive only. This preview does not create or select real files.'**
  String get demoArchiveHint;

  /// No description provided for @demoRemoteHelp.
  ///
  /// In en, this message translates to:
  /// **'Configure S3 or WebDAV, schedule backups, and back up or restore.'**
  String get demoRemoteHelp;

  /// No description provided for @demoZoteroHelp.
  ///
  /// In en, this message translates to:
  /// **'Import Zotero papers. Local import is available on desktop only.'**
  String get demoZoteroHelp;

  /// No description provided for @demoLocalHelp.
  ///
  /// In en, this message translates to:
  /// **'Export a ZIP backup, or restore and merge an existing archive.'**
  String get demoLocalHelp;

  /// No description provided for @demoLocalSource.
  ///
  /// In en, this message translates to:
  /// **'Sample library'**
  String get demoLocalSource;

  /// No description provided for @demoLocalSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Preview the import flow with fixtures, without scanning a local Zotero library.'**
  String get demoLocalSourceHint;

  /// No description provided for @demoLocalPapers.
  ///
  /// In en, this message translates to:
  /// **'3 sample papers selected'**
  String get demoLocalPapers;

  /// No description provided for @demoImport.
  ///
  /// In en, this message translates to:
  /// **'Import samples'**
  String get demoImport;

  /// No description provided for @demoStorageHint.
  ///
  /// In en, this message translates to:
  /// **'The following usage figures are sample data.'**
  String get demoStorageHint;

  /// No description provided for @demoDocuments.
  ///
  /// In en, this message translates to:
  /// **'Document files'**
  String get demoDocuments;

  /// No description provided for @demoThumbnails.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails'**
  String get demoThumbnails;

  /// No description provided for @demoTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporary files'**
  String get demoTemporary;

  /// No description provided for @demoStorageSummary.
  ///
  /// In en, this message translates to:
  /// **'896 MB · Sample usage'**
  String get demoStorageSummary;

  /// No description provided for @demoConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured for this preview · No remote connection'**
  String get demoConfigured;

  /// No description provided for @demoTokenHint.
  ///
  /// In en, this message translates to:
  /// **'The product opens this address; the preview displays the entry only.'**
  String get demoTokenHint;

  /// No description provided for @demoConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Local configuration preview'**
  String get demoConfiguration;

  /// No description provided for @demoConfigurationHint.
  ///
  /// In en, this message translates to:
  /// **'Use sample values to preview the configured state. No real credentials needed.'**
  String get demoConfigurationHint;

  /// No description provided for @demoFill.
  ///
  /// In en, this message translates to:
  /// **'Fill sample configuration'**
  String get demoFill;

  /// No description provided for @demoInvalidConfig.
  ///
  /// In en, this message translates to:
  /// **'Complete the configuration'**
  String get demoInvalidConfig;

  /// No description provided for @demoInvalidConfigHint.
  ///
  /// In en, this message translates to:
  /// **'Enter an HTTPS address and required fields. The object path is optional.'**
  String get demoInvalidConfigHint;

  /// No description provided for @demoResult.
  ///
  /// In en, this message translates to:
  /// **'Demo result'**
  String get demoResult;

  /// No description provided for @demoDialogs.
  ///
  /// In en, this message translates to:
  /// **'Dialogs and panels'**
  String get demoDialogs;

  /// No description provided for @demoDialogsHelp.
  ///
  /// In en, this message translates to:
  /// **'Open an overlay. Escape or Cancel dismisses it; form drafts apply only after confirmation.'**
  String get demoDialogsHelp;

  /// No description provided for @demoDocumentInfo.
  ///
  /// In en, this message translates to:
  /// **'Document information'**
  String get demoDocumentInfo;

  /// No description provided for @demoDocumentInfoHelp.
  ///
  /// In en, this message translates to:
  /// **'Title, authors, journal, year, DOI, and keywords support selection and copying.'**
  String get demoDocumentInfoHelp;

  /// No description provided for @demoEditFavoriteHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose an icon, edit the name, and preview it. An empty name cannot be saved.'**
  String get demoEditFavoriteHelp;

  /// No description provided for @demoDeleteFavorite.
  ///
  /// In en, this message translates to:
  /// **'Delete collection'**
  String get demoDeleteFavorite;

  /// No description provided for @demoDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'Remove this demo collection only, leaving papers intact. You can undo this action.'**
  String get demoDeleteHint;

  /// No description provided for @demoFavoriteSaved.
  ///
  /// In en, this message translates to:
  /// **'Collection updated in this preview'**
  String get demoFavoriteSaved;

  /// No description provided for @demoFavoriteRemoved.
  ///
  /// In en, this message translates to:
  /// **'Demo collection removed'**
  String get demoFavoriteRemoved;

  /// No description provided for @demoUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get demoUndo;

  /// No description provided for @demoUndoHint.
  ///
  /// In en, this message translates to:
  /// **'Restore the demo collection you just removed.'**
  String get demoUndoHint;

  /// No description provided for @demoFavoriteTitle.
  ///
  /// In en, this message translates to:
  /// **'My collection'**
  String get demoFavoriteTitle;

  /// No description provided for @demoFavoriteMenu.
  ///
  /// In en, this message translates to:
  /// **'Collection actions'**
  String get demoFavoriteMenu;

  /// No description provided for @demoFavoriteCards.
  ///
  /// In en, this message translates to:
  /// **'Collection cards'**
  String get demoFavoriteCards;

  /// No description provided for @demoFavoriteCardsHelp.
  ///
  /// In en, this message translates to:
  /// **'Empty cover for 0 papers; centered for 1; paired for 2; one large and two small for 3; a grid for 4; one large and four small for 5 or more. Right-click, hold the cover, or use More for actions.'**
  String get demoFavoriteCardsHelp;

  /// No description provided for @demoCoverCount.
  ///
  /// In en, this message translates to:
  /// **'Paper count in the first card'**
  String get demoCoverCount;

  /// No description provided for @demoMethodsCollection.
  ///
  /// In en, this message translates to:
  /// **'Research methods'**
  String get demoMethodsCollection;

  /// No description provided for @demoVisualCollection.
  ///
  /// In en, this message translates to:
  /// **'Visual interaction'**
  String get demoVisualCollection;

  /// No description provided for @demoEmptyLibrary.
  ///
  /// In en, this message translates to:
  /// **'This collection is empty'**
  String get demoEmptyLibrary;

  /// No description provided for @demoEmptyLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'Add papers and the cover layout will adapt to their count.'**
  String get demoEmptyLibraryHint;

  /// No description provided for @demoPaperTitle.
  ///
  /// In en, this message translates to:
  /// **'Organizing knowledge for deep reading'**
  String get demoPaperTitle;

  /// No description provided for @demoKeywords.
  ///
  /// In en, this message translates to:
  /// **'Keywords'**
  String get demoKeywords;

  /// No description provided for @demoKeywordValues.
  ///
  /// In en, this message translates to:
  /// **'Deep reading, knowledge organization, interaction design'**
  String get demoKeywordValues;

  /// No description provided for @demoCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get demoCopied;

  /// No description provided for @demoCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy. Select the text and copy it manually.'**
  String get demoCopyFailed;

  /// No description provided for @demoDocumentActions.
  ///
  /// In en, this message translates to:
  /// **'Document action sheet'**
  String get demoDocumentActions;

  /// No description provided for @demoSheetHelp.
  ///
  /// In en, this message translates to:
  /// **'A scrollable sheet with a drag handle and safe-area padding, without blur.'**
  String get demoSheetHelp;

  /// No description provided for @demoAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to collection'**
  String get demoAddFavorite;

  /// No description provided for @demoExportCitation.
  ///
  /// In en, this message translates to:
  /// **'Export citation'**
  String get demoExportCitation;

  /// No description provided for @demoFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback and notices'**
  String get demoFeedback;

  /// No description provided for @demoFeedbackHelp.
  ///
  /// In en, this message translates to:
  /// **'Use transient snackbars for results, progress for tasks, and inline alerts for issues requiring action.'**
  String get demoFeedbackHelp;

  /// No description provided for @demoResultSnack.
  ///
  /// In en, this message translates to:
  /// **'Result snackbar'**
  String get demoResultSnack;

  /// No description provided for @demoErrorSnack.
  ///
  /// In en, this message translates to:
  /// **'Error and retry'**
  String get demoErrorSnack;

  /// No description provided for @demoProgressSnack.
  ///
  /// In en, this message translates to:
  /// **'Single task'**
  String get demoProgressSnack;

  /// No description provided for @demoAggregateSnack.
  ///
  /// In en, this message translates to:
  /// **'Multiple tasks'**
  String get demoAggregateSnack;

  /// No description provided for @demoResultMessage.
  ///
  /// In en, this message translates to:
  /// **'Demo settings updated'**
  String get demoResultMessage;

  /// No description provided for @demoNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Demo connection interrupted. You can retry.'**
  String get demoNetworkError;

  /// No description provided for @demoRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get demoRetry;

  /// No description provided for @demoRetryReady.
  ///
  /// In en, this message translates to:
  /// **'Demo retry complete. No network request was sent.'**
  String get demoRetryReady;

  /// No description provided for @demoTaskCanceled.
  ///
  /// In en, this message translates to:
  /// **'Demo task canceled'**
  String get demoTaskCanceled;

  /// No description provided for @demoAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup cannot continue'**
  String get demoAlertTitle;

  /// No description provided for @demoAlertMessage.
  ///
  /// In en, this message translates to:
  /// **'This is a connection-failure example. Your configuration and content are preserved. Check the address and retry.'**
  String get demoAlertMessage;

  /// No description provided for @demoAlertResolved.
  ///
  /// In en, this message translates to:
  /// **'Demo issue resolved'**
  String get demoAlertResolved;

  /// No description provided for @demoResetExample.
  ///
  /// In en, this message translates to:
  /// **'Reset example'**
  String get demoResetExample;

  /// No description provided for @demoBasicControls.
  ///
  /// In en, this message translates to:
  /// **'Selection and actions'**
  String get demoBasicControls;

  /// No description provided for @demoBasicControlsHelp.
  ///
  /// In en, this message translates to:
  /// **'Choices, switches, and buttons share consistent borders, focus, and target sizes.'**
  String get demoBasicControlsHelp;

  /// No description provided for @demoNotifications.
  ///
  /// In en, this message translates to:
  /// **'Task notifications'**
  String get demoNotifications;

  /// No description provided for @demoNotificationsHelp.
  ///
  /// In en, this message translates to:
  /// **'Show a result when a task ends. This switch previews its state only.'**
  String get demoNotificationsHelp;

  /// No description provided for @demoSort.
  ///
  /// In en, this message translates to:
  /// **'Sort papers'**
  String get demoSort;

  /// No description provided for @demoRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get demoRecent;

  /// No description provided for @demoSortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get demoSortTitle;

  /// No description provided for @demoFileTypes.
  ///
  /// In en, this message translates to:
  /// **'File types'**
  String get demoFileTypes;

  /// No description provided for @demoFileTypesHelp.
  ///
  /// In en, this message translates to:
  /// **'Select multiple file types.'**
  String get demoFileTypesHelp;

  /// No description provided for @demoPrimaryAction.
  ///
  /// In en, this message translates to:
  /// **'Primary action'**
  String get demoPrimaryAction;

  /// No description provided for @demoSecondaryAction.
  ///
  /// In en, this message translates to:
  /// **'Secondary action'**
  String get demoSecondaryAction;

  /// No description provided for @demoTextAction.
  ///
  /// In en, this message translates to:
  /// **'Text action'**
  String get demoTextAction;

  /// No description provided for @demoDisabledAction.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get demoDisabledAction;

  /// No description provided for @demoUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage and progress'**
  String get demoUsage;

  /// No description provided for @demoUsageHelp.
  ///
  /// In en, this message translates to:
  /// **'Keep over-quota values visible while clamping the progress bar to 0–100%. Label local estimates.'**
  String get demoUsageHelp;

  /// No description provided for @demoQuota.
  ///
  /// In en, this message translates to:
  /// **'Sample usage ratio'**
  String get demoQuota;

  /// No description provided for @demoQuotaHelp.
  ///
  /// In en, this message translates to:
  /// **'Drag above 1.0 to preview the over-quota state.'**
  String get demoQuotaHelp;

  /// No description provided for @demoEstimatedUsage.
  ///
  /// In en, this message translates to:
  /// **'Local estimate'**
  String get demoEstimatedUsage;

  /// No description provided for @demoOverQuota.
  ///
  /// In en, this message translates to:
  /// **'Usage exceeds quota'**
  String get demoOverQuota;

  /// No description provided for @demoOverQuotaHint.
  ///
  /// In en, this message translates to:
  /// **'The full value stays visible; the progress bar remains inside its track.'**
  String get demoOverQuotaHint;

  /// No description provided for @demoIconBook.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get demoIconBook;

  /// No description provided for @demoIconScience.
  ///
  /// In en, this message translates to:
  /// **'Science'**
  String get demoIconScience;

  /// No description provided for @demoIconSchool.
  ///
  /// In en, this message translates to:
  /// **'Academic'**
  String get demoIconSchool;

  /// No description provided for @demoIconFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get demoIconFolder;

  /// No description provided for @demoIconStar.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get demoIconStar;

  /// No description provided for @demoIconReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get demoIconReading;

  /// No description provided for @demoIconGroupReading.
  ///
  /// In en, this message translates to:
  /// **'Reading and study'**
  String get demoIconGroupReading;

  /// No description provided for @demoIconGroupMark.
  ///
  /// In en, this message translates to:
  /// **'Organize and mark'**
  String get demoIconGroupMark;

  /// No description provided for @demoIconGroupIdea.
  ///
  /// In en, this message translates to:
  /// **'Ideas and themes'**
  String get demoIconGroupIdea;

  /// No description provided for @demoIconBookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get demoIconBookmark;

  /// No description provided for @demoIconHeart.
  ///
  /// In en, this message translates to:
  /// **'Heart'**
  String get demoIconHeart;

  /// No description provided for @demoIconIdea.
  ///
  /// In en, this message translates to:
  /// **'Idea'**
  String get demoIconIdea;

  /// No description provided for @demoIconPalette.
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get demoIconPalette;

  /// No description provided for @demoIconMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get demoIconMusic;

  /// No description provided for @demoIconExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get demoIconExplore;

  /// No description provided for @demoNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a collection name'**
  String get demoNameRequired;

  /// No description provided for @demoLivePreview.
  ///
  /// In en, this message translates to:
  /// **'Live preview'**
  String get demoLivePreview;

  /// No description provided for @demoPaperCount.
  ///
  /// In en, this message translates to:
  /// **'{count} papers'**
  String demoPaperCount(int count);

  /// No description provided for @demoTasks.
  ///
  /// In en, this message translates to:
  /// **'{count} demo tasks running'**
  String demoTasks(int count);

  /// No description provided for @demoCopyField.
  ///
  /// In en, this message translates to:
  /// **'Copy {field}'**
  String demoCopyField(String field);

  /// No description provided for @demoSelection.
  ///
  /// In en, this message translates to:
  /// **'Segmented selection'**
  String get demoSelection;

  /// No description provided for @demoSelectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Fixed choices share one equal-width single-selection control. Fill and a check mark indicate selection. Narrow layouts stack the segments to keep every option visible.'**
  String get demoSelectionHelp;

  /// No description provided for @generalLogLevel.
  ///
  /// In en, this message translates to:
  /// **'Minimum log level'**
  String get generalLogLevel;

  /// No description provided for @demoLogInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get demoLogInfo;

  /// No description provided for @demoLogWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get demoLogWarning;

  /// No description provided for @demoLogError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get demoLogError;

  /// No description provided for @appearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance, in context'**
  String get appearanceTitle;

  /// No description provided for @appearanceHelp.
  ///
  /// In en, this message translates to:
  /// **'Compare app brightness and reading paper in graphite with system sans. Each device keeps independent preview settings.'**
  String get appearanceHelp;

  /// No description provided for @appearanceScope.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE LAB / Content and reading samples · Product navigation unchanged'**
  String get appearanceScope;

  /// No description provided for @appearanceMode.
  ///
  /// In en, this message translates to:
  /// **'App brightness'**
  String get appearanceMode;

  /// No description provided for @appearanceModeHelp.
  ///
  /// In en, this message translates to:
  /// **'System follows the browser’s color preference. A pinned reading paper stays unchanged.'**
  String get appearanceModeHelp;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDark;

  /// No description provided for @appearancePaper.
  ///
  /// In en, this message translates to:
  /// **'Reading paper'**
  String get appearancePaper;

  /// No description provided for @appearancePaperHelp.
  ///
  /// In en, this message translates to:
  /// **'Controls the reading area only. Pinned white, sepia, green, night, or black paper stays fixed when the app changes brightness.'**
  String get appearancePaperHelp;

  /// No description provided for @appearanceFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow app'**
  String get appearanceFollow;

  /// No description provided for @appearanceWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get appearanceWhite;

  /// No description provided for @appearanceSepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get appearanceSepia;

  /// No description provided for @appearancePaleGreen.
  ///
  /// In en, this message translates to:
  /// **'Pale green'**
  String get appearancePaleGreen;

  /// No description provided for @appearanceNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get appearanceNight;

  /// No description provided for @appearanceBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get appearanceBlack;

  /// No description provided for @appearanceFollowing.
  ///
  /// In en, this message translates to:
  /// **'Reading paper follows app brightness'**
  String get appearanceFollowing;

  /// No description provided for @appearancePinned.
  ///
  /// In en, this message translates to:
  /// **'Reading paper is pinned independently'**
  String get appearancePinned;

  /// No description provided for @appearanceComponents.
  ///
  /// In en, this message translates to:
  /// **'Controls & feedback'**
  String get appearanceComponents;

  /// No description provided for @appearanceComponentsHelp.
  ///
  /// In en, this message translates to:
  /// **'Check focus, disabled controls, dialogs, scrims, snackbars, and errors. Brightness and font changes preserve your draft.'**
  String get appearanceComponentsHelp;

  /// No description provided for @appearanceDraft.
  ///
  /// In en, this message translates to:
  /// **'Reading note'**
  String get appearanceDraft;

  /// No description provided for @appearanceDraftHint.
  ///
  /// In en, this message translates to:
  /// **'Type, then change the theme'**
  String get appearanceDraftHint;

  /// No description provided for @appearanceShowSnack.
  ///
  /// In en, this message translates to:
  /// **'Show snackbar'**
  String get appearanceShowSnack;

  /// No description provided for @appearanceSnack.
  ///
  /// In en, this message translates to:
  /// **'Preview notification; your reading position is preserved'**
  String get appearanceSnack;

  /// No description provided for @appearanceShowError.
  ///
  /// In en, this message translates to:
  /// **'Error example'**
  String get appearanceShowError;

  /// No description provided for @appearanceDisabled.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get appearanceDisabled;

  /// No description provided for @appearanceErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection error sample'**
  String get appearanceErrorTitle;

  /// No description provided for @appearanceErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'A simulated error. Your note and appearance choices are preserved.'**
  String get appearanceErrorMessage;

  /// No description provided for @appearanceRetryDone.
  ///
  /// In en, this message translates to:
  /// **'Error preview recovered'**
  String get appearanceRetryDone;

  /// No description provided for @appearanceReader.
  ///
  /// In en, this message translates to:
  /// **'Reading preview'**
  String get appearanceReader;

  /// No description provided for @appearanceReaderHelp.
  ///
  /// In en, this message translates to:
  /// **'Markdown previews themed text. PDF uses an illustrative fixed layout with original page and figure colors. Neither is a real document.'**
  String get appearanceReaderHelp;

  /// No description provided for @appearanceOriginal.
  ///
  /// In en, this message translates to:
  /// **'PDF / Original-page sample'**
  String get appearanceOriginal;

  /// No description provided for @appearanceReadingPreview.
  ///
  /// In en, this message translates to:
  /// **'TEXT / Translation & figures'**
  String get appearanceReadingPreview;

  /// No description provided for @appearancePdfNote.
  ///
  /// In en, this message translates to:
  /// **'Illustrative layout: page and figures keep their original colors; the surrounding canvas follows reading paper.'**
  String get appearancePdfNote;

  /// No description provided for @appearanceMarkdownNote.
  ///
  /// In en, this message translates to:
  /// **'Text follows reading paper; figures keep original colors. Scroll the reading area independently.'**
  String get appearanceMarkdownNote;

  /// No description provided for @appearanceContrast.
  ///
  /// In en, this message translates to:
  /// **'Live contrast'**
  String get appearanceContrast;

  /// No description provided for @appearanceContrastHelp.
  ///
  /// In en, this message translates to:
  /// **'Computed from current foreground and background colors, with a 4.5:1 text threshold. These three pairs do not constitute a full accessibility audit. PDF pages keep their original colors.'**
  String get appearanceContrastHelp;

  /// No description provided for @appearanceUiText.
  ///
  /// In en, this message translates to:
  /// **'UI text'**
  String get appearanceUiText;

  /// No description provided for @appearanceReadingText.
  ///
  /// In en, this message translates to:
  /// **'Reading text'**
  String get appearanceReadingText;

  /// No description provided for @appearanceLink.
  ///
  /// In en, this message translates to:
  /// **'Reading link'**
  String get appearanceLink;

  /// No description provided for @appearancePass.
  ///
  /// In en, this message translates to:
  /// **'Pass'**
  String get appearancePass;

  /// No description provided for @appearanceFail.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get appearanceFail;

  /// No description provided for @appearanceArticleKicker.
  ///
  /// In en, this message translates to:
  /// **'READING NOTES / 01'**
  String get appearanceArticleKicker;

  /// No description provided for @appearanceArticleTitle.
  ///
  /// In en, this message translates to:
  /// **'Room to think between the lines'**
  String get appearanceArticleTitle;

  /// No description provided for @appearanceArticleByline.
  ///
  /// In en, this message translates to:
  /// **'Lin Zhou · Notes on reading & cognition · 2026'**
  String get appearanceArticleByline;

  /// No description provided for @appearanceArticleIntro.
  ///
  /// In en, this message translates to:
  /// **'Reading a paper means moving between text, figures, and our own ideas. The interface should make these transitions quiet enough for attention to remain on the content.'**
  String get appearanceArticleIntro;

  /// No description provided for @appearanceArticleHeading.
  ///
  /// In en, this message translates to:
  /// **'01  Clear hierarchy, considered color'**
  String get appearanceArticleHeading;

  /// No description provided for @appearanceArticleBody.
  ///
  /// In en, this message translates to:
  /// **'Type size, spacing, and contrast establish a clear hierarchy. Links should be discoverable and selections unmistakable, while the paper remains steady through color changes. This order should carry into the night.'**
  String get appearanceArticleBody;

  /// No description provided for @appearanceQuote.
  ///
  /// In en, this message translates to:
  /// **'A considered reading environment lets the content hold our attention.'**
  String get appearanceQuote;

  /// No description provided for @appearanceFigureTitle.
  ///
  /// In en, this message translates to:
  /// **'Figure 1 / Reading activities (sample)'**
  String get appearanceFigureTitle;

  /// No description provided for @appearanceFigureA.
  ///
  /// In en, this message translates to:
  /// **'Reading text'**
  String get appearanceFigureA;

  /// No description provided for @appearanceFigureB.
  ///
  /// In en, this message translates to:
  /// **'Exploring figures'**
  String get appearanceFigureB;

  /// No description provided for @appearanceFigureC.
  ///
  /// In en, this message translates to:
  /// **'Taking notes'**
  String get appearanceFigureC;

  /// No description provided for @appearanceFigureCaption.
  ///
  /// In en, this message translates to:
  /// **'Illustrative data. Figure colors remain unchanged on every reading paper.'**
  String get appearanceFigureCaption;

  /// No description provided for @appearanceArticleEnd.
  ///
  /// In en, this message translates to:
  /// **'When we return, the chosen paper, the note we typed, and the paragraph we were reading should still be there.'**
  String get appearanceArticleEnd;

  /// No description provided for @appearanceReference.
  ///
  /// In en, this message translates to:
  /// **'View sample reference ↗'**
  String get appearanceReference;

  /// No description provided for @appearanceSample.
  ///
  /// In en, this message translates to:
  /// **'Sample document'**
  String get appearanceSample;

  /// No description provided for @appearanceSampleHelp.
  ///
  /// In en, this message translates to:
  /// **'The document, author, and chart are fictional content for appearance validation. No external services are connected.'**
  String get appearanceSampleHelp;

  /// No description provided for @displaySettings.
  ///
  /// In en, this message translates to:
  /// **'Display settings'**
  String get displaySettings;

  /// No description provided for @interfaceFont.
  ///
  /// In en, this message translates to:
  /// **'Interface font'**
  String get interfaceFont;

  /// No description provided for @interfaceFontHelp.
  ///
  /// In en, this message translates to:
  /// **'System sans is the default; serif is optional. Applies to this preview without downloading fonts.'**
  String get interfaceFontHelp;

  /// No description provided for @fontSans.
  ///
  /// In en, this message translates to:
  /// **'Sans'**
  String get fontSans;

  /// No description provided for @fontSerif.
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get fontSerif;
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
