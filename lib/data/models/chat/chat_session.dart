/// 问 AI 会话模型——持久化为 `library/{documentId}/chats/{sessionId}.json`，
/// 与文献目录同生共死（同 translations.json 范式：自动被备份/恢复/删除覆盖）。
library;

import 'chat_activity.dart';
import '../book/reader_anchor.dart';

/// 会话中的一条消息。
class ChatMessage {
  final String id;

  /// 'user' | 'assistant'
  final String role;
  final String content;

  /// 用户划词引用的原文片段（仅 user 消息可有）。
  final String? quotedText;
  final ReaderAnchor? quoteAnchor;
  final String? figureImagePath;
  final List<ChatActivity> activities;

  /// 客户端抓取的链接内容（仅 user 消息；模型走原生 URL 工具时为 null）。
  /// 随消息持久化，历史重放时与当轮共用同一组装，多轮上下文一致。
  final String? urlContext;

  /// 产出此回答的模型 id（仅 assistant 消息）。
  final String? modelId;

  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.quotedText,
    this.quoteAnchor,
    this.figureImagePath,
    this.activities = const [],
    this.urlContext,
    this.modelId,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  factory ChatMessage.user({
    required String content,
    String? quotedText,
    ReaderAnchor? quoteAnchor,
    String? figureImagePath,
  }) => ChatMessage(
    id: newId(),
    role: 'user',
    figureImagePath: figureImagePath,
    quoteAnchor: quoteAnchor,
    content: content,
    quotedText: (quotedText?.trim().isEmpty ?? true) ? null : quotedText,
    createdAt: DateTime.now(),
  );

  /// 异步抓取完成后把链接内容挂回已落盘的消息。
  ChatMessage withUrlContext(String urlContext) => ChatMessage(
    id: id,
    role: role,
    content: content,
    quotedText: quotedText,
    figureImagePath: figureImagePath,
    quoteAnchor: quoteAnchor,
    activities: activities,
    urlContext: urlContext,
    modelId: modelId,
    createdAt: createdAt,
  );

  factory ChatMessage.assistant({
    required String content,
    required String modelId,
    List<ChatActivity> activities = const [],
  }) => ChatMessage(
    id: newId(),
    role: 'assistant',
    activities: activities,
    content: content,
    modelId: modelId,
    createdAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    if (quotedText != null) 'quotedText': quotedText,
    if (quoteAnchor != null) 'quoteAnchor': quoteAnchor!.toJson(),
    if (figureImagePath != null) 'figureImagePath': figureImagePath,
    if (activities.isNotEmpty)
      'activities': [for (final a in activities) a.toJson()],
    if (urlContext != null) 'urlContext': urlContext,
    if (modelId != null) 'modelId': modelId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    role: json['role'] as String,
    content: json['content'] as String? ?? '',
    quotedText: json['quotedText'] as String?,
    quoteAnchor: ReaderAnchor.parse(json['quoteAnchor']),
    figureImagePath: json['figureImagePath'] as String?,
    activities: [
      for (final a in json['activities'] as List? ?? const [])
        ChatActivity.fromJson(a as Map<String, dynamic>),
    ],
    urlContext: json['urlContext'] as String?,
    modelId: json['modelId'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

/// 一篇文献的一个问 AI 会话。不可变；追加消息用 [append]。
class ChatSession {
  final String id;

  /// 首条提问截断生成，会话列表展示用。
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  factory ChatSession.create({required String title}) {
    final now = DateTime.now();
    return ChatSession(
      id: ChatMessage.newId(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  ChatSession copyWith({String? title, List<ChatMessage>? messages}) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        messages: messages ?? this.messages,
      );

  ChatSession append(ChatMessage message) => ChatSession(
    id: id,
    title: title,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    messages: [...messages, message],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': [for (final m in messages) m.toJson()],
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    messages: [
      for (final m in (json['messages'] as List? ?? const []))
        ChatMessage.fromJson(m as Map<String, dynamic>),
    ],
  );
}
