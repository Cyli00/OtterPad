import '../services/model_capability_store.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/models/chat/chat_session.dart';
import '../core/app_logger.dart';
import '../services/document_chat_service.dart';
import 'agent_api_provider.dart';

/// 每文献问 AI 状态。[activeSessionId] 为 null 表示「新会话草稿」——
/// 首次发送时才落地创建会话文件，避免空会话垃圾。
class DocumentChatState {
  final bool loaded;

  /// 按 updatedAt 降序。
  final List<ChatSession> sessions;
  final String? activeSessionId;
  final bool sending;

  /// 流式回答的实时累积文本；非流式中 / 未开始为 null。
  final String? streamingText;

  /// 最近一次发送失败的可读文案；进入下一次发送时清空。
  final String? error;

  const DocumentChatState({
    this.loaded = false,
    this.sessions = const [],
    this.activeSessionId,
    this.sending = false,
    this.streamingText,
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
    Object? error = _sentinel,
  }) => DocumentChatState(
    loaded: loaded ?? this.loaded,
    sessions: sessions ?? this.sessions,
    activeSessionId: identical(activeSessionId, _sentinel)
        ? this.activeSessionId
        : activeSessionId as String?,
    sending: sending ?? this.sending,
    streamingText: identical(streamingText, _sentinel)
        ? this.streamingText
        : streamingText as String?,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );
}

const _sentinel = Object();

/// 问 AI 状态机——会话 CRUD 与发送编排。IO 与请求全部委托
/// [DocumentChatService]，自己只持状态 + CancelToken。
class DocumentChatNotifier extends StateNotifier<DocumentChatState> {
  final Ref ref;
  final String documentId;
  CancelToken? _cancelToken;

