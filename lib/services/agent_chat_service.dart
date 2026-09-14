import 'dart:convert';

import 'package:dio/dio.dart';

import '../data/models/ai/agent_config.dart';
import 'agent_http.dart';
import 'agent_activity_tracker.dart';
import '../data/models/chat/chat_activity.dart';
import 'agent_thinking_payload.dart';
import 'builtin_tools.dart';
import 'web_search_service.dart';

/// Agent 对话请求失败（已含服务商可读文案），调用方可按语境加前缀。
class AgentChatException implements Exception {
  final String message;
  final bool retryable;
  const AgentChatException(this.message, {this.retryable = false});

  @override
  String toString() => message;
}

/// 多模态消息中的一张图片（base64 PNG + 展示给模型的文字标签）。
class AgentChatImage {
  final String base64Png;
  final String label;

  const AgentChatImage({required this.base64Png, required this.label});
}

/// 多轮对话中的一轮历史。[images] 仅 user 轮可有——调用方把图片固定挂在
/// 会话第一条 user 消息上并逐轮原样重放：图片进入「稳定前缀」可被各家
/// prompt cache 命中，且多轮中模型始终看得到图（不随轮次丢失）。
class AgentChatTurn {
  final bool isUser;
  final String content;
  final List<AgentChatImage> images;

  const AgentChatTurn({
    required this.isUser,
    required this.content,
    this.images = const [],
  });
}

/// Agent 对话接缝：「provider + system/user (+images, +schema) → 文本」的
/// 唯一出口。各 provider 的请求体形状、headers、结构化输出模式、响应提取
/// 全部封装在此，调用方（翻译 / 排版修复 / 未来功能）只描述意图。
///
/// 结构化输出降级阶梯：传入 [schema] 时各 provider 先尝试原生 JSON Schema
/// 约束（OpenAI strict json_schema / Anthropic output_config / Gemini
/// responseJsonSchema / 兼容端 response_format json_schema），被服务商以
/// 400/422 拒绝时逐级退到 json_object 乃至纯 prompt 约束——兼容端各家支持
/// 差异极大，由阶梯自动适配。
///
/// 瞬时错误（429/5xx/超时/断连）内置重试一次。
class AgentChatService {
  AgentChatService._();

