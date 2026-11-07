import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/app_logger.dart';
import '../core/l10n.dart';
import '../core/otter_error_text.dart';
import '../core/rust_ai.dart';
import '../core/rust_backend.dart';
import '../core/storage/json_data.dart';
import '../data/models/chat/chat_activity.dart';
import '../data/models/chat/chat_session.dart';
import '../router/app_router.dart';
import '../services/prompts.dart';
import '../services/web_search_service.dart';
import '../src/rust/ai/search.dart';
import '../src/rust/ai/types.dart' as rust;
import '../src/rust/api.dart' show cancelTask;
import '../src/rust/api/ai.dart';
import '../src/rust/api/chat.dart';
import '../src/rust/error.dart';
import '../src/rust/prompts.dart';
import '../services/model_capability_store.dart';
import 'agent_api_provider.dart';

enum ChatModelRole { expert, fast }

typedef ChatModelSelection = ({String id, String modelId});

/// 角色对应的服务商实例（专家、快速角色可能属于不同实例）。
AgentApiState? resolveRoleState(ChatModelRole role) {
  final r = role == ChatModelRole.expert
      ? AgentApiNotifier.globalDefaultRole
      : AgentApiNotifier.globalFastRole;
  if (r.id == null || r.modelId == null) return null;
  return AgentApiNotifier.loadInstance(r.id!);
}

String? modelIdFor(AgentApiState state, ChatModelRole role) =>
    role == ChatModelRole.expert ? state.defaultModelId : state.fastModelId;

AgentApiState? resolveModelState(
  ChatModelRole role,
  ChatModelSelection? model,
) => model == null
    ? resolveRoleState(role)
    : AgentApiNotifier.loadInstance(model.id);

bool isFastModel(ChatModelRole role, ChatModelSelection? model) {
  if (model == null) return role == ChatModelRole.fast;
  final fast = AgentApiNotifier.globalFastRole;
  return fast.id == model.id && fast.modelId == model.modelId;
}

/// 每文献问 AI 状态。[activeSessionId] 为 null 表示新会话草稿，首次发送时才创建。
class DocumentChatState {
  final bool loaded;

  /// 按 updatedAt 降序。
  final List<ChatSession> sessions;
  final String? activeSessionId;
  final bool sending;

  /// 流式回答的实时累积文本；未在流式回答时为 null。
  final String? streamingText;
  final List<ChatActivity> activities;

  /// 最近一次发送失败的可读文案；下一次发送时清空。
  final String? error;

  const DocumentChatState({
    this.loaded = false,
    this.sessions = const [],
    this.activeSessionId,
    this.sending = false,
    this.streamingText,
    this.activities = const [],
    this.error,
  });

  ChatSession? get activeSession {
    if (activeSessionId == null) return null;
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return null;
  }

  DocumentChatState copyWith({
    bool? loaded,
    List<ChatSession>? sessions,
    Object? activeSessionId = _sentinel,
    bool? sending,
    Object? streamingText = _sentinel,
    List<ChatActivity>? activities,
    Object? error = _sentinel,
  }) => DocumentChatState(
    loaded: loaded ?? this.loaded,
    sessions: sessions ?? this.sessions,
    activeSessionId: identical(activeSessionId, _sentinel)
        ? this.activeSessionId
        : activeSessionId as String?,
    sending: sending ?? this.sending,
    activities: activities ?? this.activities,
    streamingText: identical(streamingText, _sentinel)
        ? this.streamingText
        : streamingText as String?,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );
}

const _sentinel = Object();

/// 问 AI：会话存取与提问都在 Rust；这里持有界面状态，并补记过程活动、
/// 中断时已流出的回答与会话标题。
class DocumentChatNotifier extends StateNotifier<DocumentChatState> {
  final Ref ref;
  final String documentId;
  String? _task;
  bool _cancelled = false;

  /// Rust 会话原文，保留修订号与未知字段，修改时在其上更新。
  final _conversations = <String, Conversation>{};