  DocumentChatNotifier(this.ref, this.documentId)
    : super(const DocumentChatState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final sessions = await DocumentChatService.listSessions(documentId);
      if (!mounted) return;
      state = state.copyWith(loaded: true, sessions: sessions);
    } catch (e, st) {
      _reportError(e, st);
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  void _reportError(Object error, StackTrace stackTrace) {
    log.w('[DocumentChat] $documentId', error: error, stackTrace: stackTrace);
    if (!mounted) return;
    state = state.copyWith(
      sending: false,
      streamingText: null,
      error: '$error'.replaceFirst('Exception: ', ''),
    );
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  /// 切到新会话草稿（不立即建文件）。
  void startNewSession() =>
      state = state.copyWith(activeSessionId: null, error: null);

  void switchSession(String sessionId) =>
      state = state.copyWith(activeSessionId: sessionId, error: null);

  Future<void> deleteSession(String sessionId) async {
    await DocumentChatService.deleteSession(documentId, sessionId);
    if (!mounted) return;
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions)
          if (s.id != sessionId) s,
      ],
      activeSessionId: state.activeSessionId == sessionId
          ? null
          : state.activeSessionId,
    );
  }

  /// 发送一轮提问。用户消息先落盘（断网/失败不丢提问）；[streaming] 开时
  /// 回答增量经 [DocumentChatState.streamingText] 实时呈现（用户中断时已
  /// 流出的部分也作为回答保留），关时一次性整体呈现；完成后整体落盘。
  Future<void> send({
    required String text,
    required ChatModelRole role,
    String? quotedText,
    String? figureImagePath,
    ThinkingLevel? thinkingOverride,
    bool webSearch = false,
    bool streaming = true,
  }) async {
    if (state.sending) return;
    final question = text.trim();
    if (question.isEmpty) return;

    var session =
        state.activeSession ?? ChatSession.create(title: _titleFrom(question));
    final history = List<ChatMessage>.from(session.messages);
    var userMsg = ChatMessage.user(content: question, quotedText: quotedText);
    session = session.append(userMsg);
    _upsert(session, sending: true);
    final cancelToken = _cancelToken = CancelToken();
    // 流式增量 80ms 节流刷入 state——每个 token 都重建 Markdown 会拖垮 UI。
    final streamBuf = StringBuffer();
    Timer? flushTimer;
    void pushDelta(String delta) {
      streamBuf.write(delta);
      flushTimer ??= Timer(const Duration(milliseconds: 80), () {
        flushTimer = null;
        if (!mounted || cancelToken.isCancelled) return;
        state = state.copyWith(streamingText: streamBuf.toString());
      });
    }

    Future<void> persistAnswer(String content) async {
      // 从 state 取最新版本再追加——标题生成可能已并发更新过同一会话。
      session = (_sessionById(session.id) ?? session).append(
        ChatMessage.assistant(content: content, modelId: _modelIdOf(role)),
      );
      _upsert(session, sending: true);
      await DocumentChatService.saveSession(documentId, session);
      if (mounted) state = state.copyWith(sending: false);
    }

    try {
      await DocumentChatService.saveSession(documentId, session);
      if (!mounted) return;
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      if (history.isEmpty) {
        unawaited(
          _generateTitle(session.id, question, quotedText).catchError((
            Object e,
            StackTrace st,
          ) {
            log.w(
              '[DocumentChat] 标题生成失败：$documentId',
              error: e,
              stackTrace: st,
            );
          }),
        );
      }
      // 客户端 URL 回退抓取（无链接 / 模型原生支持 URL 工具时为 null）。
      // 完成后挂回已落盘的 user 消息，历史重放据此与当轮保持一致。
      final urlContext = await DocumentChatService.buildUrlContextFallback(
        role: role,
        question: question,
        cancelToken: cancelToken,
      );
      if (!mounted) return;
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      if (urlContext != null) {
        userMsg = userMsg.withUrlContext(urlContext);
        final latest = _sessionById(session.id) ?? session;
        session = latest.copyWith(
          messages: [
            for (final m in latest.messages) m.id == userMsg.id ? userMsg : m,
          ],
        );
        _replaceSession(session);
        await DocumentChatService.saveSession(documentId, session);
      }
      final answer = await DocumentChatService.ask(
        documentId: documentId,
        role: role,
        history: history,
        question: question,
        quotedText: quotedText,
        figureImagePath: figureImagePath,
        urlContext: urlContext,
        supportsImages: supportsImages(role),
        thinkingOverride: thinkingOverride,
        webSearch: webSearch,
        onDelta: streaming ? pushDelta : null,
        cancelToken: cancelToken,
      );
      flushTimer?.cancel();
      if (!mounted) return;
      await persistAnswer(answer);
    } catch (e, st) {
      flushTimer?.cancel();
      if (!mounted) return;
      if (cancelToken.isCancelled) {
        // 用户中断：已流出的部分作为回答保留，不白等也不丢
        final partial = streamBuf.toString().trim();
        if (partial.isEmpty) {
          state = state.copyWith(sending: false, streamingText: null);
        } else {
          try {
            await persistAnswer(partial);
          } catch (saveError, saveStack) {
            _reportError(saveError, saveStack);
          }
        }
        return;
      }
      _reportError(e, st);
    } finally {
      flushTimer?.cancel();
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  /// 截断当前会话到 [keepCount] 条消息，然后以 [text] 重新发送。
  ///
  /// 编辑用户消息：`keepCount` = 被编辑消息的 index（丢弃该消息及之后的所有内容）。
  /// 重试 AI 回答：`keepCount` = 被重试的 assistant 消息的 index（丢弃该回答），
  ///   text 填上一条 user 消息的原文。
  Future<void> resendFrom({
    required int keepCount,
    required String text,
    required ChatModelRole role,
    String? quotedText,
    String? figureImagePath,
    ThinkingLevel? thinkingOverride,
    bool webSearch = false,
    bool streaming = true,
  }) async {
    final session = state.activeSession;
    if (session == null || state.sending) return;
    final truncated = session.copyWith(
      messages: session.messages.sublist(0, keepCount),
    );
    state = state.copyWith(sending: true, error: null);
    try {
      await DocumentChatService.saveSession(documentId, truncated);
    } catch (e, st) {
      _reportError(e, st);
      return;
    }
    if (!mounted) return;
    _upsert(truncated, sending: false);
    await send(
      text: text,
      role: role,
      quotedText: quotedText,
      figureImagePath: figureImagePath,
      thinkingOverride: thinkingOverride,
      webSearch: webSearch,
      streaming: streaming,
    );
  }

  /// 从指定消息处分叉：创建新会话，包含 [upToIndex]（含）之前的所有消息。
  Future<void> forkFromMessage(int upToIndex) async {
    final session = state.activeSession;
    if (session == null) return;
    final forked = ChatSession(
      id: ChatMessage.newId(),
      title: session.title,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: session.messages.sublist(0, upToIndex + 1),
    );
    try {
      await DocumentChatService.saveSession(documentId, forked);
    } catch (e, st) {
      _reportError(e, st);
      return;
    }
    if (!mounted) return;
    state = state.copyWith(
      sessions: [forked, ...state.sessions],
      activeSessionId: forked.id,
    );
  }

  /// 中断当前流式回答——状态收尾（含已流出部分的落盘）由 [send] 的
  /// cancel 分支统一处理。
  void cancel() => _cancelToken?.cancel();

  String _modelIdOf(ChatModelRole role) {
    final roleState = DocumentChatService.resolveRoleState(role);
    return roleState == null
        ? ''
        : (DocumentChatService.modelIdFor(roleState, role) ?? '');
  }

  /// 图片输入能力判定：优先读实例上（含用户在设置里手动覆盖的）能力标记，
  /// 实例不可达时回退 id 推断——两条路都在 AgentModelCapability 接缝内。
  /// public：供 page 发图时判定是否需自动转专家模型。
  bool supportsImages(ChatModelRole role) {
    final roleState = DocumentChatService.resolveRoleState(role);
    final modelId = roleState == null
        ? null
        : DocumentChatService.modelIdFor(roleState, role);
    if (roleState == null || modelId == null) return false;
    final inst = ref.read(agentApiProvider).byId(roleState.id);
    final cap =
        inst?.capabilityFor(modelId) ??
        AgentModelCapability.infer(
          provider: roleState.provider,
          modelId: modelId,
        );
    return cap.imageInput;
  }

  ChatSession? _sessionById(String id) {
    for (final s in state.sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 原位替换会话（不动 activeSessionId / sending）——标题异步更新用。
  void _replaceSession(ChatSession session) {
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions) s.id == session.id ? session : s,
      ],
    );
  }

  /// 首轮发出后用快速模型异步生成会话标题。与回答的落盘竞写同一文件——
  /// 双方先从 state 取最新版本再改字段，服务层按调用顺序串行写入同一文件。
  Future<void> _generateTitle(
    String sessionId,
    String question,
    String? quotedText,
  ) async {
    final title = await DocumentChatService.summarizeTitle(
      question: question,
      quotedText: quotedText,
    );
    if (!mounted || title == null) return;
    final current = _sessionById(sessionId);
    if (current == null) return; // 会话已被删除
    final updated = current.copyWith(title: title);
    _replaceSession(updated);
    try {
      await DocumentChatService.saveSession(documentId, updated);
    } catch (e, st) {
      log.w('[DocumentChat] 标题保存失败：$documentId', error: e, stackTrace: st);
    }
  }

  /// 把会话写回列表头部（updatedAt 降序）并设为活动会话。
  void _upsert(ChatSession session, {required bool sending}) {
    state = state.copyWith(
      sessions: [
        session,
        for (final s in state.sessions)
          if (s.id != session.id) s,
      ],
      activeSessionId: session.id,
      sending: sending,
      streamingText: null,
      error: null,
    );
  }

  static String _titleFrom(String question) {
    final line = question.split('\n').first.trim();
    return line.length <= 24 ? line : '${line.substring(0, 24)}…';
  }
}

final documentChatProvider =
    StateNotifierProvider.family<
      DocumentChatNotifier,
      DocumentChatState,
      String
    >((ref, documentId) => DocumentChatNotifier(ref, documentId));
