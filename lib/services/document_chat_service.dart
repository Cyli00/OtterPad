import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../data/models/chat/chat_session.dart';
import '../providers/api_provider.dart';
import '../utils/doc_paths.dart';
import 'agent_chat_service.dart';
import 'builtin_tools.dart';
import 'figure_extract_service.dart';
import 'prompt_store.dart';
import 'prompts.dart';
import 'url_context_service.dart';

/// 问 AI 的回答角色：全局专家 / 快速模型（两者可属于不同 provider 实例）。
enum ChatModelRole { expert, fast }

/// 问 AI 服务——会话文件存取 + 文献上下文组装 + 请求发送的唯一出口。
///
/// - 会话持久化在 `library/{documentId}/chats/{sessionId}.json`，与文献目录
///   同生共死（同 translations.json 范式），不走 Hive；
/// - 上下文 = extract.md 全文（进 system prompt 的 `{{document}}`）+ figures
///   图片（仅当调用方判定模型支持图片输入，判定走 AgentModelCapability 接缝）；
/// - 角色解析按全局专家/快速角色各自 `loadInstance`——两角色可能属于不同
///   实例，禁止用 effectiveAgentApiProvider 的单一文本角色视图代替。
class DocumentChatService {
  DocumentChatService._();

  // ─── 会话存取 ───

