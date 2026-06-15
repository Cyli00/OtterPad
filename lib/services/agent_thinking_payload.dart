import '../providers/api_provider.dart';
import 'agent_model_capability.dart';

/// 把跨 provider 统一的 [ThinkingLevel] 翻译成各服务商请求体 fragment。
///
/// 设计：每个方法返回**要直接 merge 进对应 body 的 fragment**。
/// - [forOpenAI] / [forAnthropic] / [forOpenAICompat] 返回顶层 fragment，
///   调用方 `body.addAll(...)`。
/// - [forGemini] 返回 `thinkingConfig` 内层 fragment，调用方放入
///   `generationConfig.thinkingConfig`。
///
/// `level == null` 时统一返回 `{}`——保留服务商默认（不发送任何 thinking 字段）。
/// 模型若不支持完全关闭（Gemini 2.5 Pro / Claude adaptive / Gemini 3 Pro 等），
/// 在各方法内部自动 fallback 到该服务商支持的最低档。
class AgentThinkingPayload {
  AgentThinkingPayload._();

  /// OpenAI Responses API：`reasoning.effort` ∈ none/low/medium/high/xhigh。
  ///
  /// 合法值随 gpt-5 代际收窄：初代（gpt-5/-mini/-nano）只接受 minimal..high
  /// （发 none/xhigh 会 400）；gpt-5.1 接受 none..high；gpt-5.2+ 才有完整
  /// none..xhigh。超出该代际能力的档位就近归并。
  static Map<String, dynamic> forOpenAI(String modelId, ThinkingLevel? level) {
    if (level == null) return const {};
    // xAI Responses API（同形复用本线路）：grok-4 系不接受 reasoning.effort
    // （400），grok-3-mini 仅 low/high——统一不发，保留服务端默认深度。
    if (modelId.toLowerCase().startsWith('grok')) return const {};
    final minor = AgentModelCapability.gpt5Minor(modelId);
    var effort = switch (level) {
      ThinkingLevel.off => 'none',
      ThinkingLevel.low => 'low',
      ThinkingLevel.medium => 'medium',
      ThinkingLevel.high => 'high',
      ThinkingLevel.xhigh => 'xhigh',
    };
    if (minor == 0) {
      if (effort == 'none') effort = 'minimal';
      if (effort == 'xhigh') effort = 'high';
    } else if (minor == 1) {
      if (effort == 'xhigh') effort = 'high';
    }
    return {
      'reasoning': {'effort': effort},
    };
  }

  /// Anthropic Messages：分 adaptive 模型（Opus 4.7+ / Fable）vs 旧模型两条路径。
  ///
  /// **Adaptive**：`thinking.type='adaptive'` + `output_config.effort` 控制力度。
  /// medium 不带 `output_config`——按 Anthropic 推荐，让 adaptive 自决。
  /// off 映射到 `effort='low'`（adaptive 不能真正关闭）。
  ///
  /// **旧模型**：`thinking.type='disabled'|'enabled'` + `budget_tokens` 数字。
  /// 注意旧模型要求 `budget_tokens < max_tokens`，调用方需用
  /// [legacyBudgetOf] 校正 max_tokens。
  static Map<String, dynamic> forAnthropic(
    String modelId,
    ThinkingLevel? level,
  ) {
    if (level == null) return const {};

    if (AgentModelCapability.isClaudeAdaptive(modelId)) {
      final effort = switch (level) {
        ThinkingLevel.off => 'low',
        ThinkingLevel.low => 'low',
        ThinkingLevel.medium => null, // 不带 effort，adaptive 自决
        ThinkingLevel.high => 'high',
        ThinkingLevel.xhigh => 'max',
      };
      return {
        'thinking': {'type': 'adaptive'},
        if (effort != null) 'output_config': {'effort': effort},
      };
    }

    if (level == ThinkingLevel.off) {
      return {
        'thinking': {'type': 'disabled'},
      };
    }
    return {
      'thinking': {'type': 'enabled', 'budget_tokens': legacyBudgetOf(level)},
    };
  }

