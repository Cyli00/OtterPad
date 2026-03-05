/// 收藏夹数据模型
class Favorite {
  final String id;
  final String emoji;
  final String name;
  final List<String> docPaths;
  final DateTime createdAt;

  /// 默认文库的固定 ID
  static const String defaultId = '_default_';

  const Favorite({
    required this.id,
    required this.emoji,
    required this.name,
    required this.docPaths,
    required this.createdAt,
  });

  bool get isDefault => id == defaultId;

  Favorite copyWith({
    String? emoji,
    String? name,
    List<String>? docPaths,
  }) {
    return Favorite(
      id: id,
      emoji: emoji ?? this.emoji,
      name: name ?? this.name,
      docPaths: docPaths ?? this.docPaths,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        'name': name,
        'docPaths': docPaths,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Favorite.fromJson(Map<String, dynamic> json) => Favorite(
        id: json['id'] as String,
        emoji: json['emoji'] as String,
        name: json['name'] as String,
        docPaths: (json['docPaths'] as List<dynamic>).cast<String>(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
