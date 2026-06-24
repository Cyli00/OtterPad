import 'dart:io';

class MarkdownResolvedDocument {
  final String cacheKey;
  final String content;

  const MarkdownResolvedDocument({
    required this.cacheKey,
    required this.content,
  });
}

class MarkdownDocumentCacheService {
  MarkdownDocumentCacheService._();

  static final MarkdownDocumentCacheService instance =
      MarkdownDocumentCacheService._();

  static const _maxEntries = 4;

  final _contentCache = <String, String>{};
  final _contentTasks = <String, Future<String>>{};

  Future<MarkdownResolvedDocument> loadDocument({
    required String mdPath,
    required String title,
  }) async {
    final key = await buildCacheKey(mdPath: mdPath, title: title);
    final cached = _readContentCache(key);
    if (cached != null) {
      return MarkdownResolvedDocument(cacheKey: key, content: cached);
    }

    final running = _contentTasks[key];
    if (running != null) {
      final content = await running;
      return MarkdownResolvedDocument(cacheKey: key, content: content);
    }

    final task = _loadDocumentInternal(mdPath: mdPath, title: title, key: key);
    _contentTasks[key] = task;
    try {
      final content = await task;
      return MarkdownResolvedDocument(cacheKey: key, content: content);
    } finally {
      _contentTasks.remove(key);
    }
  }

  void primeResolvedContent({
    required String cacheKey,
    required String content,
  }) {
    _writeContentCache(cacheKey, content);
  }

  Future<String> buildCacheKey({
    required String mdPath,
    required String title,
  }) async {
    final file = File(mdPath);
    final stat = await file.stat();
    final modified = stat.modified.millisecondsSinceEpoch;
    return '$mdPath|$modified|$title';
  }

  String buildMemoryCacheKey({
    required String mdPath,
    required String title,
    required String markdownContent,
  }) {
    return 'memory|$mdPath|$title|${markdownContent.length}|${markdownContent.hashCode}';
  }

  String? _readContentCache(String key) {
    final cached = _contentCache.remove(key);
    if (cached == null) return null;
    _contentCache[key] = cached;
    return cached;
  }

  void _writeContentCache(String key, String content) {
    _contentCache.remove(key);
    _contentCache[key] = content;
    while (_contentCache.length > _maxEntries) {
      _contentCache.remove(_contentCache.keys.first);
    }
  }

  Future<String> _loadDocumentInternal({
    required String mdPath,
    required String title,
    required String key,
  }) async {
    final content = await File(mdPath).readAsString();
    _writeContentCache(key, content);
    return content;
  }

}
