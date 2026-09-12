/// OCR / 文档提取提供商。
///
/// 线格式差异大（Paddle 同步/异步 Job vs MinerU 批量上传轮询），由各自服务类
/// 消费；本枚举只负责 UI 选择、凭据分槽与限额常量。
enum DocExtractProvider { paddle, mineru }

extension DocExtractProviderExt on DocExtractProvider {
  String get artifactKey =>
      this == DocExtractProvider.paddle ? 'paddleocr' : 'mineru';

  String get label => switch (this) {
    DocExtractProvider.paddle => 'PaddleOCR',
    DocExtractProvider.mineru => 'MinerU',
  };

  /// 获取 API Token 的引导页
  String get tokenPageUrl => switch (this) {
    DocExtractProvider.paddle => 'https://aistudio.baidu.com/paddleocr',
    DocExtractProvider.mineru => 'https://mineru.net/apiManage/token',
  };

  /// 每日额度（页）。MinerU 为「优先解析」额度——超出后降优先级而非硬拒绝。
  int get dailyPages => switch (this) {
    DocExtractProvider.paddle => 20000,
    DocExtractProvider.mineru => 1000,
  };

  /// 是否每日硬上限（超限即拒绝）。MinerU 超限仅降级，非硬上限。
  bool get dailyPagesIsHardLimit => switch (this) {
    DocExtractProvider.paddle => true,
    DocExtractProvider.mineru => false,
  };

  /// 单文件大小上限（MB）
  int get maxFileSizeMB => 200;

  /// 单文件页数上限
  int get maxPagesPerFile => switch (this) {
    DocExtractProvider.paddle => 1000,
    DocExtractProvider.mineru => 200,
  };

  /// 单次批量上传文件数上限（统一按 20 控制）
  int get maxBatchFiles => 20;

  static DocExtractProvider fromName(String? name) =>
      name == DocExtractProvider.mineru.name
      ? DocExtractProvider.mineru
      : DocExtractProvider.paddle;
}

/// 所有可选的 Markdown 忽略标签
const kAllIgnoreLabels = [
  'header',
  'header_image',
  'footer',
  'footer_image',
  'number',
  'footnote',
  'aside_text',
];

/// 默认启用的忽略标签
const kDefaultIgnoreLabels = [
  'header',
  'header_image',
  'footer',
  'footer_image',
  'number',
  'footnote',
  'aside_text',
];

class DocExtractApiState {
  /// 当前选择的提供商
  final DocExtractProvider provider;

  /// PaddleOCR Access Token
  final String paddleApiKey;

  /// MinerU API Token
  final String mineruApiKey;

  // ── PaddleOCR 提取选项 ──
  final bool useChartRecognition;
  final bool useDocOrientationClassify;
  final bool useDocUnwarping;
  final bool useSealRecognition;
  final bool useOcrForImageBlock;
  final bool restructurePages;
  final bool layoutNms;
  final bool mergeTables;
  final String layoutShapeMode;
  final double repetitionPenalty;
  final double temperature;

  // ── Markdown 忽略标签（PaddleOCR 专属参数）──
  final List<String> markdownIgnoreLabels;

  // ── MinerU 提取选项 ──
  final bool mineruIsOcr;
  final bool mineruEnableFormula;
  final bool mineruEnableTable;
  final String mineruLanguage;
  final String mineruModelVersion;
  final String mineruPageRanges;
  final List<String> mineruExtraFormats;

  /// 当前提供商的 API Key/token
  String get apiKey => switch (provider) {
    DocExtractProvider.paddle => paddleApiKey,
    DocExtractProvider.mineru => mineruApiKey,
  };

  /// 当前提供商是否已配置 token
  bool get isConfigured => apiKey.isNotEmpty;

  const DocExtractApiState({
    this.provider = DocExtractProvider.paddle,
    this.paddleApiKey = '',
    this.mineruApiKey = '',
    this.useChartRecognition = false,
    this.useDocOrientationClassify = false,
    this.useDocUnwarping = false,
    this.useSealRecognition = false,
    this.useOcrForImageBlock = false,
    this.restructurePages = true,
    this.layoutNms = true,
    this.mergeTables = true,
    this.layoutShapeMode = 'auto',
    this.repetitionPenalty = 1.0,
    this.temperature = 0.0,
    this.markdownIgnoreLabels = kDefaultIgnoreLabels,
    this.mineruIsOcr = false,
    this.mineruEnableFormula = true,
    this.mineruEnableTable = true,
    this.mineruLanguage = 'ch',
    this.mineruModelVersion = 'vlm',
    this.mineruPageRanges = '',
    this.mineruExtraFormats = const [],
  });

  DocExtractApiState copyWith({
    DocExtractProvider? provider,
    String? paddleApiKey,
    String? mineruApiKey,
    bool? useChartRecognition,
    bool? useDocOrientationClassify,
    bool? useDocUnwarping,
    bool? useSealRecognition,
    bool? useOcrForImageBlock,
    bool? restructurePages,
    bool? layoutNms,
    bool? mergeTables,
    String? layoutShapeMode,
    double? repetitionPenalty,
    double? temperature,
    List<String>? markdownIgnoreLabels,
    bool? mineruIsOcr,
    bool? mineruEnableFormula,
    bool? mineruEnableTable,
    String? mineruLanguage,
    String? mineruModelVersion,
    String? mineruPageRanges,
    List<String>? mineruExtraFormats,
  }) => DocExtractApiState(
    provider: provider ?? this.provider,
    paddleApiKey: paddleApiKey ?? this.paddleApiKey,
    mineruApiKey: mineruApiKey ?? this.mineruApiKey,
    useChartRecognition: useChartRecognition ?? this.useChartRecognition,
    useDocOrientationClassify:
        useDocOrientationClassify ?? this.useDocOrientationClassify,
    useDocUnwarping: useDocUnwarping ?? this.useDocUnwarping,
    useSealRecognition: useSealRecognition ?? this.useSealRecognition,
    useOcrForImageBlock: useOcrForImageBlock ?? this.useOcrForImageBlock,
    restructurePages: restructurePages ?? this.restructurePages,
    layoutNms: layoutNms ?? this.layoutNms,
    mergeTables: mergeTables ?? this.mergeTables,
    layoutShapeMode: layoutShapeMode ?? this.layoutShapeMode,
    repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
    temperature: temperature ?? this.temperature,
    markdownIgnoreLabels: markdownIgnoreLabels ?? this.markdownIgnoreLabels,
    mineruIsOcr: mineruIsOcr ?? this.mineruIsOcr,
    mineruEnableFormula: mineruEnableFormula ?? this.mineruEnableFormula,
    mineruEnableTable: mineruEnableTable ?? this.mineruEnableTable,
    mineruLanguage: mineruLanguage ?? this.mineruLanguage,
    mineruModelVersion: mineruModelVersion ?? this.mineruModelVersion,
    mineruPageRanges: mineruPageRanges ?? this.mineruPageRanges,
    mineruExtraFormats: mineruExtraFormats ?? this.mineruExtraFormats,
  );
}
