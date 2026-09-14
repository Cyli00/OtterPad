/// GStorage.setting 键名总表——所有设置键名字符串的单一真值源。
///
/// 规则：**禁止在调用点手写设置键名字符串、禁止重复定义键名常量**。各处一律
/// 引用本表（直接用 `SettingsKeys.foo`，或本地常量 `const _kFoo = SettingsKeys.foo;`
/// 转引）。这样改名只改本表一处，所有引用同步；重复定义会导致改名时静默 desync。
///
/// 仅收 `GStorage.setting` 键。凭据（API key / 密码）走 [SecureCredentialVault]，
/// 其键不在本表；per-prompt 键由 `PromptDef.storageKey` 自带（数据驱动，不在本表）。
class SettingsKeys {
  SettingsKeys._();

  // ── 通用 / app ──
  static const logEnabled = 'general_log_enabled';
  static const logLevel = 'general_log_level';
  static const hapticsEnabled = 'general_haptics_enabled';
  static const cacheAutoCleanup = 'general_cache_auto_cleanup';
  static const autoCheckUpdate = 'general_auto_check_update';
  static const http2Enabled = 'general_http2_enabled';
  static const ignoredUpdateVersion = 'general_ignored_update_version';
  static const locale = 'app_locale';
  static const zoteroLocalPort = 'zotero_local_port';
  static const zoteroLocalDirectory = 'zotero_local_directory';
  static const hasSeenOnboarding = 'hasSeenOnboarding';

  /// 导航栏是否展开文字标签；缺省 null = 跟随宽度自动（≥1200 展开）
  static const navRailExtended = 'nav_rail_extended';

  // ── 主题 ──
  static const themeMode = 'theme_mode';
  static const seedColor = 'seed_color';
  static const useDynamicColor = 'use_dynamic_color';
  static const textScale = 'text_scale';

  // ── 代理 ──
  static const proxyMode = 'proxy_mode';
  static const proxyHost = 'proxy_host';
  static const proxyPort = 'proxy_port';

  // ── 阅读器 ──
  static const readerTheme = 'reader_theme';
  static const readerFont = 'reader_font';
  static const readerFontSize = 'reader_font_size';
  static const readerDesktopHorizontalMargin =
      'reader_desktop_horizontal_margin';
  static const readerDesktopVerticalMargin = 'reader_desktop_vertical_margin';
  static const readerDefaultMode = 'reader_default_mode';
  static const readerPaginationMode = 'reader_pagination_mode';

  /// 停靠栏（目录/笔记/问 AI）用户拖拽调宽后的宽度；缺省 null = 跟随窗口自适应
  static const readerSidebarWidth = 'reader_sidebar_width';

  // ── chat ──
  static const webSearchProvider = 'web_search_provider';
  static const chatStreamEnabled = 'chat_stream_enabled';
  static const chatNewSessionHintDismissed = 'chat_new_session_hint_dismissed';
  static const mimoSearchPluginHintDismissed =
      'mimo_search_plugin_hint_dismissed';

  // ── 翻译 ──
  static const translationTargetLang = 'translation_config_target_language';
  static const translationTemperature = 'translation_config_temperature';
  static const translationDisplayStyle = 'translation_config_display_style';
  static const translationIgnoreSections = 'translation_config_ignore_sections';

  // ── 图片生成 ──
  static const imageAspectRatio = 'image_generation_aspect_ratio';
  static const imageFidelity = 'image_generation_fidelity';
  static const imageMaxReferenceImages =
      'image_generation_max_reference_images';

  // ── 自动备份 ──
  static const autoBackupInterval = 'auto_backup_interval';
  static const autoBackupScope = 'auto_backup_scope';

  // ── 备份：通用 + WebDAV ──
  static const backupRemoteType = 'backup_remote_type';
  static const backupWebdavServerUrl = 'backup_webdav_server_url';
  static const backupWebdavUsername = 'backup_webdav_username';
  static const backupWebdavRemoteDir = 'backup_webdav_remote_dir';
  static const backupWebdavFileName = 'backup_webdav_file_name';

  // ── 备份：S3 ──
  static const backupS3Endpoint = 'backup_s3_endpoint';
  static const backupS3Region = 'backup_s3_region';
  static const backupS3Bucket = 'backup_s3_bucket';
  static const backupS3AccessKeyId = 'backup_s3_access_key_id';
  static const backupS3ObjectKey = 'backup_s3_object_key';
  static const backupS3UsePathStyle = 'backup_s3_use_path_style';

  // ── 备份指纹 ──
  static const lastBackupSnapshot = 'last_backup_snapshot';

  // ── 模型能力表（modelcaps 订阅元数据）──
  static const modelCapsLastFetchedAt = 'model_caps_last_fetched_at';
  static const modelCapsEtag = 'model_caps_etag';
  static const modelCapsLastModified = 'model_caps_last_modified';
  static const modelCapsVersion = 'model_caps_version';

  // ── Agent API（静态）──
  static const agentApiProviderIds = 'agent_api_provider_ids';
  static const agentApiLastInstance = 'agent_api_last_instance';
  static const agentApiDefaultModelGlobal = 'agent_api_default_model_global';
  static const agentApiFastModelGlobal = 'agent_api_fast_model_global';
  static const agentApiImageModelGlobal = 'agent_api_image_model_global';

  // ── Agent API（per-instance，实例 id 后缀）──
  static String agentApiName(String id) => 'agent_api_name_$id';
  static String agentApiProtocol(String id) => 'agent_api_protocol_$id';
  static String agentApiBaseUrl(String id) => 'agent_api_base_url_$id';
  static String agentApiModels(String id) => 'agent_api_models_$id';
  static String agentApiModelParams(String id) => 'agent_api_model_params_$id';
  static String agentApiModelCaps(String id) => 'agent_api_model_caps_$id';
  static String agentApiModelTools(String id) => 'agent_api_model_tools_$id';

  // ── 文档抽取配置（键 = [docExtractPrefix] + 字段名）──
  static const docExtractPrefix = 'doc_extract_';

  /// OCR 提供商选择（'paddle' | 'mineru'），键 = docExtractPrefix + 'provider'
  static const docExtractProviderField = 'provider';

  /// 提取用量本地记账（{date, paddle, mineru} Map）
  static const docExtractUsage = 'doc_extract_usage';

  /// doc_extract 配置字段名集合；与 [docExtractPrefix] 拼成完整键。
  /// （注：DocExtractApiNotifier 的 setBool/setDouble/setString 仍按字段名
  /// 入参，调用点传字段名字面量——那是字段标识符模式，非本表管辖范围。）
  static const docExtractFields = <String>[
    'useChartRecognition',
    'useDocOrientationClassify',
    'useDocUnwarping',
    'useSealRecognition',
    'useOcrForImageBlock',
    'restructurePages',
    'layoutNms',
    'mergeTables',
    'layoutShapeMode',
    'repetitionPenalty',
    'temperature',
    'markdownIgnoreLabels',
  ];

  /// MinerU 提供商的参数字段名集合；与 [docExtractPrefix] 拼成完整键。
  static const docExtractMineruFields = <String>[
    'mineruIsOcr',
    'mineruEnableFormula',
    'mineruEnableTable',
    'mineruLanguage',
    'mineruModelVersion',
    'mineruPageRanges',
    'mineruExtraFormats',
  ];
}
