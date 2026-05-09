const kHighlightColors = [
  'FFD54F', // Amber 300
  'AED581', // Light Green 300
  '4FC3F7', // Light Blue 300
  'FF8A80', // Red A100
  'CE93D8', // Purple 200
];

const kDefaultHighlightColor = 'FFD54F';

/// 用户在 Markdown 阅读器中的标记。
class Highlight {
  final String id;
  final String documentId;
  final String text;
  final String? note;
  final String color;

  /// 同一次跨段落选择产生的多条标记共享同一个 groupId，
  /// 删除时按组联动删除。单段落标记为 null。
  final String? groupId;
  final DateTime createdAt;

  const Highlight({
    required this.id,
    required this.documentId,
    required this.text,
    this.note,
    this.color = kDefaultHighlightColor,
    this.groupId,
    required this.createdAt,
  });

  Highlight withNote(String? note) => Highlight(
    id: id, documentId: documentId, text: text,
    note: note, color: color, groupId: groupId, createdAt: createdAt,
  );

  Highlight withColor(String color) => Highlight(
    id: id, documentId: documentId, text: text,
    note: note, color: color, groupId: groupId, createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'documentId': documentId,
    'text': text,
    'note': note,
    'color': color,
    'groupId': groupId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Highlight.fromJson(Map<String, dynamic> json) {
    return Highlight(
      id: json['id'] as String,
      documentId: json['documentId'] as String,
      text: json['text'] as String,
      note: json['note'] as String?,
      color: json['color'] as String? ?? kDefaultHighlightColor,
      groupId: json['groupId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
