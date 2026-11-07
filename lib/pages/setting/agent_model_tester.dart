import '../../core/l10n.dart';
import '../../core/otter_error_text.dart';
import '../../core/rust_ai.dart';
import '../../core/rust_backend.dart';
import '../../data/models/ai/agent_config.dart';
import '../../src/rust/ai/types.dart' as rust;
import '../../src/rust/api/ai.dart';

ModelSelection _selection(
  String instanceId,
  AgentApiProvider provider,
  String baseUrl,
  String modelId, {
  int? maxTokens,
}) => modelSelection(
  AgentApiState(
    id: instanceId,
    provider: provider,
    baseUrl: baseUrl,
    models: [modelId],
    modelParams: {
      modelId: AgentModelParams(
        maxTokens: maxTokens,
        thinkingLevel: ThinkingLevel.off,
      ),
    },
  ),
  modelId,
)!;

/// 用极短请求检测模型可用；成功返回 null，失败返回可读原因。密钥取自已保存的实例。
Future<String?> testAgentModel({
  required AppLocalizations l10n,
  required String instanceId,
  required AgentApiProvider provider,
  required String baseUrl,
  required String modelId,
}) async {
  try {
    await for (final event in RustBackend.instance.generateText(
      model: _selection(instanceId, provider, baseUrl, modelId, maxTokens: 16),
      request: GenerationRequest(
        system: '',
        messages: [
          rust.Message(role: rust.Role.user, text: 'hi', images: const []),
        ],
        webSearch: false,
        urlContext: false,
        showReasoning: false,
        cachePrefix: false,
      ),
      taskId: rustTaskId('model-test'),
    )) {
      switch (event) {
        case GenerationEvent_Completed():
          return null;
        case GenerationEvent_Failed(:final error):
          throw error;
        default:
      }
    }
    return null;
  } catch (e) {
    return errorText(l10n, e);
  }
}

/// 服务商的模型列表（按 id 排序）。
Future<List<String>> fetchAvailableModels({
  required String instanceId,
  required AgentApiProvider provider,
  required String baseUrl,
}) async {
  final models = await RustBackend.instance.models(
    selection: _selection(instanceId, provider, baseUrl, ''),
    taskId: rustTaskId('models'),
  );
  return [for (final m in models) m.id]..sort();
}
