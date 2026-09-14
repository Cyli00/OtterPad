enum ChatActivityKind { reasoning, tool }

enum ChatActivityStatus { running, completed, failed, cancelled }

class ChatActivity {
  final String id;
  final ChatActivityKind kind;
  final String name;
  final String text;
  final ChatActivityStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;

  const ChatActivity({
    required this.id,
    required this.kind,
    this.name = '',
    this.text = '',
    this.status = ChatActivityStatus.running,
    required this.startedAt,
    this.endedAt,
  });

  ChatActivity update({String? text, ChatActivityStatus? status}) =>
      ChatActivity(
        id: id,
        kind: kind,
        name: name,
        text: text ?? this.text,
        status: status ?? this.status,
        startedAt: startedAt,
        endedAt: status != null && status != ChatActivityStatus.running
            ? DateTime.now()
            : endedAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'text': text,
    'status': status.name,
    'startedAt': startedAt.toIso8601String(),
    if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
  };

  factory ChatActivity.fromJson(Map<String, dynamic> json) => ChatActivity(
    id: json['id'] as String,
    kind: ChatActivityKind.values.byName(json['kind'] as String),
    name: json['name'] as String? ?? '',
    text: json['text'] as String? ?? '',
    status: ChatActivityStatus.values.byName(
      json['status'] as String? ?? 'completed',
    ),
    startedAt: DateTime.parse(json['startedAt'] as String),
    endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
  );
}
