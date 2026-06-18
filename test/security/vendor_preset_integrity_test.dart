import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/api_provider.dart';

void main() {
  /// 所有内置服务商预设 ID（与 _builtinPresets 顺序一致）。
  const builtinIds = [
    'openai',
    'anthropic',
    'gemini',
    'deepseek',
    'qwen',
    'zhipu',
    'kimi',
    'doubao',
    'mimo',
    'grok',
  ];

  group('AgentVendorPreset 完整性', () {
    test('所有内置预设都能被 isBuiltin 识别', () {
      for (final id in builtinIds) {
        expect(
          AgentApiNotifier.isBuiltin(id),
          isTrue,
          reason: '$id 应被识别为内置预设',
        );
      }
    });

    test('所有内置预设都有非空 apiKeyUrl', () {
      for (final id in builtinIds) {
        final url = AgentApiNotifier.presetApiKeyUrl(id);
        expect(url, isNotNull, reason: '$id 缺少 apiKeyUrl');
        expect(url, isNotEmpty, reason: '$id 的 apiKeyUrl 为空');
      }
    });

    test('所有 apiKeyUrl 使用 https scheme', () {
      for (final id in builtinIds) {
        final url = AgentApiNotifier.presetApiKeyUrl(id);
        final uri = Uri.tryParse(url!);
        expect(uri, isNotNull, reason: '$id 的 apiKeyUrl 无法解析: $url');
        expect(
          uri!.scheme,
          equals('https'),
          reason: '$id 的 apiKeyUrl 必须使用 https（实际: ${uri.scheme}）',
        );
      }
    });

    test('非内置 ID 返回 null', () {
      expect(AgentApiNotifier.presetApiKeyUrl('nonexistent'), isNull);
      expect(AgentApiNotifier.presetKeyHint('nonexistent'), isNull);
      expect(AgentApiNotifier.isBuiltin('nonexistent'), isFalse);
    });
  });
}
