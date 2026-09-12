enum AgentApiProvider { openai, anthropic, gemini, openAICompatible }

extension AgentApiProviderExt on AgentApiProvider {
  String get label => switch (this) {
    AgentApiProvider.openai => 'OpenAI',
    AgentApiProvider.anthropic => 'Anthropic',
    AgentApiProvider.gemini => 'Gemini',
    AgentApiProvider.openAICompatible => 'OpenAI Compatible',
  };

  /// 纯域名，不含版本路径
  String get defaultBaseUrl => switch (this) {
    AgentApiProvider.openai => 'https://api.openai.com',
    AgentApiProvider.anthropic => 'https://api.anthropic.com',
    AgentApiProvider.gemini => 'https://generativelanguage.googleapis.com',
    AgentApiProvider.openAICompatible => 'https://api.deepseek.com',
  };

  String get apiKeyHint => switch (this) {
    AgentApiProvider.openai => 'sk-...',
    AgentApiProvider.anthropic => 'sk-ant-...',
    AgentApiProvider.gemini => 'AI...',
    AgentApiProvider.openAICompatible => 'sk-...',
  };

  /// 模型列表端点路径
  String get modelsPath => switch (this) {
    AgentApiProvider.openai => '/v1/models',
    AgentApiProvider.anthropic => '/v1/models',
    AgentApiProvider.gemini => '/v1beta/models',
    AgentApiProvider.openAICompatible => '/v1/models',
  };

  /// Chat / 消息端点路径（用于预览和模型检测）
  String get chatPath => switch (this) {
    AgentApiProvider.openai => '/v1/responses',
    AgentApiProvider.anthropic => '/v1/messages',
    AgentApiProvider.gemini => '/v1beta',
    AgentApiProvider.openAICompatible => '/v1/chat/completions',
  };

  /// 实际线上协议：xAI（Grok）已停用 OpenAI 兼容的 Chat Completions、仅保留
  /// 与 OpenAI Responses 同形的自家 Responses API，按 host 升格为
  /// [AgentApiProvider.openai]；其余原样。不进协议枚举——添加服务商仍只见
  /// 4 种协议。请求构造 / 连通性检测 / 工具支持判定统一先过这一层。
  AgentApiProvider wireProtocol(String baseUrl) =>
      this == AgentApiProvider.openAICompatible && _isXaiHost(baseUrl)
      ? AgentApiProvider.openai
      : this;

  /// chat 端点完整 URL（已按 [wireProtocol] 解析，xAI 返回 `/responses`）。
  /// baseUrl 末尾已带版本段（/v1、/v3、/v4、/v1beta…）时不再追加默认版本、
  /// 直接接资源路径——兼容 Zhipu(/api/paas/v4)、Doubao(/api/v3) 等非 /v1
  /// 版本段的厂商，以及用户填带版本反代地址的场景。
  /// Gemini 返回值不含 `/models/{model}:generateContent`，由调用方追加。
  String chatUrl(String baseUrl) {
    final wire = wireProtocol(baseUrl);
    final base = _trimTrailingSlash(baseUrl);
    if (!_versionTailRe.hasMatch(base)) return '$base${wire.chatPath}';
    return switch (wire) {
      AgentApiProvider.openai => '$base/responses',
      AgentApiProvider.anthropic => '$base/messages',
      AgentApiProvider.gemini => base,
      AgentApiProvider.openAICompatible => '$base/chat/completions',
    };
  }

  /// 模型列表端点完整 URL，版本段处理同 [chatUrl]。
  String modelsUrl(String baseUrl) {
    final base = _trimTrailingSlash(baseUrl);
    if (!_versionTailRe.hasMatch(base)) return '$base$modelsPath';
    return '$base/models';
  }
}

/// URL 末尾版本段（/v1、/v3、/v4、/v1beta、/v1beta2 等）
final _versionTailRe = RegExp(r'/v[\da-z.]+$');

/// xAI 官方域名（api.x.ai 等），接受 baseUrl 或完整 chat URL（host 相同）。
bool _isXaiHost(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  return host == 'x.ai' || host.endsWith('.x.ai');
}

String _trimTrailingSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;