  /// 列出文献的全部会话，按 updatedAt 降序。损坏的 JSON 文件静默跳过。
  static Future<List<ChatSession>> listSessions(String documentId) async {
    final dir = Directory(DocPaths.chatsDir(documentId));
    if (!await dir.exists()) return [];
    final sessions = <ChatSession>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        sessions.add(
          ChatSession.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>,
          ),
        );
      } catch (_) {}
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  static Future<void> saveSession(
    String documentId,
    ChatSession session,
  ) async {
    final file = File(DocPaths.chatSession(documentId, session.id));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  static Future<void> deleteSession(String documentId, String sessionId) async {
    final file = File(DocPaths.chatSession(documentId, sessionId));
    if (await file.exists()) await file.delete();
  }

  // ─── 角色解析 ───

  /// 角色所属实例的已解析视图；角色未配置（或实例已删）返回 null。
  static AgentApiState? resolveRoleState(ChatModelRole role) {
    final r = role == ChatModelRole.expert
        ? AgentApiNotifier.globalDefaultRole
        : AgentApiNotifier.globalFastRole;
    if (r.id == null || r.modelId == null) return null;
    return AgentApiNotifier.loadInstance(r.id!);
  }

  static String? modelIdFor(AgentApiState state, ChatModelRole role) =>
      role == ChatModelRole.expert ? state.defaultModelId : state.fastModelId;

  // ─── 提问 ───

  /// 发送一轮提问，返回回答文本。[history] 是当前会话中**此轮之前**的消息；
  /// [supportsImages] 由调用方用 AgentModelCapability 接缝判定（provider 层
  /// 持有实例，能读到用户在设置里手动覆盖的能力标记）。
  ///
  /// [thinkingOverride] 非空时覆盖模型参数里的思考档位（会话级调节）；
  /// [onDelta] 非空时走流式（增量回调 + 完整文本返回值），空则非流式。
  ///
  /// [urlContext] 是当轮经客户端回退抓取的链接内容（见
  /// [buildUrlContextFallback]），与提问合并组装；模型原生支持 URL 工具时
  /// 调用方传 null，由本方法自动注入 server tool。
  ///
  /// 失败抛 [Exception]（含「AI 设置」类配置错误，可被
  /// AiSettingsPrompt.showForConfigError 识别）。
  static Future<String> ask({
    required String documentId,
    required ChatModelRole role,
    required List<ChatMessage> history,
    required String question,
    required bool supportsImages,
    String? quotedText,
    String? urlContext,
    ThinkingLevel? thinkingOverride,
    bool webSearch = false,
    void Function(String delta)? onDelta,
    CancelToken? cancelToken,
  }) async {
    final state = resolveRoleState(role);
    final modelId = state == null ? null : modelIdFor(state, role);
    if (state == null || modelId == null || modelId.isEmpty) {
      throw Exception(
        role == ChatModelRole.expert
            ? '请先在「AI 设置」中选择专家模型'
            : '请先在「AI 设置」中选择快速模型',
      );
    }
    if (state.apiKey.trim().isEmpty) {
      throw Exception('请先在「AI 设置」中填写 API Key');
    }

    final mdFile = File(DocPaths.md(documentId));
    if (!await mdFile.exists()) {
      throw Exception('该文献还没有提取结果，请先提取全文');
    }
    final document = await mdFile.readAsString();
    final systemPrompt = renderPrompt(PromptStore.resolve(Prompts.chatSystem), {
      'document': document,
    });

    final figureImages = supportsImages
        ? await _loadFigureImages(documentId)
        : const <AgentChatImage>[];

    var params = state.paramsFor(modelId);
    if (thinkingOverride != null) {
      params = params.copyWith(thinkingLevel: thinkingOverride);
    }

    // figures 固定挂在会话**第一条 user 消息**上并逐轮原样重放：
    // - 图片进入稳定前缀，可被各家 prompt cache 命中（否则每轮全价重付）；
    // - 多轮中模型始终看得到图（历史只重放文本时第二轮起就「失明」了）。
    final firstUserIdx = history.indexWhere((m) => m.isUser);
    final turns = [
      for (var i = 0; i < history.length; i++)
        AgentChatTurn(
          isUser: history[i].isUser,
          content: history[i].isUser
              ? composeUserText(
                  history[i].content,
                  history[i].quotedText,
                  history[i].urlContext,
                )
              : history[i].content,
          images: i == firstUserIdx ? figureImages : const [],
        ),
    ];
    final currentImages = firstUserIdx < 0
        ? figureImages
        : const <AgentChatImage>[];
    final userPrompt = composeUserText(question, quotedText, urlContext);

    // 原生 URL 工具：会话中任一 user 文本含链接即注入（追问轮模型可按需
    // 重新抓取——server tool 的抓取结果不在我们持久化的历史里）。
    final nativeUrlTool =
        BuiltInToolsHelper.isSupported(
          provider: state.provider,
          modelId: modelId,
          tool: BuiltInToolNames.urlContext,
          baseUrl: state.effectiveBaseUrl,
        ) &&
        (UrlContextService.containsUrl(question) ||
            history.any(
              (m) => m.isUser && UrlContextService.containsUrl(m.content),
            ));

    if (onDelta != null) {
      return AgentChatService.sendStream(
        provider: state.provider,
        baseUrl: state.effectiveBaseUrl,
        apiKey: state.apiKey,
        modelId: modelId,
        modelParams: params,
        systemPrompt: systemPrompt,
        history: turns,
        userPrompt: userPrompt,
        images: currentImages,
        anthropicMaxTokens: 8192,
        anthropicCachePrefix: true,
        webSearch: webSearch,
        urlContext: nativeUrlTool,
        cancelToken: cancelToken,
        onDelta: onDelta,
      );
    }
    return AgentChatService.send(
      provider: state.provider,
      baseUrl: state.effectiveBaseUrl,
      apiKey: state.apiKey,
      modelId: modelId,
      modelParams: params,
      systemPrompt: systemPrompt,
      history: turns,
      userPrompt: userPrompt,
      images: currentImages,
      anthropicMaxTokens: 8192,
      anthropicCachePrefix: true,
      webSearch: webSearch,
      urlContext: nativeUrlTool,
      cancelToken: cancelToken,
    );
  }

  /// 客户端 URL 抓取回退：仅当提问含链接、且角色模型**不**支持原生 URL
  /// 工具时抓取，返回供 [ask] 注入并随消息持久化的上下文块；其余情况返回
  /// null。角色未配置时也返回 null——配置错误交给 [ask] 统一抛出。
  static Future<String?> buildUrlContextFallback({
    required ChatModelRole role,
    required String question,
    CancelToken? cancelToken,
  }) async {
    if (!UrlContextService.containsUrl(question)) return null;
    final state = resolveRoleState(role);
    final modelId = state == null ? null : modelIdFor(state, role);
    if (state == null || modelId == null || modelId.isEmpty) return null;
    if (BuiltInToolsHelper.isSupported(
      provider: state.provider,
      modelId: modelId,
      tool: BuiltInToolNames.urlContext,
      baseUrl: state.effectiveBaseUrl,
    )) {
      return null;
    }
    return UrlContextService.instance.buildContext(
      question,
      cancelToken: cancelToken,
    );
  }

  /// 用快速模型（强制关思考，保证「迅速」）给首条提问生成会话短标题。
  /// 快速角色未配置或请求失败返回 null——调用方保留截断回退标题，
  /// 标题生成永远不打断主对话流程。
  static Future<String?> summarizeTitle({
    required String question,
    String? quotedText,
  }) async {
    final state = resolveRoleState(ChatModelRole.fast);
    final modelId = state == null
        ? null
        : modelIdFor(state, ChatModelRole.fast);
    if (state == null || modelId == null || modelId.isEmpty) return null;
    if (state.apiKey.trim().isEmpty) return null;

    var input = composeUserText(question, quotedText);
    if (input.length > 1000) input = input.substring(0, 1000);
    try {
      final title = await AgentChatService.send(
        provider: state.provider,
        baseUrl: state.effectiveBaseUrl,
        apiKey: state.apiKey,
        modelId: modelId,
        modelParams: state
            .paramsFor(modelId)
            .copyWith(thinkingLevel: ThinkingLevel.off),
        systemPrompt: Prompts.chatTitleSystem,
        userPrompt: input,
        receiveTimeout: const Duration(seconds: 30),
      );
      final t = title.trim().split('\n').first.trim();
      if (t.isEmpty) return null;
      return t.length > 30 ? '${t.substring(0, 30)}…' : t;
    } catch (_) {
      return null;
    }
  }

  /// 划词引用以 Markdown blockquote、客户端抓取的链接内容以独立块前置到
  /// 提问文本——当轮与历史重放共用同一组装，保证模型在多轮中看到一致的
  /// 上下文。
  static String composeUserText(
    String question,
    String? quotedText, [
    String? urlContext,
  ]) {
    final quote = quotedText?.trim();
    return [
      if (urlContext != null && urlContext.isNotEmpty) urlContext,
      if (quote != null && quote.isNotEmpty)
        quote.split('\n').map((l) => '> $l').join('\n'),
      question,
    ].join('\n\n');
  }

  /// figures 全量读为 base64，caption 作为图片标签（模型据此把图片与正文
  /// 中的 Figure 引用对上）。manifest 缺失/为空返回空列表。
  static Future<List<AgentChatImage>> _loadFigureImages(
    String documentId,
  ) async {
    final manifest = await FigureExtractService.loadManifest(documentId);
    if (manifest == null || manifest.isEmpty) return const [];
    final images = <AgentChatImage>[];
    for (final entry in manifest) {
      final path = p.isAbsolute(entry.imagePath)
          ? entry.imagePath
          : p.join(
              DocPaths.figuresDir(documentId),
              p.basename(entry.imagePath),
            );
      final file = File(path);
      if (!await file.exists()) continue;
      images.add(
        AgentChatImage(
          base64Png: base64Encode(await file.readAsBytes()),
          label: entry.captionText.isNotEmpty
              ? entry.captionText
              : p.basename(path),
        ),
      );
    }
    return images;
  }
}
