import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _brands = <String, List<String>>{
  'claude-color': ['claude'],
  'gemini-color': ['gemini', 'nano-banana'],
  'deepseek-color': ['deepseek'],
  'qwen-color': ['qwen', 'qwq', 'qvq', '通义'],
  'doubao-color': ['doubao', '豆包', 'bytedance', '火山'],
  'zhipu-color': ['glm', 'zhipu', '智谱'],
  'kimi-color': ['kimi'],
  'moonshot': ['moonshot', '月之暗面'],
  'minimax-color': ['minimax'],
  'mistral-color': ['mistral', 'mixtral', 'magistral', 'codestral', 'devstral'],
  'gemma-color': ['gemma'],
  'ollama': ['ollama'],
  'meta-color': ['llama', 'meta'],
  'hunyuan-color': ['hunyuan', 'tencent', '混元'],
  'perplexity-color': ['perplexity', 'sonar'],
  'stepfun-color': ['stepfun', 'step-', '阶跃'],
  'xiaomimimo': ['mimo', 'xiaomi', '小米'],
  'cohere-color': ['cohere', 'command-r', 'command-a'],
  'xai': ['grok', 'xai', 'x.ai'],
  'openai': ['openai', 'gpt', 'chatgpt'],
  'anthropic': ['anthropic'],
  'google-color': ['google'],
  'siliconcloud-color': ['siliconflow', 'siliconcloud', '硅基'],
  'openrouter': ['openrouter'],
  'groq': ['groq'],
};

String? aiBrandAsset(String name) {
  final normalized = name.toLowerCase();
  if (RegExp(r'(^|[/\s])o\d(?:\b|-)').hasMatch(normalized)) {
    return 'assets/icons/ai-openai.svg';
  }
  for (final entry in _brands.entries) {
    if (entry.value.any(normalized.contains)) {
      return 'assets/icons/ai-${entry.key}.svg';
    }
  }
  return null;
}

/// AI 品牌图标。
///
/// 外框尺寸与内缩比例由本组件固定，调用方不再各自传 `size`——同一个列表里
/// 所有图标占位一致，不会忽大忽小。
///
/// 深浅色定位：
/// - 单色资产走 `currentColor`，经 [SvgTheme] 取当前 `onSurface`：浅色模式深字、
///   深色模式浅字。
/// - 彩色资产保留品牌原色。**不铺主题底板**：底板会让 doubao / qwen / deepseek
///   这类深蓝品牌色在深色模式下糊进背景，而浅色模式下又会压掉品牌色对比。
/// - 资产自带深色底板的品牌（Kimi）由资产承担对比，浅色模式下依然可读。
/// - 无品牌资产时退化为 [ColorScheme.primaryContainer] 字母块。
class AiBrandIcon extends StatelessWidget {
  /// 图标外框边长：全 App 统一，不允许调用方覆盖。
  static const double boxSize = 32;

  /// 图形在内缩后的占比。
  static const double _glyphRatio = .75;

  final String name;
  final String fallback;
  const AiBrandIcon({super.key, required this.name, this.fallback = ''});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final asset = aiBrandAsset(name) ?? aiBrandAsset(fallback);
    final label = name.trim().isNotEmpty ? name.trim() : fallback.trim();
    final glyph = boxSize * _glyphRatio;

    if (asset == null) {
      return Container(
        width: boxSize,
        height: boxSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label.isEmpty ? '?' : label.characters.first.toUpperCase(),
          style: theme.textTheme.labelLarge?.copyWith(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Center(
        child: SvgPicture.asset(
          asset,
          width: glyph,
          height: glyph,
          theme: SvgTheme(currentColor: cs.onSurface),
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
