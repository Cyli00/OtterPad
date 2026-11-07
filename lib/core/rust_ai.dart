import '../data/models/ai/agent_config.dart' as dart;
import '../providers/agent_api_provider.dart'
    show AgentApiNotifier, AgentProvidersState;
import '../providers/translation_config_provider.dart' as dart;
import '../src/rust/ai/catalog.dart';
import '../src/rust/ai/types.dart';
import '../src/rust/api/ai.dart';
import '../src/rust/translate.dart';

/// 服务商实例与模型转为 Rust 的模型选择。密钥由凭据注入 Rust，不随请求传递；
/// 能力与思考规格由 Rust 能力表补全，这里只传用户手动覆写的能力。
ModelSelection? modelSelection(
  dart.AgentApiState state,
  String? modelId, {
  dart.AgentModelCapability? capability,
}) {
  if (state.id.isEmpty || modelId == null) return null;
  final params = state.paramsFor(modelId);
  return ModelSelection(
    instanceId: state.id,
    config: ModelConfig(
      provider: switch (state.provider.wireProtocol(state.effectiveBaseUrl)) {
        dart.AgentApiProvider.openai => Provider.openai,
        dart.AgentApiProvider.anthropic => Provider.anthropic,
        dart.AgentApiProvider.gemini => Provider.gemini,
        dart.AgentApiProvider.openAICompatible => Provider.openaiCompatible,
      },
      baseUrl: state.effectiveBaseUrl,
      model: modelId,
      params: ModelParams(
        temperature: params.temperature,
        topP: params.topP,
        maxTokens: params.maxTokens,
        topK: params.topK,
        thinking: thinkingLevel(params.thinkingLevel),
        verbosity: params.verbosity,
        parallelToolCalls: params.parallelToolCalls,
        truncation: params.truncation,
        presencePenalty: params.presencePenalty,
        frequencyPenalty: params.frequencyPenalty,
      ),
      capabilities: capability == null
          ? null
          : ModelCapabilities(
              textInput: capability.textInput,
              imageInput: capability.imageInput,
              textOutput: capability.textOutput,
              imageOutput: capability.imageOutput,
              embedding: capability.embedding,
              tool: capability.tool,
              reasoning: capability.reasoning,
              webSearch: capability.webSearch,
            ),
    ),
  );
}

ThinkingLevel? thinkingLevel(dart.ThinkingLevel? level) => switch (level) {
  null => null,
  dart.ThinkingLevel.off => ThinkingLevel.off,
  dart.ThinkingLevel.low => ThinkingLevel.low,
  dart.ThinkingLevel.medium => ThinkingLevel.medium,
  dart.ThinkingLevel.high => ThinkingLevel.high,
  dart.ThinkingLevel.xhigh => ThinkingLevel.xhigh,
};

/// 文本调用（翻译、摘要提示词等）的模型：快速模型优先，其次专家模型。
ModelSelection? textModelSelection(AgentProvidersState providers) {
  final state = AgentApiNotifier.resolveEffectiveState();
  if (state == null) return null;
  final modelId = state.fastModelId ?? state.defaultModelId;
  if (modelId == null || modelId.isEmpty) return null;
  return modelSelection(
    state,
    modelId,
    capability: providers.byId(state.id)?.modelCaps[modelId],
  );
}

/// 翻译设置转为 Rust 的翻译参数；思考默认关闭，与 0.1.x 一致。
TranslationConfig translationConfig(dart.TranslationConfig config) =>
    TranslationConfig(
      language: config.targetLanguage,
      systemPrompt: config.systemPrompt,
      userPrompt: config.userPrompt,
      temperature: config.temperature,
      thinking: ThinkingLevel.off,
    );
