import 'dart:convert';

import 'package:flutter/services.dart';

import '../providers/api_provider.dart';

enum AgentModelModality { text, image }

class AgentModelCapability {
  final bool textInput;
  final bool imageInput;

  /// 文本输出（对话模型恒有；embedding 在编辑器中隐藏输出，不参与展示）。
  final bool textOutput;
  final bool imageOutput;
  final bool embedding;

  /// 函数调用能力（工具）。embedding 模型恒为 false。
  final bool tool;

  /// 推理 / 思考能力。embedding 模型恒为 false。
  final bool reasoning;

  const AgentModelCapability({
    this.textInput = true,
    this.imageInput = false,
    this.textOutput = true,
    this.imageOutput = false,
    this.embedding = false,
    this.tool = false,
    this.reasoning = false,
  });

  bool get canGenerateImage => imageOutput && !embedding;

  AgentModelCapability copyWith({
    bool? textInput,
    bool? imageInput,
    bool? textOutput,
    bool? imageOutput,
    bool? embedding,
    bool? tool,
    bool? reasoning,
  }) => AgentModelCapability(
    textInput: textInput ?? this.textInput,
    imageInput: imageInput ?? this.imageInput,
    textOutput: textOutput ?? this.textOutput,
    imageOutput: imageOutput ?? this.imageOutput,
    embedding: embedding ?? this.embedding,
    tool: tool ?? this.tool,
    reasoning: reasoning ?? this.reasoning,
  );

  Map<String, dynamic> toJson() => {
    'textInput': textInput,
    'imageInput': imageInput,
    'textOutput': textOutput,
    'imageOutput': imageOutput,
    'embedding': embedding,
    'tool': tool,
    'reasoning': reasoning,
  };

  factory AgentModelCapability.fromJson(Map<String, dynamic> json) =>
      AgentModelCapability(
        textInput: json['textInput'] as bool? ?? true,
        imageInput: json['imageInput'] as bool? ?? false,
        textOutput: json['textOutput'] as bool? ?? true,
        imageOutput: json['imageOutput'] as bool? ?? false,
        embedding: json['embedding'] as bool? ?? false,
        tool: json['tool'] as bool? ?? false,
        reasoning: json['reasoning'] as bool? ?? false,
      );

  factory AgentModelCapability.infer({
    required AgentApiProvider provider,
    required String modelId,
    Map<String, dynamic>? raw,
  }) {
    if (provider == AgentApiProvider.gemini && raw != null) {
      return AgentModelCapability.fromGeminiModel(raw, fallbackId: modelId);
    }
    return AgentModelCapability.fromModelId(
      provider: provider,
      modelId: modelId,
    );
  }

  factory AgentModelCapability.fromGeminiModel(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
    final name = (json['name'] as String?) ?? fallbackId;
    final modelId = name.startsWith('models/') ? name.substring(7) : name;
    final methods =
        (json['supportedGenerationMethods'] as List?)
            ?.map((e) => e.toString())
            .toSet() ??
        const <String>{};
    final embedding =
        methods.contains('embedContent') &&
        !methods.contains('generateContent');
    final inferred = AgentModelCapability.fromModelId(
      provider: AgentApiProvider.gemini,
      modelId: modelId,
    );
    if (embedding) {
      return const AgentModelCapability(embedding: true);
    }
    return inferred;
  }

  factory AgentModelCapability.fromModelId({
    required AgentApiProvider provider,
    required String modelId,
  }) {
    final id = modelId.toLowerCase();
    if (_isLikelyEmbedding(id)) {
      return const AgentModelCapability(embedding: true);
    }

    final imageOutput = isImageGenerationModel(provider: provider, modelId: id);
    final imageInput = imageOutput || _isKnownVisionModel(id);
    // 生图模型不带工具/推理能力（对齐 kelivo）
    final tool = !imageOutput && _isToolModel(id);
    final reasoning = !imageOutput && _isReasoningModel(id);
    return AgentModelCapability(
      imageInput: imageInput,
      imageOutput: imageOutput,
      tool: tool,
      reasoning: reasoning,
    );
  }

