import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/services/agent_model_capability.dart';
import 'package:otter_pad/services/model_capability_store.dart';

/// 能力判定测试（方案 C）：优先级链「用户手动覆写 > 远程能力表(modelcaps)
/// > 兜底（全 false）」。modelcaps 未收录的模型默认无能力，由用户在能力卡片
/// 手动指定。远程表层用 debugInject 注入，绕过网络/缓存。
void main() {
  group('ModelCapabilityStore.lookup 纯 id 提取', () {
    setUp(() => ModelCapabilityStore.instance.debugInject({}));

    test('全 id 剥前缀命中纯 id key', () {
      ModelCapabilityStore.instance.debugInject({
        'inkling': AgentModelCapability(
            imageInput: true, tool: true, reasoning: true),
        'mimo-v2.5-pro':
            AgentModelCapability(imageInput: false, tool: true, reasoning: true),
      });
      expect(
          ModelCapabilityStore.instance
              .lookup('thinkingmachines/inkling')?.imageInput,
          isTrue);
      expect(
          ModelCapabilityStore.instance
              .lookup('openrouter/xiaomi/mimo-v2.5-pro')?.imageInput,
          isFalse);
      expect(
          ModelCapabilityStore.instance
              .lookup('openrouter/xiaomi/mimo-v2.5-pro')?.tool,
          isTrue);
      expect(
          ModelCapabilityStore.instance.lookup('inkling')?.reasoning, isTrue);
    });

    test('未知模型未命中返回 null', () {
      ModelCapabilityStore.instance.debugInject({});
      expect(
          ModelCapabilityStore.instance.lookup('future-unknown-model'), isNull);
    });
  });

  group('AgentModelCapability.fromModelId 兜底', () {
    test('未知模型默认无能力（方案 C，由用户手动指定）', () {
      final cap = AgentModelCapability.fromModelId(
        provider: AgentApiProvider.openAICompatible,
        modelId: 'future-unknown-model',
      );
      expect(cap.imageInput, isFalse);
      expect(cap.imageOutput, isFalse);
      expect(cap.tool, isFalse);
      expect(cap.reasoning, isFalse);
      expect(cap.embedding, isFalse);
    });
  });

  group('ModelCapabilityStore.isImageGenerationModel（查远程表 imageOutput）',
      () {
    setUp(() => ModelCapabilityStore.instance.debugInject({}));

    test('远程表命中 imageOutput=true → 判定为生图', () {
      ModelCapabilityStore.instance.debugInject({
        'gpt-image-2': AgentModelCapability(imageOutput: true),
        'gpt-image-2-2026-04-21': AgentModelCapability(imageOutput: true),
        'gemini-3.1-flash-image-preview': AgentModelCapability(imageOutput: true),
        'seedance-2.0-draw': AgentModelCapability(imageOutput: true),
      });
      expect(
          ModelCapabilityStore.instance.isImageGenerationModel('gpt-image-2'),
          isTrue);
      expect(
          ModelCapabilityStore.instance
              .isImageGenerationModel('openai/gpt-image-2-2026-04-21'),
          isTrue);
      expect(
          ModelCapabilityStore.instance
              .isImageGenerationModel('gemini-3.1-flash-image-preview'),
          isTrue);
      expect(
          ModelCapabilityStore.instance
              .isImageGenerationModel('seedance-2.0-draw'),
          isTrue);
    });

    test('远程表命中 imageOutput=false → 不判定为生图', () {
      ModelCapabilityStore.instance.debugInject({
        'gpt-4o':
            AgentModelCapability(imageOutput: false, imageInput: true, tool: true),
        'gemini-2.5-pro':
            AgentModelCapability(imageOutput: false, reasoning: true),
      });
      expect(
          ModelCapabilityStore.instance.isImageGenerationModel('gpt-4o'),
          isFalse);
      expect(
          ModelCapabilityStore.instance
              .isImageGenerationModel('gemini-2.5-pro'),
          isFalse);
    });

    test('远程表未命中 → false（能力置空，用户手动指定）', () {
      ModelCapabilityStore.instance.debugInject({});
      expect(
          ModelCapabilityStore.instance
              .isImageGenerationModel('gpt-image-9-future'),
          isFalse);
    });
  });

  group('AgentModelCapability 序列化', () {
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