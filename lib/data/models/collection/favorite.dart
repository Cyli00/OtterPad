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
    final documentIdsRaw = json['documentIds'];
    final legacyDocPaths = json['docPaths'];
    final List<String> documentIds;
    if (documentIdsRaw is List) {
      documentIds = documentIdsRaw.cast<String>();
    } else if (legacyDocPaths is List) {
      // 旧 schema：docPaths 形如 `<root>/(docs|library)/<documentId>/source.pdf`。
      // 取倒数第二段即为目录名，等同于今天 Document.id（rebuild 时
      // documentId = basename(entity.path) 已保证迁移幂等）。
      documentIds = _docPathsToDocumentIds(legacyDocPaths.cast<String>());
    } else {
      documentIds = const [];
    }
    return Favorite(
      id: json['id'] as String,
      emoji: json['emoji'] as String,
      name: json['name'] as String,
      documentIds: documentIds,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  static List<String> _docPathsToDocumentIds(List<String> paths) {
    final ids = <String>[];
    for (final raw in paths) {
      final normalized = raw.replaceAll('\\', '/');
      final trimmed = normalized.endsWith('/')
          ? normalized.substring(0, normalized.length - 1)
          : normalized;
      final parts = trimmed
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 2) ids.add(parts[parts.length - 2]);
    }
    return ids;
  }
}