  // ─── 生图模型识别（从 assets/config/image_models.json 加载） ───

  static Map<String, List<String>> _imageModelPatterns = {};

  /// 从 JSON 加载生图模型匹配规则，应在 app 启动时调用一次。
  static Future<void> init() async {
    final raw = await rootBundle.loadString('assets/config/image_models.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    _imageModelPatterns = data.map(
      (k, v) => MapEntry(k, (v as List).cast<String>()),
    );
  }

  static bool isImageGenerationModel({
    required AgentApiProvider provider,
    required String modelId,
  }) {
    final id = modelId.toLowerCase();
    final key = provider == AgentApiProvider.openAICompatible
        ? 'openAICompatible'
        : provider.name;
    final patterns = _imageModelPatterns[key];
    if (patterns == null) return false;
    return patterns.any((p) => id.contains(p));
  }

  static bool _isLikelyEmbedding(String id) {
    return id.contains('embedding') ||
        RegExp(r'(^|[-_/])embed(?:dings?)?([-.]|$)').hasMatch(id);
  }

  /// 视觉（图片输入）识别。除通用 vl/vision 关键字外补充各厂命名：
  /// GLM-4.5V/4.6V/5V、Doubao Seed 1.6+（原生多模态）、Kimi k2.5/k2.6、
  /// Grok 4、MiMo V2.5 系列（均为多模态，依据各家官方 API 文档）。
  static bool _isKnownVisionModel(String id) {
    return RegExp(
      r'(gpt-4o|gpt-4\.1|gpt-5|gemini|claude|qwen-vl|vision|vl|'
      r'glm-[\d.]+v\b|doubao-seed|kimi-k2\.[5-9]|grok-4|mimo)',
      caseSensitive: false,
    ).hasMatch(id);
  }

  // ─── 能力识别（工具 / 推理）—— 正则移植自 kelivo ModelRegistry，
  //     并按各厂 API 文档补充 MiMo / Doubao Seed ───

  static final RegExp _toolRe = RegExp(
    r'(gpt-4o|gpt-4\.1|gpt-oss|gpt-5(?!-chat)|o\d|gemini|claude|qwen-?3|'
    r'grok-4|kimi-k2|glm-4[-.](?:5|6|7)|glm-5|minimax-m2|mimo|doubao-seed|'
    r'deepseek-(?:chat|r1|reasoner|v3|v3\.1|v3\.2|v4))',
    caseSensitive: false,
  );

  static final RegExp _reasoningRe = RegExp(
    r'(gpt-oss|gpt-5(?!-chat)|o\d|gemini-(?:2\.5|3)|gemma[-_]?4|claude|'
    r'qwen-?3|grok-4|kimi-k2|glm-4[-.](?:5|6|7)|glm-5|minimax-m2|mimo|'
    r'doubao-seed|deepseek-(?:r1|reasoner|v3\.1|v3\.2|v4))',
    caseSensitive: false,
  );

  static bool _isToolModel(String id) => _toolRe.hasMatch(id);

  static bool _isReasoningModel(String id) => _reasoningRe.hasMatch(id);

  // ─── Thinking / reasoning 版本识别 ───────────────────────────────────
  // 这些方法服务于请求构造层把统一的 ThinkingLevel 翻译成各家具体字段。
  // 集中维护识别规则——后续模型升级（Gemini 3.5 / Claude Opus 5）只改这里。

  /// Gemini 3 系列（用 `thinkingLevel` 字段，3.1 Pro 不支持 minimal）。
  static bool isGemini3(String modelId) {
    final id = modelId.toLowerCase();
    return RegExp(r'(?:^|[/-])gemini-3(?:[.-]|$)').hasMatch(id);
  }

