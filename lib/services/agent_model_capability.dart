import 'dart:convert';

import 'package:flutter/services.dart';

import '../providers/api_provider.dart';

enum AgentModelModality { text, image }

class AgentModelCapability {
  final bool textInput;
  final bool imageInput;
  final bool imageOutput;
  final bool embedding;

  const AgentModelCapability({
    this.textInput = true,
    this.imageInput = false,
    this.imageOutput = false,
    this.embedding = false,
  });

  bool get canGenerateImage => imageOutput && !embedding;

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
    return AgentModelCapability(
      imageInput: imageInput,
      imageOutput: imageOutput,
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

  static bool _isKnownVisionModel(String id) {
    return RegExp(
      r'(gpt-4o|gpt-4\.1|gpt-5|gemini|claude|qwen-vl|vision|vl)',
      caseSensitive: false,
    ).hasMatch(id);
  }
}
