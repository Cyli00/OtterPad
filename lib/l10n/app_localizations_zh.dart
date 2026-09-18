// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get sharedFilesImportFailed => '分享文件导入失败，请从文库重新导入。';

  @override
  String get sharedFilesSkipped => '部分分享文件不是可读取的 PDF，已跳过。';

  @override
  String readerTranslationIncomplete(int count) {
    return '还有 $count 个段落未翻译，重试可继续。';
  }

  @override
  String get appTitle => 'OtterPad';

  @override
  String get home => '首页';

  @override
  String get library => '库';

  @override
  String get outline => '大纲';

  @override
  String get notes => '笔记';

  @override
  String get appearance => '外观';

  @override
  String get translate => '翻译';

  @override
  String get retryTranslation => '重试翻译';

  @override
  String get bilingual => '双语';

  @override
  String get original => '原文';

  @override
  String get translated => '译文';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get confirm => '确认';

  @override
  String get retry => '重试';

  @override
  String get close => '关闭';

  @override
  String get back => '返回';

  @override
  String get copy => '复制';

  @override
  String get more => '更多';

  @override
  String get add => '添加';

  @override
  String get edit => '编辑';

  @override
  String get remove => '移除';

  @override
  String get done => '完成';

  @override
  String get search => '搜索';

  @override
  String get test => '测试';

  @override
  String get create => '创建';

  @override
  String get refresh => '刷新';

  @override
  String get processing => '处理中...';

  @override
  String get cancelAll => '取消全部';

  @override
  String get goToSettings => '前往设置';

  @override
  String get configurationRequired => '需要配置';

  @override
  String get cancelled => '已取消';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get settings => '设置';

  @override
  String get navShowLabels => '显示标签';

  @override
  String get navHideLabels => '隐藏标签';

  @override
  String get readerShowNavigation => '显示导航栏';

  @override
  String get readerHideNavigation => '隐藏导航栏';

  @override
  String get networkSettings => '网络设置';

  @override
  String get networkSettingsSubtitle => '代理 · 连通性测试';

  @override
  String get aiSettings => 'AI 设置';

  @override
  String get aiSettingsSubtitle => '模型接口 · 翻译设置 · 生图设置';

  @override
  String get ocrSettings => 'OCR 设置';

  @override
  String get ocrSettingsSubtitle => 'OCR 接口 · 输出控制 · 识别增强 · 文档校正';

  @override
  String get appearanceSettings => '显示设置';

  @override
  String get appearanceSettingsSubtitle => '主题模式 · 主题色彩 · 阅读设置';

  @override
  String get dataManagement => '数据管理';

  @override
  String get dataManagementSubtitle => '远程备份 · 本地备份 · Zotero 同步';

  @override
  String get systemSettings => '系统设置';

  @override
  String get about => '关于';

  @override
  String get themeMode => '主题模式';

  @override
  String get autoMode => '自动';

  @override
  String get lightMode => '浅色';

  @override
  String get darkMode => '深色';

  @override
  String get systemMode => '跟随系统';

  @override
  String get themeColor => '主题色彩';

  @override
  String get readingSettings => '阅读设置';

  @override
  String get defaultReadingMode => '默认阅读模式';

  @override
  String get defaultReadingModeHint => '选择 Markdown 时，若文档无提取结果将自动回退到 PDF 视图';

  @override
  String get textSize => '字体';

  @override
  String get appLanguage => '应用语言';

  @override
  String get appLanguageDesc => '覆盖应用界面的显示语言';

  @override
  String get systemTextScale => '系统文字缩放';

  @override
  String get textSizeStandard => '标准';

  @override
  String get textSizeLarge => '大';

  @override
  String get textSizeExtraLarge => '特大';

  @override
  String get textSizeHint => '影响整个应用的文字显示大小，重启后仍保留';

  @override
  String get readerThemeWhite => '白色';

  @override
  String get readerThemeSepia => '羊皮纸';

  @override
  String get readerThemeGreen => '护眼绿';

  @override
  String get readerThemeNight => '夜间';

  @override
  String get readerThemeDark => '纯黑';

  @override
  String get readerThemeWhiteShort => '白色';

  @override
  String get readerThemeSepiaShort => '羊皮';

  @override
  String get readerThemeGreenShort => '护眼';

  @override
  String get readerThemeNightShort => '夜间';

  @override
  String get readerThemeDarkShort => '纯黑';

  @override
  String get fontSize => '字号';

  @override
  String get fontFamily => '字体';

  @override
  String get appFont => '应用字体';

  @override
  String get appFontSans => 'Sans（无衬线）';

  @override
  String get appFontSerif => 'Serif（衬线）';

  @override
  String get appFontPreview => 'Aa 123 · 中文 · 日本語 · 한국어 · العربية';

  @override
  String get appFontHint => '用于应用界面；阅读器字体单独设置。所选字体缺少的字符会使用系统回退字体。';

  @override
  String get appFontLoadFailed => '无法读取系统字体，仍可选择 Sans 或 Serif。';

  @override
  String get appFontSaveFailed => '字体设置未能保存，请重试。';

  @override
  String get paginationMode => '翻页方式';

  @override
  String get verticalPagination => '上下翻页';

  @override
  String get horizontalPagination => '左右翻页';

  @override
  String get translationStyle => '译文样式';

  @override
  String get highlightsAndNotes => '标注与笔记';

  @override
  String get noHighlights => '还没有标注';

  @override
  String get noHighlightsHint => '选中文本后点击颜色圆点即可创建';

  @override
  String get editNote => '编辑笔记';

  @override
  String get editNoteTitle => '编辑笔记';

  @override
  String get writeYourThoughts => '写下你的想法...';

  @override
  String highlightCount(int count) {
    return '$count 条';
  }

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get color => '颜色';

  @override
  String get background => '背景';

  @override
  String get translationDone => '翻译完成';

  @override
  String get translationCacheUsed => '已加载翻译缓存';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageChinese => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get recommend => '推荐';

  @override
  String get documentLibrary => '文献库';

  @override
  String get recommendContent => '推荐内容';

  @override
  String get batchDelete => '批量删除';

  @override
  String get searchDocumentsHint => '搜索文献...';

  @override
  String get searchDocumentsHintDesktop => '搜索文献、作者、关键词...';

  @override
  String get enterKeywordToSearch => '输入关键词搜索文献';

  @override
  String get noDocumentsFound => '未找到匹配的文献';

  @override
  String get noDocuments => '暂无文献';

  @override
  String get listView => '列表视图';

  @override
  String get gridView => '网格视图';

  @override
  String get tools => '工具';

  @override
  String get addFiles => '添加文件';

  @override
  String get addByIdentifier => '通过标识符添加';

  @override
  String get rebuildLibrary => '重构文库';

  @override
  String get addByIdentifierTitle => '通过标识符添加条目';

  @override
  String get batchExtracting => '批量提取中';

  @override
  String get extractionDone => '提取完成';

  @override
  String get cancelExtraction => '取消提取';

  @override
  String get waitingSubmit => '等待提交';

  @override
  String get extractionComplete => '提取完成';

  @override
  String extractionCompletePages(int totalPages) {
    return '完成（共 $totalPages 页）';
  }

  @override
  String get extractionFailed => '提取失败';

  @override
  String get extractionCancelled => '已取消提取';

  @override
  String failedCount(int failed) {
    return '完成（$failed 篇失败）';
  }

  @override
  String get exitMultiSelect => '退出多选';

  @override
  String get deselectAll => '取消全选';

  @override
  String get selectAll => '全选';

  @override
  String get textExtraction => '文本提取';

  @override
  String get addToFavorite => '加入收藏夹';

  @override
  String get removeFromFavorite => '移出收藏夹';

  @override
  String get openInReader => '打开';

  @override
  String get enterSelection => '进入多选';

  @override
  String get deleteFavorite => '删除收藏夹';

  @override
  String get myLibrary => '我的库';

  @override
  String get readingHistory => '阅读历史';

  @override
  String get noFileEntries => '无文件条目';

  @override
  String get favorites => '收藏夹';

  @override
  String get addDocument => '添加文献';

  @override
  String get addDocuments => '添加文献';

  @override
  String get allDocumentsHaveFiles => '所有文献都有对应文件';

  @override
  String get attachFile => '附加文件';

  @override
  String get viewInBrowser => '在浏览器中查看';

  @override
  String get redownload => '重新下载';

  @override
  String get entryDeleted => '已删除条目';

  @override
  String get fileAttached => '文件附加成功';

  @override
  String get clearHistory => '清空历史';

  @override
  String get noReadingHistory => '暂无阅读记录';

  @override
  String get removedFromHistory => '已从历史移除';

  @override
  String get clearReadingHistory => '清空阅读历史';

  @override
  String get readingHistoryCleared => '已清空阅读历史';

  @override
  String get alreadyInFavorite => '已包含当前文献';

  @override
  String get createFavorite => '新建收藏夹';

  @override
  String get createThenSelect => '创建后可在下方勾选';

  @override
  String get editFavorite => '编辑收藏夹';

  @override
  String get selectIcon => '选择图标';

  @override
  String get favoriteName => '收藏夹名称';

  @override
  String get unnamed => '未命名';

  @override
  String get enterFavoriteName => '输入收藏夹名称';

  @override
  String get documentNotInFavorite => '此文献不在收藏夹中';

  @override
  String get moveToFavorite => '移入收藏夹';

  @override
  String get libraryEmpty => '文献库为空';

  @override
  String selectedCount(int count) {
    return '确认 ($count)';
  }

  @override
  String get alreadyInThisFavorite => '已在收藏夹';

  @override
  String get reformatDone => '重新排版完成';

  @override
  String get viewPdf => '查看 PDF';

  @override
  String get viewExtractResult => '查看提取结果';

  @override
  String get documentExtract => '文档提取';

  @override
  String get loadFailed => '加载失败';

  @override
  String get extractResultEmpty => '提取结果为空';

  @override
  String get copyAll => '复制全部';

  @override
  String get share => '分享';

  @override
  String get generateSummary => '生成总结图';

  @override
  String get reExtract => '重新提取';

  @override
  String get documentInfo => '文献信息';

  @override
  String get viewSummary => '查看总结图';

  @override
  String get reformat => '重新排版';

  @override
  String get reTranslate => '重新翻译';

  @override
  String get searchContent => '搜索正文内容';

  @override
  String get exitSearch => '退出搜索';

  @override
  String get matchCase => '区分大小写';

  @override
  String get matchWholeWord => '全词匹配';

  @override
  String get noMatchFound => '未找到匹配内容';

  @override
  String get previousResult => '上一个结果';

  @override
  String get nextResult => '下一个结果';

  @override
  String get translateText => '翻译';

  @override
  String get deleteHighlight => '删除高亮';

  @override
  String get saveNote => '保存';

  @override
  String get streaming => '流式接收中';

  @override
  String get copied => '已复制';

  @override
  String get addToNote => '添加到注释';

  @override
  String get copyTranslation => '复制译文';

  @override
  String get copyOriginal => '复制原文';

  @override
  String get closeImage => '关闭';

  @override
  String get copyImage => '复制图片';

  @override
  String get shareImage => '分享图片';

  @override
  String get saveImage => '保存图片';

  @override
  String get imageNotFound => '图片文件不存在';

  @override
  String get saveImageTitle => '保存图片';

  @override
  String get savedToGallery => '已保存到相册';

  @override
  String get galleryAccessDenied => '未获得相册访问权限';

  @override
  String get showOriginal => '显示原文';

  @override
  String get showTranslation => '显示翻译';

  @override
  String get viewInDocument => '在文中查看';

  @override
  String get viewOriginalImage => '查看原图';

  @override
  String get generatingSummary => '正在生成总结图…';

  @override
  String get referencesNotFound => '未找到参考文献';

  @override
  String get author => '作者';

  @override
  String get journal => '期刊';

  @override
  String get year => '年份';

  @override
  String get modelApi => '模型接口';

  @override
  String get translationSettings => '翻译设置';

  @override
  String get imageGenSettings => '生图设置';

  @override
  String get deleteProvider => '删除服务商';

  @override
  String get providers => '服务商';

  @override
  String get addProvider => '添加服务商';

  @override
  String get selectProtocol => '选择协议';

  @override
  String get manageModels => '管理模型';

  @override
  String get addApiKeyFirst => '填写 API Key 以管理模型';

  @override
  String get models => '模型';

  @override
  String get globalModelRoles => '全局模型角色';

  @override
  String get expertModel => '专家模型';

  @override
  String get fastModel => '快速模型';

  @override
  String get imageModel => '生图模型';

  @override
  String get notSet => '未设置';

  @override
  String get pleaseAddImageModel => '请先添加支持图片输出的模型';

  @override
  String get pleaseAddMultimodalModel => '请先添加多模态模型';

  @override
  String get pleaseAddModels => '请先在各服务商下添加模型';

  @override
  String get providerName => '服务商名称';

  @override
  String get nameField => '名称';

  @override
  String get detectModel => '检测模型';

  @override
  String get modelType => '模型类型';

  @override
  String get chat => '聊天';

  @override
  String get embedding => '嵌入';

  @override
  String get inputMode => '输入模式';

  @override
  String get text => '文本';

  @override
  String get image => '多模态';

  @override
  String get outputMode => '输出模式';

  @override
  String get capabilities => '能力';

  @override
  String get reasoning => '推理';

  @override
  String get resetToAuto => '重置为自动推断';

  @override
  String get defaultLevel => '默认';

  @override
  String get off => '关闭';

  @override
  String get low => '低';

  @override
  String get medium => '中等';

  @override
  String get high => '高';

  @override
  String get ultraHigh => '超高';

  @override
  String get thinkingIntensity => '思考强度';

  @override
  String get fetchModelsFailed => '获取模型列表失败';

  @override
  String get showAllModels => '显示全部模型';

  @override
  String get showImageGenModels => '仅显示生图模型';

  @override
  String get showMultimodalModels => '仅显示多模态模型';

  @override
  String get noImageGenModels => '未检测到支持图片输出的模型';

  @override
  String get noMultimodalModels => '未检测到多模态模型';

  @override
  String get noResults => '无匹配结果';

  @override
  String get expert => '专家';

  @override
  String get fast => '快速';

  @override
  String get imageGen => '生图';

  @override
  String get addModel => '添加';

  @override
  String addModelById(String id) {
    return '添加「$id」';
  }

  @override
  String get removeModel => '移除';

  @override
  String get addModelTitle => '添加模型';

  @override
  String get restoreDefaults => '恢复默认';

  @override
  String get targetLanguage => '目标语言';

  @override
  String get translationStyleSetting => '译文样式';

  @override
  String get translationIgnore => '翻译忽略内容';

  @override
  String get temperature => '温度';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get userPrompt => '用户提示词';

  @override
  String get classicPhotography => '经典摄影';

  @override
  String get referenceImageCount => '参考图数量';

  @override
  String get aspectRatio => '画幅比例';

  @override
  String get resolution => '清晰度';

  @override
  String get proxy => '代理';

  @override
  String get customProxy => '自定义代理';

  @override
  String get customProxySubtitle => '手动指定代理地址';

  @override
  String get hostAddress => '主机地址';

  @override
  String get port => '端口';

  @override
  String get systemProxy => '系统代理';

  @override
  String get systemProxySubtitle => '使用系统环境变量中的代理设置';

  @override
  String get noProxy => '不使用代理';

  @override
  String get noProxySubtitle => '直接连接网络';

  @override
  String get connectivityTest => '连通性测试';

  @override
  String get testAddress => '测试地址';

  @override
  String get connectionTimeout => '连接超时';

  @override
  String get connectionOk => '连接正常';

  @override
  String get connectionFailed => '连接失败';

  @override
  String get remoteBackup => '远程备份';

  @override
  String get backupMethod => '备份方式';

  @override
  String get localBackup => '本地备份';

  @override
  String get exportBackup => '导出备份文件';

  @override
  String get restoreFromBackup => '从备份文件恢复';

  @override
  String get storage => '存储';

  @override
  String get clearCache => '清除缓存';

  @override
  String get clearAllData => '清除所有数据';

  @override
  String get clearAllDataConfirm => '这将删除所有文献、数据库和缓存，此操作无法撤销';

  @override
  String get storageSpace => '存储空间';

  @override
  String get storageSpaceTotal => '合计';

  @override
  String get storageSpaceDetails => '详情';

  @override
  String get storageSpaceLoadFailed => '加载存储信息失败';

  @override
  String storageSpaceClearable(String size) {
    return '可清理：$size';
  }

  @override
  String storageSpaceFilesCount(int count) {
    return '$count 个文件';
  }

  @override
  String get storageGroupPapers => '文献';

  @override
  String get storageCategoryImages => '图片';

  @override
  String get storageCategoryFiles => '文件';

  @override
  String get storageCategoryChat => '聊天记录';

  @override
  String get storageCategoryCache => '缓存';

  @override
  String get storageCategoryLogs => '日志';

  @override
  String get storageCategoryDatabase => '数据库';

  @override
  String get storageSpaceSelected => '已选择';

  @override
  String get storageSpaceCleared => '已清除所选数据';

  @override
  String get clearData => '清除数据';

  @override
  String clearDataConfirm(String names) {
    return '以下数据将被永久删除：$names';
  }

  @override
  String get listSeparator => '、';

  @override
  String get resetAndReimport => '重置并全量重新导入';

  @override
  String get reimport => '重新导入';

  @override
  String get detecting => '正在检测连接';

  @override
  String get configure => '配置';

  @override
  String get cacheCleared => '缓存已清除';

  @override
  String get allDataCleared => '所有数据已清除';

  @override
  String get saveBackupFile => '保存备份文件';

  @override
  String get selectBackupFile => '选择备份文件';

  @override
  String get restoreSettingsTitle => '恢复设置';

  @override
  String get restoreMethod => '恢复方式';

  @override
  String get restoreScope => '恢复范围';

  @override
  String get startMerge => '开始合并';

  @override
  String get startRestore => '开始恢复';

  @override
  String get clearField => '清空';

  @override
  String get address => '地址';

  @override
  String get account => '账号';

  @override
  String get password => '密码';

  @override
  String get region => '区域';

  @override
  String get objectPath => '对象路径';

  @override
  String get usePathStyle => '使用路径式地址';

  @override
  String get remote => '远程';

  @override
  String get zoteroSync => 'Zotero 同步';

  @override
  String get fullResync => '重置并全量重新导入';

  @override
  String get layoutAnalysis => '版面分析';

  @override
  String get layoutGeometry => '版面几何形状';

  @override
  String get layoutGeometryHelp => '版面检测框的几何形状表示';

  @override
  String get outputControl => '输出控制';

  @override
  String get repetitionPenalty => '重复抑制强度';

  @override
  String get repetitionPenaltyHint => '结果中出现重复文字、重复表格内容时，可适当调高';

  @override
  String get crossPageTableMerge => '跨页表格合并';

  @override
  String get crossPageTableMergeDesc => '开启后，会识别跨页表格，将其合并为一个';

  @override
  String get recognitionStability => '识别稳定性';

  @override
  String get recognitionStabilityHint => '结果不稳定或出现明显幻觉时调低，漏识别或者重复较多时可略微调高';

  @override
  String get recognitionEnhancement => '识别增强';

  @override
  String get documentCorrection => '文档校正';

  @override
  String get ocrAuto => '自动';

  @override
  String get ocrRectangle => '矩形';

  @override
  String get ocrQuadrilateral => '四边形';

  @override
  String get ocrPolygon => '多边形';

  @override
  String get chartRecognition => '图表识别';

  @override
  String get stampRecognition => '印章识别';

  @override
  String get imageAreaOcr => '图片文字识别';

  @override
  String get orientationCorrection => '方向校正';

  @override
  String get curvatureCorrection => '弯曲校正';

  @override
  String get deduplicateBoxes => 'NMS后处理';

  @override
  String get multiPageReconstruction => '多页重构';

  @override
  String get ocrHeader => '页眉';

  @override
  String get ocrHeaderImage => '页眉图片';

  @override
  String get ocrFooter => '页脚';

  @override
  String get ocrFooterImage => '页脚图片';

  @override
  String get ocrPageNumber => '页码';

  @override
  String get ocrFootnote => '脚注';

  @override
  String get ocrSideNote => '旁注';

  @override
  String get searchToolLabel => '搜索';

  @override
  String get streamOutput => '流式输出';

  @override
  String get tavilySearchSection => '联网搜索回退（Tavily）';

  @override
  String get tavilySearchDesc =>
      '为不支持原生联网搜索的模型（如 DeepSeek、豆包）提供搜索能力。填入 Key 后，对话页的联网开关对这些模型即可生效';

  @override
  String get tavilyNotConfiguredHint =>
      '当前模型无原生联网搜索，请在 AI 设置中配置 Tavily API Key 以启用';

  @override
  String get mimoSearchPluginTitle => '开通联网搜索插件';

  @override
  String get mimoSearchPluginHint => 'MiMo 联网搜索需先在平台控制台开通插件';

  @override
  String get mimoSearchPluginOpenConsole => '打开插件控制台';

  @override
  String get taskInProgress => '该文献已有任务正在进行中';

  @override
  String get savingResult => '正在保存结果';

  @override
  String get saveResultFailed => '保存结果失败';

  @override
  String get summaryCancelled => '已取消总结图生成';

  @override
  String get preparingContent => '正在整理文献内容';

  @override
  String get requestingImageModel => '正在请求生图模型';

  @override
  String get summaryGenerated => '总结图已生成';

  @override
  String get downloadCancelled => '已取消下载';

  @override
  String get summaryNotFound => '总结图文件不存在';

  @override
  String get generateSummaryTitle => '生成总结图';

  @override
  String get exportAll => '一键导出';

  @override
  String get roleBadgeEmbedding => '嵌入';

  @override
  String get roleBadgeVision => '视觉';

  @override
  String get roleBadgeImageGen => '生图';

  @override
  String get roleBadgeTools => '工具';

  @override
  String get roleBadgeReasoning => '推理';

  @override
  String storageUsage(String size) {
    return '占用 $size';
  }

  @override
  String backupTo(String target) {
    return '备份到$target';
  }

  @override
  String uploadBackupTo(String target) {
    return '上传完整备份到$target';
  }

  @override
  String pleaseConfigureFirst(String target) {
    return '请先配置$target连接信息';
  }

  @override
  String restoreFromRemote(String target) {
    return '从$target恢复';
  }

  @override
  String downloadAndRestore(String target) {
    return '下载$target并恢复';
  }

  @override
  String get generateZipAndSave => '生成 zip 备份并保存到本地';

  @override
  String get selectLocalZipRestore => '选择本地 zip 备份文件进行恢复';

  @override
  String get thumbnailsAndTemp => '缩略图、临时文件等';

  @override
  String get allDataWillBeDeleted => '文献库、数据库将全部删除';

  @override
  String get getToken => '获取 Token';

  @override
  String get syncZoteroLibrary => '同步 Zotero 文库';

  @override
  String zoteroImportedPull(int count) {
    return '已导入 $count 篇 · 拉取新增条目';
  }

  @override
  String get pleaseFillApiKey => '请先填写 API Key';

  @override
  String get zoteroImportHint => '从 Zotero 个人库导入文献';

  @override
  String get zoteroResetHint => '清除导入记录，从 Zotero 重新拉取（找回已删除条目）';

  @override
  String get resetZoteroSync => '重置 Zotero 同步';

  @override
  String get resetZoteroConfirm =>
      '将清除本地的 Zotero 导入记录并从文库全量重新拉取：已删除的条目会重新出现，仍在库中的不会重复。继续吗？';

  @override
  String get s3Config => 'S3 配置';

  @override
  String get webDavConfig => 'WebDAV 配置';

  @override
  String remoteNotConfigured(String target) {
    return '未配置$target远程备份信息';
  }

  @override
  String s3BucketInfo(String bucket, String region) {
    return 'Bucket：$bucket  ·  区域：$region';
  }

  @override
  String s3ObjectInfo(String key) {
    return '对象：$key';
  }

  @override
  String webDavAccountInfo(String username) {
    return '账号：$username';
  }

  @override
  String webDavPathInfo(String path) {
    return '路径：$path';
  }

  @override
  String get clearingCache => '正在清除缓存...';

  @override
  String get confirmDeleteAllDataBody => '此操作将删除所有文献文件和数据库，且无法恢复。确定继续吗？';

  @override
  String get clearingData => '正在清除数据...';

  @override
  String get generatingLocalBackup => '正在生成本地备份...';

  @override
  String backupExportedTo(String path) {
    return '备份已导出到 $path';
  }

  @override
  String exportBackupFailed(String error) {
    return '导出备份失败：$error';
  }

  @override
  String get mergingBackup => '正在合并备份...';

  @override
  String get restoringBackup => '正在恢复备份...';

  @override
  String get backupInvalidData => '备份不完整或已损坏，尚未替换当前资料。';

  @override
  String get backupUnsupportedVersion => '暂不支持此备份的版本，请更新 OtterPad 后再恢复。';

  @override
  String get backupPendingRestore => '检测到上次恢复留下的副本，已保留这些资料。请先处理上次恢复，再重试。';

  @override
  String get backupActiveTasks => '后台任务尚未结束，请等待任务结束后再恢复。';

  @override
  String get backupChangedDuringCreation => '备份期间资料发生了变化，请等待编辑和后台任务结束后重试。';

  @override
  String get backupOperationInProgress => '备份或恢复正在进行，请等待完成后再试。';

  @override
  String restoreFailed(String error) {
    return '恢复失败：$error';
  }

  @override
  String get generatingAndUploading => '正在生成并上传远程备份...';

  @override
  String get backupScopeTitle => '备份范围';

  @override
  String get backupScopeFull => '完整备份';

  @override
  String get backupScopeFullDesc => '包含 PDF 与提取文件，备份体积较大';

  @override
  String get backupScopeData => '仅数据';

  @override
  String get backupScopeDataDesc => '设置、元数据、批注、翻译与对话；不含 PDF 与提取文件';

  @override
  String get startBackup => '开始备份';

  @override
  String get autoBackup => '自动备份';

  @override
  String get autoBackupOff => '关闭';

  @override
  String get autoBackupDaily => '每日';

  @override
  String get autoBackupWeekly => '每周';

  @override
  String get autoBackupHint => '到期后台自动上传到远端，仅在内容有变化时执行';

  @override
  String get cloudSync => '云同步';

  @override
  String get syncBackupNow => '立即备份';

  @override
  String syncLastBackup(String info) {
    return '上次备份：$info';
  }

  @override
  String get syncLastBackupNever => '尚未备份过';

  @override
  String get syncRemoteNotConfigured => '未配置远端备份';

  @override
  String get syncRemoteNotConfiguredDesc => '配置 S3 或 WebDAV 后即可备份并在此查看同步状态';

  @override
  String get syncGroupChanged => '有变更未备份';

  @override
  String get syncGroupNever => '从未备份';

  @override
  String get syncGroupSynced => '已备份';

  @override
  String get syncReasonAdded => '新导入';

  @override
  String get syncReasonContent => '文件变更';

  @override
  String get syncReasonMeta => '元数据 / 批注';

  @override
  String get syncReasonFiles => '翻译 / 对话';

  @override
  String remoteBackupUploaded(String target) {
    return '远程备份已上传到 $target';
  }

  @override
  String uploadRemoteFailed(String error) {
    return '上传远程备份失败：$error';
  }

  @override
  String get downloadingRemoteBackup => '正在下载远程备份...';

  @override
  String get mergingRemoteBackup => '正在合并远程备份...';

  @override
  String get restoringRemoteBackup => '正在恢复远程备份...';

  @override
  String remoteRestoreFailed(String error) {
    return '远程恢复失败：$error';
  }

  @override
  String restoreCompleteRefreshed(String prefix) {
    return '$prefix恢复完成，当前页面状态已同步刷新';
  }

  @override
  String mergeCompleteUpToDate(String prefix) {
    return '$prefix合并完成，本地数据已是最新';
  }

  @override
  String mergeDocumentsAdded(int count) {
    return '新增 $count 篇文献';
  }

  @override
  String mergeHighlightsAdded(int count) {
    return '新增 $count 条标注';
  }

  @override
  String mergeFilesCopied(int count) {
    return '复制 $count 个文件';
  }

  @override
  String mergeSettingsAdded(int count) {
    return '新增 $count 项设置';
  }

  @override
  String mergeCompleteSummary(String prefix, String details) {
    return '$prefix合并完成：$details';
  }

  @override
  String get webDavServerAddress => 'WebDAV服务器地址';

  @override
  String get s3Endpoint => 'S3 / R2 / MinIO Endpoint';

  @override
  String get s3ObjectPathDefault => '默认可用 otter-pad/otter_pad_backup.zip';

  @override
  String get s3PathStyleHint => 'MinIO / R2 等 S3 兼容服务通常建议开启';

  @override
  String get selectImageModelFirst => '请先在「AI 设置」中选择生图模型';

  @override
  String get summaryUploadFailed => '上传总结图失败';

  @override
  String estimatedCost(String dollar, String cost) {
    return '当前设置预估费用约 $dollar$cost / 张';
  }

  @override
  String get useAppImageGen => '若希望使用 App 生图，请点击 App 生图，手动上传素材';

  @override
  String get appImageGen => 'App 生图';

  @override
  String get markdownNotFound => '未找到 Markdown 文件，请先完成文档提取';

  @override
  String promptGenerationFailed(String error) {
    return '生成 prompt 失败：$error';
  }

  @override
  String get saveExportZip => '保存导出 ZIP';

  @override
  String exportedWithPromptCopied(String name) {
    return '已导出到 $name，prompt 已复制';
  }

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get exportToAppImageGen => '导出至 App 生图';

  @override
  String get exportToAppImageGenHint =>
      '将文献素材导出后，到 ChatGPT / Gemini 等官方 App 中手动上传以生图';

  @override
  String get exportShareHint => '同时分享 figures + Markdown，prompt 自动复制到剪贴板';

  @override
  String get exportZipHint =>
      '打包 figures + article.md + prompt.md 为 ZIP，prompt 自动复制到剪贴板';

  @override
  String get ocrChartRecognitionDesc => '将图表解析为表格';

  @override
  String get ocrStampRecognitionDesc => '识别文档中的印章';

  @override
  String get ocrImageAreaDesc => '开启后，对图片版面元素中的文本进行识别';

  @override
  String get ocrOrientationDesc => '自动纠正 0°/90°/180°/270° 旋转';

  @override
  String get ocrCurvatureDesc => '校正弯曲或褶皱的文档';

  @override
  String get ocrDeduplicateDesc => '当且仅当使用版面分析模块时生效，开启后，会自动移除重复或高度重叠的区域框';

  @override
  String get ocrMultiPageDesc => '重构多页文档结构';

  @override
  String get ocrFilterHelp => '勾选的标签区域将不会输出到 Markdown 结果中，默认全忽略';

  @override
  String get resetOcrSettings => '重置设置';

  @override
  String get resetOcrSettingsConfirm => '这将把除 API Key 外的所有 OCR 配置恢复为默认值，是否继续？';

  @override
  String get reset => '重置';

  @override
  String get ocrSettingsReset => '已重置 OCR 配置';

  @override
  String get ocrInterface => 'OCR 接口';

  @override
  String get ocrProvider => '提供商';

  @override
  String get ocrProviderHelp =>
      'PaddleOCR 与 MinerU 的 Token 各自独立保存，切换提供商不影响已配置的提取选项';

  @override
  String get mineruOptions => 'MinerU 解析选项';

  @override
  String get mineruScannedOcr => '扫描件 OCR';

  @override
  String get mineruScannedOcrDesc => '扫描版 / 纯图片 PDF 开启';

  @override
  String get mineruFormulaRecognition => '公式识别';

  @override
  String get mineruFormulaRecognitionDesc =>
      '默认开启。VLM 模型下仅影响行内公式；Pipeline 模型下控制公式识别。';

  @override
  String get mineruTableRecognition => '表格识别';

  @override
  String get mineruTableRecognitionDesc => '将表格解析为 HTML';

  @override
  String get ocrLanguage => '文档语言';

  @override
  String get ocrLanguageHelp => '选择文档的主要语言或语言组，默认为中英文。';

  @override
  String get ocrLangChinese => '中英文';

  @override
  String get ocrLangEnglish => '英文';

  @override
  String get ocrUsageTitle => '今日额度';

  @override
  String ocrUsagePages(int used, int limit) {
    return '今日已解析 $used / $limit 页';
  }

  @override
  String get ocrUsageHardLimitNote => '每日硬上限，超出即被拒绝。本地估算，以服务商实际记账为准';

  @override
  String get ocrUsagePriorityNote => '优先解析额度，超出后排队降速继续。本地估算，以服务商实际记账为准';

  @override
  String ocrUsageLimitsLine(int sizeMB, int pages, int batch) {
    return '单文件 ≤ ${sizeMB}MB / $pages 页 · 批量 ≤ $batch 个文件';
  }

  @override
  String extractFileTooLarge(int maxMB, int count) {
    return '$count 个文件超过 ${maxMB}MB 大小限制，已跳过';
  }

  @override
  String extractFileTooLargeSingle(int maxMB) {
    return '文件超过 ${maxMB}MB 大小限制';
  }

  @override
  String extractTooManyPages(int maxPages) {
    return '页数超过单文件 $maxPages 页限制';
  }

  @override
  String batchExtractTooManyFiles(int max) {
    return '一次最多批量提取 $max 个文件';
  }

  @override
  String get aiFixNotForMinerU => 'MinerU 提取的文档已自带图表说明，无需 AI 修缮';

  @override
  String get aspectSquare => '方形 · 社交配图';

  @override
  String get aspectClassic => '经典摄影';

  @override
  String get aspectWide => '横屏视频 · 桌面壁纸';

  @override
  String get aspectUltraWide => '超宽屏 · 电影';

  @override
  String get aspectTall => '竖屏 · 手机壁纸';

  @override
  String get imageRefCountHint =>
      '从文献 figure 按顺序选取参考图，最多 10 张；超出时优先剔除补充图（Supplementary / Extended Data 等）';

  @override
  String get aspectRatioHint => 'OpenAI 会映射到最接近的输出尺寸，并在 prompt 中保留比例要求';

  @override
  String get summaryPromptHint =>
      '用于控制文献总结图的视觉风格和信息组织方式；运行时会自动追加文献标题、元数据、Markdown 和参考 figure';

  @override
  String get summaryPromptLabel => '总结图 Prompt';

  @override
  String get summaryPromptFieldHint => '描述文献总结图的版式、颜色、信息密度和风格要求';

  @override
  String estimatedCostShort(String dollar, String cost) {
    return '预估 $dollar$cost';
  }

  @override
  String get translationTargetLangDesc => '翻译提示词中 targetLanguage 变量的实际值';

  @override
  String get translationStyleDesc => '文档全文翻译时译文的视觉区分方式';

  @override
  String get translationIgnoreDesc => '勾选的区域翻译时跳过，取消勾选则合并为整段翻译';

  @override
  String get temperatureDesc => '越低越稳重，越高越发散';

  @override
  String get systemPromptDesc => '翻译 System Prompt';

  @override
  String get systemPromptHint => '例如：You are a professional translator…';

  @override
  String get userPromptDesc => '翻译 User Prompt';

  @override
  String promptPlaceholdersAvailable(String placeholders) {
    return '可用占位符：$placeholders';
  }

  @override
  String documentsAddedCount(int added) {
    return '已加入 $added 篇文献';
  }

  @override
  String documentsAddedSkipped(int added, int skipped) {
    return '已加入 $added 篇文献，$skipped 篇已存在已跳过';
  }

  @override
  String confirmDeleteDocuments(int count) {
    return '确定要删除 $count 篇文献吗？此操作不可撤销';
  }

  @override
  String deletedDocuments(int count) {
    return '已删除 $count 篇文献';
  }

  @override
  String get configureExtractToken => '请先在设置中配置文档提取 Access Token';

  @override
  String get noPdfFilesSelected => '所选文献中无本地 PDF 文件，无法提取';

  @override
  String get pdfNotFound => 'PDF 文件不存在';

  @override
  String get reformatting => '正在重新排版…';

  @override
  String reformatFailed(String error) {
    return '排版失败: $error';
  }

  @override
  String get aiFixFigures => 'AI 修缮图表';

  @override
  String get aiFixFiguresAnalyzing => '正在分析版面...';

  @override
  String get aiFixFiguresCalling => '正在调用 AI 模型...';

  @override
  String get aiFixFiguresApplying => '正在应用修缮...';

  @override
  String aiFixFiguresCropping(int done, int total) {
    return '正在裁剪图表 ($done/$total)';
  }

  @override
  String get aiFixFiguresDone => '图表已修缮。如需回退请用「重新排版」';

  @override
  String aiFixFiguresFailed(String error) {
    return 'AI 修缮失败: $error';
  }

  @override
  String get aiFixFiguresCancelled => 'AI 修缮已取消';

  @override
  String get aiFixFiguresMissingExtract => '请先提取文档，再修缮图表';

  @override
  String get aiFixFiguresModelNotSet => '请先设置专家模型或快速模型';

  @override
  String get aiFixFiguresInvalidLlmOutput => 'AI 返回内容无法解析，请重试';

  @override
  String get aiFixFiguresFailedGeneric => 'AI 修缮失败，请重试';

  @override
  String addedToFavorite(String name) {
    return '已添加到「$name」';
  }

  @override
  String addedToFavorites(int count) {
    return '已添加到 $count 个收藏夹';
  }

  @override
  String removedFromFavoriteSingle(String name) {
    return '已从「$name」移出';
  }

  @override
  String removedFromFavorites(int count) {
    return '已从 $count 个收藏夹移出';
  }

  @override
  String translationFailed(String error) {
    return '翻译失败：$error';
  }

  @override
  String get pdfFileNotFoundTitle => '找不到该文献的 PDF 文件';

  @override
  String removedFromFavoriteCount(int count) {
    return '已从收藏夹移除 $count 篇文献';
  }

  @override
  String confirmDeleteEntries(int count) {
    return '确定要删除 $count 个无文件条目吗？';
  }

  @override
  String deletedEntries(int count) {
    return '已删除 $count 个条目';
  }

  @override
  String attachFileFailed(String error) {
    return '附加文件失败: $error';
  }

  @override
  String addingDocumentsTo(int total) {
    return '将 $total 篇文献加入…';
  }

  @override
  String allSelectedAlreadyHere(int count) {
    return '所选 $count 篇已全部在此';
  }

  @override
  String currentDocumentCount(int count) {
    return '当前 $count 篇文献';
  }

  @override
  String overlapAndNew(int overlap, int newCount) {
    return '已含 $overlap 篇 · 将新增 $newCount 篇';
  }

  @override
  String confirmDeleteFavorite(String name) {
    return '确定要删除「$name」吗？收藏夹内的文献不会被删除';
  }

  @override
  String favoriteDocumentCount(int count) {
    return '$count 篇文献';
  }

  @override
  String get clearReadingHistoryConfirm => '将清除所有阅读记录，文献本身不会被删除。此操作不可撤销';

  @override
  String get noReadingHistoryHint => '打开任意文献后，这里会按日期显示浏览顺序';

  @override
  String get identifierInputHint => '输入 ISBN、DOI、PMID 或 arXiv ID 来添加条目到您的文库：';

  @override
  String get identifierExample => '例如: 10.1038/s41586-021-03811-w';

  @override
  String get addFilesSubtitle => '导入本地 PDF，并提取标题、作者、期刊、年份与 DOI';

  @override
  String get addByIdentifierSubtitle => '输入 DOI、PMID、arXiv ID 或 ISBN 直接创建条目';

  @override
  String get rebuildLibrarySubtitle => '重新扫描目录，补回 PDF 并重试提取核心元数据';

  @override
  String get downloadPdf => '下载 PDF';

  @override
  String viewLibraryTotal(int count) {
    return '查看文库 · 共 $count 篇';
  }

  @override
  String addedDocumentsToFavorite(int count) {
    return '已添加 $count 篇文献';
  }

  @override
  String get searchDocumentHint => '搜索文献标题 / 作者 / 期刊';

  @override
  String get noDocumentsInLibrary => '暂无文献，请添加 PDF 文件到文库';

  @override
  String get providerDescOpenai => 'gpt / o 系列 · 生图支持 gpt-image';

  @override
  String get providerDescAnthropic => 'Claude 系列';

  @override
  String get providerDescGemini => 'Google AI · 多模态';

  @override
  String get providerDescOpenaiCompatible => 'DeepSeek / 自部署等 OpenAI 兼容 API';

  @override
  String confirmDeleteProvider(String name) {
    return '确定删除「$name」？将清除其 API Key、地址和模型';
  }

  @override
  String modelConnected(String modelId) {
    return '$modelId 连接成功';
  }

  @override
  String get apiAddress => 'API 地址';

  @override
  String get apiKey => 'API Key';

  @override
  String previewUrl(String url) {
    return '预览: $url';
  }

  @override
  String selectRole(String role) {
    return '选择$role';
  }

  @override
  String addProtocol(String protocol) {
    return '添加 $protocol';
  }

  @override
  String get assignRoleHint => '为此模型分配场景角色（可选）';

  @override
  String willReplace(String current) {
    return '将替换 $current';
  }

  @override
  String providerModels(String provider) {
    return '$provider 模型';
  }

  @override
  String get searchModelHint => '搜索模型 ID 或名称';

  @override
  String connectionOkMs(String ms) {
    return '连接正常，$ms ms';
  }

  @override
  String get cannotConnectCheckProxy => '无法连接，请检查代理设置';

  @override
  String requestFailed(String error) {
    return '请求失败：$error';
  }

  @override
  String testFailed(String error) {
    return '测试失败：$error';
  }

  @override
  String copyFailed(String error) {
    return '复制失败：$error';
  }

  @override
  String shareFailed(String error) {
    return '分享失败：$error';
  }

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String savedToPath(String path) {
    return '已保存到 $path';
  }

  @override
  String get figuresNotFoundHint => '未找到图表\n请先提取文档';

  @override
  String copiedReference(int number, String snippet) {
    return '已复制 [$number] $snippet';
  }

  @override
  String searchMatchesFound(int count) {
    return '找到 $count 条匹配';
  }

  @override
  String get searchPdfContentHint => '搜索 PDF 内容';

  @override
  String get markdownIgnoreLabels => 'Markdown 忽略标签';

  @override
  String get resolutionHint => 'OpenAI 映射为 quality；Gemini 映射为 imageSize';

  @override
  String get translationStyleThemed => '主题色';

  @override
  String get translationStyleBold => '加粗';

  @override
  String get translationStyleItalic => '斜体';

  @override
  String get translationStyleWeakened => '弱化';

  @override
  String get translationStyleDashed => '虚线下划线';

  @override
  String get translationStyleHighlight => '背景色';

  @override
  String get translationStyleBlur => '模糊';

  @override
  String get translationStyleQuote => '引用';

  @override
  String get skipSectionReferences => '参考文献';

  @override
  String get skipSectionAcknowledgments => '致谢';

  @override
  String get skipSectionAuthorsContributions => '作者贡献/利益冲突';

  @override
  String get skipSectionFundingData => '资助/数据声明';

  @override
  String get skipSectionSupplementaryAppendix => '附录/补充材料';

  @override
  String get skipSectionEthicsLegends => '伦理声明/图表说明';

  @override
  String get fidelityAuto => '自动';

  @override
  String get fidelityStandard => '标准';

  @override
  String get fidelityHigh => '高';

  @override
  String tasksInProgress(int count) {
    return '$count 个任务进行中';
  }

  @override
  String get aiSettingsSelectTextModel => '请先在「AI 设置」中选择快速模型或专家模型';

  @override
  String get aiSettingsFillApiKey => '请先在「AI 设置」中填写 API Key';

  @override
  String get aiSettingsFillImageApiKey => '请先在「AI 设置」中填写生图模型 API Key';

  @override
  String get targetLanguageChangedRetranslate => '目标语言已变更，请重新翻译';

  @override
  String get preparingTranslation => '准备中';

  @override
  String get noTranslatableParagraphs => '未检测到可翻译段落';

  @override
  String waitingExtractTitle(String title) {
    return '等待提取: $title';
  }

  @override
  String submittingTaskTitle(String title) {
    return '正在提交任务: $title';
  }

  @override
  String extractionCompleteTitle(String title) {
    return '文档提取完成：$title';
  }

  @override
  String networkError(String message) {
    return '网络错误: $message';
  }

  @override
  String extractionFailedDetail(String error) {
    return '提取失败: $error';
  }

  @override
  String waitingSubmitTitle(String title) {
    return '等待提交: $title';
  }

  @override
  String submittedWaitingTitle(String title) {
    return '已提交，等待处理: $title';
  }

  @override
  String extractingTitle(String title) {
    return '正在提取… · $title';
  }

  @override
  String waitingSummaryTitle(String title) {
    return '等待生成总结图: $title';
  }

  @override
  String generatingSummaryTitle(String title) {
    return '正在生成总结图: $title';
  }

  @override
  String summaryGenerationFailed(String error) {
    return '总结图生成失败: $error';
  }

  @override
  String waitingDownloadTitle(String title) {
    return '等待下载: $title';
  }

  @override
  String downloadingTitle(String title) {
    return '正在下载: $title';
  }

  @override
  String downloadSuccessTitle(String title) {
    return '下载成功：$title';
  }

  @override
  String get downloadFailedNoSource => '下载失败，未找到可用的 PDF 源';

  @override
  String downloadFailed(String error) {
    return '下载失败: $error';
  }

  @override
  String get downloadingPdf => '正在下载 PDF';

  @override
  String downloadCancelledPartial(int count) {
    return '已取消下载，已成功 $count 篇';
  }

  @override
  String downloadCompleteAll(int count) {
    return '下载完成，成功 $count 篇';
  }

  @override
  String downloadCompletePartial(int ok, int fail) {
    return '下载完成：成功 $ok 篇，失败 $fail 篇';
  }

  @override
  String get preparingImport => '准备导入文件...';

  @override
  String get importingFilesBusy => '正在导入文件，请稍候';

  @override
  String importingFile(String fileName) {
    return '正在导入: $fileName';
  }

  @override
  String get documentAlreadyExists => '该文献已存在于文库中';

  @override
  String addedDocumentNoPdf(String title) {
    return '已添加「$title」，但未获取到关联 PDF';
  }

  @override
  String get goAdd => '去添加';

  @override
  String addedDocumentTitle(String title) {
    return '已添加: $title';
  }

  @override
  String get networkRequestFailedRetry => '网络请求失败，请稍后重试';

  @override
  String addFailedError(String error) {
    return '添加失败: $error';
  }

  @override
  String resolvingIdentifier(String identifier) {
    return '正在解析标识符: $identifier';
  }

  @override
  String get resolvingIdentifierBusy => '正在解析标识符，请稍候';

  @override
  String get preparingRebuild => '准备重构文库...';

  @override
  String get rebuildInProgress => '文库重构正在进行中';

  @override
  String get rebuildCancelled => '已取消重构文库';

  @override
  String get rebuildComplete => '文库重构完成';

  @override
  String rebuildAdded(int count) {
    return '新增 $count 篇';
  }

  @override
  String rebuildRemoved(int count) {
    return '清理 $count 篇';
  }

  @override
  String rebuildRepaired(int count) {
    return '修复元数据 $count 篇';
  }

  @override
  String rebuildUnresolved(int count) {
    return '仍有 $count 篇待补全元数据';
  }

  @override
  String rebuildNoFile(int count) {
    return '$count 个无文件条目';
  }

  @override
  String get rebuildNormal => '，文库状态正常';

  @override
  String get fetchingZoteroItems => '正在拉取 Zotero 条目...';

  @override
  String get zoteroSyncInProgress => 'Zotero 同步正在进行中';

  @override
  String get zoteroSyncCancelled => '已取消 Zotero 同步';

  @override
  String get fetchingZoteroProgress => '正在拉取 Zotero 条目';

  @override
  String get importingDocuments => '正在导入文献...';

  @override
  String zoteroSyncCompleteAdded(int count) {
    return 'Zotero 同步完成，新增 $count 篇';
  }

  @override
  String get zoteroSyncCompleteNoNew => 'Zotero 同步完成，暂无新增条目';

  @override
  String zoteroSyncFailed(String error) {
    return 'Zotero 同步失败：$error';
  }

  @override
  String get zoteroSyncNetworkFailed => 'Zotero 同步失败：网络请求失败';

  @override
  String existsInLibrary(String title) {
    return '文库中已存在: $title';
  }

  @override
  String importedCountPart(int count) {
    return '导入 $count 篇';
  }

  @override
  String duplicateCountPart(int count) {
    return '重复 $count 篇';
  }

  @override
  String importedFile(String title) {
    return '已导入: $title';
  }

  @override
  String get importCancelledLabel => '已取消导入';

  @override
  String get noFilesImported => '未导入任何文件';

  @override
  String get importCompleteLabel => '导入完成';

  @override
  String get taskBusy => '任务正在进行中';

  @override
  String promptMissingPlaceholders(String placeholders) {
    return '缺少必需占位符：$placeholders';
  }

  @override
  String get expertRequiresVision => '专家模型需要支持图片输入';

  @override
  String get switchedToExpertForImage => '快速模型不支持图片，已切换至专家模型';

  @override
  String get askAi => '问 AI';

  @override
  String get newChat => '新会话';

  @override
  String get chatHistory => '会话历史';

  @override
  String get chatNoHistory => '还没有会话';

  @override
  String get chatInputHint => '针对这篇文献提问…';

  @override
  String get chatEmptyHint => '问点关于这篇文献的问题吧——回答基于提取的全文与图表';

  @override
  String chatMessageCount(int count) {
    return '$count 条消息';
  }

  @override
  String get chatSend => '发送';

  @override
  String get chatRemoveQuote => '移除引用';

  @override
  String get chatLocateSource => '定位原文';

  @override
  String get chatReturnToAi => '返回问 AI';

  @override
  String chatNewSessionHint(String title) {
    return '新会话仍将基于《$title》的全文与图表进行问答';
  }

  @override
  String get chatCopyMessage => '复制消息';

  @override
  String get chatSelectText => '选择文本';

  @override
  String get chatEditingMessage => '正在编辑消息';

  @override
  String get chatEditHint => '编辑将从此处重新开始对话';

  @override
  String get chatFork => '分叉';

  @override
  String get dontRemindAgain => '不再提醒';

  @override
  String get aboutSubtitle => '开源 AI 文献阅读助手';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutSystem => '系统';

  @override
  String get aboutSystemCopyHint => '点击复制系统信息';

  @override
  String get aboutReportIssue => '报告问题';

  @override
  String get aboutReportIssueDesc => '复制系统信息并打开 GitHub 缺陷表单';

  @override
  String get aboutSpecsCopied => '系统信息已复制 — 粘贴到 issue 表单中';

  @override
  String get aboutOpenIssueFailed => '无法打开 GitHub';

  @override
  String get aboutProject => '项目地址';

  @override
  String get aboutCheckUpdate => '检查更新';

  @override
  String get aboutLicense => '开源协议说明';

  @override
  String get aboutDisclaimer => '免责声明';

  @override
  String get aboutDisclaimerContent =>
      '本软件仅供学习交流、科研等非商业性质的用途，严禁将本软件用于商业目的。如有任何商业行为，均与本软件无关';

  @override
  String get aboutAgree => '同意';

  @override
  String get aboutDisagree => '不同意';

  @override
  String get aboutLicenseContent =>
      '本软件依据 GNU 通用公共许可证第三版 (GPL-3.0) 发布。\n\n你可以自由地使用、修改和分发本软件，但修改后的版本必须以相同许可证发布，并公开源代码。\n\n详细条款请参阅项目仓库中的 LICENSE 文件';

  @override
  String get aboutViewFullLicense => '查看全文';

  @override
  String get generalSettings => '通用';

  @override
  String get generalSettingsSubtitle => '日志、缓存与系统偏好';

  @override
  String get generalSystem => '系统';

  @override
  String get generalLogRecording => '日志记录';

  @override
  String get generalLogRecordingDesc => '将日志写入本地文件，便于排查问题';

  @override
  String get generalLogLevel => '最低记录级别';

  @override
  String get generalLogLevelInfo => '信息';

  @override
  String get generalLogLevelWarning => '警告';

  @override
  String get generalLogLevelError => '错误';

  @override
  String get generalExportTodayLog => '导出当前日志';

  @override
  String get generalExportTodayLogDesc => '分享或保存今日日志文件，便于提交缺陷报告';

  @override
  String get generalExportLogEmpty => '尚无日志文件 — 请开启日志记录、复现问题后再导出';

  @override
  String get generalExportLogFailed => '导出日志失败';

  @override
  String generalExportLogSaved(String path) {
    return '日志已保存到 $path';
  }

  @override
  String get generalReportIssue => '报告问题';

  @override
  String get generalReportIssueDesc => '复制系统信息并打开 GitHub 缺陷表单';

  @override
  String get generalHapticFeedback => '震动反馈';

  @override
  String get generalHapticFeedbackDesc => '点击与交互时提供振动反馈';

  @override
  String get generalCacheAutoCleanup => '自动清理缓存';

  @override
  String get generalCacheAutoCleanupDesc => '启动应用时自动清理 WebView 与缩略图缓存';

  @override
  String get generalAutoCheckUpdate => '启动时检查更新';

  @override
  String get generalAutoCheckUpdateDesc => '应用启动时自动检查新版本';

  @override
  String get updateNewVersionFound => '发现新版本';

  @override
  String get updateViewFullChangelog => '查看完整更新日志';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateIgnoreVersion => '忽略此版本';

  @override
  String get updateLater => '稍后';

  @override
  String get updateOpenReleasePage => '打开发布页';

  @override
  String get updateUpToDate => '已是最新版本';

  @override
  String get updateCheckFailed => '检查更新失败';

  @override
  String get updateDownloading => '下载更新中';

  @override
  String get updateDownloadFailed => '下载更新失败';

  @override
  String get generalEnableHttp2 => 'HTTP/2';

  @override
  String get generalEnableHttp2Desc => '将并发 API 请求多路复用到单个连接，减少翻译等并行任务的网络开销';

  @override
  String get onboardingWelcomeTitle => '欢迎使用 OtterPad';

  @override
  String get onboardingWelcomeBody => '让我们完成一些初始设置。你可以稍后在设置中随时更改';

  @override
  String get onboardingStart => '开始设置';

  @override
  String get onboardingSkip => '跳过';

  @override
  String get onboardingOcrTitle => '设置文档 OCR';

  @override
  String get onboardingOcrBody =>
      'OtterPad 使用 PaddleOCR 从 PDF 中提取文字。你需要一个 API Token 才能开始使用';

  @override
  String get onboardingOcrGuide => '前往设置';

  @override
  String get onboardingToolsHint => '通过此按钮可以添加 PDF 文件和进行 OCR 文字提取';

  @override
  String get onboardingAiTitle => '设置 AI 模型';

  @override
  String get onboardingAiBody => '配置 AI 模型以解锁文献对话、翻译等功能。也可以跳过，稍后再设置';

  @override
  String get onboardingAiGuide => '前往配置';

  @override
  String get onboardingExpertHint => '配置多模态模型，用于文献内对话和 OCR 校正';

  @override
  String get onboardingFastHint => '配置快速模型，用于翻译、快问快答和标题重命名';

  @override
  String get onboardingImageGenHint => '配置生图模型，用于生成文献摘要图片';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingFinish => '完成';

  @override
  String get onboardingGotIt => '知道了';

  @override
  String get emptyLibraryTitle => '文献库还是空的';

  @override
  String get emptyLibraryBody => '设置 OCR 和 AI 模型，然后添加你的第一篇 PDF 开始阅读';

  @override
  String get emptyLibraryAction => '初始设置';

  @override
  String get emptyLibraryDropHint => '也可以将 PDF 拖到此处导入';

  @override
  String get dropPdfToImport => '拖入 PDF 以导入';

  @override
  String get dropPdfOnly => '仅支持导入 PDF 文件';

  @override
  String get mineruModel => '解析模型';

  @override
  String get mineruModelHelp => '当前固定使用 VLM 解析；Pipeline 暂未开放。';

  @override
  String get mineruModelVlm => 'VLM';

  @override
  String get mineruExtraFormats => '额外导出格式';

  @override
  String get mineruExtraFormatsHelp =>
      'Markdown 和 JSON 默认生成。勾选的额外格式随结果包保存在文献目录中的 mineru.exports.zip。';

  @override
  String get mineruLangChServer => '繁体与手写体';

  @override
  String get mineruLangJapan => '日文';

  @override
  String get mineruLangKorean => '韩文';

  @override
  String get mineruLangChineseCht => '繁体中文';

  @override
  String get mineruLangTa => '泰米尔文';

  @override
  String get mineruLangTe => '泰卢固文';

  @override
  String get mineruLangKa => '卡纳达文';

  @override
  String get mineruLangEl => '希腊文';

  @override
  String get mineruLangTh => '泰文';

  @override
  String get mineruLangLatin => '拉丁语系';

  @override
  String get mineruLangArabic => '阿拉伯语系';

  @override
  String get mineruLangCyrillic => '西里尔语系';

  @override
  String get mineruLangEastSlavic => '东斯拉夫语系';

  @override
  String get mineruLangDevanagari => '天城文语系';

  @override
  String get reformatSourceChoice => '选择排版来源';

  @override
  String get reformatSourceChoiceHelp => '选择用于正文和图表的 OCR 提取结果。';

  @override
  String get extractProviderChoiceHelp =>
      '选择本次提取使用的 OCR 接口，沿用该接口的解析设置，不改变默认接口。';

  @override
  String get mineruProgressRequestingUpload => '正在申请上传...';

  @override
  String get mineruProgressUploading => '正在上传...';

  @override
  String get mineruProgressQueued => '排队中...';

  @override
  String get mineruProgressParsing => '正在解析...';

  @override
  String get mineruProgressConverting => '正在转换格式...';

  @override
  String get mineruProgressDownloading => '正在下载结果...';

  @override
  String mineruErrInvalidParams(String msg) {
    return '参数错误: $msg';
  }

  @override
  String get mineruErrUnsupportedFormat => '不支持的文件格式';

  @override
  String get mineruErrFileUnreadable => '文件读取失败或为空';

  @override
  String get mineruErrFileTooLarge => '文件超过 200MB 大小限制';

  @override
  String get mineruErrTooManyPages => '页数超过单文件 200 页限制';

  @override
  String get mineruErrFileTimeout => '文件读取超时';

  @override
  String get mineruErrParseFailed => '文档解析失败';

  @override
  String get mineruErrConvertFailed => '文件 / 格式转换失败';

  @override
  String get mineruErrQuotaExhausted => '今日解析额度已用尽，请明日再试';

  @override
  String mineruErrUnknown(String code) {
    return '未知错误 ($code)';
  }

  @override
  String get mineruErrTokenInvalid => 'API Token 无效（A0202）';

  @override
  String get mineruErrTokenExpired => 'API Token 已过期（A0211）';

  @override
  String mineruErrRequestRejected(String code, String msg) {
    return '请求被拒绝 ($code): $msg';
  }

  @override
  String mineruErrRequestUploadFailed(String detail) {
    return '申请上传失败: $detail';
  }

  @override
  String get mineruErrMissingFileUrls => '申请上传响应缺少 batch_id / file_urls';

  @override
  String mineruErrUploadFailed(String file, String detail) {
    return '上传文件失败 ($file): $detail';
  }

  @override
  String mineruErrPollFailed(String detail) {
    return '查询结果失败: $detail';
  }

  @override
  String mineruErrDownloadFailed(String detail) {
    return '下载结果失败: $detail';
  }

  @override
  String get mineruErrMissingResultUrl => '任务完成但无结果链接';

  @override
  String get mineruErrTaskFailed => '解析失败';

  @override
  String mineruErrSaveResultFailed(String detail) {
    return '保存结果失败: $detail';
  }

  @override
  String get mineruErrResultPackageIncomplete => 'MinerU 结果包缺少 full.md 或结构化结果';

  @override
  String get exportDocuments => '导出文献';

  @override
  String get exportNotesMarkdown => '笔记和标注（Markdown）';

  @override
  String get exportCitationsBibtex => '参考文献（BibTeX）';

  @override
  String get exportNoNotes => '这篇文献还没有标注或笔记。';

  @override
  String get exportNoDocuments => '所选文献已不存在。';

  @override
  String get documentExportSaved => '导出文件已保存';

  @override
  String get zoteroLocalTitle => '本机 Zotero';

  @override
  String get zoteroLocalEntryHint => '从这台电脑上的 Zotero 导入题录和 PDF';

  @override
  String get zoteroLocalHint => '请打开 Zotero，并在高级设置中允许其他应用与它通信。';

  @override
  String get zoteroLocalPort => '连接端口';

  @override
  String get zoteroLocalConnect => '读取文库';

  @override
  String get zoteroLocalInvalidPort => '请输入 1 到 65535 之间的端口号。';

  @override
  String get zoteroLocalDirectory => '选择 Zotero 资料库文件夹';

  @override
  String get zoteroLocalDirectorySelected => '更换 Zotero 资料库文件夹';

  @override
  String get zoteroLocalDirectoryHint =>
      '这个版本的 Zotero 需要选择资料库位置。请选择包含 zotero.sqlite 的文件夹；切换资料库后请重新选择。';

  @override
  String zoteroLocalLoading(int fetched, int total) {
    return '正在读取 $fetched / $total 条记录';
  }

  @override
  String zoteroLocalSelection(int selected, int total) {
    return '已选 $selected / $total 篇文献';
  }

  @override
  String get zoteroLocalEmpty => '个人文库中没有可导入的文献。';

  @override
  String get zoteroLocalMetadataOnly => '仅导入题录';

  @override
  String get zoteroLocalChoosePdf => '选择 PDF';

  @override
  String get zoteroLocalNoPdf => '没有 PDF 附件，仍可导入题录。';

  @override
  String get zoteroLocalImport => '导入所选';

  @override
  String get zoteroLocalUnavailable => '无法连接 Zotero。请打开 Zotero，并检查端口号。';

  @override
  String get zoteroLocalDisabled =>
      '请在 Zotero 的高级设置中允许此计算机上的其他应用程序与 Zotero 通信。';

  @override
  String get zoteroLocalIncompatible =>
      '这个 Zotero 客户端不支持所需的本地接口。请更新 Zotero 后重试。';

  @override
  String get zoteroLocalChanged => '读取期间 Zotero 文库发生变化，请重新读取文库后再导入。';

  @override
  String get zoteroLocalInvalidResponse => 'Zotero 返回的数据不完整或无法识别，请重新读取文库。';

  @override
  String get zoteroLocalInvalidFile => '这个附件不是本机 PDF 文件。';

  @override
  String get zoteroLocalFailed => '本机 Zotero 导入失败。请检查连接和文件夹访问权限后重试。';

  @override
  String get zoteroLocalStopped => '本次导入未完成，已处理的文献会保留，可以重试。';

  @override
  String zoteroLocalResult(
    int added,
    int updated,
    int copied,
    int missing,
    int kept,
    int failed,
  ) {
    return '题录新增 $added 篇、更新 $updated 篇；PDF 补齐 $copied 份、本机未就绪 $missing 份、保留已有 $kept 份。失败 $failed 篇。';
  }

  @override
  String get readerFontSerif => '衬线';

  @override
  String get readerFontSans => '无衬线';

  @override
  String get readerWidthFluid => '自适应';

  @override
  String get readerHorizontalMargin => '左右留白';

  @override
  String get readerVerticalMargin => '上下留白';

  @override
  String get readerReadingProgress => '阅读进度';

  @override
  String get readerTextAppearance => '文本与背景';

  @override
  String get readerPageLayout => '页面布局';

  @override
  String get readerReadingOptions => '阅读方式';

  @override
  String get readerFontSizeHint => '调整流式阅读正文的字号。';

  @override
  String get readerMarginHint => '调整阅读区域的留白，PDF 与流式查看共享此设置。';

  @override
  String get readerAutoLayoutHint =>
      '连续上下滚动。宽屏双语按段落左原文、右译文对照，PDF 双语并排显示同一页；窄窗自动调整。';

  @override
  String get readerContinuousReading => '连续阅读';

  @override
  String get readerContinuousReadingHint => '正文连续上下滚动，双语对照随窗口宽度自动切换左右或上下布局。';

  @override
  String get restoreModeOverwrite => '覆盖恢复';

  @override
  String get restoreModeOverwriteDescription => '清除本地数据后用备份替换';

  @override
  String get restoreModeMerge => '合并恢复';

  @override
  String get restoreModeMergeDescription => '保留本地数据，仅添加备份中不存在的内容';

  @override
  String get restoreScopeFull => '完整恢复';

  @override
  String get restoreScopeFullDescription => '恢复文库与设置';

  @override
  String get restoreScopeLibrary => '仅恢复文库数据';

  @override
  String get restoreScopeLibraryDescription => '恢复文献库、收藏、标注和文档文件';

  @override
  String get restoreScopeSettings => '仅恢复设置';

  @override
  String get restoreScopeSettingsDescription => '恢复设置类数据';

  @override
  String get historyToday => '今天';

  @override
  String get historyYesterday => '昨天';

  @override
  String get historyThisWeek => '本周';

  @override
  String get historyThisMonth => '本月';

  @override
  String historyMonth(DateTime month) {
    final intl.DateFormat monthDateFormat = intl.DateFormat.yMMMM(localeName);
    final String monthString = monthDateFormat.format(month);

    return '$monthString';
  }

  @override
  String get libraryName => 'OtterPad 文库';

  @override
  String get rebuildScanningFiles => '正在扫描 PDF 文件…';

  @override
  String get rebuildCheckingFiles => '正在检查文件完整性…';

  @override
  String get rebuildExtractingMetadata => '正在提取 PDF 元数据…';

  @override
  String exportSelectionSummary(int count) {
    return '已选 $count 篇文献';
  }

  @override
  String get exportNotesDescription => '将原文摘录、标注和笔记整理到一个文件。';

  @override
  String get exportCitationsDescription => '导出作者、题名与出版信息，用于论文引用。';

  @override
  String get zoteroLocalConnection => '连接本机文库';

  @override
  String get zoteroLocalDocuments => '选择文献与 PDF';

  @override
  String get zoteroLocalSelectionHint =>
      '补齐缺失的 PDF，保留已有 PDF 和你手动改过的题录。多个附件时请选择要导入的 PDF。';

  @override
  String get webSearchSettingsTitle => '联网搜索服务';

  @override
  String get webSearchSettingsDesc =>
      '优先使用模型原生搜索；模型不支持时使用所选服务。各服务的 API Key 独立保存，切换不会清空。';

  @override
  String get webSearchNotConfigured => '请在 AI 设置中为所选联网搜索服务配置 API Key。';

  @override
  String get chatToggleKeyVisibility => '显示或隐藏 API Key';

  @override
  String get chatSelectModel => '选择模型';

  @override
  String get chatNoModels => '请先在 AI 设置中添加对话模型';

  @override
  String get chatFastTextOnly => '快速模型仅接收文本，本轮及历史中的配图均不会发送；正文和图注仍保留。';

  @override
  String get chatModelTextOnly => '当前模型不支持图片，本轮仅发送正文和图注。';

  @override
  String get chatProcess => 'ReAct 链';

  @override
  String get chatProcessRunning => 'ReAct 链运行中';

  @override
  String get chatReasoning => '思考';

  @override
  String get chatStepRunning => '进行中';

  @override
  String get chatStepCompleted => '已完成';

  @override
  String get chatStepFailed => '失败';

  @override
  String get chatStepCancelled => '已停止';

  @override
  String chatStepDuration(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get chatImageUnavailable => '图片暂不可用';

  @override
  String get chatPreviewFigure => '查看图片与图注';

  @override
  String get chatReadLink => '读取链接';

  @override
  String get chatExpandQuote => '展开引用';

  @override
  String get chatCollapseQuote => '收起引用';

  @override
  String get chatSourceNotFound => '未找到对应原文，文献内容可能已更新。';

  @override
  String get metadataCertificateFailed => '无法验证元数据服务的 TLS 证书，请检查系统信任证书和代理配置。';

  @override
  String get metadataProxyFailed => '代理连接或认证失败，请检查代理及网络设置。';

  @override
  String get metadataRequestTimedOut => '元数据请求超时，请稍后重试。';

  @override
  String get metadataNotFound => '未找到对应的文献元数据。';

  @override
  String get metadataConnectionFailed => '无法连接元数据服务，请检查网络。';

  @override
  String get tableCopyTsv => '复制到电子表格（TSV）';

  @override
  String get tableCopyMarkdown => '复制 Markdown';

  @override
  String get tableFlattenNote => 'TSV 和 Markdown 会展平合并单元格；内容仅放在起始格。';

  @override
  String tableSourcePages(String pages) {
    return '来源页码：$pages';
  }

  @override
  String figureFallback(String kind, int page) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'table': '表格',
      'chart': '图表',
      'other': '插图',
    });
    return '$_temp0 · 第 $page 页';
  }

  @override
  String get figureDataLayer => '解析蒙版';

  @override
  String get figureDataSource => '来自文献提取 JSON · 不请求 AI';

  @override
  String get figureDataUnavailable => '此图没有可用的表格或图表解析内容，仍可查看与导出原图。';

  @override
  String get figureDataLoadFailed => '无法读取提取 JSON，仍可查看与导出原图。';

  @override
  String get figureDataStale => '提取 JSON 与此图的来源版本不一致，请重新提取图表后查看解析内容。';

  @override
  String get figureDataIncomplete => '部分来源块没有可用数据，蒙版及其导出仅包含已取得的部分。';

  @override
  String get figureFitImage => '适应窗口';

  @override
  String get figureOverlayOpacity => '蒙版不透明度';

  @override
  String get figureCopyCaption => '复制题注';

  @override
  String get figureExport => '导出';

  @override
  String get figureExportHtml => '表格数据（.html）';

  @override
  String get figureExportTsv => '电子表格数据（.tsv）';

  @override
  String get figureExportMarkdown => '表格数据（.md）';

  @override
  String get figurePrevious => '上一张';

  @override
  String get figureNext => '下一张';

  @override
  String get figureCaption => '题注';

  @override
  String get figureHideCaption => '收起题注';

  @override
  String get figureShowCaption => '展开题注';

  @override
  String get websiteTitle => 'OtterPad · 把论文读进去';

  @override
  String get websiteDocsTitle => '开始使用 · OtterPad 使用指南';

  @override
  String get websiteDescription =>
      '在手机和桌面上阅读与管理学术文献。PDF 重排、双语对照、图表提取与全文问答，让注意力回到论文。';

  @override
  String get websiteSkip => '跳转到正文';

  @override
  String get websiteNavigation => '主导航';

  @override
  String get websiteFeatures => '功能';

  @override
  String get websiteGuide => '使用指南';

  @override
  String get websiteDownload => '下载';

  @override
  String get websiteDownloadApp => '下载 OtterPad';

  @override
  String get websiteGetStarted => '开始使用';

  @override
  String get websiteResources => '资源';

  @override
  String get websiteFooterDescription => '为手机与桌面上的学术阅读而做。';

  @override
  String get websiteReleases => '版本发布';

  @override
  String get websiteFeedback => '反馈问题';

  @override
  String get websiteOpenSource => '开源';

  @override
  String get websiteEyebrow => '学术文献阅读与管理';

  @override
  String get websiteHeroFirst => '在手机和桌面，';

  @override
  String get websiteHeroSecond => '好好读论文。';

  @override
  String get websiteHeroDescription =>
      '把复杂的 PDF 变成好读的文献。重排、翻译、图表与问答，放在同一个阅读空间里。';

  @override
  String get websitePreview => '阅读界面预览';

  @override
  String get websiteBilingual => '双语重排';

  @override
  String get websitePdf => 'PDF 对照';

  @override
  String get websiteLibrary => '文献库';

  @override
  String get websiteDesktopPreview => '桌面端 · 主题预览';

  @override
  String get websiteReadingAlt => 'OtterPad 桌面阅读器，左侧英文原文、右侧中文译文，正文中保留论文图表';

  @override
  String get websitePdfAlt => 'OtterPad PDF 原文与译文左右对照，保留论文版面';

  @override
  String get websiteLibraryAlt => 'OtterPad 文献库中的论文封面、期刊信息和阅读进度';

  @override
  String get websiteReadingCaption => '原文与译文并排，图表留在上下文里。';

  @override
  String get websitePdfCaption => '保留熟悉的 PDF 版面，对照阅读原文与译文。';

  @override
  String get websiteLibraryCaption => '封面、期刊与阅读进度，让下一篇文献更容易找到。';

  @override
  String get websiteReadingGuide => '阅读指南';

  @override
  String get websiteLibraryGuide => '了解文献管理';

  @override
  String get websiteSummaryRead => '读得顺';

  @override
  String get websiteSummaryReadBody => '复杂版面重新排，原文与译文对照。字号与主题按你的习惯调整。';

  @override
  String get websiteSummaryUnderstand => '看得明白';

  @override
  String get websiteSummaryUnderstandBody => '把图表展开，带着全文提问。需要核对时，回到原文继续读。';

  @override
  String get websiteSummaryOrganize => '放得有序';

  @override
  String get websiteSummaryOrganizeBody => '检索、分类、Zotero 同步与云备份，让读过的文献有处可寻。';

  @override
  String get websiteReadingLabel => '阅读与理解';

  @override
  String get websiteMobileTitle => '小屏幕，也容得下整篇论文。';

  @override
  String get websiteMobileBody =>
      '从双栏 PDF 到连贯的段落，在通勤或桌前都能接着读。图表、译文和问题，始终围绕同一篇文献。';

  @override
  String get websiteMobileReadingAlt => '手机上的双语重排阅读，英文段落与中文译文上下排列';

  @override
  String get websiteMobileFiguresAlt => '手机上的论文图表列表，可单独打开查看';

  @override
  String get websiteReflow => '适合小屏的重排';

  @override
  String get websiteReflowBody =>
      '通过 PaddleOCR 或 MinerU 解析版面，把段落、公式与图表整理为可连续阅读的内容。';

  @override
  String get websiteFigures => '图表提取';

  @override
  String get websiteFiguresBody => '图表单独打开、缩放、复制与分享。看清细节，再回到正文。';

  @override
  String get websiteChat => '全文问答';

  @override
  String get websiteScreenshotNote => '截图来自实际应用，展示配色已适配网站主题；界面可能随版本变化。';

  @override
  String get websiteLibraryLabel => '文献与工作流';

  @override
  String get websiteWorkspaceTitle => '读过的，和接下来要读的。';

  @override
  String get websiteSearchTitle => '找到文献，也理清文献';

  @override
  String get websiteSearchBody => '多源检索与元数据解析，配合分类、标签和 AI 自动命名，整理自己的文献库。';

  @override
  String get websiteZoteroTitle => '接上已有的文献库';

  @override
  String get websiteZoteroBody => '支持 Zotero 本地文献导入与双向同步，延续已有的文献管理习惯。';

  @override
  String get websiteBackupTitle => '备份到自己的存储';

  @override
  String get websiteBackupBody => '连接 S3 或 WebDAV，备份与恢复文献数据，也可以设置自动备份。';

  @override
  String get websiteModelTitle => '带着全文，向模型提问';

  @override
  String get websiteModelBody =>
      '基于提取的正文与图表问答、翻译段落。支持 OpenAI、Anthropic、Google 与兼容接口。';

  @override
  String get websiteServiceNote => '文献保存在本地。OCR、翻译与 AI 问答会使用你配置的服务；同步和备份需另行配置。';

  @override
  String get websiteLearnMore => '服务与数据';

  @override
  String get websiteDownloadTitle => '从下一篇论文开始。';

  @override
  String get websiteDownloadBody => '选择设备对应的安装包。源代码与版本记录都在 GitHub 上公开。';

  @override
  String get websiteViewDownloads => '前往 GitHub Releases';

  @override
  String get websiteWindowsPackage => 'x64 · 安装器或便携 ZIP';

  @override
  String get websiteMacNote =>
      'macOS 版本适用于 Apple 芯片，尚未签名；首次打开需在系统「隐私与安全性」中放行。Linux 暂不支持。';

  @override
  String get websiteInstallation => '下载与安装';

  @override
  String get websiteOverview => '概览';

  @override
  String get websiteFirstPaper => '读第一篇论文';

  @override
  String get websiteReadingAndTranslation => '阅读与翻译';

  @override
  String get websiteSync => '同步与备份';

  @override
  String get websiteServices => '服务与数据';

  @override
  String get websiteViewSource => '查看源代码';

  @override
  String get websiteDocsIntro =>
      'OtterPad 是一款开源的学术文献阅读与管理工具，支持 Android、Windows 和 macOS。';

  @override
  String get websiteDocsIntroBody =>
      '这份指南从导入第一篇 PDF 开始，介绍重排阅读、翻译、图表与问答，以及文献库的同步和备份。';

  @override
  String get websiteBeforeStart => '开始前';

  @override
  String get websiteBeforeStartBody =>
      '可以先导入 PDF 阅读原文。重排需要配置 OCR 服务；翻译和问答需要配置 AI 服务与模型。两类服务分别设置。';

  @override
  String get websiteInstallBody =>
      '打开 GitHub Releases，按设备与架构选择安装包。升级前可以在应用中备份现有文献数据。';

  @override
  String get websitePlatform => '平台';

  @override
  String get websitePackage => '安装包';

  @override
  String get websiteAndroidInstall => '现代设备选 arm64-v8a；旧款 32 位设备选 armeabi-v7a。';

  @override
  String get websiteStepImport => '导入一份 PDF';

  @override
  String get websiteStepImportBody =>
      '在文献库中使用导入入口选择本地 PDF，然后打开文献。你可以先用 PDF 模式阅读原始版面。';

  @override
  String get websiteStepExtract => '配置 OCR 并提取内容';

  @override
  String get websiteStepExtractBody =>
      '在设置的 OCR 页面选择 PaddleOCR 或 MinerU，填入对应服务的 Token。回到文献，运行内容提取，完成后即可使用重排视图与提取的图表。';

  @override
  String get websiteStepRead => '选择阅读方式';

  @override
  String get websiteStepReadBody =>
      '在原始 PDF 与重排视图间切换。需要译文时，先在 AI 设置中添加服务商和模型，再发起翻译，使用双语对照阅读。';

  @override
  String get websiteReadingDoc =>
      'PDF 模式保留原始页码与排版；重排模式把内容整理成连续段落，更适合手机。桌面上可以并排阅读原文和译文，根据阅读任务选择视图。';

  @override
  String get websiteTranslationTitle => '段落翻译与双语对照';

  @override
  String get websiteTranslationDoc =>
      '翻译按段落进行，并保护公式、代码块和引用编号。已完成的译文会缓存；有未完成的段落时，可重试继续翻译。';

  @override
  String get websiteAppearanceDoc =>
      '在阅读外观设置中调整字号、字体和主题。阅读时可以高亮、添加批注，并通过大纲定位章节。';

  @override
  String get websiteFiguresDoc =>
      '内容提取完成后，可从图表列表打开论文中的图片与表格，放大查看，并使用界面提供的复制或分享操作。';

  @override
  String get websiteFiguresDetail =>
      '图表识别结果取决于原始 PDF 和 OCR 服务。需要核对题注、数值或图文关系时，以原始页面为准。';

  @override
  String get websiteAiDoc =>
      '在 AI 设置中添加 OpenAI、Anthropic、Google 或兼容服务商，填写接口信息并选择模型。提取全文后，在阅读器中打开问答，围绕当前论文提问。';

  @override
  String get websiteAiTipTitle => '从具体问题开始';

  @override
  String get websiteAiTipBody =>
      '例如：“作者如何设置对照组？”“图 2 的结果支持了哪一个结论？”带着明确的问题，更容易回到相应段落核对。';

  @override
  String get websiteAiVerify => '问答使用提取的正文与图表作为上下文，但模型仍可能出错。引用结论之前，请对照原文确认。';

  @override
  String get websiteLibraryDoc =>
      '通过 DOI、PubMed、Crossref、Semantic Scholar 等来源检索与解析元数据，为文献补齐标题、作者和期刊信息。';

  @override
  String get websiteLibraryDetail =>
      '使用分类与标签整理阅读主题，通过封面和阅读进度找回文献。配置 AI 后，也可使用自动命名来整理文件。';

  @override
  String get websiteZoteroDoc =>
      '在数据管理中配置 Zotero API Key，进行文献库同步。也可以使用本地导入入口，从已有的 Zotero 文献库导入内容。';

  @override
  String get websiteBackupDoc =>
      '在数据管理中选择 S3 或 WebDAV，配置自己的存储服务，执行备份或恢复。需要定期备份时，可以启用并配置自动备份。';

  @override
  String get websiteServicesIntro => '不同功能使用的数据范围不同。是否调用外部服务，取决于你使用的功能和配置。';

  @override
  String get websiteLocalFiles => '本地阅读';

  @override
  String get websiteLocalFilesBody => '导入的文献与已生成的阅读内容保存在设备上。';

  @override
  String get websiteOcrService => '文档提取会把待解析的文献发送给选定的 PaddleOCR 或 MinerU 服务。';

  @override
  String get websiteAiServiceTitle => '翻译与问答';

  @override
  String get websiteAiService => '相关文本或图表会发送给所配置的模型服务商；可用额度与费用由服务商决定。';

  @override
  String get websiteSyncService => '启用后，数据会传输到你配置的 Zotero、S3 或 WebDAV 服务。';

  @override
  String get websiteNeedHelp => '遇到问题，或想补充这份指南？';

  @override
  String get websiteOnThisPage => '本页内容';

  @override
  String get websiteMobilePdfAlt => '手机上的原始 PDF 阅读，保留双栏版面与文献图表';

  @override
  String get websiteOriginalPdf => '随时回到原文';

  @override
  String get websiteOriginalPdfBody => '保留 PDF 的页码与排版。需要核对公式、引用或上下文时，回到原始页面。';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String readerTranslationIncomplete(int count) {
    return '還有 $count 個段落未翻譯，重試可繼續。';
  }

  @override
  String get appTitle => 'OtterPad';

  @override
  String get home => '首頁';

  @override
  String get library => '庫';

  @override
  String get outline => '大綱';

  @override
  String get notes => '筆記';

  @override
  String get appearance => '外觀';

  @override
  String get translate => '翻譯';

  @override
  String get retryTranslation => '重試翻譯';

  @override
  String get bilingual => '雙語';

  @override
  String get original => '原文';

  @override
  String get translated => '譯文';

  @override
  String get cancel => '取消';

  @override
  String get save => '儲存';

  @override
  String get delete => '刪除';

  @override
  String get confirm => '確認';

  @override
  String get retry => '重試';

  @override
  String get close => '關閉';

  @override
  String get back => '返回';

  @override
  String get copy => '複製';

  @override
  String get more => '更多';

  @override
  String get add => '新增';

  @override
  String get edit => '編輯';

  @override
  String get remove => '移除';

  @override
  String get done => '完成';

  @override
  String get search => '搜尋';

  @override
  String get test => '測試';

  @override
  String get create => '建立';

  @override
  String get refresh => '重新整理';

  @override
  String get processing => '處理中...';

  @override
  String get cancelAll => '取消全部';

  @override
  String get goToSettings => '前往設定';

  @override
  String get configurationRequired => '需要設定';

  @override
  String get cancelled => '已取消';

  @override
  String get copiedToClipboard => '已複製到剪貼簿';

  @override
  String get settings => '設定';

  @override
  String get navShowLabels => '顯示標籤';

  @override
  String get navHideLabels => '隱藏標籤';

  @override
  String get readerShowNavigation => '顯示導覽列';

  @override
  String get readerHideNavigation => '隱藏導覽列';

  @override
  String get networkSettings => '網路設定';

  @override
  String get networkSettingsSubtitle => '代理 · 連通性測試';

  @override
  String get aiSettings => 'AI 設定';

  @override
  String get aiSettingsSubtitle => '模型介面 · 翻譯設定 · 生圖設定';

  @override
  String get ocrSettings => 'OCR 設定';

  @override
  String get ocrSettingsSubtitle => 'OCR 介面 · 輸出控制 · 辨識增強 · 文件校正';

  @override
  String get appearanceSettings => '顯示設定';

  @override
  String get appearanceSettingsSubtitle => '主題模式 · 主題色彩 · 閱讀設定';

  @override
  String get dataManagement => '資料管理';

  @override
  String get dataManagementSubtitle => '遠端備份 · 本地備份 · Zotero 同步';

  @override
  String get systemSettings => '系統設定';

  @override
  String get about => '關於';

  @override
  String get themeMode => '主題模式';

  @override
  String get autoMode => '自動';

  @override
  String get lightMode => '淺色';

  @override
  String get darkMode => '深色';

  @override
  String get systemMode => '跟隨系統';

  @override
  String get themeColor => '主題色彩';

  @override
  String get readingSettings => '閱讀設定';

  @override
  String get defaultReadingMode => '預設閱讀模式';

  @override
  String get defaultReadingModeHint => '選擇 Markdown 時，若文件無擷取結果將自動回退到 PDF 檢視';

  @override
  String get textSize => '字體';

  @override
  String get appLanguage => '應用語言';

  @override
  String get appLanguageDesc => '覆蓋應用介面的顯示語言';

  @override
  String get systemTextScale => '系統文字縮放';

  @override
  String get textSizeStandard => '標準';

  @override
  String get textSizeLarge => '大';

  @override
  String get textSizeExtraLarge => '特大';

  @override
  String get textSizeHint => '影響整個應用的文字顯示大小，重啟後仍保留';

  @override
  String get readerThemeWhite => '白色';

  @override
  String get readerThemeSepia => '羊皮紙';

  @override
  String get readerThemeGreen => '護眼綠';

  @override
  String get readerThemeNight => '夜間';

  @override
  String get readerThemeDark => '純黑';

  @override
  String get readerThemeWhiteShort => '白色';

  @override
  String get readerThemeSepiaShort => '羊皮';

  @override
  String get readerThemeGreenShort => '護眼';

  @override
  String get readerThemeNightShort => '夜間';

  @override
  String get readerThemeDarkShort => '純黑';

  @override
  String get fontSize => '字號';

  @override
  String get fontFamily => '字體';

  @override
  String get appFont => '應用程式字體';

  @override
  String get appFontSans => 'Sans（無襯線）';

  @override
  String get appFontSerif => 'Serif（襯線）';

  @override
  String get appFontPreview => 'Aa 123 · 中文 · 日本語 · 한국어 · العربية';

  @override
  String get appFontHint => '用於應用程式介面；閱讀器字體另外設定。所選字體缺少的字元會使用系統後備字體。';

  @override
  String get appFontLoadFailed => '無法讀取系統字體，仍可選擇 Sans 或 Serif。';

  @override
  String get appFontSaveFailed => '字體設定未能儲存，請重試。';

  @override
  String get paginationMode => '翻頁方式';

  @override
  String get verticalPagination => '上下翻頁';

  @override
  String get horizontalPagination => '左右翻頁';

  @override
  String get translationStyle => '譯文樣式';

  @override
  String get highlightsAndNotes => '標註與筆記';

  @override
  String get noHighlights => '還沒有標註';

  @override
  String get noHighlightsHint => '選取文字後點擊顏色圓點即可建立';

  @override
  String get editNote => '編輯筆記';

  @override
  String get editNoteTitle => '編輯筆記';

  @override
  String get writeYourThoughts => '寫下你的想法...';

  @override
  String highlightCount(int count) {
    return '$count 條';
  }

  @override
  String get justNow => '剛剛';

  @override
  String minutesAgo(int count) {
    return '$count 分鐘前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小時前';
  }

  @override
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get color => '顏色';

  @override
  String get background => '背景';

  @override
  String get translationDone => '翻譯完成';

  @override
  String get translationCacheUsed => '已載入翻譯快取';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageChinese => '簡體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get recommend => '推薦';

  @override
  String get documentLibrary => '文獻庫';

  @override
  String get recommendContent => '推薦內容';

  @override
  String get batchDelete => '批次刪除';

  @override
  String get searchDocumentsHint => '搜尋文獻...';

  @override
  String get searchDocumentsHintDesktop => '搜尋文獻、作者、關鍵字...';

  @override
  String get enterKeywordToSearch => '輸入關鍵字搜尋文獻';

  @override
  String get noDocumentsFound => '未找到相符的文獻';

  @override
  String get noDocuments => '暫無文獻';

  @override
  String get listView => '列表檢視';

  @override
  String get gridView => '網格檢視';

  @override
  String get tools => '工具';

  @override
  String get addFiles => '新增檔案';

  @override
  String get addByIdentifier => '透過識別碼新增';

  @override
  String get rebuildLibrary => '重建文庫';

  @override
  String get addByIdentifierTitle => '透過識別碼新增條目';

  @override
  String get batchExtracting => '批次擷取中';

  @override
  String get extractionDone => '擷取完成';

  @override
  String get cancelExtraction => '取消擷取';

  @override
  String get waitingSubmit => '等待提交';

  @override
  String get extractionComplete => '擷取完成';

  @override
  String extractionCompletePages(int totalPages) {
    return '完成（共 $totalPages 頁）';
  }

  @override
  String get extractionFailed => '擷取失敗';

  @override
  String get extractionCancelled => '已取消擷取';

  @override
  String failedCount(int failed) {
    return '完成（$failed 篇失敗）';
  }

  @override
  String get exitMultiSelect => '退出多選';

  @override
  String get deselectAll => '取消全選';

  @override
  String get selectAll => '全選';

  @override
  String get textExtraction => '文字擷取';

  @override
  String get addToFavorite => '加入收藏夾';

  @override
  String get removeFromFavorite => '移出收藏夾';

  @override
  String get openInReader => '開啟';

  @override
  String get enterSelection => '進入多選';

  @override
  String get deleteFavorite => '刪除收藏夾';

  @override
  String get myLibrary => '我的庫';

  @override
  String get readingHistory => '閱讀歷史';

  @override
  String get noFileEntries => '無檔案條目';

  @override
  String get favorites => '收藏夾';

  @override
  String get addDocument => '新增文獻';

  @override
  String get addDocuments => '新增文獻';

  @override
  String get allDocumentsHaveFiles => '所有文獻都有對應檔案';

  @override
  String get attachFile => '附加檔案';

  @override
  String get viewInBrowser => '在瀏覽器中檢視';

  @override
  String get redownload => '重新下載';

  @override
  String get entryDeleted => '已刪除條目';

  @override
  String get fileAttached => '檔案附加成功';

  @override
  String get clearHistory => '清空歷史';

  @override
  String get noReadingHistory => '暫無閱讀記錄';

  @override
  String get removedFromHistory => '已從歷史移除';

  @override
  String get clearReadingHistory => '清空閱讀歷史';

  @override
  String get readingHistoryCleared => '已清空閱讀歷史';

  @override
  String get alreadyInFavorite => '已包含目前文獻';

  @override
  String get createFavorite => '新建收藏夾';

  @override
  String get createThenSelect => '建立後可在下方勾選';

  @override
  String get editFavorite => '編輯收藏夾';

  @override
  String get selectIcon => '選擇圖示';

  @override
  String get favoriteName => '收藏夾名稱';

  @override
  String get unnamed => '未命名';

  @override
  String get enterFavoriteName => '輸入收藏夾名稱';

  @override
  String get documentNotInFavorite => '此文獻不在收藏夾中';

  @override
  String get moveToFavorite => '移入收藏夾';

  @override
  String get libraryEmpty => '文獻庫為空';

  @override
  String selectedCount(int count) {
    return '確認 ($count)';
  }

  @override
  String get alreadyInThisFavorite => '已在收藏夾';

  @override
  String get reformatDone => '重新排版完成';

  @override
  String get viewPdf => '檢視 PDF';

  @override
  String get viewExtractResult => '檢視擷取結果';

  @override
  String get documentExtract => '文件擷取';

  @override
  String get loadFailed => '載入失敗';

  @override
  String get extractResultEmpty => '擷取結果為空';

  @override
  String get copyAll => '複製全部';

  @override
  String get share => '分享';

  @override
  String get generateSummary => '產生摘要圖';

  @override
  String get reExtract => '重新擷取';

  @override
  String get documentInfo => '文獻資訊';

  @override
  String get viewSummary => '檢視摘要圖';

  @override
  String get reformat => '重新排版';

  @override
  String get reTranslate => '重新翻譯';

  @override
  String get searchContent => '搜尋正文內容';

  @override
  String get exitSearch => '退出搜尋';

  @override
  String get matchCase => '區分大小寫';

  @override
  String get matchWholeWord => '全字相符';

  @override
  String get noMatchFound => '未找到相符內容';

  @override
  String get previousResult => '上一個結果';

  @override
  String get nextResult => '下一個結果';

  @override
  String get translateText => '翻譯';

  @override
  String get deleteHighlight => '刪除醒目提示';

  @override
  String get saveNote => '儲存';

  @override
  String get streaming => '串流接收中';

  @override
  String get copied => '已複製';

  @override
  String get addToNote => '新增到筆記';

  @override
  String get copyTranslation => '複製譯文';

  @override
  String get copyOriginal => '複製原文';

  @override
  String get closeImage => '關閉';

  @override
  String get copyImage => '複製圖片';

  @override
  String get shareImage => '分享圖片';

  @override
  String get saveImage => '儲存圖片';

  @override
  String get imageNotFound => '圖片檔案不存在';

  @override
  String get saveImageTitle => '儲存圖片';

  @override
  String get savedToGallery => '已儲存到相簿';

  @override
  String get galleryAccessDenied => '未取得相簿存取權限';

  @override
  String get showOriginal => '顯示原文';

  @override
  String get showTranslation => '顯示翻譯';

  @override
  String get viewInDocument => '在文中檢視';

  @override
  String get viewOriginalImage => '檢視原圖';

  @override
  String get generatingSummary => '正在產生摘要圖…';

  @override
  String get referencesNotFound => '未找到參考文獻';

  @override
  String get author => '作者';

  @override
  String get journal => '期刊';

  @override
  String get year => '年份';

  @override
  String get modelApi => '模型介面';

  @override
  String get translationSettings => '翻譯設定';

  @override
  String get imageGenSettings => '生圖設定';

  @override
  String get deleteProvider => '刪除服務商';

  @override
  String get providers => '服務商';

  @override
  String get addProvider => '新增服務商';

  @override
  String get selectProtocol => '選擇協定';

  @override
  String get manageModels => '管理模型';

  @override
  String get addApiKeyFirst => '填寫 API Key 以管理模型';

  @override
  String get models => '模型';

  @override
  String get globalModelRoles => '全域模型角色';

  @override
  String get expertModel => '專家模型';

  @override
  String get fastModel => '快速模型';

  @override
  String get imageModel => '生圖模型';

  @override
  String get notSet => '未設定';

  @override
  String get pleaseAddImageModel => '請先新增支援圖片輸出的模型';

  @override
  String get pleaseAddMultimodalModel => '請先新增多模態模型';

  @override
  String get pleaseAddModels => '請先在各服務商下新增模型';

  @override
  String get providerName => '服務商名稱';

  @override
  String get nameField => '名稱';

  @override
  String get detectModel => '偵測模型';

  @override
  String get modelType => '模型類型';

  @override
  String get chat => '聊天';

  @override
  String get embedding => '嵌入';

  @override
  String get inputMode => '輸入模式';

  @override
  String get text => '文字';

  @override
  String get image => '多模態';

  @override
  String get outputMode => '輸出模式';

  @override
  String get capabilities => '能力';

  @override
  String get reasoning => '推理';

  @override
  String get resetToAuto => '重設為自動推斷';

  @override
  String get defaultLevel => '預設';

  @override
  String get off => '關閉';

  @override
  String get low => '低';

  @override
  String get medium => '中等';

  @override
  String get high => '高';

  @override
  String get ultraHigh => '超高';

  @override
  String get thinkingIntensity => '思考強度';

  @override
  String get fetchModelsFailed => '取得模型清單失敗';

  @override
  String get showAllModels => '顯示全部模型';

  @override
  String get showImageGenModels => '僅顯示生圖模型';

  @override
  String get showMultimodalModels => '僅顯示多模態模型';

  @override
  String get noImageGenModels => '未偵測到支援圖片輸出的模型';

  @override
  String get noMultimodalModels => '未偵測到多模態模型';

  @override
  String get noResults => '無相符結果';

  @override
  String get expert => '專家';

  @override
  String get fast => '快速';

  @override
  String get imageGen => '生圖';

  @override
  String get addModel => '新增';

  @override
  String addModelById(String id) {
    return '新增「$id」';
  }

  @override
  String get removeModel => '移除';

  @override
  String get addModelTitle => '新增模型';

  @override
  String get restoreDefaults => '恢復預設';

  @override
  String get targetLanguage => '目標語言';

  @override
  String get translationStyleSetting => '譯文樣式';

  @override
  String get translationIgnore => '翻譯忽略內容';

  @override
  String get temperature => '溫度';

  @override
  String get systemPrompt => '系統提示詞';

  @override
  String get userPrompt => '使用者提示詞';

  @override
  String get classicPhotography => '經典攝影';

  @override
  String get referenceImageCount => '參考圖數量';

  @override
  String get aspectRatio => '畫幅比例';

  @override
  String get resolution => '清晰度';

  @override
  String get proxy => '代理';

  @override
  String get customProxy => '自訂代理';

  @override
  String get customProxySubtitle => '手動指定代理位址';

  @override
  String get hostAddress => '主機位址';

  @override
  String get port => '連接埠';

  @override
  String get systemProxy => '系統代理';

  @override
  String get systemProxySubtitle => '使用系統環境變數中的代理設定';

  @override
  String get noProxy => '不使用代理';

  @override
  String get noProxySubtitle => '直接連線網路';

  @override
  String get connectivityTest => '連通性測試';

  @override
  String get testAddress => '測試位址';

  @override
  String get connectionTimeout => '連線逾時';

  @override
  String get connectionOk => '連線正常';

  @override
  String get connectionFailed => '連線失敗';

  @override
  String get remoteBackup => '遠端備份';

  @override
  String get backupMethod => '備份方式';

  @override
  String get localBackup => '本地備份';

  @override
  String get exportBackup => '匯出備份檔案';

  @override
  String get restoreFromBackup => '從備份檔案還原';

  @override
  String get storage => '儲存空間';

  @override
  String get clearCache => '清除快取';

  @override
  String get clearAllData => '清除所有資料';

  @override
  String get clearAllDataConfirm => '這將刪除所有文獻、資料庫和快取，此操作無法撤銷';

  @override
  String get storageSpace => '儲存空間';

  @override
  String get storageSpaceTotal => '合計';

  @override
  String get storageSpaceDetails => '詳情';

  @override
  String get storageSpaceLoadFailed => '載入儲存資訊失敗';

  @override
  String storageSpaceClearable(String size) {
    return '可清理：$size';
  }

  @override
  String storageSpaceFilesCount(int count) {
    return '$count 個檔案';
  }

  @override
  String get storageGroupPapers => '文獻';

  @override
  String get storageCategoryImages => '圖片';

  @override
  String get storageCategoryFiles => '檔案';

  @override
  String get storageCategoryChat => '聊天紀錄';

  @override
  String get storageCategoryCache => '快取';

  @override
  String get storageCategoryLogs => '日誌';

  @override
  String get storageCategoryDatabase => '資料庫';

  @override
  String get storageSpaceSelected => '已選擇';

  @override
  String get storageSpaceCleared => '已清除所選資料';

  @override
  String get clearData => '清除資料';

  @override
  String clearDataConfirm(String names) {
    return '以下資料將被永久刪除：$names';
  }

  @override
  String get listSeparator => '、';

  @override
  String get resetAndReimport => '重設並全量重新匯入';

  @override
  String get reimport => '重新匯入';

  @override
  String get detecting => '正在偵測連線';

  @override
  String get configure => '設定';

  @override
  String get cacheCleared => '快取已清除';

  @override
  String get allDataCleared => '所有資料已清除';

  @override
  String get saveBackupFile => '儲存備份檔案';

  @override
  String get selectBackupFile => '選擇備份檔案';

  @override
  String get restoreSettingsTitle => '還原設定';

  @override
  String get restoreMethod => '還原方式';

  @override
  String get restoreScope => '還原範圍';

  @override
  String get startMerge => '開始合併';

  @override
  String get startRestore => '開始還原';

  @override
  String get clearField => '清空';

  @override
  String get address => '位址';

  @override
  String get account => '帳號';

  @override
  String get password => '密碼';

  @override
  String get region => '區域';

  @override
  String get objectPath => '物件路徑';

  @override
  String get usePathStyle => '使用路徑式位址';

  @override
  String get remote => '遠端';

  @override
  String get zoteroSync => 'Zotero 同步';

  @override
  String get fullResync => '重設並全量重新匯入';

  @override
  String get layoutAnalysis => '版面分析';

  @override
  String get layoutGeometry => '版面幾何形狀';

  @override
  String get layoutGeometryHelp => '版面偵測框的幾何形狀表示';

  @override
  String get outputControl => '輸出控制';

  @override
  String get repetitionPenalty => '重複抑制強度';

  @override
  String get repetitionPenaltyHint => '結果中出現重複文字、重複表格內容時，可適當調高';

  @override
  String get crossPageTableMerge => '跨頁表格合併';

  @override
  String get crossPageTableMergeDesc => '開啟後，會識別跨頁表格，將其合併為一個';

  @override
  String get recognitionStability => '辨識穩定性';

  @override
  String get recognitionStabilityHint => '結果不穩定或出現明顯幻覺時調低，漏辨識或重複較多時可略微調高';

  @override
  String get recognitionEnhancement => '辨識增強';

  @override
  String get documentCorrection => '文件校正';

  @override
  String get ocrAuto => '自動';

  @override
  String get ocrRectangle => '矩形';

  @override
  String get ocrQuadrilateral => '四邊形';

  @override
  String get ocrPolygon => '多邊形';

  @override
  String get chartRecognition => '圖表辨識';

  @override
  String get stampRecognition => '印章辨識';

  @override
  String get imageAreaOcr => '圖片文字辨識';

  @override
  String get orientationCorrection => '方向校正';

  @override
  String get curvatureCorrection => '彎曲校正';

  @override
  String get deduplicateBoxes => 'NMS後處理';

  @override
  String get multiPageReconstruction => '多頁重構';

  @override
  String get ocrHeader => '頁首';

  @override
  String get ocrHeaderImage => '頁首圖片';

  @override
  String get ocrFooter => '頁尾';

  @override
  String get ocrFooterImage => '頁尾圖片';

  @override
  String get ocrPageNumber => '頁碼';

  @override
  String get ocrFootnote => '腳註';

  @override
  String get ocrSideNote => '旁註';

  @override
  String get searchToolLabel => '搜尋';

  @override
  String get streamOutput => '串流輸出';

  @override
  String get tavilySearchSection => '聯網搜尋回退（Tavily）';

  @override
  String get tavilySearchDesc =>
      '為不支援原生聯網搜尋的模型（如 DeepSeek、豆包）提供搜尋能力。填入 Key 後，對話頁的聯網開關對這些模型即可生效';

  @override
  String get tavilyNotConfiguredHint =>
      '目前模型無原生聯網搜尋，請在 AI 設定中設定 Tavily API Key 以啟用';

  @override
  String get mimoSearchPluginTitle => '開通聯網搜尋外掛';

  @override
  String get mimoSearchPluginHint => 'MiMo 聯網搜尋需先在平台控制台開通外掛';

  @override
  String get mimoSearchPluginOpenConsole => '開啟外掛控制台';

  @override
  String get taskInProgress => '該文獻已有工作正在進行中';

  @override
  String get savingResult => '正在儲存結果';

  @override
  String get saveResultFailed => '儲存結果失敗';

  @override
  String get summaryCancelled => '已取消摘要圖產生';

  @override
  String get preparingContent => '正在整理文獻內容';

  @override
  String get requestingImageModel => '正在請求生圖模型';

  @override
  String get summaryGenerated => '摘要圖已產生';

  @override
  String get downloadCancelled => '已取消下載';

  @override
  String get summaryNotFound => '摘要圖檔案不存在';

  @override
  String get generateSummaryTitle => '產生摘要圖';

  @override
  String get exportAll => '一鍵匯出';

  @override
  String get roleBadgeEmbedding => '嵌入';

  @override
  String get roleBadgeVision => '視覺';

  @override
  String get roleBadgeImageGen => '生圖';

  @override
  String get roleBadgeTools => '工具';

  @override
  String get roleBadgeReasoning => '推理';

  @override
  String storageUsage(String size) {
    return '佔用 $size';
  }

  @override
  String backupTo(String target) {
    return '備份到$target';
  }

  @override
  String uploadBackupTo(String target) {
    return '上傳完整備份到$target';
  }

  @override
  String pleaseConfigureFirst(String target) {
    return '請先設定$target連線資訊';
  }

  @override
  String restoreFromRemote(String target) {
    return '從$target還原';
  }

  @override
  String downloadAndRestore(String target) {
    return '下載$target並還原';
  }

  @override
  String get generateZipAndSave => '產生 zip 備份並儲存到本地';

  @override
  String get selectLocalZipRestore => '選擇本地 zip 備份檔案進行還原';

  @override
  String get thumbnailsAndTemp => '縮圖、暫存檔案等';

  @override
  String get allDataWillBeDeleted => '文獻庫、資料庫將全部刪除';

  @override
  String get getToken => '取得 Token';

  @override
  String get syncZoteroLibrary => '同步 Zotero 文庫';

  @override
  String zoteroImportedPull(int count) {
    return '已匯入 $count 篇 · 拉取新增條目';
  }

  @override
  String get pleaseFillApiKey => '請先填寫 API Key';

  @override
  String get zoteroImportHint => '從 Zotero 個人庫匯入文獻';

  @override
  String get zoteroResetHint => '清除匯入記錄，從 Zotero 重新拉取（找回已刪除條目）';

  @override
  String get resetZoteroSync => '重設 Zotero 同步';

  @override
  String get resetZoteroConfirm =>
      '將清除本地的 Zotero 匯入記錄並從文庫全量重新拉取：已刪除的條目會重新出現，仍在庫中的不會重複。繼續嗎？';

  @override
  String get s3Config => 'S3 設定';

  @override
  String get webDavConfig => 'WebDAV 設定';

  @override
  String remoteNotConfigured(String target) {
    return '未設定$target遠端備份資訊';
  }

  @override
  String s3BucketInfo(String bucket, String region) {
    return 'Bucket：$bucket  ·  區域：$region';
  }

  @override
  String s3ObjectInfo(String key) {
    return '物件：$key';
  }

  @override
  String webDavAccountInfo(String username) {
    return '帳號：$username';
  }

  @override
  String webDavPathInfo(String path) {
    return '路徑：$path';
  }

  @override
  String get clearingCache => '正在清除快取...';

  @override
  String get confirmDeleteAllDataBody => '此操作將刪除所有文獻檔案和資料庫，且無法復原。確定繼續嗎？';

  @override
  String get clearingData => '正在清除資料...';

  @override
  String get generatingLocalBackup => '正在產生本地備份...';

  @override
  String backupExportedTo(String path) {
    return '備份已匯出到 $path';
  }

  @override
  String exportBackupFailed(String error) {
    return '匯出備份失敗：$error';
  }

  @override
  String get mergingBackup => '正在合併備份...';

  @override
  String get restoringBackup => '正在還原備份...';

  @override
  String get backupInvalidData => '備份不完整或已損毀，尚未取代目前資料。';

  @override
  String get backupUnsupportedVersion => '不支援此備份的版本，請先更新 OtterPad 再還原。';

  @override
  String get backupPendingRestore => '偵測到上次還原留下的檔案，已保留這些資料；請先處理上次還原再重試。';

  @override
  String get backupActiveTasks => '背景任務尚未結束，請等待任務結束後再還原。';

  @override
  String get backupChangedDuringCreation => '備份期間資料發生變化，請等待編輯與背景任務結束後重試。';

  @override
  String get backupOperationInProgress => '備份或還原正在進行中，請等待完成後再試。';

  @override
  String restoreFailed(String error) {
    return '還原失敗：$error';
  }

  @override
  String get generatingAndUploading => '正在產生並上傳遠端備份...';

  @override
  String get backupScopeTitle => '備份範圍';

  @override
  String get backupScopeFull => '完整備份';

  @override
  String get backupScopeFullDesc => '包含 PDF 與擷取檔案，備份體積較大';

  @override
  String get backupScopeData => '僅資料';

  @override
  String get backupScopeDataDesc => '設定、中繼資料、標註、翻譯與對話；不含 PDF 與擷取檔案';

  @override
  String get startBackup => '開始備份';

  @override
  String get autoBackup => '自動備份';

  @override
  String get autoBackupOff => '關閉';

  @override
  String get autoBackupDaily => '每日';

  @override
  String get autoBackupWeekly => '每週';

  @override
  String get autoBackupHint => '到期後台自動上傳到遠端，僅在內容有變化時執行';

  @override
  String get cloudSync => '雲同步';

  @override
  String get syncBackupNow => '立即備份';

  @override
  String syncLastBackup(String info) {
    return '上次備份：$info';
  }

  @override
  String get syncLastBackupNever => '尚未備份過';

  @override
  String get syncRemoteNotConfigured => '未設定遠端備份';

  @override
  String get syncRemoteNotConfiguredDesc => '設定 S3 或 WebDAV 後即可備份並在此檢視同步狀態';

  @override
  String get syncGroupChanged => '有變更未備份';

  @override
  String get syncGroupNever => '從未備份';

  @override
  String get syncGroupSynced => '已備份';

  @override
  String get syncReasonAdded => '新匯入';

  @override
  String get syncReasonContent => '檔案變更';

  @override
  String get syncReasonMeta => '中繼資料 / 標註';

  @override
  String get syncReasonFiles => '翻譯 / 對話';

  @override
  String remoteBackupUploaded(String target) {
    return '遠端備份已上傳到 $target';
  }

  @override
  String uploadRemoteFailed(String error) {
    return '上傳遠端備份失敗：$error';
  }

  @override
  String get downloadingRemoteBackup => '正在下載遠端備份...';

  @override
  String get mergingRemoteBackup => '正在合併遠端備份...';

  @override
  String get restoringRemoteBackup => '正在還原遠端備份...';

  @override
  String remoteRestoreFailed(String error) {
    return '遠端還原失敗：$error';
  }

  @override
  String restoreCompleteRefreshed(String prefix) {
    return '$prefix還原完成，目前頁面狀態已同步重新整理';
  }

  @override
  String mergeCompleteUpToDate(String prefix) {
    return '$prefix合併完成，本地資料已是最新';
  }

  @override
  String mergeDocumentsAdded(int count) {
    return '新增 $count 篇文獻';
  }

  @override
  String mergeHighlightsAdded(int count) {
    return '新增 $count 條標註';
  }

  @override
  String mergeFilesCopied(int count) {
    return '複製 $count 個檔案';
  }

  @override
  String mergeSettingsAdded(int count) {
    return '新增 $count 項設定';
  }

  @override
  String mergeCompleteSummary(String prefix, String details) {
    return '$prefix合併完成：$details';
  }

  @override
  String get webDavServerAddress => 'WebDAV 伺服器位址';

  @override
  String get s3Endpoint => 'S3 / R2 / MinIO Endpoint';

  @override
  String get s3ObjectPathDefault => '預設可用 otter-pad/otter_pad_backup.zip';

  @override
  String get s3PathStyleHint => 'MinIO / R2 等 S3 相容服務通常建議開啟';

  @override
  String get selectImageModelFirst => '請先在「AI 設定」中選擇生圖模型';

  @override
  String get summaryUploadFailed => '上傳摘要圖失敗';

  @override
  String estimatedCost(String dollar, String cost) {
    return '目前設定預估費用約 $dollar$cost / 張';
  }

  @override
  String get useAppImageGen => '若希望使用 App 生圖，請點擊 App 生圖，手動上傳素材';

  @override
  String get appImageGen => 'App 生圖';

  @override
  String get markdownNotFound => '未找到 Markdown 檔案，請先完成文件擷取';

  @override
  String promptGenerationFailed(String error) {
    return '產生 prompt 失敗：$error';
  }

  @override
  String get saveExportZip => '儲存匯出 ZIP';

  @override
  String exportedWithPromptCopied(String name) {
    return '已匯出到 $name，prompt 已複製';
  }

  @override
  String exportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String get exportToAppImageGen => '匯出至 App 生圖';

  @override
  String get exportToAppImageGenHint =>
      '將文獻素材匯出後，到 ChatGPT / Gemini 等官方 App 中手動上傳以生圖';

  @override
  String get exportShareHint => '同時分享 figures + Markdown，prompt 自動複製到剪貼簿';

  @override
  String get exportZipHint =>
      '打包 figures + article.md + prompt.md 為 ZIP，prompt 自動複製到剪貼簿';

  @override
  String get ocrChartRecognitionDesc => '將圖表解析為表格';

  @override
  String get ocrStampRecognitionDesc => '辨識文件中的印章';

  @override
  String get ocrImageAreaDesc => '開啟後，對圖片版面元素中的文字進行辨識';

  @override
  String get ocrOrientationDesc => '自動校正 0°/90°/180°/270° 旋轉';

  @override
  String get ocrCurvatureDesc => '校正彎曲或皺褶的文件';

  @override
  String get ocrDeduplicateDesc => '僅當使用版面分析模組時生效，開啟後，會自動移除重複或高度重疊的區域框';

  @override
  String get ocrMultiPageDesc => '重構多頁文件結構';

  @override
  String get ocrFilterHelp => '勾選的標籤區域將不會輸出到 Markdown 結果中，預設全忽略';

  @override
  String get resetOcrSettings => '重設設定';

  @override
  String get resetOcrSettingsConfirm => '這將把除 API Key 外的所有 OCR 設定恢復為預設值，是否繼續？';

  @override
  String get reset => '重設';

  @override
  String get ocrSettingsReset => '已重設 OCR 設定';

  @override
  String get ocrInterface => 'OCR 介面';

  @override
  String get ocrProvider => '服務商';

  @override
  String get ocrProviderHelp =>
      'PaddleOCR 與 MinerU 的 Token 各自獨立儲存，切換服務商不影響已設定的擷取選項';

  @override
  String get mineruOptions => 'MinerU 解析選項';

  @override
  String get mineruScannedOcr => '掃描件 OCR';

  @override
  String get mineruScannedOcrDesc => '掃描版 / 純圖片 PDF 開啟';

  @override
  String get mineruFormulaRecognition => '公式辨識';

  @override
  String get mineruFormulaRecognitionDesc =>
      '預設開啟。VLM 模型下僅影響行內公式；Pipeline 模型下控制公式辨識。';

  @override
  String get mineruTableRecognition => '表格辨識';

  @override
  String get mineruTableRecognitionDesc => '將表格解析為 HTML';

  @override
  String get ocrLanguage => '文件語言';

  @override
  String get ocrLanguageHelp => '選擇文件的主要語言或語系，預設為中英文。';

  @override
  String get ocrLangChinese => '中英文';

  @override
  String get ocrLangEnglish => '英文';

  @override
  String get ocrUsageTitle => '每日配額';

  @override
  String ocrUsagePages(int used, int limit) {
    return '今日已解析 $used / $limit 頁';
  }

  @override
  String get ocrUsageHardLimitNote => '每日硬性上限，超出即遭拒絕。僅為本地估算，以服務商實際計算為準';

  @override
  String get ocrUsagePriorityNote => '優先配額，超出後以較低優先權繼續。僅為本地估算，以服務商實際計算為準';

  @override
  String ocrUsageLimitsLine(int sizeMB, int pages, int batch) {
    return '單檔 ≤ ${sizeMB}MB / $pages 頁 · 批次 ≤ $batch 個檔案';
  }

  @override
  String extractFileTooLarge(int maxMB, int count) {
    return '$count 個檔案超過 ${maxMB}MB 大小限制，已跳過';
  }

  @override
  String extractFileTooLargeSingle(int maxMB) {
    return '檔案超過 ${maxMB}MB 大小限制';
  }

  @override
  String extractTooManyPages(int maxPages) {
    return '頁數超過單一檔案 $maxPages 頁限制';
  }

  @override
  String batchExtractTooManyFiles(int max) {
    return '一次最多批次擷取 $max 個檔案';
  }

  @override
  String get aiFixNotForMinerU => 'MinerU 擷取的文件已自帶圖表說明，無須 AI 修繕';

  @override
  String get aspectSquare => '方形 · 社群配圖';

  @override
  String get aspectClassic => '經典攝影';

  @override
  String get aspectWide => '橫屏影片 · 桌面桌布';

  @override
  String get aspectUltraWide => '超寬螢幕 · 電影';

  @override
  String get aspectTall => '直屏 · 手機桌布';

  @override
  String get imageRefCountHint =>
      '從文獻 figure 按順序選取參考圖，最多 10 張；超出時優先剔除補充圖（Supplementary / Extended Data 等）';

  @override
  String get aspectRatioHint => 'OpenAI 會對應到最接近的輸出尺寸，並在 prompt 中保留比例要求';

  @override
  String get summaryPromptHint =>
      '用於控制文獻摘要圖的視覺風格和資訊組織方式；執行時會自動追加文獻標題、中繼資料、Markdown 和參考 figure';

  @override
  String get summaryPromptLabel => '摘要圖 Prompt';

  @override
  String get summaryPromptFieldHint => '描述文獻摘要圖的版式、顏色、資訊密度和風格要求';

  @override
  String estimatedCostShort(String dollar, String cost) {
    return '預估 $dollar$cost';
  }

  @override
  String get translationTargetLangDesc => '翻譯提示詞中 targetLanguage 變數的實際值';

  @override
  String get translationStyleDesc => '文件全文翻譯時譯文的視覺區分方式';

  @override
  String get translationIgnoreDesc => '勾選的區域翻譯時跳過，取消勾選則合併為整段翻譯';

  @override
  String get temperatureDesc => '越低越穩重，越高越發散';

  @override
  String get systemPromptDesc => '翻譯 System Prompt，支援 targetLanguage 佔位符';

  @override
  String get systemPromptHint => '例如：You are a professional translator…';

  @override
  String get userPromptDesc => '翻譯 User Prompt，支援 targetLanguage 和 input 佔位符';

  @override
  String documentsAddedCount(int added) {
    return '已加入 $added 篇文獻';
  }

  @override
  String documentsAddedSkipped(int added, int skipped) {
    return '已加入 $added 篇文獻，$skipped 篇已存在已跳過';
  }

  @override
  String confirmDeleteDocuments(int count) {
    return '確定要刪除 $count 篇文獻嗎？此操作不可復原';
  }

  @override
  String deletedDocuments(int count) {
    return '已刪除 $count 篇文獻';
  }

  @override
  String get configureExtractToken => '請先在設定中配置文件擷取 Access Token';

  @override
  String get noPdfFilesSelected => '所選文獻中無本地 PDF 檔案，無法擷取';

  @override
  String get pdfNotFound => 'PDF 檔案不存在';

  @override
  String get reformatting => '正在重新排版…';

  @override
  String reformatFailed(String error) {
    return '排版失敗: $error';
  }

  @override
  String get aiFixFigures => 'AI 修繕圖表';

  @override
  String get aiFixFiguresAnalyzing => '正在分析版面...';

  @override
  String get aiFixFiguresCalling => '正在呼叫 AI 模型...';

  @override
  String get aiFixFiguresApplying => '正在套用修繕...';

  @override
  String aiFixFiguresCropping(int done, int total) {
    return '正在裁剪圖表 ($done/$total)';
  }

  @override
  String get aiFixFiguresDone => '圖表已修繕。如需復原請用「重新排版」';

  @override
  String aiFixFiguresFailed(String error) {
    return 'AI 修繕失敗: $error';
  }

  @override
  String get aiFixFiguresCancelled => 'AI 修繕已取消';

  @override
  String get aiFixFiguresMissingExtract => '請先提取文件，再修繕圖表';

  @override
  String get aiFixFiguresModelNotSet => '請先設定專家模型或快速模型';

  @override
  String get aiFixFiguresInvalidLlmOutput => 'AI 回傳內容無法解析，請重試';

  @override
  String get aiFixFiguresFailedGeneric => 'AI 修繕失敗，請重試';

  @override
  String addedToFavorite(String name) {
    return '已新增到「$name」';
  }

  @override
  String addedToFavorites(int count) {
    return '已新增到 $count 個收藏夾';
  }

  @override
  String removedFromFavoriteSingle(String name) {
    return '已從「$name」移出';
  }

  @override
  String removedFromFavorites(int count) {
    return '已從 $count 個收藏夾移出';
  }

  @override
  String translationFailed(String error) {
    return '翻譯失敗：$error';
  }

  @override
  String get pdfFileNotFoundTitle => '找不到該文獻的 PDF 檔案';

  @override
  String removedFromFavoriteCount(int count) {
    return '已從收藏夾移除 $count 篇文獻';
  }

  @override
  String confirmDeleteEntries(int count) {
    return '確定要刪除 $count 個無檔案條目嗎？';
  }

  @override
  String deletedEntries(int count) {
    return '已刪除 $count 個條目';
  }

  @override
  String attachFileFailed(String error) {
    return '附加檔案失敗: $error';
  }

  @override
  String addingDocumentsTo(int total) {
    return '將 $total 篇文獻加入…';
  }

  @override
  String allSelectedAlreadyHere(int count) {
    return '所選 $count 篇已全部在此';
  }

  @override
  String currentDocumentCount(int count) {
    return '目前 $count 篇文獻';
  }

  @override
  String overlapAndNew(int overlap, int newCount) {
    return '已含 $overlap 篇 · 將新增 $newCount 篇';
  }

  @override
  String confirmDeleteFavorite(String name) {
    return '確定要刪除「$name」嗎？收藏夾內的文獻不會被刪除';
  }

  @override
  String favoriteDocumentCount(int count) {
    return '$count 篇文獻';
  }

  @override
  String get clearReadingHistoryConfirm => '將清除所有閱讀記錄，文獻本身不會被刪除。此操作不可復原';

  @override
  String get noReadingHistoryHint => '開啟任意文獻後，這裡會按日期顯示瀏覽順序';

  @override
  String get identifierInputHint => '輸入 ISBN、DOI、PMID 或 arXiv ID 來新增條目到您的文庫：';

  @override
  String get identifierExample => '例如: 10.1038/s41586-021-03811-w';

  @override
  String get addFilesSubtitle => '匯入本地 PDF，並擷取標題、作者、期刊、年份與 DOI';

  @override
  String get addByIdentifierSubtitle => '輸入 DOI、PMID、arXiv ID 或 ISBN 直接建立條目';

  @override
  String get rebuildLibrarySubtitle => '重新掃描目錄，補回 PDF 並重試擷取核心中繼資料';

  @override
  String get downloadPdf => '下載 PDF';

  @override
  String viewLibraryTotal(int count) {
    return '檢視文庫 · 共 $count 篇';
  }

  @override
  String addedDocumentsToFavorite(int count) {
    return '已新增 $count 篇文獻';
  }

  @override
  String get searchDocumentHint => '搜尋文獻標題 / 作者 / 期刊';

  @override
  String get noDocumentsInLibrary => '暫無文獻，請新增 PDF 檔案到文庫';

  @override
  String get providerDescOpenai => 'gpt / o 系列 · 生圖支援 gpt-image';

  @override
  String get providerDescAnthropic => 'Claude 系列';

  @override
  String get providerDescGemini => 'Google AI · 多模態';

  @override
  String get providerDescOpenaiCompatible => 'DeepSeek / 自部署等 OpenAI 相容 API';

  @override
  String confirmDeleteProvider(String name) {
    return '確定刪除「$name」？將清除其 API Key、位址和模型';
  }

  @override
  String modelConnected(String modelId) {
    return '$modelId 連線成功';
  }

  @override
  String get apiAddress => 'API 位址';

  @override
  String get apiKey => 'API Key';

  @override
  String previewUrl(String url) {
    return '預覽: $url';
  }

  @override
  String selectRole(String role) {
    return '選擇$role';
  }

  @override
  String addProtocol(String protocol) {
    return '新增 $protocol';
  }

  @override
  String get assignRoleHint => '為此模型分配場景角色（可選）';

  @override
  String willReplace(String current) {
    return '將取代 $current';
  }

  @override
  String providerModels(String provider) {
    return '$provider 模型';
  }

  @override
  String get searchModelHint => '搜尋模型 ID 或名稱';

  @override
  String connectionOkMs(String ms) {
    return '連線正常，$ms ms';
  }

  @override
  String get cannotConnectCheckProxy => '無法連線，請檢查代理設定';

  @override
  String requestFailed(String error) {
    return '請求失敗：$error';
  }

  @override
  String testFailed(String error) {
    return '測試失敗：$error';
  }

  @override
  String copyFailed(String error) {
    return '複製失敗：$error';
  }

  @override
  String shareFailed(String error) {
    return '分享失敗：$error';
  }

  @override
  String saveFailed(String error) {
    return '儲存失敗：$error';
  }

  @override
  String savedToPath(String path) {
    return '已儲存到 $path';
  }

  @override
  String get figuresNotFoundHint => '未找到圖表\n請先擷取文件';

  @override
  String copiedReference(int number, String snippet) {
    return '已複製 [$number] $snippet';
  }

  @override
  String searchMatchesFound(int count) {
    return '找到 $count 條相符';
  }

  @override
  String get searchPdfContentHint => '搜尋 PDF 內容';

  @override
  String get markdownIgnoreLabels => 'Markdown 忽略標籤';

  @override
  String get resolutionHint => 'OpenAI 對應為 quality；Gemini 對應為 imageSize';

  @override
  String get translationStyleThemed => '主題色';

  @override
  String get translationStyleBold => '粗體';

  @override
  String get translationStyleItalic => '斜體';

  @override
  String get translationStyleWeakened => '弱化';

  @override
  String get translationStyleDashed => '虛線底線';

  @override
  String get translationStyleHighlight => '背景色';

  @override
  String get translationStyleBlur => '模糊';

  @override
  String get translationStyleQuote => '引用';

  @override
  String get skipSectionReferences => '參考文獻';

  @override
  String get skipSectionAcknowledgments => '致謝';

  @override
  String get skipSectionAuthorsContributions => '作者貢獻/利益衝突';

  @override
  String get skipSectionFundingData => '資助/資料聲明';

  @override
  String get skipSectionSupplementaryAppendix => '附錄/補充材料';

  @override
  String get skipSectionEthicsLegends => '倫理聲明/圖表說明';

  @override
  String get fidelityAuto => '自動';

  @override
  String get fidelityStandard => '標準';

  @override
  String get fidelityHigh => '高';

  @override
  String tasksInProgress(int count) {
    return '$count 個任務進行中';
  }

  @override
  String get aiSettingsSelectTextModel => '請先在「AI 設定」中選擇快速模型或專家模型';

  @override
  String get aiSettingsFillApiKey => '請先在「AI 設定」中填寫 API Key';

  @override
  String get aiSettingsFillImageApiKey => '請先在「AI 設定」中填寫圖模型 API Key';

  @override
  String get targetLanguageChangedRetranslate => '目標語言已變更，請重新翻譯';

  @override
  String get preparingTranslation => '準備中';

  @override
  String get noTranslatableParagraphs => '未偵測到可翻譯段落';

  @override
  String waitingExtractTitle(String title) {
    return '等待擷取: $title';
  }

  @override
  String submittingTaskTitle(String title) {
    return '正在提交任務: $title';
  }

  @override
  String extractionCompleteTitle(String title) {
    return '文件擷取完成：$title';
  }

  @override
  String networkError(String message) {
    return '網路錯誤: $message';
  }

  @override
  String extractionFailedDetail(String error) {
    return '擷取失敗: $error';
  }

  @override
  String waitingSubmitTitle(String title) {
    return '等待提交: $title';
  }

  @override
  String submittedWaitingTitle(String title) {
    return '已提交，等待處理: $title';
  }

  @override
  String extractingTitle(String title) {
    return '正在擷取… · $title';
  }

  @override
  String waitingSummaryTitle(String title) {
    return '等待產生摘要圖: $title';
  }

  @override
  String generatingSummaryTitle(String title) {
    return '正在產生摘要圖: $title';
  }

  @override
  String summaryGenerationFailed(String error) {
    return '摘要圖產生失敗: $error';
  }

  @override
  String waitingDownloadTitle(String title) {
    return '等待下載: $title';
  }

  @override
  String downloadingTitle(String title) {
    return '正在下載: $title';
  }

  @override
  String downloadSuccessTitle(String title) {
    return '下載成功：$title';
  }

  @override
  String get downloadFailedNoSource => '下載失敗，未找到可用的 PDF 來源';

  @override
  String downloadFailed(String error) {
    return '下載失敗: $error';
  }

  @override
  String get downloadingPdf => '正在下載 PDF';

  @override
  String downloadCancelledPartial(int count) {
    return '已取消下載，已成功 $count 篇';
  }

  @override
  String downloadCompleteAll(int count) {
    return '下載完成，成功 $count 篇';
  }

  @override
  String downloadCompletePartial(int ok, int fail) {
    return '下載完成：成功 $ok 篇，失敗 $fail 篇';
  }

  @override
  String get preparingImport => '準備匯入檔案...';

  @override
  String get importingFilesBusy => '正在匯入檔案，請稍候';

  @override
  String importingFile(String fileName) {
    return '正在匯入: $fileName';
  }

  @override
  String get documentAlreadyExists => '該文獻已存在於文庫中';

  @override
  String addedDocumentNoPdf(String title) {
    return '已新增「$title」，但未獲取到關聯 PDF';
  }

  @override
  String get goAdd => '去新增';

  @override
  String addedDocumentTitle(String title) {
    return '已新增: $title';
  }

  @override
  String get networkRequestFailedRetry => '網路請求失敗，請稍後重試';

  @override
  String addFailedError(String error) {
    return '新增失敗: $error';
  }

  @override
  String resolvingIdentifier(String identifier) {
    return '正在解析識別碼: $identifier';
  }

  @override
  String get resolvingIdentifierBusy => '正在解析識別碼，請稍候';

  @override
  String get preparingRebuild => '準備重構文庫...';

  @override
  String get rebuildInProgress => '文庫重構正在進行中';

  @override
  String get rebuildCancelled => '已取消重構文庫';

  @override
  String get rebuildComplete => '文庫重構完成';

  @override
  String rebuildAdded(int count) {
    return '新增 $count 篇';
  }

  @override
  String rebuildRemoved(int count) {
    return '清理 $count 篇';
  }

  @override
  String rebuildRepaired(int count) {
    return '修復中繼資料 $count 篇';
  }

  @override
  String rebuildUnresolved(int count) {
    return '仍有 $count 篇待補全中繼資料';
  }

  @override
  String rebuildNoFile(int count) {
    return '$count 個無檔案條目';
  }

  @override
  String get rebuildNormal => '，文庫狀態正常';

  @override
  String get fetchingZoteroItems => '正在拉取 Zotero 條目...';

  @override
  String get zoteroSyncInProgress => 'Zotero 同步正在進行中';

  @override
  String get zoteroSyncCancelled => '已取消 Zotero 同步';

  @override
  String get fetchingZoteroProgress => '正在拉取 Zotero 條目';

  @override
  String get importingDocuments => '正在匯入文獻...';

  @override
  String zoteroSyncCompleteAdded(int count) {
    return 'Zotero 同步完成，新增 $count 篇';
  }

  @override
  String get zoteroSyncCompleteNoNew => 'Zotero 同步完成，暫無新增條目';

  @override
  String zoteroSyncFailed(String error) {
    return 'Zotero 同步失敗：$error';
  }

  @override
  String get zoteroSyncNetworkFailed => 'Zotero 同步失敗：網路請求失敗';

  @override
  String existsInLibrary(String title) {
    return '文庫中已存在: $title';
  }

  @override
  String importedCountPart(int count) {
    return '匯入 $count 篇';
  }

  @override
  String duplicateCountPart(int count) {
    return '重複 $count 篇';
  }

  @override
  String importedFile(String title) {
    return '已匯入: $title';
  }

  @override
  String get importCancelledLabel => '已取消匯入';

  @override
  String get noFilesImported => '未匯入任何檔案';

  @override
  String get importCompleteLabel => '匯入完成';

  @override
  String get taskBusy => '任務正在進行中';

  @override
  String promptMissingPlaceholders(String placeholders) {
    return '缺少必需佔位符：$placeholders';
  }

  @override
  String get expertRequiresVision => '專家模型需要支援圖片輸入';

  @override
  String get switchedToExpertForImage => '快速模型不支持圖片，已切換至專家模型';

  @override
  String get askAi => '問 AI';

  @override
  String get newChat => '新對話';

  @override
  String get chatHistory => '對話歷史';

  @override
  String get chatNoHistory => '還沒有對話';

  @override
  String get chatInputHint => '針對這篇文獻提問…';

  @override
  String get chatEmptyHint => '問點關於這篇文獻的問題吧——回答基於擷取的全文與圖表';

  @override
  String chatMessageCount(int count) {
    return '$count 則訊息';
  }

  @override
  String get chatSend => '發送';

  @override
  String get chatRemoveQuote => '移除引用';

  @override
  String get chatLocateSource => '定位原文';

  @override
  String get chatReturnToAi => '返回問 AI';

  @override
  String chatNewSessionHint(String title) {
    return '新對話仍將基於《$title》的全文與圖表進行問答';
  }

  @override
  String get chatCopyMessage => '複製訊息';

  @override
  String get chatSelectText => '選取文字';

  @override
  String get chatEditingMessage => '正在編輯訊息';

  @override
  String get chatEditHint => '編輯將從此處重新開始對話';

  @override
  String get chatFork => '分叉';

  @override
  String get dontRemindAgain => '不再提醒';

  @override
  String get aboutSubtitle => '開源 AI 文獻閱讀助手';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutSystem => '系統';

  @override
  String get aboutSystemCopyHint => '點擊複製系統資訊';

  @override
  String get aboutReportIssue => '回報問題';

  @override
  String get aboutReportIssueDesc => '複製系統資訊並開啟 GitHub 缺陷表單';

  @override
  String get aboutSpecsCopied => '系統資訊已複製 — 貼上到 issue 表單中';

  @override
  String get aboutOpenIssueFailed => '無法開啟 GitHub';

  @override
  String get aboutProject => '專案地址';

  @override
  String get aboutCheckUpdate => '檢查更新';

  @override
  String get aboutLicense => '開源協議說明';

  @override
  String get aboutDisclaimer => '免責聲明';

  @override
  String get aboutDisclaimerContent =>
      '本軟體僅供學習交流、科研等非商業性質的用途，嚴禁將本軟體用於商業目的。如有任何商業行為，均與本軟體無關';

  @override
  String get aboutAgree => '同意';

  @override
  String get aboutDisagree => '不同意';

  @override
  String get aboutLicenseContent =>
      '本軟體依據 GNU 通用公共許可證第三版 (GPL-3.0) 發布。\n\n你可以自由地使用、修改和散布本軟體，但修改後的版本必須以相同許可證發布，並公開原始碼。\n\n詳細條款請參閱專案儲存庫中的 LICENSE 檔案';

  @override
  String get aboutViewFullLicense => '檢視全文';

  @override
  String get generalSettings => '一般';

  @override
  String get generalSettingsSubtitle => '日誌、快取與系統偏好';

  @override
  String get generalSystem => '系統';

  @override
  String get generalLogRecording => '日誌記錄';

  @override
  String get generalLogRecordingDesc => '將日誌寫入本機檔案，便於排查問題';

  @override
  String get generalLogLevel => '最低記錄層級';

  @override
  String get generalLogLevelInfo => '資訊';

  @override
  String get generalLogLevelWarning => '警告';

  @override
  String get generalLogLevelError => '錯誤';

  @override
  String get generalExportTodayLog => '匯出目前日誌';

  @override
  String get generalExportTodayLogDesc => '分享或儲存今日日誌檔，便於提交缺陷回報';

  @override
  String get generalExportLogEmpty => '尚無日誌檔 — 請開啟日誌記錄、重現問題後再匯出';

  @override
  String get generalExportLogFailed => '匯出日誌失敗';

  @override
  String generalExportLogSaved(String path) {
    return '日誌已儲存到 $path';
  }

  @override
  String get generalReportIssue => '回報問題';

  @override
  String get generalReportIssueDesc => '複製系統資訊並開啟 GitHub 缺陷表單';

  @override
  String get generalHapticFeedback => '震動回饋';

  @override
  String get generalHapticFeedbackDesc => '點擊與互動時提供振動回饋';

  @override
  String get generalCacheAutoCleanup => '自動清理快取';

  @override
  String get generalCacheAutoCleanupDesc => '啟動應用程式時自動清理 WebView 與縮圖快取';

  @override
  String get generalAutoCheckUpdate => '啟動時檢查更新';

  @override
  String get generalAutoCheckUpdateDesc => '應用程式啟動時自動檢查新版本';

  @override
  String get updateNewVersionFound => '發現新版本';

  @override
  String get updateViewFullChangelog => '查看完整更新日誌';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateIgnoreVersion => '忽略此版本';

  @override
  String get updateLater => '稍後';

  @override
  String get updateOpenReleasePage => '開啟發布頁';

  @override
  String get updateUpToDate => '已是最新版本';

  @override
  String get updateCheckFailed => '檢查更新失敗';

  @override
  String get updateDownloading => '下載更新中';

  @override
  String get updateDownloadFailed => '下載更新失敗';

  @override
  String get generalEnableHttp2 => 'HTTP/2';

  @override
  String get generalEnableHttp2Desc => '將並行 API 請求多工到單一連線，減少翻譯等並行任務的網路開銷';

  @override
  String get onboardingWelcomeTitle => '歡迎使用 OtterPad';

  @override
  String get onboardingWelcomeBody => '讓我們完成一些初始設定。你可以稍後在設定中隨時更改';

  @override
  String get onboardingStart => '開始設定';

  @override
  String get onboardingSkip => '跳過';

  @override
  String get onboardingOcrTitle => '設定文件 OCR';

  @override
  String get onboardingOcrBody =>
      'OtterPad 使用 PaddleOCR 從 PDF 中擷取文字。你需要一個 API Token 才能開始使用';

  @override
  String get onboardingOcrGuide => '前往設定';

  @override
  String get onboardingToolsHint => '透過此按鈕可以新增 PDF 檔案和進行 OCR 文字擷取';

  @override
  String get onboardingAiTitle => '設定 AI 模型';

  @override
  String get onboardingAiBody => '設定 AI 模型以解鎖文獻對話、翻譯等功能。也可以跳過，稍後再設定';

  @override
  String get onboardingAiGuide => '前往設定';

  @override
  String get onboardingExpertHint => '設定多模態模型，用於文獻內對話和 OCR 校正';

  @override
  String get onboardingFastHint => '設定快速模型，用於翻譯、快問快答和標題重新命名';

  @override
  String get onboardingImageGenHint => '設定生圖模型，用於產生文獻摘要圖片';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingFinish => '完成';

  @override
  String get onboardingGotIt => '知道了';

  @override
  String get emptyLibraryTitle => '文獻庫還是空的';

  @override
  String get emptyLibraryBody => '設定 OCR 和 AI 模型，然後新增你的第一篇 PDF 開始閱讀';

  @override
  String get emptyLibraryAction => '初始設定';

  @override
  String get emptyLibraryDropHint => '也可以將 PDF 拖到此處匯入';

  @override
  String get dropPdfToImport => '拖入 PDF 以匯入';

  @override
  String get dropPdfOnly => '僅支援匯入 PDF 檔案';

  @override
  String get mineruModel => '解析模型';

  @override
  String get mineruModelHelp => '目前固定使用 VLM 解析；Pipeline 暫未開放。';

  @override
  String get mineruModelVlm => 'VLM';

  @override
  String get mineruExtraFormats => '額外匯出格式';

  @override
  String get mineruExtraFormatsHelp =>
      'Markdown 與 JSON 一律產生。勾選的額外格式隨結果保存在文件目錄的 mineru.exports.zip。';

  @override
  String get mineruLangChServer => '繁體與手寫體';

  @override
  String get mineruLangJapan => '日文';

  @override
  String get mineruLangKorean => '韓文';

  @override
  String get mineruLangChineseCht => '繁體中文';

  @override
  String get mineruLangTa => '泰米爾文';

  @override
  String get mineruLangTe => '泰盧固文';

  @override
  String get mineruLangKa => '卡納達文';

  @override
  String get mineruLangEl => '希臘文';

  @override
  String get mineruLangTh => '泰文';

  @override
  String get mineruLangLatin => '拉丁語系';

  @override
  String get mineruLangArabic => '阿拉伯語系';

  @override
  String get mineruLangCyrillic => '西里爾語系';

  @override
  String get mineruLangEastSlavic => '東斯拉夫語系';

  @override
  String get mineruLangDevanagari => '天城文語系';

  @override
  String get reformatSourceChoice => '選擇重新排版來源';

  @override
  String get reformatSourceChoiceHelp => '選擇用於正文與圖表的 OCR 擷取結果。';

  @override
  String get extractProviderChoiceHelp =>
      '選擇本次擷取使用的 OCR 服務商，將沿用該服務商的解析設定，不會變更預設服務商。';

  @override
  String get mineruProgressRequestingUpload => '正在申請上傳...';

  @override
  String get mineruProgressUploading => '正在上傳...';

  @override
  String get mineruProgressQueued => '排隊中...';

  @override
  String get mineruProgressParsing => '正在解析...';

  @override
  String get mineruProgressConverting => '正在轉換格式...';

  @override
  String get mineruProgressDownloading => '正在下載結果...';

  @override
  String mineruErrInvalidParams(String msg) {
    return '參數錯誤: $msg';
  }

  @override
  String get mineruErrUnsupportedFormat => '不支援的檔案格式';

  @override
  String get mineruErrFileUnreadable => '檔案讀取失敗或為空';

  @override
  String get mineruErrFileTooLarge => '檔案超過 200MB 大小限制';

  @override
  String get mineruErrTooManyPages => '頁數超過單一檔案 200 頁限制';

  @override
  String get mineruErrFileTimeout => '檔案讀取逾時';

  @override
  String get mineruErrParseFailed => '文件解析失敗';

  @override
  String get mineruErrConvertFailed => '檔案 / 格式轉換失敗';

  @override
  String get mineruErrQuotaExhausted => '今日解析配額已用盡，請明日再試';

  @override
  String mineruErrUnknown(String code) {
    return '未知錯誤 ($code)';
  }

  @override
  String get mineruErrTokenInvalid => 'API Token 無效（A0202）';

  @override
  String get mineruErrTokenExpired => 'API Token 已過期（A0211）';

  @override
  String mineruErrRequestRejected(String code, String msg) {
    return '請求遭拒絕 ($code): $msg';
  }

  @override
  String mineruErrRequestUploadFailed(String detail) {
    return '申請上傳失敗: $detail';
  }

  @override
  String get mineruErrMissingFileUrls => '申請上傳回應缺少 batch_id / file_urls';

  @override
  String mineruErrUploadFailed(String file, String detail) {
    return '上傳檔案失敗 ($file): $detail';
  }

  @override
  String mineruErrPollFailed(String detail) {
    return '查詢結果失敗: $detail';
  }

  @override
  String mineruErrDownloadFailed(String detail) {
    return '下載結果失敗: $detail';
  }

  @override
  String get mineruErrMissingResultUrl => '任務完成但無結果連結';

  @override
  String get mineruErrTaskFailed => '解析失敗';

  @override
  String mineruErrSaveResultFailed(String detail) {
    return '儲存結果失敗: $detail';
  }

  @override
  String get mineruErrResultPackageIncomplete => 'MinerU 結果包缺少 full.md 或結構化結果';

  @override
  String get exportDocuments => '匯出文獻';

  @override
  String get exportNotesMarkdown => '筆記與標註（Markdown）';

  @override
  String get exportCitationsBibtex => '參考文獻（BibTeX）';

  @override
  String get exportNoNotes => '這篇文獻還沒有標註或筆記。';

  @override
  String get exportNoDocuments => '所選文獻已不存在。';

  @override
  String get documentExportSaved => '匯出檔案已儲存';

  @override
  String get zoteroLocalTitle => '本機 Zotero';

  @override
  String get zoteroLocalEntryHint => '從這台電腦上的 Zotero 匯入題錄和 PDF';

  @override
  String get zoteroLocalHint =>
      '請開啟 Zotero，並在進階設定中允許其他應用程式與它通訊。讀取個人文庫，補齊缺失的 PDF，保留已有 PDF 和你手動改過的題錄。多個附件時請在下方選擇 PDF。';

  @override
  String get zoteroLocalPort => '連線埠';

  @override
  String get zoteroLocalConnect => '讀取文庫';

  @override
  String get zoteroLocalInvalidPort => '請輸入 1 到 65535 之間的連線埠號。';

  @override
  String get zoteroLocalDirectory => '選擇 Zotero 資料庫資料夾';

  @override
  String get zoteroLocalDirectorySelected => '更換 Zotero 資料庫資料夾';

  @override
  String get zoteroLocalDirectoryHint =>
      '這個版本的 Zotero 需要選擇資料庫位置。請選擇包含 zotero.sqlite 的資料夾；切換資料庫後請重新選擇。';

  @override
  String zoteroLocalLoading(int fetched, int total) {
    return '正在讀取 $fetched / $total 筆記錄';
  }

  @override
  String zoteroLocalSelection(int selected, int total) {
    return '已選 $selected / $total 篇文獻';
  }

  @override
  String get zoteroLocalEmpty => '個人文庫中沒有可匯入的文獻。';

  @override
  String get zoteroLocalMetadataOnly => '僅匯入題錄';

  @override
  String get zoteroLocalChoosePdf => '選擇 PDF';

  @override
  String get zoteroLocalNoPdf => '沒有 PDF 附件，仍可匯入題錄。';

  @override
  String get zoteroLocalImport => '匯入 / 更新所選文獻';

  @override
  String get zoteroLocalUnavailable => '無法連線至 Zotero。請開啟 Zotero，並檢查連線埠號。';

  @override
  String get zoteroLocalDisabled => '請在 Zotero 的進階設定中允許此電腦上的其他應用程式與 Zotero 通訊。';

  @override
  String get zoteroLocalIncompatible =>
      '這個 Zotero 用戶端不支援所需的本機介面。請更新 Zotero 後重試。';

  @override
  String get zoteroLocalChanged => '讀取期間 Zotero 文庫發生變化，請重新讀取文庫後再匯入。';

  @override
  String get zoteroLocalInvalidResponse => 'Zotero 傳回的資料不完整或無法辨識，請重新讀取文庫。';

  @override
  String get zoteroLocalInvalidFile => '這個附件不是本機 PDF 檔案。';

  @override
  String get zoteroLocalFailed => '本機 Zotero 匯入失敗。請檢查連線和資料夾存取權限後重試。';

  @override
  String get zoteroLocalStopped => '本次匯入未完成，已處理的文獻會保留，可以重試。';

  @override
  String zoteroLocalResult(
    int added,
    int updated,
    int copied,
    int missing,
    int kept,
    int failed,
  ) {
    return '題錄新增 $added 篇、更新 $updated 篇；PDF 補齊 $copied 份、本機未就緒 $missing 份、保留已有 $kept 份。失敗 $failed 篇。';
  }

  @override
  String get readerFontSerif => '襯線';

  @override
  String get readerFontSans => '無襯線';

  @override
  String get readerWidthFluid => '自適應';

  @override
  String get readerHorizontalMargin => '左右留白';

  @override
  String get readerVerticalMargin => '上下留白';

  @override
  String get readerReadingProgress => '閱讀進度';

  @override
  String get readerTextAppearance => '文字與背景';

  @override
  String get readerPageLayout => '頁面配置';

  @override
  String get readerReadingOptions => '閱讀方式';

  @override
  String get readerFontSizeHint => '調整流式閱讀內文的字級。';

  @override
  String get readerMarginHint => '調整閱讀區域的留白，PDF 與流式檢視共用此設定。';

  @override
  String get readerAutoLayoutHint =>
      '連續上下捲動。寬螢幕雙語按段落左原文、右譯文對照，PDF 雙語並排顯示同一頁；窄視窗自動調整。';

  @override
  String get readerContinuousReading => '連續閱讀';

  @override
  String get readerContinuousReadingHint => '正文連續上下捲動，雙語對照隨視窗寬度自動切換左右或上下版面。';

  @override
  String get restoreModeOverwrite => '覆寫還原';

  @override
  String get restoreModeOverwriteDescription => '清除本機資料後以備份取代';

  @override
  String get restoreModeMerge => '合併還原';

  @override
  String get restoreModeMergeDescription => '保留本機資料，僅加入備份中尚未存在的內容';

  @override
  String get restoreScopeFull => '完整還原';

  @override
  String get restoreScopeFullDescription => '還原文庫與設定';

  @override
  String get restoreScopeLibrary => '僅還原文庫資料';

  @override
  String get restoreScopeLibraryDescription => '還原文獻庫、收藏、標註與文件';

  @override
  String get restoreScopeSettings => '僅還原設定';

  @override
  String get restoreScopeSettingsDescription => '還原應用程式設定';

  @override
  String get historyToday => '今天';

  @override
  String get historyYesterday => '昨天';

  @override
  String get historyThisWeek => '本週';

  @override
  String get historyThisMonth => '本月';

  @override
  String historyMonth(DateTime month) {
    final intl.DateFormat monthDateFormat = intl.DateFormat.yMMMM(localeName);
    final String monthString = monthDateFormat.format(month);

    return '$monthString';
  }

  @override
  String get libraryName => 'OtterPad 文庫';

  @override
  String get rebuildScanningFiles => '正在掃描 PDF 檔案…';

  @override
  String get rebuildCheckingFiles => '正在檢查檔案完整性…';

  @override
  String get rebuildExtractingMetadata => '正在擷取 PDF 中繼資料…';

  @override
  String get webSearchSettingsTitle => '聯網搜尋服務';

  @override
  String get webSearchSettingsDesc =>
      '優先使用模型原生搜尋；模型不支援時使用所選服務。各服務的 API Key 獨立儲存，切換不會清空。';

  @override
  String get webSearchNotConfigured => '请在 AI 设置中为所选聯網搜尋服務配置 API Key。';

  @override
  String get chatToggleKeyVisibility => '顯示或隱藏 API Key';

  @override
  String get chatSelectModel => '選擇模型';

  @override
  String get chatNoModels => '請先在 AI 設定中新增對話模型';

  @override
  String get chatFastTextOnly => '快速模型僅接收文字，本輪及歷史中的配圖均不會傳送；正文和圖說仍保留。';

  @override
  String get chatModelTextOnly => '目前模型不支援圖片，本輪僅傳送正文和圖說。';

  @override
  String get chatProcess => 'ReAct 鏈';

  @override
  String get chatProcessRunning => 'ReAct 鏈執行中';

  @override
  String get chatReasoning => '思考';

  @override
  String get chatStepRunning => '進行中';

  @override
  String get chatStepCompleted => '已完成';

  @override
  String get chatStepFailed => '失敗';

  @override
  String get chatStepCancelled => '已停止';

  @override
  String chatStepDuration(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get chatImageUnavailable => '圖片暫不可用';

  @override
  String get chatPreviewFigure => '查看圖片與圖說';

  @override
  String get chatReadLink => '讀取連結';

  @override
  String get chatExpandQuote => '展開引用';

  @override
  String get chatCollapseQuote => '收合引用';

  @override
  String get chatSourceNotFound => '找不到對應原文，文獻內容可能已更新。';

  @override
  String get tableCopyTsv => '複製到試算表（TSV）';

  @override
  String get tableCopyMarkdown => '複製 Markdown';

  @override
  String get tableFlattenNote => 'TSV 和 Markdown 會展平合併儲存格；內容僅放在起始格。';

  @override
  String tableSourcePages(String pages) {
    return '來源頁碼：$pages';
  }

  @override
  String figureFallback(String kind, int page) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'table': '表格',
      'chart': '圖表',
      'other': '插圖',
    });
    return '$_temp0 · 第 $page 頁';
  }

  @override
  String get figureDataLayer => '解析遮罩';

  @override
  String get figureDataSource => '來自文獻擷取 JSON · 不請求 AI';

  @override
  String get figureDataUnavailable => '此圖沒有可用的表格或圖表解析內容，仍可查看與匯出原圖。';

  @override
  String get figureDataLoadFailed => '無法讀取擷取 JSON，仍可查看與匯出原圖。';

  @override
  String get figureDataStale => '擷取 JSON 與此圖的來源版本不一致，請重新擷取圖表後查看解析內容。';

  @override
  String get figureDataIncomplete => '部分來源區塊沒有可用資料，遮罩及其匯出僅包含已取得的部分。';

  @override
  String get figureFitImage => '符合視窗';

  @override
  String get figureOverlayOpacity => '遮罩不透明度';

  @override
  String get figureCopyCaption => '複製圖說';

  @override
  String get figureExport => '匯出';

  @override
  String get figureExportHtml => '表格／圖表資料（.html）';

  @override
  String get figureExportTsv => '試算表資料（.tsv）';

  @override
  String get figureExportMarkdown => '表格／圖表資料（.md）';

  @override
  String get figurePrevious => '上一張';

  @override
  String get figureNext => '下一張';

  @override
  String get figureCaption => '圖說';

  @override
  String get figureHideCaption => '收合圖說';

  @override
  String get figureShowCaption => '展開圖說';
}