  /// Gemini 2.5 系列（用 `thinkingBudget` 数字，由 ThinkingLevel 映射）。
  static bool isGemini25(String modelId) {
    final id = modelId.toLowerCase();
    return RegExp(r'(?:^|[/-])gemini-2\.5(?:[.-]|$)').hasMatch(id);
  }

  /// Gemini 2.5 Pro：**不可关闭思考**，最小 budget=128，上限 32768。
  /// Flash / Flash Lite / Robotics-ER / Live Audio 上限 24576 且可设 0 关闭。
  static bool isGemini25Pro(String modelId) {
    final id = modelId.toLowerCase();
    return RegExp(r'(?:^|[/-])gemini-2\.5-pro(?:[.-]|$)').hasMatch(id);
  }

  /// Gemini 2.5 系列的 thinkingBudget 上限（xhigh 档用）。
  static int gemini25MaxBudget(String modelId) =>
      isGemini25Pro(modelId) ? 32768 : 24576;

  /// OpenAI gpt-5 系列代际（用于 reasoning.effort 合法值判断）：
  /// `null`=非 gpt-5；`0`=初代（gpt-5/-mini/-nano，effort ∈ minimal..high）；
  /// `1`=gpt-5.1（none..high）；`>=2`=gpt-5.2+（none..xhigh）。
  static int? gpt5Minor(String modelId) {
    final m = RegExp(r'(?:^|[/-])gpt-5(?:\.(\d+))?(?:[.-]|$)')
        .firstMatch(modelId.toLowerCase());
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '0') ?? 0;
  }

  /// Qwen VL 系列（DashScope 专属参数 `vl_high_resolution_images` 等适用，
  /// 该参数把单图 token 上限从 1280 提到 16384，密集文档页需要）。
  static bool isQwenVl(String modelId) {
    final id = modelId.toLowerCase();
    return RegExp(r'qwen[\w.-]*-vl').hasMatch(id);
  }

  /// Claude 是否走 adaptive thinking 模型（Opus 4.7+ / Fable）。
  /// 这些模型上 `budget_tokens` 已移除（发送会 400），只能用 adaptive。
  /// 其余 Claude 模型用旧 `thinking.type:disabled/enabled` + budget。
  ///
  /// 识别策略：opus-4-7/4-8/4-9 与 fable 系列归为 adaptive；后续新系列
  /// 上来后在此处追加正则。Anthropic 的 model id 形如 `claude-opus-4-8`。
  static bool isClaudeAdaptive(String modelId) {
    final id = modelId.toLowerCase();
    return RegExp(r'claude-(?:opus-4-[789]|fable)(?:\b|-)').hasMatch(id);
  }

  // ─── Server-side 工具版本门槛 ────────────────────────────────────────
  // BuiltInToolsHelper 据此判定是否注入 search / url_context 工具。

  /// Claude 3.7 起（含 4.x / Fable / Mythos），支持 web_search / web_fetch。
  static bool isModernClaude(String modelId) {
    final id = modelId.toLowerCase();
    return id.startsWith('claude-opus-4') ||
        id.startsWith('claude-sonnet-4') ||
        id.startsWith('claude-haiku-4') ||
        id.startsWith('claude-fable') ||
        id.startsWith('claude-mythos') ||
        id.startsWith('claude-3-7') ||
        id.startsWith('claude-3-5-haiku');
  }

  /// Gemini 2.0+（支持 google_search；1.x 是已弃用的旧格式）。
  static bool isGeminiWithSearch(String modelId) =>
      !modelId.toLowerCase().startsWith('gemini-1');

  /// Gemini 2.5+（支持 url_context）。
  static bool isGeminiWithUrlContext(String modelId) {
    final id = modelId.toLowerCase();
    return !id.startsWith('gemini-1') && !id.startsWith('gemini-2.0');
  }
}
