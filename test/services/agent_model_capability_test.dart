import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/services/agent_model_capability.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AgentModelCapability.init();
  });

  group('AgentModelCapability', () {
    test('识别 OpenAI 生图模型', () {
      expect(
        AgentModelCapability.isImageGenerationModel(
          provider: AgentApiProvider.openai,
          modelId: 'gpt-image-2',
        ),
        isTrue,
      );
      expect(
        AgentModelCapability.isImageGenerationModel(
          provider: AgentApiProvider.openai,
          modelId: 'gpt-image-2-2026-04-21',
        ),
        isTrue,
      );
      expect(
        AgentModelCapability.isImageGenerationModel(
          provider: AgentApiProvider.openai,
          modelId: 'gpt-image-1.5',
        ),
        isFalse,
      );
      expect(
        AgentModelCapability.isImageGenerationModel(
          provider: AgentApiProvider.openai,
          modelId: 'gpt-image-1',
        ),
        isFalse,
      );
      expect(
        AgentModelCapability.isImageGenerationModel(
          provider: AgentApiProvider.openai,
          modelId: 'gpt-4o',
        ),
        isFalse,
      );
    });

    test('识别 Gemini 生图模型', () {
      expect(
        AgentModelCapability.isImageGenerationModel(
          provider: AgentApiProvider.gemini,
          modelId: 'gemini-3.1-flash-image-preview',
        ),
        isTrue,
      );
      expect(
        AgentModelCapability.isImageGenerationModel(
          provider: AgentApiProvider.gemini,
          modelId: 'gemini-2.5-pro',
        ),
        isFalse,
      );
    });

    test('embedding 模型不会被识别为生图模型', () {
      final capability = AgentModelCapability.fromModelId(
        provider: AgentApiProvider.openAICompatible,
        modelId: 'text-embedding-3-large',
      );
      expect(capability.embedding, isTrue);
      expect(capability.canGenerateImage, isFalse);
    });
  });
}
