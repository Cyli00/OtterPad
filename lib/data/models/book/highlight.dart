/// 用户在 Markdown 阅读器中的标记。
class Highlight {
  final String id;
  final String documentId;
  final String text;
  final String? note;

  /// 同一次跨段落选择产生的多条标记共享同一个 groupId，
  /// 删除时按组联动删除。单段落标记为 null。
  final String? groupId;
  final DateTime createdAt;

  const Highlight({
    required this.id,
    required this.documentId,
    required this.text,
    this.note,
    this.groupId,
    required this.createdAt,
  });

  /// 返回带有指定笔记的副本（传 null 可清除笔记）。
  Highlight withNote(String? note) {
    return Highlight(
      id: id,
      documentId: documentId,
      text: text,
      note: note,
      groupId: groupId,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'documentId': documentId,
    'text': text,
    'note': note,
    'groupId': groupId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Highlight.fromJson(Map<String, dynamic> json) {
    return Highlight(
      id: json['id'] as String,
      documentId: json['documentId'] as String,
      text: json['text'] as String,
      note: json['note'] as String?,
      groupId: json['groupId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
