// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '獭祭鱼 OtterPad';

  @override
  String get home => '首页';

  @override
  String get library => '文献库';

  @override
  String get outline => '大纲';

  @override
  String get notes => '笔记';

  @override
  String get appearance => '外观';

  @override
  String get font => '字体';

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
  String get cancelled => '已取消';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get settings => '设置';

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
  String get ocrSettingsSubtitle => 'OCR 接口 · 识别参数';

  @override
  String get appearanceSettings => '外观设置';

  @override
  String get appearanceSettingsSubtitle => '主题模式 · 主题色彩 · 阅读设置 · 文字大小';

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
  String get textSize => '文字大小';

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
  String get paginationMode => '翻页方式';

  @override
  String get verticalPagination => '上下翻页';

  @override
  String get horizontalPagination => '左右翻页';

  @override
  String get translationStyle => '译文样式';

  @override
  String get toolbarOpacityOpaque => '不透明';

  @override
  String get toolbarOpacitySlight => '微透明';

  @override
  String get toolbarOpacityGlass => '毛玻璃';

  @override
  String get toolbarOpacityHalf => '半透明';

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
  String get toolbarOpacity => '工具栏透明度';

  @override
  String get translationDone => '翻译完成';

  @override
  String get translationCacheUsed => '使用了之前的翻译缓存，如需重新翻译请点击右上角省略号里的重新翻译';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageChinese => '简体中文';

  @override
  String get languageEnglish => 'English';

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
  String get deleteFavorite => '删除收藏夹';

  @override
  String get myLibrary => '我的库';

  @override
  String get synced => '已同步';

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
  String get copyTranslation => '复制译文';

  @override
  String get copyOriginal => '复制原文';

  @override
  String get closeImage => '关闭';

  @override
  String get copyImage => '复制图片';

  @override
  String get saveImage => '保存图片';

  @override
  String get imageNotFound => '图片文件不存在';

  @override
  String get saveImageTitle => '保存图片';

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
  String get noSummary => '暂无总结图';

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
  String get image => '图片';

  @override
  String get outputMode => '输出模式';

  @override
  String get capabilities => '能力';

  @override
  String get reasoning => '推理';

  @override
  String get resetToAuto => '重置为自动推断';

  @override
  String get builtInTools => '内置工具';

  @override
  String get official => '官方';

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
  String get showImageModels => '仅显示生图模型';

  @override
  String get noImageModels => '未检测到支持图片输出的模型';

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
  String get layoutDetectionThreshold => '版面检测阈值';

  @override
  String get outputControl => '输出控制';

  @override
  String get repetitionPenalty => '重复惩罚';

  @override
  String get repetitionPenaltyHint => '出现重复文字或表格内容时适当调高';

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
  String get imageAreaOcr => '图片区 OCR';

  @override
  String get orientationCorrection => '方向校正';

  @override
  String get curvatureCorrection => '弯曲校正';

  @override
  String get deduplicateBoxes => '去重叠检测框';

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
  String get codeExecutionLabel => '代码执行';

  @override
  String get urlContextLabel => 'URL 上下文';

  @override
  String get youtubeLabel => 'YouTube';

  @override
  String get codeInterpreterLabel => '代码解释器';

  @override
  String get imageGenerationLabel => '图片生成';

  @override
  String get searchToolDesc => '使用网络搜索获取最新信息';

  @override
  String get codeExecutionDesc => '在沙箱中执行代码并返回结果';

  @override
  String get urlContextDesc => '读取 URL 内容作为上下文';

  @override
  String get youtubeDesc => '自动识别并提取 YouTube 视频信息';

  @override
  String get codeInterpreterDesc => '在沙箱中运行代码、处理文件';

  @override
  String get imageGenerationDesc => '在对话中生成图片';

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
  String restoreFailed(String error) {
    return '恢复失败：$error';
  }

  @override
  String get generatingAndUploading => '正在生成并上传远程备份...';

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
  String get summaryApiCostHint => '总结图由第三方生图模型生成，可能产生 API 调用费用。';

  @override
  String estimatedCost(String dollar, String cost) {
    return '当前设置预估费用约 $dollar$cost / 张';
  }

  @override
  String get useAppImageGen => '若希望使用 App 生图，请点击 App 生图，手动上传素材。';

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
      '将文献素材导出后，到 ChatGPT / Gemini 等官方 App 中手动上传以生图。';

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
  String get ocrImageAreaDesc => '对图片区域执行文字识别';

  @override
  String get ocrOrientationDesc => '自动纠正 0°/90°/180°/270° 旋转';

  @override
  String get ocrCurvatureDesc => '校正弯曲或褶皱的文档';

  @override
  String get ocrDeduplicateDesc => '移除重叠的版面检测框';

  @override
  String get ocrMultiPageDesc => '重构多页文档结构';

  @override
  String get ocrThresholdHelp => '区域过滤的阈值，值越高保留的区域越少';

  @override
  String get ocrFilterHelp => '勾选的标签区域将不会输出到 Markdown 结果中，默认全忽略。';

  @override
  String get ocrInterface => 'OCR 接口';

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
  String get imageRefCountHint => '从文献提取的 figure 中按顺序选择参考图；不同模型会按自身上限自动裁剪。';

  @override
  String get aspectRatioHint => 'OpenAI 会映射到最接近的输出尺寸，并在 prompt 中保留比例要求。';

  @override
  String get summaryPromptHint =>
      '用于控制文献总结图的视觉风格和信息组织方式；运行时会自动追加文献标题、元数据、Markdown 和参考 figure。';

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
  String get systemPromptDesc => '翻译 System Prompt，支持 targetLanguage 占位符';

  @override
  String get systemPromptHint => '例如：You are a professional translator…';

  @override
  String get userPromptDesc => '翻译 User Prompt，支持 targetLanguage 和 input 占位符';

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
    return '确定要删除 $count 篇文献吗？此操作不可撤销。';
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
    return '确定要删除「$name」吗？收藏夹内的文献不会被删除。';
  }

  @override
  String favoriteDocumentCount(int count) {
    return '$count 篇文献';
  }

  @override
  String get clearReadingHistoryConfirm => '将清除所有阅读记录，文献本身不会被删除。此操作不可撤销。';

  @override
  String get noReadingHistoryHint => '打开任意文献后，这里会按日期显示浏览顺序';

  @override
  String get identifierInputHint =>
      '输入 ISBN、DOI、PMID、arXiv ID 或 ADS 条码来添加条目到您的文库：';

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
    return '确定删除「$name」？将清除其 API Key、地址和模型。';
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
  String copiedReferenceNumber(int number) {
    return '已复制参考文献 $number';
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
  String get resolutionHint => 'OpenAI 映射为 quality；Gemini 映射为 imageSize。';

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
}