  /// 发送一次非流式对话请求，返回模型输出文本。
  ///
  /// [schema] 非空时启用结构化输出（含降级阶梯），[schemaName] 为 OpenAI
  /// 系 json_schema 的命名。[anthropicMaxTokens] 是 Anthropic 的输出上限
  /// 基线（thinking budget 更大时自动抬高）。
  /// 失败抛 [Exception]，message 已转为可读文案。
  static Future<String> send({
    required AgentApiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    AgentModelParams modelParams = const AgentModelParams(),
    required String systemPrompt,
    required String userPrompt,
    List<AgentChatTurn> history = const [],
    List<AgentChatImage> images = const [],
    double? temperature,
    Map<String, dynamic>? schema,
    String schemaName = 'response',
    int anthropicMaxTokens = 4096,

    /// Anthropic 显式 prompt cache（system + 首图 + 当轮尾块打 ephemeral
    /// 断点）。其余 provider 自动前缀缓存、此参数无效。**仅适合「同一大
    /// 前缀反复发送」的调用方**（如文献问答）；一次性 prompt（翻译/排版
    /// 修复）勿开——缓存写入加价 25%，命不中等于白付。
    bool anthropicCachePrefix = false,

    /// 启用模型内置网络搜索（server-side tool）。仅在 [BuiltInToolsHelper]
    /// 判定该 provider+model 官方支持时注入，不支持则静默忽略（避免 400）。
    /// 例外：兼容端无原生搜索且已配置外部搜索 Key 时，回退到客户端
    /// function calling 搜索（[WebSearchService]）。
    bool webSearch = false,

    /// 启用 URL 内容提取（Anthropic `web_fetch_20250910` / Gemini
    /// `url_context`），模型可读取消息中出现的链接全文。与 [webSearch]
    /// 同样经 [BuiltInToolsHelper] 把关；OpenAI 与兼容端无对应 server
    /// tool，此参数无效（调用方走客户端抓取回退）。
    bool urlContext = false,
    void Function(ChatActivity)? onActivity,
    bool includeReasoning = false,
    Duration receiveTimeout = const Duration(minutes: 5),
    CancelToken? cancelToken,
  }) async {
    final activities = AgentActivityTracker(
      onActivity,
      requestReasoning: includeReasoning && onActivity != null,
    );
    // xAI（Grok）按 host 升格走 OpenAI Responses 同形线路
    provider = provider.wireProtocol(baseUrl);
    final url = provider.chatUrl(baseUrl);
    final dio = AgentHttp.instance.dio(receiveTimeout: receiveTimeout);

    final modes = schema == null
        ? const ['none']
        : switch (provider) {
            AgentApiProvider.openai => const ['schema', 'json'],
            AgentApiProvider.anthropic => const ['schema', 'none'],
            AgentApiProvider.gemini => const ['schema', 'json'],
            AgentApiProvider.openAICompatible => const [
              'schema',
              'json',
              'none',
            ],
          };

    for (var m = 0; m < modes.length; m++) {
      try {
        return await _withTransientRetry(
          cancelToken,
          () => _postRequest(
            dio: dio,
            url: url,
            provider: provider,
            apiKey: apiKey,
            modelId: modelId,
            modelParams: modelParams,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            history: history,
            images: images,
            temperature: temperature,
            schema: schema,
            schemaName: schemaName,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicCachePrefix: anthropicCachePrefix,
            webSearch: webSearch,
            urlContext: urlContext,
            activities: activities,
            mode: modes[m],
            cancelToken: cancelToken,
          ),
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        final code = e.response?.statusCode;
        final canFallback =
            m < modes.length - 1 && (code == 400 || code == 422);
        if (!canFallback) {
          throw AgentChatException(
            readableMessage(e),
            retryable: _isTransientDioException(e),
          );
        }
      }
    }
    throw StateError('unreachable');
  }

  /// 429/5xx/超时/断连重试一次（移动网络抖动常见），其余错误直接抛出。
  static bool _isTransientDioException(DioException e) {
    final code = e.response?.statusCode;
    return code == null
        ? const {
            DioExceptionType.connectionTimeout,
            DioExceptionType.sendTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.connectionError,
          }.contains(e.type)
        : const {429, 500, 502, 503, 529}.contains(code);
  }

  static Future<T> _withTransientRetry<T>(
    CancelToken? cancelToken,
    Future<T> Function() run,
  ) async {
    try {
      return await run();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      if (!_isTransientDioException(e)) rethrow;
      await Future.any<void>([
        Future<void>.delayed(const Duration(seconds: 2)),
        if (cancelToken != null) cancelToken.whenCancel.then((_) {}),
      ]);
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      return run();
    }
  }

  static Future<String> _postRequest({
    required Dio dio,
    required String url,
    required AgentApiProvider provider,
    required String apiKey,
    required String modelId,
    required AgentModelParams modelParams,
    required String systemPrompt,
    required String userPrompt,
    required List<AgentChatTurn> history,
    required List<AgentChatImage> images,
    required double? temperature,
    required Map<String, dynamic>? schema,
    required String schemaName,
    required int anthropicMaxTokens,
    required bool anthropicCachePrefix,
    required bool webSearch,
    required bool urlContext,
    required String mode,
    required AgentActivityTracker activities,
    required CancelToken? cancelToken,
  }) async {
    // 兼容端按 host 识别厂商，传完整 chat URL 等价于 baseUrl。
    final useWebSearch =
        webSearch &&
        BuiltInToolsHelper.isSupported(
          provider: provider,
          modelId: modelId,
          tool: BuiltInToolNames.search,
          baseUrl: url,
        );
    final useUrlContext =
        urlContext &&
        BuiltInToolsHelper.isSupported(
          provider: provider,
          modelId: modelId,
          tool: BuiltInToolNames.urlContext,
          baseUrl: url,
        );
    final Response<Map<String, dynamic>> resp;

    switch (provider) {
      case AgentApiProvider.openai:
        resp = await dio.post(
          url,
          data: _openAIBody(
            showReasoning: activities.requestReasoning,
            modelId: modelId,
            modelParams: modelParams,
            systemPrompt: systemPrompt,
            history: history,
            images: images,
            userPrompt: userPrompt,
            temperature: temperature,
            webSearch: useWebSearch,
            stream: false,
            mode: mode,
            schema: schema,
            schemaName: schemaName,
          ),
          options: Options(headers: _bearerHeaders(apiKey)),
          cancelToken: cancelToken,
        );
        final openAIData = resp.data;
        if (openAIData == null) {
          throw const AgentChatException('Empty response body');
        }
        activities.record(
          AgentApiProvider.openai,
          openAIData,
          streaming: false,
        );
        activities.finish();
        return _extractOpenAI(openAIData);

      case AgentApiProvider.anthropic:
        resp = await dio.post(
          url,
          data: _anthropicBody(
            modelId: modelId,
            modelParams: modelParams,
            systemPrompt: systemPrompt,
            history: history,
            images: images,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokensBase: anthropicMaxTokens,
            cachePrefix: anthropicCachePrefix,
            webSearch: useWebSearch,
            urlContext: useUrlContext,
            stream: false,
            mode: mode,
            schema: schema,
          ),
          options: Options(headers: _anthropicHeaders(apiKey)),
          cancelToken: cancelToken,
        );
        final anthropicData = resp.data;
        if (anthropicData == null) {
          throw const AgentChatException('Empty response body');
        }
        activities.record(
          AgentApiProvider.anthropic,
          anthropicData,
          streaming: false,
        );
        activities.finish();
        return _extractAnthropic(anthropicData);

      case AgentApiProvider.gemini:
        resp = await dio.post(
          '$url/models/$modelId:generateContent',
          data: _geminiBody(
            showReasoning: activities.requestReasoning,
            modelId: modelId,
            modelParams: modelParams,
            systemPrompt: systemPrompt,
            history: history,
            images: images,
            userPrompt: userPrompt,
            temperature: temperature,
            webSearch: useWebSearch,
            urlContext: useUrlContext,
            mode: mode,
            schema: schema,
          ),
          options: Options(headers: {'x-goog-api-key': apiKey}),
          cancelToken: cancelToken,
        );
        final geminiData = resp.data;
        if (geminiData == null) {
          throw const AgentChatException('Empty response body');
        }
        activities.record(
          AgentApiProvider.gemini,
          geminiData,
          streaming: false,
        );
        activities.finish();
        return _extractGemini(geminiData);

      case AgentApiProvider.openAICompatible:
        final vendor = _effectiveCompatVendor(webSearch, url);
        var messages = _compatMessages(
          systemPrompt,
          history,
          images,
          userPrompt,
        );
        // Kimi $web_search / 外部 web_search 都是「工具回环」：模型发起
        // tool_call，客户端回填结果后重发（Kimi 回传 arguments 即触发服务端
        // 搜索，外部搜索由客户端真实执行）。上限 3 轮防御异常死循环，超限后
        // 按普通回答提取。其余厂商服务端单轮即返回。
        final loopTool = _searchLoopToolName(vendor);
        final hasImages =
            images.isNotEmpty || history.any((t) => t.images.isNotEmpty);
        for (var round = 0; ; round++) {
          final compatResp = await dio.post<Map<String, dynamic>>(
            url,
            data: _compatBody(
              modelId: modelId,
              modelParams: modelParams,
              messages: messages,
              temperature: temperature,
              hasImages: hasImages,
              vendor: vendor,
              stream: false,
              mode: mode,
              schema: schema,
              schemaName: schemaName,
            ),
            options: Options(headers: _bearerHeaders(apiKey)),
            cancelToken: cancelToken,
          );
          final data = compatResp.data!;
          final searchCalls = loopTool != null && round < 3
              ? _searchToolCalls(data, loopTool)
              : const <Map<String, dynamic>>[];
          activities.record(provider, data, streaming: false);
          if (searchCalls.isEmpty) {
            activities.finish();
            return _extractOpenAICompatible(data);
          }
          messages = [
            ...messages,
            (data['choices'] as List)[0]['message'] as Map<String, dynamic>,
            ...await _searchToolResults(
              vendor,
              searchCalls,
              cancelToken,
              activities,
            ),
          ];
        }
    }
  }

  // ─── 共享消息构造（send 与 sendStream 复用，形状保持一致） ───

  /// Anthropic server tools：web_search_20250305 / web_fetch_20250910 均已
  /// GA，无需 beta header。web_fetch 限 5 次 + 10 万 token，防止超长网页
  /// 击穿上下文（文献全文已占据 system prompt 大头）。
  static List<Map<String, dynamic>> _anthropicTools(
    bool webSearch,
    bool urlContext,
  ) => [
    if (webSearch) {'type': 'web_search_20250305', 'name': 'web_search'},
    if (urlContext)
      {
        'type': 'web_fetch_20250910',
        'name': 'web_fetch',
        'max_uses': 5,
        'max_content_tokens': 100000,
      },
  ];

  static List<Map<String, dynamic>> _geminiTools(
    bool webSearch,
    bool urlContext,
  ) => [
    if (webSearch) {'google_search': <String, dynamic>{}},
    if (urlContext) {'url_context': <String, dynamic>{}},
  ];

  // ─── 共享请求体构造（send 与 sendStream 共用一份事实，新厂商参数只改
  // 这里；流式差异 = `stream: true` + 结构化输出仅非流式传 mode/schema） ───

  /// Bearer 鉴权 headers（OpenAI / 兼容端），流式追加 SSE Accept。
  static Map<String, String> _bearerHeaders(
    String apiKey, {
    bool stream = false,
  }) => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
    if (stream) 'Accept': 'text/event-stream',
  };