  /// Anthropic 旧模型（非 adaptive）各档对应的 `budget_tokens`。
  /// off 返回 0（不会被 enabled 路径用到）。
  static int legacyBudgetOf(ThinkingLevel level) => switch (level) {
    ThinkingLevel.off => 0,
    ThinkingLevel.low => 1024,
    ThinkingLevel.medium => 4096,
    ThinkingLevel.high => 16384,
    ThinkingLevel.xhigh => 32000,
  };

  /// Gemini：返回放在 `generationConfig.thinkingConfig` 下的 fragment。
  ///
  /// **3 系列**：用 `thinkingLevel: minimal/low/medium/high`，xhigh 也 fallback
  /// 到 high（3 系列上限即 high）。3.x Pro 不支持 minimal，off 改用 'low'；
  /// gemini-3-pro（非 3.1）只接受 low/high，medium 会 400，归到 high
  /// （该模型默认即 high/dynamic）。
  ///
  /// **2.5 系列**：用 `thinkingBudget` 数字。映射 [off=0, low=512, medium=4096,
  /// high=16384, xhigh=模型上限]；2.5 Pro 不能完全关，off clamp 到 128。
  static Map<String, dynamic> forGemini(String modelId, ThinkingLevel? level) {
    if (level == null) return const {};

    if (AgentModelCapability.isGemini3(modelId)) {
      final id = modelId.toLowerCase();
      final isPro = id.contains('pro');
      final isLegacy3Pro = id.contains('gemini-3-pro');
      final lv = switch (level) {
        ThinkingLevel.off => isPro ? 'low' : 'minimal',
        ThinkingLevel.low => 'low',
        ThinkingLevel.medium => isLegacy3Pro ? 'high' : 'medium',
        ThinkingLevel.high || ThinkingLevel.xhigh => 'high',
      };
      return {'thinkingLevel': lv};
    }

    if (AgentModelCapability.isGemini25(modelId)) {
      final maxB = AgentModelCapability.gemini25MaxBudget(modelId);
      final isPro = AgentModelCapability.isGemini25Pro(modelId);
      final budget = switch (level) {
        ThinkingLevel.off => isPro ? 128 : 0,
        ThinkingLevel.low => 512,
        ThinkingLevel.medium => 4096,
        ThinkingLevel.high => 16384,
        ThinkingLevel.xhigh => maxB,
      };
      return {'thinkingBudget': budget};
    }

    // 既非 2.5 也非 3——可能是更老的 Gemini（1.5 Pro 等），不发 thinking 字段
    return const {};
  }

  /// OpenAI Compatible (DeepSeek 等)：`thinking.type` + 顶层 `reasoning_effort`。
  ///
  /// **Schema 来源**：DeepSeek 官方文档（OpenAI Format 路径）。两个字段独立：
  /// - `{thinking:{type:enabled/disabled}}` 控制是否思考（默认 enabled）
  /// - 顶层 `reasoning_effort` 控制思考力度（low/medium/high/xhigh）
  ///
  /// 5 档 → `reasoning_effort` 直接传原字符串，**不在 client 提前归并**：
  /// - off → 仅 `{thinking:{type:disabled}}`，不发 reasoning_effort
  /// - low / medium / high / xhigh → `{thinking:{type:enabled}}` + 原值
  ///
  /// 字符串选择理由：xhigh 既被 OpenAI Reasoning API 识别，也被 DeepSeek 接受
  /// （服务端自动映射到 max）；low/medium 在 DeepSeek 上会被归类到 high，但
  /// 让 server 端做归类，client 保留用户原意。GLM / Doubao 的 `thinking.type`
  /// 字段与此结构兼容；其他 OpenAI 兼容服务（OpenRouter/Together/Groq 等）
  /// 若不识别某字段会忽略，行为退化为 thinking-on 默认深度。
  static Map<String, dynamic> forOpenAICompat(ThinkingLevel? level) {
    if (level == null) return const {};
    if (level == ThinkingLevel.off) {
      return {
        'thinking': {'type': 'disabled'},
      };
    }
    final effort = switch (level) {
      ThinkingLevel.low => 'low',
      ThinkingLevel.medium => 'medium',
      ThinkingLevel.high => 'high',
      ThinkingLevel.xhigh => 'xhigh',
      ThinkingLevel.off => 'low', // unreachable
    };
    return {
      'thinking': {'type': 'enabled'},
      'reasoning_effort': effort,
    };
  }
}
