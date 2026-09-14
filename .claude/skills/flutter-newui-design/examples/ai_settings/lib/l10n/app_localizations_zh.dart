// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get aiSettings => 'AI 设置';

  @override
  String get subtitle => '集中配置模型连接、翻译偏好与概要配图。';

  @override
  String get demoNote => '交互预览 · 更改仅在本页有效';

  @override
  String get darkMode => '切换深浅主题';

  @override
  String get language => '切换中英文';

  @override
  String get fontScale => '调整文字大小';

  @override
  String get reduceMotion => '减少动态效果';

  @override
  String get modelApi => '模型接口';

  @override
  String get modelApiHelp => '连接服务商，为阅读、翻译和图像设置模型。';

  @override
  String get provider => '服务商';

  @override
  String get providerHint => '选择提供大模型服务的供应商。';

  @override
  String get apiKey => 'API Key';

  @override
  String get getApiKey => '获取 API Key';

  @override
  String get apiKeyActionMessage => '演示不连接外部服务商，请在服务商控制台获取 API Key。';

  @override
  String get keyHint => '演示无需真实密钥。输入仅保留在当前页面。';

  @override
  String get keyPlaceholder => '输入演示密钥';

  @override
  String get showKey => '显示 API Key';

  @override
  String get hideKey => '隐藏 API Key';

  @override
  String get endpoint => 'API 地址';

  @override
  String get endpointHint => '填写接口的基础地址。';

  @override
  String get endpointError => '请输入有效的 HTTPS 地址。';

  @override
  String get models => '模型';

  @override
  String get modelHint => '选择模型并查看能力；获取模型会加载本地演示目录，不访问服务商。';

  @override
  String get vision => '视觉';

  @override
  String get tools => '工具';

  @override
  String get reasoning => '推理';

  @override
  String get roles => '全局模型角色';

  @override
  String get expert => '专家模型';

  @override
  String get expertHint => '用于深度思考、复杂分析和高质量回答。';

  @override
  String get fast => '快速模型';

  @override
  String get fastHint => '用于简单问答、快速响应和日常对话。';

  @override
  String get imageModel => '图像模型';

  @override
  String get imageModelHint => '用于生成文献概要配图。';

  @override
  String get search => '联网搜索';

  @override
  String get searchHint => '为阅读助手补充网络资料。';

  @override
  String get searchKey => '搜索 API Key';

  @override
  String get clear => '未指定';

  @override
  String get translation => '翻译设置';

  @override
  String get translationHelp => '调整译文的呈现方式和生成偏好。';

  @override
  String get targetLanguage => '目标语言';

  @override
  String get simplifiedChinese => '中文（简体）';

  @override
  String get english => '英语';

  @override
  String get japanese => '日语';

  @override
  String get korean => '韩语';

  @override
  String get french => '法语';

  @override
  String get german => '德语';

  @override
  String get styles => '译文样式';

  @override
  String get styleHint => '一次选择一种译文样式。';

  @override
  String get normal => '默认';

  @override
  String get accent => '主题色';

  @override
  String get bold => '加粗';

  @override
  String get italic => '斜体';

  @override
  String get muted => '弱化';

  @override
  String get underline => '虚线下划线';

  @override
  String get background => '背景色';

  @override
  String get blur => '模糊';

  @override
  String get quote => '引用';

  @override
  String get ignore => '翻译忽略内容';

  @override
  String get references => '参考文献';

  @override
  String get acknowledgments => '致谢';

  @override
  String get contributions => '作者贡献／利益冲突';

  @override
  String get funding => '资助／数据声明';

  @override
  String get supplement => '附录／补充材料';

  @override
  String get ethics => '伦理声明／图表说明';

  @override
  String get ignoreHint => '已选择的部分会跳过翻译。';

  @override
  String get temperature => '温度';

  @override
  String get temperatureHelp => '每档 0.05。较低数值保持稳定，较高数值增加表达变化。';

  @override
  String get resetTemperature => '重置温度';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get userPrompt => '用户提示词';

  @override
  String get promptHint => '保留模板中的变量；文字内容可自由编辑。';

  @override
  String get promptError => '请保留 text 和 targetLanguage 两个模板变量；当前内容未生效。';

  @override
  String get resetPrompt => '恢复默认提示词';

  @override
  String get imageSettings => '生图设置';

  @override
  String get imageHelp => '设置概要配图的比例、质量和参考图片。';

  @override
  String get aspectRatio => '宽高比';

  @override
  String get aspectHint => '选择配图的画面比例。';

  @override
  String get quality => '图像质量';

  @override
  String get auto => '自动';

  @override
  String get standard => '标准';

  @override
  String get high => '高质量';

  @override
  String get referenceImages => '参考图片数';

  @override
  String get referenceImagesHelp => '最多使用 1–10 张文献图片辅助生成，默认 10 张。';

  @override
  String get resetReferences => '重置参考图片数';

  @override
  String get imagePrompt => '概要配图提示词';

  @override
  String get imagePromptHint => '描述图像的重点、结构与风格。';

  @override
  String get fetchModels => '获取模型';

  @override
  String get retryModels => '重试获取';

  @override
  String get fetchingModels => '正在加载演示模型…';

  @override
  String modelsFetched(int count) {
    return '已获取 $count 个演示模型';
  }

  @override
  String get modelsDemoHint => '本地演示目录 · 不发送网络请求';

  @override
  String get fetchModelsError => '未能获取模型：请先修正 API 地址，再重试。';

  @override
  String get account => '账号';

  @override
  String get address => '地址';

  @override
  String get author => '作者';

  @override
  String get autoBackup => '自动备份';

  @override
  String get autoBackupDaily => '每日';

  @override
  String get autoBackupHint => '到期后台自动上传到远端，仅在内容有变化时执行';

  @override
  String get autoBackupOff => '关闭';

  @override
  String get autoBackupWeekly => '每周';

  @override
  String get backupMethod => '备份方式';

  @override
  String get backupScopeData => '仅数据';

  @override
  String get backupScopeDataDesc => '设置、元数据、批注、翻译与对话；不含 PDF 与提取文件';

  @override
  String get backupScopeFull => '完整备份';

  @override
  String get backupScopeFullDesc => '包含 PDF 与提取文件，备份体积较大';

  @override
  String get backupScopeTitle => '备份范围';

  @override
  String backupTo(String target) {
    return '备份到$target';
  }

  @override
  String get cancel => '取消';

  @override
  String get clearField => '清空';

  @override
  String get close => '关闭';

  @override
  String get configure => '配置';

  @override
  String get dataManagement => '数据管理';

  @override
  String get delete => '删除';

  @override
  String downloadAndRestore(String target) {
    return '下载$target并恢复';
  }

  @override
  String get edit => '编辑';

  @override
  String get editFavorite => '编辑收藏夹';

  @override
  String get enterFavoriteName => '输入收藏夹名称';

  @override
  String get exportBackup => '导出备份文件';

  @override
  String get favoriteName => '收藏夹名称';

  @override
  String get fullResync => '重置并全量重新导入';

  @override
  String get generateZipAndSave => '生成 zip 备份并保存到本地';

  @override
  String get getToken => '获取 Token';

  @override
  String get journal => '期刊';

  @override
  String get localBackup => '本地备份';

  @override
  String get objectPath => '对象路径';

  @override
  String get password => '密码';

  @override
  String pleaseConfigureFirst(String target) {
    return '请先配置$target连接信息';
  }

  @override
  String get pleaseFillApiKey => '请先填写 API Key';

  @override
  String get region => '区域';

  @override
  String get reimport => '重新导入';

  @override
  String get remoteBackup => '远程备份';

  @override
  String remoteNotConfigured(String target) {
    return '未配置$target远程备份信息';
  }

  @override
  String get resetZoteroConfirm =>
      '将清除本地的 Zotero 导入记录并从文库全量重新拉取：已删除的条目会重新出现，仍在库中的不会重复。继续吗？';

  @override
  String get resetZoteroSync => '重置 Zotero 同步';

  @override
  String get restoreFromBackup => '从备份文件恢复';

  @override
  String restoreFromRemote(String target) {
    return '从$target恢复';
  }

  @override
  String get restoreMethod => '恢复方式';

  @override
  String get restoreModeMerge => '合并恢复';

  @override
  String get restoreModeMergeDescription => '保留本地数据，仅添加备份中不存在的内容';

  @override
  String get restoreModeOverwrite => '覆盖恢复';

  @override
  String get restoreModeOverwriteDescription => '清除本地数据后用备份替换';

  @override
  String get restoreScope => '恢复范围';

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
  String get restoreSettingsTitle => '恢复设置';

  @override
  String get s3Config => 'S3 配置';

  @override
  String get s3Endpoint => 'S3 / R2 / MinIO Endpoint';

  @override
  String get s3ObjectPathDefault => '默认可用 otter-pad/otter_pad_backup.zip';

  @override
  String get s3PathStyleHint => 'MinIO / R2 等 S3 兼容服务通常建议开启';

  @override
  String get save => '保存';

  @override
  String get selectIcon => '选择图标';

  @override
  String get selectLocalZipRestore => '选择本地 zip 备份文件进行恢复';

  @override
  String get startBackup => '开始备份';

  @override
  String get startMerge => '开始合并';

  @override
  String get startRestore => '开始恢复';

  @override
  String get storage => '存储';

  @override
  String get storageSpace => '存储空间';

  @override
  String get syncZoteroLibrary => '同步 Zotero 文库';

  @override
  String get thumbnailsAndTemp => '缩略图、临时文件等';

  @override
  String get unnamed => '未命名';

  @override
  String uploadBackupTo(String target) {
    return '上传完整备份到$target';
  }

  @override
  String get usePathStyle => '使用路径式地址';

  @override
  String viewLibraryTotal(int count) {
    return '查看文库 · 共 $count 篇';
  }

  @override
  String get webDavConfig => 'WebDAV 配置';

  @override
  String get webDavServerAddress => 'WebDAV服务器地址';

  @override
  String get year => '年份';

  @override
  String get zoteroImportHint => '从 Zotero 个人库导入文献';

  @override
  String zoteroImportedPull(int count) {
    return '已导入 $count 篇 · 拉取新增条目';
  }

  @override
  String get zoteroLocalDirectory => '选择 Zotero 资料库文件夹';

  @override
  String get zoteroLocalEntryHint => '从这台电脑上的 Zotero 导入题录和 PDF';

  @override
  String get zoteroLocalMetadataOnly => '仅导入题录';

  @override
  String get zoteroLocalTitle => '本机 Zotero';

  @override
  String get zoteroResetHint => '清除导入记录，从 Zotero 重新拉取（找回已删除条目）';

  @override
  String get zoteroSync => 'Zotero 同步';

  @override
  String get demoBackupHelp => '管理远程备份、Zotero 文献和本地数据。';

  @override
  String get demoWidgetTitle => '基础组件';

  @override
  String get demoWidgetHelp => '同一套纸白石墨语言，覆盖内容页、浮层和反馈。';

  @override
  String get demoOperationDone => '演示流程已完成，未读写真实数据。';

  @override
  String get demoOperationRunning => '正在运行演示流程…';

  @override
  String get demoArchiveHint => '使用演示备份；此预览不创建或选择真实文件。';

  @override
  String get demoRemoteHelp => '配置 S3 或 WebDAV，选择自动备份周期并执行备份或恢复。';

  @override
  String get demoZoteroHelp => '导入 Zotero 文献；本地导入仅在桌面端显示。';

  @override
  String get demoLocalHelp => '导出 ZIP 备份，或从备份恢复和合并数据。';

  @override
  String get demoLocalSource => '演示资料库';

  @override
  String get demoLocalSourceHint => '使用内置样例演示导入界面，不扫描本机 Zotero 目录。';

  @override
  String get demoLocalPapers => '已选择 3 篇演示文献';

  @override
  String get demoImport => '导入样例';

  @override
  String get demoStorageHint => '以下为静态演示用量。';

  @override
  String get demoDocuments => '文献文件';

  @override
  String get demoThumbnails => '缩略图';

  @override
  String get demoTemporary => '临时文件';

  @override
  String get demoStorageSummary => '896 MB · 演示用量';

  @override
  String get demoConfigured => '配置已用于本页预览 · 未连接远程服务';

  @override
  String get demoTokenHint => '正式产品会打开此地址；预览仅展示入口。';

  @override
  String get demoConfiguration => '本页配置预览';

  @override
  String get demoConfigurationHint => '可填入样例观察配置状态，无需真实凭据。';

  @override
  String get demoFill => '填入演示配置';

  @override
  String get demoInvalidConfig => '请完善配置';

  @override
  String get demoInvalidConfigHint => '填写 HTTPS 地址及必填字段；对象路径可留空。';

  @override
  String get demoResult => '演示结果';

  @override
  String get demoDialogs => '对话框与面板';

  @override
  String get demoDialogsHelp => '点击入口打开真实浮层。Esc 或取消关闭，表单草稿仅在确认后提交。';

  @override
  String get demoDocumentInfo => '文献信息';

  @override
  String get demoDocumentInfoHelp => '展示标题、作者、期刊、年份、DOI 与关键词；可选择和复制。';

  @override
  String get demoEditFavoriteHelp => '选择图标、编辑名称并即时预览；空名称不能保存。';

  @override
  String get demoDeleteFavorite => '删除收藏夹';

  @override
  String get demoDeleteHint => '仅移除此演示收藏夹，不删除其中的文献；删除后可以撤销。';

  @override
  String get demoFavoriteSaved => '收藏夹已在本页更新';

  @override
  String get demoFavoriteRemoved => '演示收藏夹已移除';

  @override
  String get demoUndo => '撤销';

  @override
  String get demoUndoHint => '可以恢复刚刚移除的演示收藏夹。';

  @override
  String get demoFavoriteTitle => '我的收藏';

  @override
  String get demoFavoriteMenu => '收藏夹操作';

  @override
  String get demoFavoriteCards => '收藏夹卡片';

  @override
  String get demoFavoriteCardsHelp =>
      '0 篇为空封面，1 篇居中，2 篇并列，3 篇主次布局，4 篇网格，5 篇以上展示一大四小。右键、长按封面或更多按钮打开菜单。';

  @override
  String get demoCoverCount => '首张卡片的文献数量';

  @override
  String get demoMethodsCollection => '研究方法';

  @override
  String get demoVisualCollection => '视觉与交互';

  @override
  String get demoEmptyLibrary => '收藏夹还是空的';

  @override
  String get demoEmptyLibraryHint => '加入文献后，封面会按数量自动排版。';

  @override
  String get demoPaperTitle => '面向深度阅读的知识组织方法';

  @override
  String get demoKeywords => '关键词';

  @override
  String get demoKeywordValues => '深度阅读，知识组织，交互设计';

  @override
  String get demoCopied => '已复制到剪贴板';

  @override
  String get demoCopyFailed => '未能复制，请选择文本手动复制。';

  @override
  String get demoDocumentActions => '文献操作面板';

  @override
  String get demoSheetHelp => '使用安全区域、拖拽柄与可滚动内容，不叠加模糊。';

  @override
  String get demoAddFavorite => '加入收藏夹';

  @override
  String get demoExportCitation => '导出引用';

  @override
  String get demoFeedback => '反馈与提示';

  @override
  String get demoFeedbackHelp => '结果使用短暂 Snackbar；任务显示进度；需要处理的问题就地显示 Alert。';

  @override
  String get demoResultSnack => '结果提示';

  @override
  String get demoErrorSnack => '失败与重试';

  @override
  String get demoProgressSnack => '单任务进度';

  @override
  String get demoAggregateSnack => '多任务进度';

  @override
  String get demoResultMessage => '演示设置已更新';

  @override
  String get demoNetworkError => '演示连接中断，可重试。';

  @override
  String get demoRetry => '重试';

  @override
  String get demoRetryReady => '演示重试已完成，未发起网络请求。';

  @override
  String get demoTaskCanceled => '演示任务已取消';

  @override
  String get demoAlertTitle => '备份暂时无法继续';

  @override
  String get demoAlertMessage => '这是连接失败的示例。已保留配置与当前内容，请检查地址后重试。';

  @override
  String get demoAlertResolved => '演示问题已处理';

  @override
  String get demoResetExample => '重置示例';

  @override
  String get demoBasicControls => '基础选择与操作';

  @override
  String get demoBasicControlsHelp => '单选、多选、开关与按钮共用一致的边界、焦点和命中区域。';

  @override
  String get demoNotifications => '任务完成通知';

  @override
  String get demoNotificationsHelp => '任务结束后显示结果提示。此开关仅演示状态。';

  @override
  String get demoSort => '文献排序';

  @override
  String get demoRecent => '最近添加';

  @override
  String get demoSortTitle => '标题';

  @override
  String get demoFileTypes => '文件类型';

  @override
  String get demoFileTypesHelp => '可同时选择多种类型。';

  @override
  String get demoPrimaryAction => '主要操作';

  @override
  String get demoSecondaryAction => '次要操作';

  @override
  String get demoTextAction => '文字操作';

  @override
  String get demoDisabledAction => '暂不可用';

  @override
  String get demoUsage => '用量与进度';

  @override
  String get demoUsageHelp => '保留超额数值，进度条限制在 0–100%；本地估算明确标识。';

  @override
  String get demoQuota => '演示用量比例';

  @override
  String get demoQuotaHelp => '拖至 1.0 以上观察超额状态。';

  @override
  String get demoEstimatedUsage => '本地估算';

  @override
  String get demoOverQuota => '用量超出配额';

  @override
  String get demoOverQuotaHint => '数值仍完整显示；进度条不溢出容器。';

  @override
  String get demoIconBook => '书本';

  @override
  String get demoIconScience => '科学';

  @override
  String get demoIconSchool => '学术';

  @override
  String get demoIconFolder => '文件夹';

  @override
  String get demoIconStar => '星标';

  @override
  String get demoIconReading => '阅读';

  @override
  String get demoIconGroupReading => '阅读与学习';

  @override
  String get demoIconGroupMark => '整理与标记';

  @override
  String get demoIconGroupIdea => '灵感与主题';

  @override
  String get demoIconBookmark => '书签';

  @override
  String get demoIconHeart => '心形';

  @override
  String get demoIconIdea => '灵感';

  @override
  String get demoIconPalette => '调色板';

  @override
  String get demoIconMusic => '音乐';

  @override
  String get demoIconExplore => '探索';

  @override
  String get demoNameRequired => '请输入收藏夹名称';

  @override
  String get demoLivePreview => '效果预览';

  @override
  String demoPaperCount(int count) {
    return '$count 篇文献';
  }

  @override
  String demoTasks(int count) {
    return '$count 个演示任务进行中';
  }

  @override
  String demoCopyField(String field) {
    return '复制$field';
  }

  @override
  String get demoSelection => '分段选择';

  @override
  String get demoSelectionHelp =>
      '固定选项使用连续等分的单选条；选中底色与勾选共同表达状态。空间不足时纵向排列，保持所有选项可见。';

  @override
  String get generalLogLevel => '最低记录级别';

  @override
  String get demoLogInfo => '信息';

  @override
  String get demoLogWarning => '警告';

  @override
  String get demoLogError => '错误';

  @override
  String get appearanceTitle => '外观 · 阅读之间';

  @override
  String get appearanceHelp => '比较应用明暗与阅读纸面；默认石墨配色、系统无衬线字体。两端可独立操作，设置仅在预览中有效。';

  @override
  String get appearanceScope => '外观实验 / 内容区与阅读样例 · 不改变产品导航';

  @override
  String get appearanceMode => '应用明暗';

  @override
  String get appearanceModeHelp => '跟随系统读取浏览器的系统明暗偏好；固定阅读纸面不受此开关影响。';

  @override
  String get appearanceSystem => '自动';

  @override
  String get appearanceLight => '浅色';

  @override
  String get appearanceDark => '深色';

  @override
  String get appearancePaper => '阅读纸面';

  @override
  String get appearancePaperHelp => '仅控制阅读区。固定白纸、米纸、淡绿、夜间或纯黑时，应用切换明暗也保留你的选择。';

  @override
  String get appearanceFollow => '跟随应用';

  @override
  String get appearanceWhite => '白纸';

  @override
  String get appearanceSepia => '米纸';

  @override
  String get appearancePaleGreen => '淡绿';

  @override
  String get appearanceNight => '夜间';

  @override
  String get appearanceBlack => '纯黑';

  @override
  String get appearanceFollowing => '当前：阅读纸面随应用明暗切换';

  @override
  String get appearancePinned => '当前：纸面已固定，独立于应用明暗';

  @override
  String get appearanceComponents => '控件与反馈';

  @override
  String get appearanceComponentsHelp =>
      '检查输入焦点、禁用、弹窗、遮罩、Snackbar 与错误。切换明暗与字体保留草稿。';

  @override
  String get appearanceDraft => '阅读备注';

  @override
  String get appearanceDraftHint => '输入内容后试着切换主题';

  @override
  String get appearanceShowSnack => '显示提示';

  @override
  String get appearanceSnack => '这是一条预览提示，阅读位置已保留';

  @override
  String get appearanceShowError => '错误示例';

  @override
  String get appearanceDisabled => '暂不可用';

  @override
  String get appearanceErrorTitle => '连接中断示例';

  @override
  String get appearanceErrorMessage => '这是一条模拟错误，备注与外观选择仍保留。';

  @override
  String get appearanceRetryDone => '错误示例已恢复';

  @override
  String get appearanceReader => '阅读预览';

  @override
  String get appearanceReaderHelp =>
      'Markdown 展示可换肤正文；PDF 使用固定版面样例，保留白纸与图表原色。两者均非真实文献。';

  @override
  String get appearanceOriginal => 'PDF / 原稿版面样例';

  @override
  String get appearanceReadingPreview => '正文 / 译文与插图';

  @override
  String get appearancePdfNote => '版面示意：白色原稿与图表保留原色，周围画布跟随阅读纸面。';

  @override
  String get appearanceMarkdownNote => '正文随纸面换色；文献插图保留原色。阅读区域可独立滚动。';

  @override
  String get appearanceContrast => '实时对比度';

  @override
  String get appearanceContrastHelp =>
      '按当前实际前景与背景计算，正文门槛为 4.5:1。这里只检查三个颜色对，不代表完整无障碍验收；PDF 原稿保持原色。';

  @override
  String get appearanceUiText => '界面正文';

  @override
  String get appearanceReadingText => '阅读正文';

  @override
  String get appearanceLink => '阅读链接';

  @override
  String get appearancePass => '通过';

  @override
  String get appearanceFail => '需调整';

  @override
  String get appearanceArticleKicker => '阅读札记 / 01';

  @override
  String get appearanceArticleTitle => '在信息之间，留一点空白';

  @override
  String get appearanceArticleByline => '林舟 · 阅读与认知研究札记 · 2026';

  @override
  String get appearanceArticleIntro =>
      '阅读一篇论文时，我们不断在正文、图表与自己的想法之间移动。界面的任务，是让这些转换足够安静，让注意力留在内容上。';

  @override
  String get appearanceArticleHeading => '01 让层级清楚，让颜色克制';

  @override
  String get appearanceArticleBody =>
      '文字的层级来自字号、间距与适当的对比。链接需要被找到，选中状态需要被确认，而纸面不必随着每一次配色选择重新染色。夜间阅读也应保留这种秩序。';

  @override
  String get appearanceQuote => '好的阅读环境，允许内容成为视线停留最久的地方。';

  @override
  String get appearanceFigureTitle => '图 1 / 阅读活动分布（示例）';

  @override
  String get appearanceFigureA => '阅读正文';

  @override
  String get appearanceFigureB => '查看图表';

  @override
  String get appearanceFigureC => '整理笔记';

  @override
  String get appearanceFigureCaption => '图表为虚构示例，颜色在所有阅读纸面下保持一致。';

  @override
  String get appearanceArticleEnd => '当我们回到刚才的位置，选中的纸面、输入的备注和正在阅读的段落，都应该还在那里。';

  @override
  String get appearanceReference => '查看示例引用 ↗';

  @override
  String get appearanceSample => '演示文献';

  @override
  String get appearanceSampleHelp => '文献、作者与图表均为外观验证用的虚构内容，不连接外部服务。';

  @override
  String get displaySettings => '显示设置';

  @override
  String get interfaceFont => '界面字体';

  @override
  String get interfaceFontHelp => '默认使用系统无衬线字体；衬线字体为可选外观。仅改变当前预览，不下载字体。';

  @override
  String get fontSans => '无衬线';

  @override
  String get fontSerif => '衬线';
}
