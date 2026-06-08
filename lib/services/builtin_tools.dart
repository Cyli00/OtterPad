import '../core/l10n.dart';
import '../providers/api_provider.dart';

/// 内置工具名常量（snake_case，与各厂 API 字段名对齐）。
abstract class BuiltInToolNames {
  // 通用
  static const search = 'search';

  // Gemini
  static const codeExecution = 'code_execution';
  static const urlContext = 'url_context';
  static const youtube = 'youtube';

  // OpenAI
  static const codeInterpreter = 'code_interpreter';
  static const imageGeneration = 'image_generation';

  static String label(String tool, [AppLocalizations? l10n]) => switch (tool) {
    search => l10n?.searchToolLabel ?? '搜索',
    codeExecution => l10n?.codeExecutionLabel ?? '代码执行',
    urlContext => l10n?.urlContextLabel ?? 'URL 上下文',
    youtube => l10n?.youtubeLabel ?? 'YouTube',
    codeInterpreter => l10n?.codeInterpreterLabel ?? '代码解释器',
    imageGeneration => l10n?.imageGenerationLabel ?? '图片生成',
    _ => tool,
  };

  static String description(String tool, [AppLocalizations? l10n]) =>
      switch (tool) {
    search => l10n?.searchToolDesc ?? '使用网络搜索获取最新信息',
    codeExecution => l10n?.codeExecutionDesc ?? '在沙箱中执行代码并返回结果',
    urlContext => l10n?.urlContextDesc ?? '读取 URL 内容作为上下文',
    youtube => l10n?.youtubeDesc ?? '自动识别并提取 YouTube 视频信息',
    codeInterpreter => l10n?.codeInterpreterDesc ?? '在沙箱中运行代码、处理文件',
    imageGeneration => l10n?.imageGenerationDesc ?? '在对话中生成图片',
    _ => '',
  };

  /// 各协议可用的内置工具列表。
  static List<String> forProvider(AgentApiProvider provider) => switch (provider) {
    AgentApiProvider.gemini => [search, codeExecution, urlContext, youtube],
    AgentApiProvider.openai => [search, codeInterpreter, imageGeneration],
    AgentApiProvider.anthropic => [search],
    AgentApiProvider.openAICompatible => [search],
  };
}

/// 各服务商 + 模型组合的官方支持检测。
abstract class BuiltInToolsHelper {
  /// 该工具是否被 provider+model 官方支持。
  static bool isSupported({
    required AgentApiProvider provider,
    required String modelId,
    required String tool,
  }) => switch (provider) {
    AgentApiProvider.gemini => true,
    AgentApiProvider.anthropic =>
      tool == BuiltInToolNames.search && _isClaudeSearchModel(modelId),
    AgentApiProvider.openai => tool == BuiltInToolNames.search
        ? _isOpenAISearchModel(modelId)
        : true,
    AgentApiProvider.openAICompatible => false,
  };

  static bool _isClaudeSearchModel(String modelId) {
    final m = modelId.trim().toLowerCase();
    const supported = <String>{
      'claude-opus-4-7',
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-sonnet-4-5-20250929',
      'claude-sonnet-4-20250514',
      'claude-3-7-sonnet-20250219',
      'claude-haiku-4-5-20251001',
      'claude-3-5-haiku-latest',
      'claude-opus-4-1-20250805',
      'claude-opus-4-20250514',
    };
    return supported.contains(m);
  }

  static bool _isOpenAISearchModel(String modelId) {
    final m = modelId.trim().toLowerCase();
    return m.startsWith('gpt-4o') ||
        m.startsWith('gpt-4.1') ||
        m.startsWith('o4-mini') ||
        m == 'o3' ||
        m.startsWith('o3-') ||
        m.startsWith('gpt-5');
  }
}
