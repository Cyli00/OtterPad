import '../data/models/ai/agent_config.dart';

/// 内置 server-side 工具的内部标识常量。
///
/// 实际发往各厂的工具字段在 AgentChatService 请求构造层翻译：
/// - [search]：OpenAI `web_search` / Anthropic `web_search_20250305` /
///   Gemini `google_search`
/// - [urlContext]：Anthropic `web_fetch_20250910` / Gemini `url_context`；
///   OpenAI 与兼容端无对应 server tool，由 UrlContextService 客户端抓取回退。
abstract class BuiltInToolNames {
  static const search = 'search';
  static const urlContext = 'url_context';
}

/// OpenAI 兼容端的联网搜索方式（按 baseUrl 域名识别厂商）。各家字段
/// 互不兼容，请求构造层按厂商分发：Qwen 顶层 `enable_search` / Zhipu
/// `web_search` 工具 / Kimi `$web_search` 内置函数回环 / MiMo `web_search`
/// 工具（官方端需先在控制台开通联网插件）。
/// Doubao（插件仅 Bot API）、DeepSeek 的标准 chat completions 均无可用
/// 搜索 → [none]。Grok 不在此列——已按 host 升格走自家 Responses API
/// （见 [AgentApiProviderExt.wireProtocol]），搜索在 openai 线路注入。
///
/// [external] 是伪厂商：不由域名识别（[compatSearchVendor] 不会返回它），
/// 由 AgentChatService 在「无原生搜索 + 已配置外部搜索 Key」时主动升级，
/// 走客户端 function calling 搜索回退。
enum CompatSearchVendor { qwen, zhipu, kimi, mimo, external, none }

/// 各服务商 + 模型组合的官方支持检测。不支持的组合由调用方静默跳过工具
/// 注入（避免 400），而不是报错。
abstract class BuiltInToolsHelper {
  /// 该工具是否被 provider+model 官方支持。openAICompatible 的搜索支持按
  /// [baseUrl] 域名识别厂商（见 [compatSearchVendor]），其余协议无需传。
  /// 判定前先过 [AgentApiProviderExt.wireProtocol]——xAI 升格到 openai 线路，
  /// 调用方传协议枚举原值即可。
  static bool isSupported({
    required AgentApiProvider provider,
    required String modelId,
    required String tool,
    String baseUrl = '',
  }) {
    final m = modelId.trim().toLowerCase();
    return switch (provider.wireProtocol(baseUrl)) {
      AgentApiProvider.gemini => switch (tool) {
        BuiltInToolNames.search => AgentModelCapability.isGeminiWithSearch(m),
        BuiltInToolNames.urlContext =>
          AgentModelCapability.isGeminiWithUrlContext(m),
        _ => false,
      },
      AgentApiProvider.anthropic => AgentModelCapability.isModernClaude(m),
      AgentApiProvider.openai =>
        tool == BuiltInToolNames.search &&
            (_isOpenAISearchModel(m) || _isXaiSearchModel(m)),
      // URL 提取兼容端无 server tool，统一走客户端抓取回退。
      AgentApiProvider.openAICompatible =>
        tool == BuiltInToolNames.search &&
            compatSearchVendor(baseUrl) != CompatSearchVendor.none,
    };
  }

  /// 从 baseUrl（或完整 chat URL，host 相同）识别兼容端搜索厂商。
  static CompatSearchVendor compatSearchVendor(String baseUrl) {
    final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
    if (host.contains('dashscope')) return CompatSearchVendor.qwen;
    if (host.endsWith('bigmodel.cn')) return CompatSearchVendor.zhipu;
    if (host.contains('moonshot') || host.contains('kimi')) {
      return CompatSearchVendor.kimi;
    }
    if (host.contains('xiaomimimo')) return CompatSearchVendor.mimo;
    return CompatSearchVendor.none;
  }

  /// xAI Responses API 的 server-side `web_search`（与 OpenAI 同名同形），
  /// 官方支持 grok-4 系（grok-4 / grok-4-fast / grok-4.1…）；grok-3 及
  /// grok-code 不支持 → 静默跳过注入。
  static bool _isXaiSearchModel(String m) => m.startsWith('grok-4');

  static bool _isOpenAISearchModel(String m) {
    return m.startsWith('gpt-4o') ||
        m.startsWith('gpt-4.1') ||
        m.startsWith('o4-mini') ||
        m == 'o3' ||
        m.startsWith('o3-') ||
        m.startsWith('gpt-5');
  }
}