  static Map<String, String> _anthropicHeaders(
    String apiKey, {
    bool stream = false,
  }) => {
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
    'Content-Type': 'application/json',
    if (stream) 'Accept': 'text/event-stream',
  };

  /// OpenAI Responses API 请求体。
  static Map<String, dynamic> _openAIBody({
    required String modelId,
    required AgentModelParams modelParams,
    required String systemPrompt,
    required List<AgentChatTurn> history,
    required List<AgentChatImage> images,
    required String userPrompt,
    required double? temperature,
    required bool webSearch,
    required bool stream,
    bool showReasoning = false,
    String mode = 'none',
    Map<String, dynamic>? schema,
    String schemaName = 'response',
  }) {
    final text = <String, dynamic>{
      if (mode == 'schema')
        'format': {
          'type': 'json_schema',
          'name': schemaName,
          'strict': true,
          'schema': schema,
        }
      else if (mode == 'json')
        'format': {'type': 'json_object'},
      if (modelParams.verbosity != null) 'verbosity': modelParams.verbosity,
    };
    final reasoning = Map<String, dynamic>.from(
      AgentThinkingPayload.forOpenAI(modelId, modelParams.thinkingLevel),
    );
    if (showReasoning && !modelId.toLowerCase().startsWith('grok')) {
      reasoning['reasoning'] = {
        ...?reasoning['reasoning'] as Map<String, dynamic>?,
        'summary': 'auto',
      };
    }
    return {
      'model': modelId,
      'instructions': systemPrompt,
      'input': _openAIInput(history, images, userPrompt),
      if (stream) 'stream': true,
      if (text.isNotEmpty) 'text': text,
      if (webSearch)
        'tools': [
          {'type': 'web_search'},
        ],
      'temperature': ?temperature,
      ...reasoning,
    };
  }

  /// Anthropic Messages 请求体。thinking 与 output_config 的合并、旧模型
  /// `budget_tokens < max_tokens` 的校正集中在此。
  static Map<String, dynamic> _anthropicBody({
    required String modelId,
    required AgentModelParams modelParams,
    required String systemPrompt,
    required List<AgentChatTurn> history,
    required List<AgentChatImage> images,
    required String userPrompt,
    required double? temperature,
    required int maxTokensBase,
    required bool cachePrefix,
    required bool webSearch,
    required bool urlContext,
    required bool stream,
    String mode = 'none',
    Map<String, dynamic>? schema,
  }) {
    final thinking = Map<String, dynamic>.from(
      AgentThinkingPayload.forAnthropic(modelId, modelParams.thinkingLevel),
    );
    // adaptive 模型的 effort 也在 output_config 里，与 format 合并发送
    final outputConfig = <String, dynamic>{
      if (mode == 'schema') 'format': {'type': 'json_schema', 'schema': schema},
      ...?(thinking.remove('output_config') as Map<String, dynamic>?),
    };
    // 旧模型要求 budget_tokens < max_tokens
    var maxTokens = maxTokensBase;
    final t = thinking['thinking'];
    if (t is Map && t['budget_tokens'] is int) {
      final budget = t['budget_tokens'] as int;
      if (budget >= maxTokens) maxTokens = budget + 8192;
    }
    return {
      'model': modelId,
      'system': _anthropicSystem(systemPrompt, cachePrefix),
      'max_tokens': maxTokens,
      'messages': _anthropicMessages(
        history,
        images,
        userPrompt,
        cachePrefix: cachePrefix,
      ),
      if (stream) 'stream': true,
      if (webSearch || urlContext)
        'tools': _anthropicTools(webSearch, urlContext),
      'temperature': ?temperature,
      if (outputConfig.isNotEmpty) 'output_config': outputConfig,
      ...thinking,
    };
  }

  /// Gemini generateContent 请求体（流式与否只差 URL 与 `alt=sse`）。
  static Map<String, dynamic> _geminiBody({
    required String modelId,
    required AgentModelParams modelParams,
    required String systemPrompt,
    required List<AgentChatTurn> history,
    required List<AgentChatImage> images,
    required String userPrompt,
    required double? temperature,
    required bool webSearch,
    required bool urlContext,
    bool showReasoning = false,
    String mode = 'none',
    Map<String, dynamic>? schema,
  }) {
    final thinkingCfg = AgentThinkingPayload.forGemini(
      modelId,
      modelParams.thinkingLevel,
    );
    final includeThoughts = showReasoning;
    return {
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': _geminiContents(history, images, userPrompt),
      if (webSearch || urlContext) 'tools': _geminiTools(webSearch, urlContext),
      'generationConfig': {
        'temperature': ?temperature,
        if (schema != null) 'responseMimeType': 'application/json',
        if (mode == 'schema') 'responseJsonSchema': schema,
        if (thinkingCfg.isNotEmpty || includeThoughts)
          'thinkingConfig': {
            ...thinkingCfg,
            if (includeThoughts) 'includeThoughts': true,
          },
      },
    };
  }

