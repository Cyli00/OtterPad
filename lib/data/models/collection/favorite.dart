/// 收藏夹数据模型
class Favorite {
  final String id;
  final String emoji;
  final String name;
  final List<String> documentIds;
  final DateTime createdAt;

  /// "我的收藏"默认收藏夹的固定 ID
  static const String defaultId = '_default_';

  const Favorite({
    required this.id,
    required this.emoji,
    required this.name,
    required this.documentIds,
    required this.createdAt,
  });

  bool get isDefault => id == defaultId;

  Favorite copyWith({String? emoji, String? name, List<String>? documentIds}) {
    return Favorite(
      id: id,
      emoji: emoji ?? this.emoji,
      name: name ?? this.name,
      documentIds: documentIds ?? this.documentIds,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'emoji': emoji,
    'name': name,
    'documentIds': documentIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Favorite.fromJson(Map<String, dynamic> json) {
    final raw = json['documentIds'];
    return Favorite(
      id: json['id'] as String,
      emoji: json['emoji'] as String,
      name: json['name'] as String,
      documentIds: raw is List ? raw.cast<String>() : const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