  DocumentChatNotifier(this.ref, this.documentId)
    : super(const DocumentChatState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final list = await RustBackend.instance.conversations(
        document: documentId,
      );
      if (!mounted) return;
      for (final c in list.sessions) {
        _conversations[c.id] = c;
      }
      state = state.copyWith(loaded: true, sessions: _sorted());
    } catch (e, st) {
      _reportError(e, st);
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  List<ChatSession> _sorted() =>
      [for (final c in _conversations.values) _session(c)]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void _reportError(Object error, StackTrace stackTrace) {
    log.w('[DocumentChat] $documentId', error: error, stackTrace: stackTrace);
    if (!mounted) return;
    final ctx = rootNavigatorKey.currentContext;
    final l10n = ctx == null ? null : AppLocalizations.of(ctx);
    state = state.copyWith(
      sending: false,
      streamingText: null,
      error: l10n == null ? '$error' : errorText(l10n, error),
    );
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  void startNewSession() =>
      state = state.copyWith(activeSessionId: null, error: null);

  void switchSession(String sessionId) =>
      state = state.copyWith(activeSessionId: sessionId, error: null);

  Future<void> deleteSession(String sessionId) async {
    await RustBackend.instance.deleteConversation(
      document: documentId,
      id: sessionId,
    );
    _conversations.remove(sessionId);
    if (!mounted) return;
    state = state.copyWith(
      sessions: _sorted(),
      activeSessionId: state.activeSessionId == sessionId
          ? null
          : state.activeSessionId,
    );
  }

  Future<Conversation> _save(Conversation c) async {
    final saved = await RustBackend.instance.saveConversation(
      document: documentId,
      session: c,
    );
    _conversations[saved.id] = saved;
    return saved;
  }

  /// 发送一轮提问。用户消息由 Rust 先落盘；中断时已流出的部分作为回答保留。
  Future<void> send({
    required String text,
    required ChatModelRole role,
    ChatModelSelection? model,
    String? quotedText,
    String? figureImagePath,
    Map<String, dynamic>? quoteAnchor,
    ThinkingLevel? thinkingOverride,
    bool webSearch = false,
    bool streaming = true,
  }) async {
    if (state.sending) return;
    final question = text.trim();
    if (question.isEmpty) return;
    final selection = _selection(role, model, thinkingOverride);
    if (selection == null) {
      _reportError(
        const OtterError(code: ErrorCode.invalidArgument, detail: 'model'),
        StackTrace.current,
      );
      return;
    }

    _cancelled = false;
    state = state.copyWith(sending: true, error: null, activities: const []);
    var conversation = _conversations[state.activeSessionId];
    final firstTurn = conversation == null || conversation.messages.isEmpty;
    try {
      conversation ??= await RustBackend.instance.createConversation(
        document: documentId,
        title: _titleFrom(question),
      );
      _conversations[conversation.id] = conversation;
      final message = ConversationMessage(
        id: ChatMessage.newId(),
        role: rust.Role.user,
        content: question,
        quotedText: (quotedText?.trim().isEmpty ?? true) ? null : quotedText,
        quoteAnchor: quoteAnchor == null ? null : toJsonData(quoteAnchor),
        figureImagePath: figureImagePath,
        activities: const [],
        modelId: null,
        urlContext: null,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        extra: const [],
      );
      _conversations[conversation.id] = _withMessages(conversation, [
        ...conversation.messages,
        message,
      ]);
      if (!mounted) return;
      state = state.copyWith(
        sessions: _sorted(),
        activeSessionId: conversation.id,
      );
      if (firstTurn) {
        unawaited(_generateTitle(conversation.id, question, quotedText));
      }
      await _ask(
        conversation.id,
        message,
        selection,
        role,
        model,
        webSearch,
        streaming,
      );
    } catch (e, st) {
      if (!mounted) return;
      if (isCancellation(e)) {
        state = state.copyWith(sending: false, streamingText: null);
        return;
      }
      _reportError(e, st);
    }
  }

  Future<void> _ask(
    String sessionId,
    ConversationMessage message,
    ModelSelection selection,
    ChatModelRole role,
    ChatModelSelection? model,
    bool webSearch,
    bool streaming,
  ) async {
    final text = StringBuffer();
    final activities = <String, ChatActivity>{};
    Timer? flush;
    void schedule() {
      flush ??= Timer(const Duration(milliseconds: 80), () {
        flush = null;
        if (!mounted) return;
        state = state.copyWith(
          streamingText: text.toString(),
          activities: activities.values.toList(),
        );
      });
    }

    void finishReasoning() {
      final reasoning = activities['reasoning'];
      if (reasoning?.status == ChatActivityStatus.running) {
        activities['reasoning'] = reasoning!.update(
          status: ChatActivityStatus.completed,
        );
      }
    }

    final task = rustTaskId('chat');
    _task = task;
    final systemPrompt = await RustBackend.instance.prompt(
      kind: PromptKind.chatSystem,
    );
    final searchProvider = webSearch && WebSearchService.isConfigured
        ? switch (WebSearchService.provider) {
            WebSearchProvider.tavily => SearchProvider.tavily,
            WebSearchProvider.exa => SearchProvider.exa,
            WebSearchProvider.brave => SearchProvider.brave,
          }
        : null;
    try {
      await for (final event in RustBackend.instance.askDocument(
        options: AskDocument(
          documentId: documentId,
          sessionId: sessionId,
          message: message,
          model: selection,
          systemPrompt: systemPrompt.text,
          fast: isFastModel(role, model),
          webSearch: webSearch,
          stream: streaming,
          searchProvider: searchProvider,
        ),
        taskId: task,
      )) {
        switch (event) {
          case ConversationEvent_Delta(
            event: rust.ChatEvent_TextDelta(text: final t),
          ):
            finishReasoning();
            text.write(t);
            schedule();
          case ConversationEvent_Delta(
            event: rust.ChatEvent_ReasoningDelta(text: final t),
          ):
            final current =
                activities['reasoning'] ??
                ChatActivity(
                  id: 'reasoning',
                  kind: ChatActivityKind.reasoning,
                  startedAt: DateTime.now(),
                );
            activities['reasoning'] = current.update(text: current.text + t);
            schedule();
          case ConversationEvent_Delta(event: rust.ChatEvent_Tool(:final name)):
            final id = 'tool-${activities.length}';
            activities[id] = ChatActivity(
              id: id,
              kind: ChatActivityKind.tool,
              name: name,
              startedAt: DateTime.now(),
            ).update(status: ChatActivityStatus.completed);
            schedule();
          case ConversationEvent_Saved(:final conversation):
            flush?.cancel();
            finishReasoning();
            var saved = conversation;
            if (activities.isNotEmpty && saved.messages.isNotEmpty) {
              final last = saved.messages.last;
              saved = await _save(
                _withMessages(saved, [
                  ...saved.messages.take(saved.messages.length - 1),
                  _withActivities(last, activities.values),
                ]),
              );
            }
            _conversations[saved.id] = saved;
            if (mounted) {
              state = state.copyWith(
                sessions: _sorted(),
                sending: false,
                streamingText: null,
                activities: const [],
              );
            }
          case ConversationEvent_Failed(:final error):
            throw error;
          default:
        }
      }
    } catch (e) {
      flush?.cancel();
      if (!_cancelled || !isCancellation(e)) rethrow;
      // 用户中断：保留已流出的回答与过程。
      final partial = text.toString().trim();
      for (final entry in activities.entries.toList()) {
        if (entry.value.status == ChatActivityStatus.running) {
          activities[entry.key] = entry.value.update(
            status: ChatActivityStatus.cancelled,
          );
        }
      }
      if (partial.isNotEmpty || activities.isNotEmpty) {
        final latest = await RustBackend.instance.conversation(
          document: documentId,
          id: sessionId,
        );
        await _save(
          _withMessages(latest, [
            ...latest.messages,
            ConversationMessage(
              id: ChatMessage.newId(),
              role: rust.Role.assistant,
              content: partial,
              activities: [
                for (final a in activities.values) toJsonData(a.toJson()),
              ],
              modelId: selection.config.model,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              extra: const [],
            ),
          ]),
        );
      }
      if (mounted) {
        state = state.copyWith(
          sessions: _sorted(),
          sending: false,
          streamingText: null,
          activities: const [],
        );
      }
    } finally {
      if (_task == task) _task = null;
    }
  }

  /// 截断当前会话到 [keepCount] 条消息后以 [text] 重新发送。
  Future<void> resendFrom({
    required int keepCount,
    required String text,
    required ChatModelRole role,
    ChatModelSelection? model,
    String? quotedText,
    String? figureImagePath,
    Map<String, dynamic>? quoteAnchor,
    ThinkingLevel? thinkingOverride,
    bool webSearch = false,
    bool streaming = true,
  }) async {
    final conversation = _conversations[state.activeSessionId];
    if (conversation == null || state.sending) return;
    try {
      await _save(
        _withMessages(
          conversation,
          conversation.messages.sublist(0, keepCount),
        ),
      );
    } catch (e, st) {
      _reportError(e, st);
      return;
    }
    if (!mounted) return;
    state = state.copyWith(sessions: _sorted());
    await send(
      text: text,
      role: role,
      model: model,
      quotedText: quotedText,
      figureImagePath: figureImagePath,
      quoteAnchor: quoteAnchor,
      thinkingOverride: thinkingOverride,
      webSearch: webSearch,
      streaming: streaming,
    );
  }

  /// 从指定消息分叉出新会话，包含 [upToIndex]（含）之前的消息。
  Future<void> forkFromMessage(int upToIndex) async {
    final source = _conversations[state.activeSessionId];
    if (source == null) return;
    try {
      final created = await RustBackend.instance.createConversation(
        document: documentId,
        title: source.title,
      );
      final forked = await _save(
        _withMessages(created, source.messages.sublist(0, upToIndex + 1)),
      );
      if (!mounted) return;
      state = state.copyWith(sessions: _sorted(), activeSessionId: forked.id);
    } catch (e, st) {
      _reportError(e, st);
    }
  }

  void cancel() {
    final task = _task;
    if (task == null) return;
    _cancelled = true;
    cancelTask(taskId: task);
  }

  /// 图片输入：快速模型不发图；其余按实例（含手动覆写）的能力判定。
  bool supportsImages(ChatModelRole role, {ChatModelSelection? model}) =>
      !isFastModel(role, model) && _capabilityFor(role, model).imageInput;

  AgentModelCapability _capabilityFor(
    ChatModelRole role,
    ChatModelSelection? model,
  ) {
    final roleState = resolveModelState(role, model);
    final modelId =
        model?.modelId ??
        (roleState == null ? null : modelIdFor(roleState, role));
    if (roleState == null || modelId == null) {
      return const AgentModelCapability();
    }
    return ref
            .read(agentApiProvider)
            .byId(roleState.id)
            ?.capabilityFor(modelId) ??
        const AgentModelCapability();
  }

  ModelSelection? _selection(
    ChatModelRole role,
    ChatModelSelection? model,
    ThinkingLevel? thinkingOverride,
  ) {
    final roleState = resolveModelState(role, model);
    final modelId =
        model?.modelId ??
        (roleState == null ? null : modelIdFor(roleState, role));
    if (roleState == null ||
        modelId == null ||
        !roleState.models.contains(modelId)) {
      return null;
    }
    final params = roleState.paramsFor(modelId);
    final state = thinkingOverride == null
        ? roleState
        : roleState.copyWith(
            modelParams: {
              ...roleState.modelParams,
              modelId: params.copyWith(thinkingLevel: thinkingOverride),
            },
          );
    return modelSelection(
      state,
      modelId,
      capability: ref
          .read(agentApiProvider)
          .byId(roleState.id)
          ?.modelCaps[modelId],
    );
  }

  /// 首轮发出后用快速模型生成会话标题，失败时保留截断的提问。
  Future<void> _generateTitle(
    String sessionId,
    String question,
    String? quotedText,
  ) async {
    final selection = _selection(ChatModelRole.fast, null, ThinkingLevel.off);
    if (selection == null) return;
    var input = quotedText == null || quotedText.trim().isEmpty
        ? question
        : '$quotedText\n\n$question';
    if (input.length > 1000) input = input.substring(0, 1000);
    try {
      String? title;
      await for (final event in RustBackend.instance.generateText(
        model: selection,
        request: GenerationRequest(
          system: Prompts.chatTitleSystem,
          messages: [
            rust.Message(role: rust.Role.user, text: input, images: const []),
          ],
          webSearch: false,
          urlContext: false,
          showReasoning: false,
          cachePrefix: false,
        ),
        taskId: rustTaskId('chat-title'),
      )) {
        switch (event) {
          case GenerationEvent_Completed(:final response):
            title = response.text.trim();
          case GenerationEvent_Failed(:final error):
            throw error;
          default:
        }
      }
      if (title == null || title.isEmpty || !mounted) return;
      final latest = await RustBackend.instance.conversation(
        document: documentId,
        id: sessionId,
      );
      await _save(
        Conversation(
          id: latest.id,
          title: title,
          createdAt: latest.createdAt,
          updatedAt: latest.updatedAt,
          messages: latest.messages,
          revision: latest.revision,
          extra: latest.extra,
        ),
      );
      if (mounted) state = state.copyWith(sessions: _sorted());
    } catch (e, st) {
      log.w('[DocumentChat] 标题生成失败：$documentId', error: e, stackTrace: st);
    }
  }

  static String _titleFrom(String question) {
    final line = question.split('\n').first.trim();
    return line.length <= 24 ? line : '${line.substring(0, 24)}…';
  }
}

Conversation _withMessages(
  Conversation c,
  List<ConversationMessage> messages,
) => Conversation(
  id: c.id,
  title: c.title,
  createdAt: c.createdAt,
  updatedAt: c.updatedAt,
  messages: messages,
  revision: c.revision,
  extra: c.extra,
);

ConversationMessage _withActivities(
  ConversationMessage m,
  Iterable<ChatActivity> activities,
) => ConversationMessage(
  id: m.id,
  role: m.role,
  content: m.content,
  quotedText: m.quotedText,
  quoteAnchor: m.quoteAnchor,
  figureImagePath: m.figureImagePath,
  activities: [for (final a in activities) toJsonData(a.toJson())],
  urlContext: m.urlContext,
  modelId: m.modelId,
  createdAt: m.createdAt,
  extra: m.extra,
);

ChatSession _session(Conversation c) => ChatSession(
  id: c.id,
  title: c.title,
  createdAt: DateTime.tryParse(c.createdAt)?.toLocal() ?? DateTime.now(),
  updatedAt: DateTime.tryParse(c.updatedAt)?.toLocal() ?? DateTime.now(),
  messages: [
    for (final m in c.messages)
      ChatMessage(
        id: m.id,
        role: m.role == rust.Role.user ? 'user' : 'assistant',
        content: m.content,
        quotedText: m.quotedText,
        quoteAnchor: m.quoteAnchor == null
            ? null
            : (fromJsonData(m.quoteAnchor!) as Map?)?.cast<String, dynamic>(),
        figureImagePath: m.figureImagePath,
        activities: [
          for (final a in m.activities)
            if (fromJsonData(a) case final Map<String, dynamic> json)
              ChatActivity.fromJson(json),
        ],
        urlContext: m.urlContext,
        modelId: m.modelId,
        createdAt: DateTime.tryParse(m.createdAt)?.toLocal() ?? DateTime.now(),
      ),
  ],
);

final documentChatProvider =
    StateNotifierProvider.family<
      DocumentChatNotifier,
      DocumentChatState,
      String
    >((ref, documentId) => DocumentChatNotifier(ref, documentId));