  /// 兼容端单轮请求体（搜索回环每轮重建，messages 由调用方维护）。
  static Map<String, dynamic> _compatBody({
    required String modelId,
    required AgentModelParams modelParams,
    required List<Map<String, dynamic>> messages,
    required double? temperature,
    required bool hasImages,
    required CompatSearchVendor vendor,
    required bool stream,
    String mode = 'none',
    Map<String, dynamic>? schema,
    String schemaName = 'response',
  }) {
    final body = <String, dynamic>{
      'model': modelId,
      'messages': messages,
      if (stream) 'stream': true,
      'temperature': ?temperature,
      if (modelParams.maxTokens != null) 'max_tokens': modelParams.maxTokens,
      if (modelParams.topP != null) 'top_p': modelParams.topP,
      if (modelParams.frequencyPenalty != null)
        'frequency_penalty': modelParams.frequencyPenalty,
      if (modelParams.presencePenalty != null)
        'presence_penalty': modelParams.presencePenalty,
      if (mode == 'schema')
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': schemaName, 'strict': true, 'schema': schema},
        }
      else if (mode == 'json')
        'response_format': {'type': 'json_object'},
      // DashScope 专属：把单图 token 上限 1280 → 16384，密集文档页必需
      if (hasImages && AgentModelCapability.isQwenVl(modelId))
        'vl_high_resolution_images': true,
      ...AgentThinkingPayload.forOpenAICompat(modelParams.thinkingLevel),
      ..._compatSearchFragment(vendor),
    };
    if (vendor == CompatSearchVendor.kimi) {
      body.remove('reasoning_effort');
    }
    return body;
  }

  /// 兼容端的生效搜索方式：原生厂商优先；无原生且已配置外部搜索 Key 时
  /// 升级为客户端 function calling 回退（[CompatSearchVendor.external]）。
  static CompatSearchVendor _effectiveCompatVendor(bool webSearch, String url) {
    if (!webSearch) return CompatSearchVendor.none;
    final native = BuiltInToolsHelper.compatSearchVendor(url);
    if (native != CompatSearchVendor.none) return native;
    return WebSearchService.isConfigured
        ? CompatSearchVendor.external
        : CompatSearchVendor.none;
  }

  /// 需要客户端回环的搜索工具名；服务端单轮完成的厂商返回 null。
  static String? _searchLoopToolName(CompatSearchVendor vendor) =>
      switch (vendor) {
        CompatSearchVendor.kimi => r'$web_search',
        CompatSearchVendor.external => 'web_search',
        _ => null,
      };

  /// 兼容端各厂商联网搜索的请求体 fragment（字段互不兼容，按厂商分发）。
  /// Kimi 的 `thinking: disabled` 放在 fragment 里以覆盖前面 spread 的思考
  /// payload——官方限制：$web_search 暂不兼容思考模式。
  static Map<String, dynamic> _compatSearchFragment(
    CompatSearchVendor vendor,
  ) => switch (vendor) {
    CompatSearchVendor.qwen => const {'enable_search': true},
    CompatSearchVendor.zhipu => const {
      'tools': [
        {
          'type': 'web_search',
          'web_search': {'enable': true, 'search_result': true},
        },
      ],
    },
    CompatSearchVendor.kimi => const {
      'tools': [
        {
          'type': 'builtin_function',
          'function': {'name': r'$web_search'},
        },
      ],
      'thinking': {'type': 'disabled'},
    },
    CompatSearchVendor.mimo => const {
      'tools': [
        {'type': 'web_search'},
      ],
    },
    CompatSearchVendor.external => const {
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'web_search',
            'description': '搜索互联网获取实时或最新信息。需要联网才能准确回答时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'query': {'type': 'string', 'description': '搜索关键词'},
              },
              'required': ['query'],
            },
          },
        },
      ],
    },
    CompatSearchVendor.none => const {},
  };

  /// 非流式响应里属于 [toolName] 的 tool_calls；非 tool_calls 收尾或混入
  /// 其他工具（不应出现，我们没发别的工具）时返回空，按普通回答提取。
  static List<Map<String, dynamic>> _searchToolCalls(
    Map<String, dynamic> data,
    String toolName,
  ) {
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return const [];
    final choice = choices[0] as Map<String, dynamic>;
    if (choice['finish_reason'] != 'tool_calls') return const [];
    final calls = (choice['message'] as Map<String, dynamic>?)?['tool_calls'];
    if (calls is! List || calls.isEmpty) return const [];
    final result = <Map<String, dynamic>>[];
    for (final c in calls) {
      if (c is! Map<String, dynamic>) return const [];
      if ((c['function'] as Map<String, dynamic>?)?['name'] != toolName) {
        return const [];
      }
      result.add(c);
    }
    return result;
  }

  /// 搜索回环的 tool 结果消息。Kimi：content = arguments **原样回传**，
  /// 服务端收到回传时才真正执行搜索；外部搜索：客户端解析 query 并真实
  /// 执行搜索，回填结果文本。
  static Future<List<Map<String, dynamic>>> _searchToolResults(
    CompatSearchVendor vendor,
    List<Map<String, dynamic>> calls,
    CancelToken? cancelToken,
    AgentActivityTracker activities,
  ) async {
    final results = <Map<String, dynamic>>[];
    for (final c in calls) {
      final args =
          ((c['function'] as Map<String, dynamic>?)?['arguments'] as String?) ??
          '{}';
      final activityId = c['id'] as String? ?? 'search-${results.length}';
      activities.tool(activityId, 'web_search', args);
      String content;
      if (vendor == CompatSearchVendor.kimi) {
        content = args;
      } else {
        String query = '';
        try {
          final parsed = jsonDecode(args);
          if (parsed is Map<String, dynamic>) {
            query = (parsed['query'] as String?)?.trim() ?? '';
          }
        } catch (_) {}
        content = query.isEmpty
            ? '（搜索失败：未提供搜索关键词）'
            : await WebSearchService.search(query, cancelToken: cancelToken);
      }
      activities.tool(
        activityId,
        'web_search',
        '$args\n\n$content',
        status: content.startsWith('（搜索失败')
            ? ChatActivityStatus.failed
            : ChatActivityStatus.completed,
      );
      results.add({
        'role': 'tool',
        'tool_call_id': c['id'],
        'name': _searchLoopToolName(vendor),
        'content': content,
      });
    }
    return results;
  }

  /// OpenAI Responses API 的 `input`。无图无历史时用纯字符串
  /// （与多模态数组等价，更省字节）。
  static Object _openAIInput(
    List<AgentChatTurn> history,
    List<AgentChatImage> images,
    String userPrompt,
  ) {
    Object content(List<AgentChatImage> imgs, String text) {
      if (imgs.isEmpty) return text;
      return [
        for (final img in imgs) ...[
          {'type': 'input_text', 'text': img.label},
          {
            'type': 'input_image',
            'image_url': 'data:image/png;base64,${img.base64Png}',
            'detail': 'high',
          },
        ],
        {'type': 'input_text', 'text': text},
      ];
    }

    if (images.isEmpty && history.isEmpty) return userPrompt;
    return [
      for (final t in history)
        {
          'role': t.isUser ? 'user' : 'assistant',
          'content': t.isUser ? content(t.images, t.content) : t.content,
        },
      {'role': 'user', 'content': content(images, userPrompt)},
    ];
  }

  /// Anthropic 的 system 字段：开缓存时升格为 content block 数组并在全文块
  /// 上打 ephemeral 断点（字符串形式无法携带 cache_control）。
  static Object _anthropicSystem(String systemPrompt, bool cachePrefix) {
    if (!cachePrefix) return systemPrompt;
    return [
      {
        'type': 'text',
        'text': systemPrompt,
        'cache_control': {'type': 'ephemeral'},
      },
    ];
  }

  /// [cachePrefix] 开启 Anthropic 显式 prompt cache 的消息侧断点：
  /// - 携图 user 轮的**最后一张图**上打断点（稳定前缀 = system+全文+全部图片）；
  /// - 当轮最后一个 text 块上打断点（增量对话缓存：下一轮整个前缀命中，
  ///   Anthropic 会自动回查最近的历史断点位置）。
  /// 连同 system 断点共最多 3 个，不超过 4 个上限。
  static List<Map<String, dynamic>> _anthropicMessages(
    List<AgentChatTurn> history,
    List<AgentChatImage> images,
    String userPrompt, {
    bool cachePrefix = false,
  }) {
    Object content(
      List<AgentChatImage> imgs,
      String text, {
      bool cacheImages = false,
      bool cacheText = false,
    }) {
      if (imgs.isEmpty && !cacheText) return text;
      return [
        for (var i = 0; i < imgs.length; i++) ...[
          {'type': 'text', 'text': imgs[i].label},
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': 'image/png',
              'data': imgs[i].base64Png,
            },
            if (cacheImages && i == imgs.length - 1)
              'cache_control': {'type': 'ephemeral'},
          },
        ],
        {
          'type': 'text',
          'text': text,
          if (cacheText) 'cache_control': {'type': 'ephemeral'},
        },
      ];
    }

    return [
      for (final t in history)
        {
          'role': t.isUser ? 'user' : 'assistant',
          'content': t.isUser
              ? content(
                  t.images,
                  t.content,
                  cacheImages: cachePrefix && t.images.isNotEmpty,
                )
              : t.content,
        },
      {
        'role': 'user',
        'content': content(
          images,
          userPrompt,
          cacheImages: cachePrefix && images.isNotEmpty,
          cacheText: cachePrefix,
        ),
      },
    ];
  }

  static List<Map<String, dynamic>> _geminiContents(
    List<AgentChatTurn> history,
    List<AgentChatImage> images,
    String userPrompt,
  ) {
    List<Map<String, dynamic>> parts(List<AgentChatImage> imgs, String text) =>
        [
          for (final img in imgs) ...[
            {'text': img.label},
            {
              'inline_data': {'mime_type': 'image/png', 'data': img.base64Png},
            },
          ],
          {'text': text},
        ];

    return [
      for (final t in history)
        {
          'role': t.isUser ? 'user' : 'model',
          'parts': t.isUser
              ? parts(t.images, t.content)
              : [
                  {'text': t.content},
                ],
        },
      {'role': 'user', 'parts': parts(images, userPrompt)},
    ];
  }

  static List<Map<String, dynamic>> _compatMessages(
    String systemPrompt,
    List<AgentChatTurn> history,
    List<AgentChatImage> images,
    String userPrompt,
  ) {
    Object content(List<AgentChatImage> imgs, String text) {
      if (imgs.isEmpty) return text;
      return [
        for (final img in imgs) ...[
          {'type': 'text', 'text': img.label},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/png;base64,${img.base64Png}',
              'detail': 'high',
            },
          },
        ],
        {'type': 'text', 'text': text},
      ];
    }

    return [
      {'role': 'system', 'content': systemPrompt},
      for (final t in history)
        {
          'role': t.isUser ? 'user' : 'assistant',
          'content': t.isUser ? content(t.images, t.content) : t.content,
        },
      {'role': 'user', 'content': content(images, userPrompt)},
    ];
  }

  // ─── 流式 ───

  /// 流式对话：与 [send] 同一套请求形状（history/images/thinking），文本增量
  /// 经 [onDelta] 回调，完整文本作为返回值。
  ///
  /// 与 [send] 的差异：不支持 [Map] schema（结构化输出与流式互斥）；瞬时错误
  /// **不重试**——流断在中途无法安全重放，重试策略交给调用方。SSE 事件形状
  /// 与 TranslationService 的流式实现对齐（后续收敛的基准在这里）。
  static Future<String> sendStream({
    required AgentApiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    AgentModelParams modelParams = const AgentModelParams(),
    required String systemPrompt,
    required String userPrompt,
    List<AgentChatTurn> history = const [],
    List<AgentChatImage> images = const [],
    double? temperature,
    int anthropicMaxTokens = 4096,

    /// 语义同 [send] 的同名参数（仅 Anthropic 生效）。
    bool anthropicCachePrefix = false,

    /// 语义同 [send] 的同名参数。
    bool webSearch = false,

    /// 语义同 [send] 的同名参数。
    bool urlContext = false,
    void Function(ChatActivity)? onActivity,
    bool includeReasoning = false,
    Duration receiveTimeout = const Duration(minutes: 5),
    CancelToken? cancelToken,
    required void Function(String delta) onDelta,
  }) async {
    final activities = AgentActivityTracker(
      onActivity,
      requestReasoning: includeReasoning && onActivity != null,
    );
    // xAI（Grok）按 host 升格走 OpenAI Responses 同形线路
    provider = provider.wireProtocol(baseUrl);
    final url = provider.chatUrl(baseUrl);
    final dio = AgentHttp.instance.dio(receiveTimeout: receiveTimeout);
    final useWebSearch =
        webSearch &&
        BuiltInToolsHelper.isSupported(
          provider: provider,
          modelId: modelId,
          tool: BuiltInToolNames.search,
          baseUrl: baseUrl,
        );
    final useUrlContext =
        urlContext &&
        BuiltInToolsHelper.isSupported(
          provider: provider,
          modelId: modelId,
          tool: BuiltInToolNames.urlContext,
          baseUrl: baseUrl,
        );

    final stream = switch (provider) {
      AgentApiProvider.openai => _streamOpenAI(
        dio,
        url,
        apiKey,
        modelId,
        modelParams,
        systemPrompt,
        userPrompt,
        history,
        images,
        temperature,
        useWebSearch,
        cancelToken,
        activities,
      ),
      AgentApiProvider.anthropic => _streamAnthropic(
        dio,
        url,
        apiKey,
        modelId,
        modelParams,
        systemPrompt,
        userPrompt,
        history,
        images,
        temperature,
        anthropicMaxTokens,
        anthropicCachePrefix,
        useWebSearch,
        useUrlContext,
        cancelToken,
        activities,
      ),
      AgentApiProvider.gemini => _streamGemini(
        dio,
        url,
        apiKey,
        modelId,
        modelParams,
        systemPrompt,
        userPrompt,
        history,
        images,
        temperature,
        useWebSearch,
        useUrlContext,
        cancelToken,
        activities,
      ),
      AgentApiProvider.openAICompatible => _streamOpenAICompatible(
        dio,
        url,
        apiKey,
        modelId,
        modelParams,
        systemPrompt,
        userPrompt,
        history,
        images,
        temperature,
        _effectiveCompatVendor(webSearch, baseUrl),
        cancelToken,
        activities,
      ),
    };

    final buffer = StringBuffer();
    try {
      await for (final delta in stream) {
        buffer.write(delta);
        onDelta(delta);
      }
      activities.finish();
    } on DioException catch (e) {
      activities.finish(
        e.type == DioExceptionType.cancel
            ? ChatActivityStatus.cancelled
            : ChatActivityStatus.failed,
      );
      if (e.type == DioExceptionType.cancel) rethrow;
      throw AgentChatException(await _readableStreamMessage(e));
    } catch (_) {
      activities.finish(ChatActivityStatus.failed);
      rethrow;
    }
    return buffer.toString();
  }

  /// OpenAI Responses API 流式：`response.output_text.delta`，
  /// 兼容 Chat Completions fallback（`choices[].delta.content`）。
  static Stream<String> _streamOpenAI(
    Dio dio,
    String url,
    String apiKey,
    String modelId,
    AgentModelParams modelParams,
    String systemPrompt,
    String userPrompt,
    List<AgentChatTurn> history,
    List<AgentChatImage> images,
    double? temperature,
    bool webSearch,
    CancelToken? cancelToken,
    AgentActivityTracker activities,
  ) async* {
    final resp = await dio.post<ResponseBody>(
      url,
      data: _openAIBody(
        showReasoning: activities.requestReasoning,
        modelId: modelId,
        modelParams: modelParams,
        systemPrompt: systemPrompt,
        history: history,
        images: images,
        userPrompt: userPrompt,
        temperature: temperature,
        webSearch: webSearch,
        stream: true,
      ),
      options: Options(
        headers: _bearerHeaders(apiKey, stream: true),
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
    );

    final body = resp.data;
    if (body == null) {
      throw const AgentChatException('Empty stream response');
    }
    await for (final event in _sseEventStream(body.stream)) {
      final data = _extractSseData(event);
      if (data == null || data == '[DONE]') continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        activities.record(AgentApiProvider.openai, json);
        _checkStreamError(json);
        if (json['type'] == 'response.output_text.delta') {
          final d = json['delta'];
          if (d is String && d.isNotEmpty) yield d;
          continue;
        }
        final choices = json['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final delta = (choices[0] as Map<String, dynamic>)['delta'];
          if (delta is Map<String, dynamic>) {
            final content = delta['content'];
            if (content is String && content.isNotEmpty) yield content;
          }
        }
      } on AgentChatException {
        rethrow;
      } catch (_) {
        // 单 event 解析失败 → 跳过，其他 event 继续
      }
    }
  }

  /// Anthropic Messages 流式：`content_block_delta.delta.text`
  /// （`thinking_delta` 自然被 type 过滤掉，思考过程不进正文）。
  static Stream<String> _streamAnthropic(
    Dio dio,
    String url,
    String apiKey,
    String modelId,
    AgentModelParams modelParams,
    String systemPrompt,
    String userPrompt,
    List<AgentChatTurn> history,
    List<AgentChatImage> images,
    double? temperature,
    int anthropicMaxTokens,
    bool anthropicCachePrefix,
    bool webSearch,
    bool urlContext,
    CancelToken? cancelToken,
    AgentActivityTracker activities,
  ) async* {
    final resp = await dio.post<ResponseBody>(
      url,
      data: _anthropicBody(
        modelId: modelId,
        modelParams: modelParams,
        systemPrompt: systemPrompt,
        history: history,
        images: images,
        userPrompt: userPrompt,
        temperature: temperature,
        maxTokensBase: anthropicMaxTokens,
        cachePrefix: anthropicCachePrefix,
        webSearch: webSearch,
        urlContext: urlContext,
        stream: true,
      ),
      options: Options(
        headers: _anthropicHeaders(apiKey, stream: true),
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
    );

    final body = resp.data;
    if (body == null) {
      throw const AgentChatException('Empty stream response');
    }
    await for (final event in _sseEventStream(body.stream)) {
      final data = _extractSseData(event);
      if (data == null) continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        activities.record(AgentApiProvider.anthropic, json);
        _checkStreamError(json);
        if (json['type'] == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          if (delta?['type'] == 'text_delta') {
            final text = delta!['text'];
            if (text is String && text.isNotEmpty) yield text;
          }
        }
      } on AgentChatException {
        rethrow;
      } catch (_) {}
    }
  }

  /// Gemini 流式：`:streamGenerateContent?alt=sse`，过滤 thought parts。
  static Stream<String> _streamGemini(
    Dio dio,
    String url,
    String apiKey,
    String modelId,
    AgentModelParams modelParams,
    String systemPrompt,
    String userPrompt,
    List<AgentChatTurn> history,
    List<AgentChatImage> images,
    double? temperature,
    bool webSearch,
    bool urlContext,
    CancelToken? cancelToken,
    AgentActivityTracker activities,
  ) async* {
    final resp = await dio.post<ResponseBody>(
      '$url/models/$modelId:streamGenerateContent',
      queryParameters: {'alt': 'sse'},
      data: _geminiBody(
        showReasoning: activities.requestReasoning,
        modelId: modelId,
        modelParams: modelParams,
        systemPrompt: systemPrompt,
        history: history,
        images: images,
        userPrompt: userPrompt,
        temperature: temperature,
        webSearch: webSearch,
        urlContext: urlContext,
      ),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'x-goog-api-key': apiKey,
        },
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
    );

    final body = resp.data;
    if (body == null) {
      throw const AgentChatException('Empty stream response');
    }
    await for (final event in _sseEventStream(body.stream)) {
      final data = _extractSseData(event);
      if (data == null) continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        activities.record(AgentApiProvider.gemini, json);
        _checkStreamError(json);
        final candidates = json['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) continue;
        final content = (candidates[0] as Map<String, dynamic>)['content'];
        if (content is! Map<String, dynamic>) continue;
        final parts = content['parts'] as List<dynamic>?;
        if (parts == null) continue;
        for (final part in parts) {
          if (part is Map<String, dynamic> && part['thought'] != true) {
            final text = part['text'];
            if (text is String && text.isNotEmpty) yield text;
          }
        }
      } on AgentChatException {
        rethrow;
      } catch (_) {}
    }
  }

  /// OpenAI Compatible 流式：标准 `choices[].delta.content`，
  /// 过滤 `reasoning_content`（DeepSeek 思考流不进正文）。
  ///
  /// [searchVendor] 为 kimi / external 时处理搜索工具回环：流中按 index
  /// 归并 tool_calls 增量，流结束后回填结果（Kimi 原样回传 arguments /
  /// 外部搜索客户端真实执行）并重新发起流式请求（上限 3 轮，与非流式一致）。
  static Stream<String> _streamOpenAICompatible(
    Dio dio,
    String url,
    String apiKey,
    String modelId,
    AgentModelParams modelParams,
    String systemPrompt,
    String userPrompt,
    List<AgentChatTurn> history,
    List<AgentChatImage> images,
    double? temperature,
    CompatSearchVendor searchVendor,
    CancelToken? cancelToken,
    AgentActivityTracker activities,
  ) async* {
    var messages = _compatMessages(systemPrompt, history, images, userPrompt);
    final loopTool = _searchLoopToolName(searchVendor);
    final hasImages =
        images.isNotEmpty || history.any((t) => t.images.isNotEmpty);
    for (var round = 0; round <= 3; round++) {
      final resp = await dio.post<ResponseBody>(
        url,
        data: _compatBody(
          modelId: modelId,
          modelParams: modelParams,
          messages: messages,
          temperature: temperature,
          hasImages: hasImages,
          vendor: searchVendor,
          stream: true,
        ),
        options: Options(
          headers: _bearerHeaders(apiKey, stream: true),
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );

      final body = resp.data;
      if (body == null) {
        throw const AgentChatException('Empty stream response');
      }
      // tool_calls 增量按 index 归并：id/name 在首个分片，arguments 逐段拼接
      final toolCallAcc = <int, Map<String, dynamic>>{};
      var finishedByToolCalls = false;
      await for (final event in _sseEventStream(body.stream)) {
        final data = _extractSseData(event);
        if (data == null || data == '[DONE]') continue;
        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
          activities.record(AgentApiProvider.openAICompatible, json);
          _checkStreamError(json);
        } on AgentChatException {
          rethrow;
        } catch (_) {
          continue;
        }
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final choice = choices[0] as Map<String, dynamic>;
        if (choice['finish_reason'] == 'insufficient_system_resource') {
          throw const AgentChatException('服务器资源不足，请稍后重试');
        }
        if (choice['finish_reason'] == 'tool_calls') {
          finishedByToolCalls = true;
        }
        final delta = choice['delta'];
        if (delta is! Map<String, dynamic>) continue;
        final content = delta['content'];
        if (content is String && content.isNotEmpty) yield content;
        final deltaCalls = delta['tool_calls'];
        if (deltaCalls is List) {
          for (final c in deltaCalls) {
            if (c is! Map<String, dynamic>) continue;
            final idx = (c['index'] as num?)?.toInt() ?? 0;
            final acc = toolCallAcc.putIfAbsent(
              idx,
              () => {
                'id': '',
                'type': 'function',
                'function': {'name': '', 'arguments': ''},
              },
            );
            final id = c['id'];
            if (id is String && id.isNotEmpty) acc['id'] = id;
            final fn = c['function'];
            if (fn is Map<String, dynamic>) {
              final accFn = acc['function'] as Map<String, dynamic>;
              final name = fn['name'];
              if (name is String && name.isNotEmpty) accFn['name'] = name;
              final args = fn['arguments'];
              if (args is String && args.isNotEmpty) {
                accFn['arguments'] = '${accFn['arguments']}$args';
              }
            }
          }
        }
      }

      final calls = [
        for (final k in toolCallAcc.keys.toList()..sort()) toolCallAcc[k]!,
      ];
      final isSearchLoop =
          loopTool != null &&
          finishedByToolCalls &&
          calls.isNotEmpty &&
          calls.every(
            (c) => (c['function'] as Map<String, dynamic>)['name'] == loopTool,
          );
      if (!isSearchLoop) return;
      messages = [
        ...messages,
        {'role': 'assistant', 'content': '', 'tool_calls': calls},
        ...await _searchToolResults(
          searchVendor,
          calls,
          cancelToken,
          activities,
        ),
      ];
    }
  }

  static void _checkStreamError(Map<String, dynamic> data) {
    final error = data['error'] ?? (data['response'] as Map?)?['error'];
    if (error != null) {
      throw AgentChatException(
        error is Map
            ? '${error['message'] ?? error['type'] ?? 'Stream error'}'
            : '$error',
      );
    }
  }

  // ── SSE 通用解析（与 TranslationService 同构，待收敛） ──

  /// 把字节流切成 SSE 事件（以 `\n\n` 或 `\r\n\r\n` 分隔）。
  /// UTF-8 解码器跨 chunk 保留半个字符，避免中文在网络分片边界损坏。
  static Stream<String> _sseEventStream(Stream<List<int>> source) async* {
    String buffer = '';
    const decoder = Utf8Decoder(allowMalformed: true);
    await for (final chunk in decoder.bind(source)) {
      buffer += chunk;
      while (true) {
        int delim = buffer.indexOf('\n\n');
        int delimLen = 2;
        if (delim < 0) {
          final alt = buffer.indexOf('\r\n\r\n');
          if (alt < 0) break;
          delim = alt;
          delimLen = 4;
        }
        final event = buffer.substring(0, delim);
        buffer = buffer.substring(delim + delimLen);
        if (event.isNotEmpty) yield event;
      }
    }
    if (buffer.trim().isNotEmpty) yield buffer;
  }

  /// 从单个 SSE event 抽取 `data:` 负载，多行按 SSE 规范用 `\n` 拼接。
  static String? _extractSseData(String event) {
    final dataLines = <String>[];
    for (final line in event.split(RegExp(r'\r?\n'))) {
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) return null;
    return dataLines.join('\n');
  }

  /// 流式请求的错误响应体是 [ResponseBody]（字节流），需 drain 后才能提取
  /// 服务商错误文案——[readableMessage] 只认已解析的 Map。
  static Future<String> _readableStreamMessage(DioException e) async {
    final body = e.response?.data;
    if (body is! ResponseBody) return readableMessage(e);
    final fallback = 'HTTP ${e.response?.statusCode ?? "?"}';
    try {
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(
        const Utf8Decoder(allowMalformed: true).convert(bytes),
      );
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error'];
        if (err is Map) return err['message'] as String? ?? fallback;
        if (err is String) return err;
      }
    } catch (_) {}
    return fallback;
  }

  /// 从 DioException 提取服务商可读错误文案。
  static String readableMessage(DioException e) {
    final body = e.response?.data;
    String msg = 'HTTP ${e.response?.statusCode ?? "?"}';
    if (body is Map<String, dynamic>) {
      final err = body['error'];
      if (err is Map) msg = err['message'] as String? ?? msg;
      if (err is String) msg = err;
    }
    return msg;
  }

  // ── 响应提取（兼容 thinking 模型）────────────────────────
  //
  // 统一取「最后一个非思考 text」：thinking 模型的思考块在前、正文在后，
  // 取首块会拿到空串或思考内容（此前翻译/排版修复两份副本在此已漂移）。

  static String _extractOpenAI(Map<String, dynamic> data) {
    // Responses API: output[].content[].text
    final output = data['output'] as List<dynamic>?;
    if (output != null) {
      for (final item in output) {
        if (item is Map<String, dynamic> && item['type'] == 'message') {
          final content = item['content'] as List<dynamic>?;
          if (content != null) {
            for (final c in content) {
              if (c is Map<String, dynamic> && c['type'] == 'output_text') {
                return (c['text'] as String? ?? '').trim();
              }
            }
          }
        }
      }
    }
    // Chat Completions fallback
    final choices = data['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final msg = (choices[0] as Map<String, dynamic>)['message'];
      if (msg is Map<String, dynamic>) {
        return (msg['content'] as String? ?? '').trim();
      }
    }
    throw Exception('无法从 OpenAI 响应中提取结果');
  }

  static String _extractAnthropic(Map<String, dynamic> data) {
    final content = data['content'] as List<dynamic>?;
    if (content != null) {
      for (final block in content.reversed) {
        if (block is Map<String, dynamic> && block['type'] == 'text') {
          return (block['text'] as String? ?? '').trim();
        }
      }
    }
    throw Exception('无法从 Anthropic 响应中提取结果');
  }

  static String _extractGemini(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates != null && candidates.isNotEmpty) {
      final parts =
          ((candidates[0] as Map<String, dynamic>)['content']
                  as Map<String, dynamic>?)?['parts']
              as List<dynamic>?;
      if (parts != null) {
        for (final part in parts.reversed) {
          if (part is Map<String, dynamic> &&
              part['thought'] != true &&
              part.containsKey('text')) {
            return (part['text'] as String? ?? '').trim();
          }
        }
      }
    }
    throw Exception('无法从 Gemini 响应中提取结果');
  }

  /// Chat Completions 标准格式，兼容 DeepSeek `insufficient_system_resource`
  static String _extractOpenAICompatible(Map<String, dynamic> data) {
    final choices = data['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final choice = choices[0] as Map<String, dynamic>;
      if (choice['finish_reason'] == 'insufficient_system_resource') {
        throw Exception('服务器资源不足，请稍后重试');
      }
      final msg = choice['message'];
      if (msg is Map<String, dynamic>) {
        return (msg['content'] as String? ?? '').trim();
      }
    }
    throw Exception('无法从 API 响应中提取结果');
  }
}
