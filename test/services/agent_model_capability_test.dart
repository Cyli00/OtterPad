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

  group('AgentModelCapability 能力推断', () {
    AgentModelCapability cap(String id) => AgentModelCapability.fromModelId(
      provider: AgentApiProvider.openAICompatible,
      modelId: id,
    );

    test('gpt-4o：工具 + 视觉，无推理', () {
      final c = cap('gpt-4o');
      expect(c.tool, isTrue);
      expect(c.reasoning, isFalse);
      expect(c.imageInput, isTrue);
    });

    test('o3：工具 + 推理', () {
      final c = cap('o3');
      expect(c.tool, isTrue);
      expect(c.reasoning, isTrue);
    });

    test('claude-opus-4-7：工具 + 推理 + 视觉', () {
      final c = cap('claude-opus-4-7');
      expect(c.tool, isTrue);
      expect(c.reasoning, isTrue);
      expect(c.imageInput, isTrue);
    });

    test('deepseek-chat：工具，无推理', () {
      final c = cap('deepseek-chat');
      expect(c.tool, isTrue);
      expect(c.reasoning, isFalse);
    });

    test('embedding 模型清空工具/推理', () {
      final c = cap('text-embedding-3-large');
      expect(c.embedding, isTrue);
      expect(c.tool, isFalse);
      expect(c.reasoning, isFalse);
    });

    test('生图模型不带工具/推理', () {
      final c = AgentModelCapability.fromModelId(
        provider: AgentApiProvider.openai,
        modelId: 'gpt-image-2',
      );
      expect(c.imageOutput, isTrue);
      expect(c.tool, isFalse);
      expect(c.reasoning, isFalse);
    });

    test('toJson/fromJson 往返保真', () {
      const c = AgentModelCapability(
        textInput: true,
        imageInput: true,
        imageOutput: false,
        embedding: false,
        tool: true,
        reasoning: true,
      );
      final r = AgentModelCapability.fromJson(c.toJson());
      expect(r.textInput, c.textInput);
      expect(r.imageInput, c.imageInput);
      expect(r.imageOutput, c.imageOutput);
      expect(r.embedding, c.embedding);
      expect(r.tool, c.tool);
      expect(r.reasoning, c.reasoning);
    });
  });
}
