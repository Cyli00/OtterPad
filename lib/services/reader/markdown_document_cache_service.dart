import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

class MarkdownResolvedDocument {
  final String cacheKey;
  final String content;

  const MarkdownResolvedDocument({
    required this.cacheKey,
    required this.content,
  });
}

class MarkdownSearchBlock {
  final String heading;
  final String plainText;
  final int charOffset;

  const MarkdownSearchBlock({
    required this.heading,
    required this.plainText,
    required this.charOffset,
  });
}

class MarkdownSearchSnapshot {
  final List<MarkdownSearchBlock> blocks;

  const MarkdownSearchSnapshot({required this.blocks});
}

class MarkdownDocumentCacheService {
  MarkdownDocumentCacheService._();

  static final MarkdownDocumentCacheService instance =
      MarkdownDocumentCacheService._();

  static const _maxEntries = 4;

  final _contentCache = LinkedHashMap<String, String>();
  final _searchSnapshotCache =
      LinkedHashMap<String, MarkdownSearchSnapshot>();
  final _contentTasks = <String, Future<String>>{};
  final _searchSnapshotTasks = <String, Future<MarkdownSearchSnapshot>>{};

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

  Future<MarkdownSearchSnapshot> getSearchSnapshot({
    required String cacheKey,
    required String markdownContent,
    String? jsonPath,
  }) async {
    final cached = _readSearchSnapshotCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final running = _searchSnapshotTasks[cacheKey];
    if (running != null) return await running;

    final task = _buildSearchSnapshotInternal(
      cacheKey: cacheKey,
      markdownContent: markdownContent,
      jsonPath: jsonPath,
    );
    _searchSnapshotTasks[cacheKey] = task;
    try {
      return await task;
    } finally {
      _searchSnapshotTasks.remove(cacheKey);
    }
  }

  void prewarmSearchSnapshot({
    required String cacheKey,
    required String markdownContent,
    String? jsonPath,
  }) {
    unawaited(
      getSearchSnapshot(
        cacheKey: cacheKey,
        markdownContent: markdownContent,
        jsonPath: jsonPath,
      ),
    );
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

  MarkdownSearchSnapshot? _readSearchSnapshotCache(String key) {
    final cached = _searchSnapshotCache.remove(key);
    if (cached == null) return null;
    _searchSnapshotCache[key] = cached;
    return cached;
  }

  void _writeContentCache(String key, String content) {
    _contentCache.remove(key);
    _contentCache[key] = content;
    while (_contentCache.length > _maxEntries) {
      _contentCache.remove(_contentCache.keys.first);
    }
  }

  void _writeSearchSnapshotCache(String key, MarkdownSearchSnapshot snapshot) {
    _searchSnapshotCache.remove(key);
    _searchSnapshotCache[key] = snapshot;
    while (_searchSnapshotCache.length > _maxEntries) {
      _searchSnapshotCache.remove(_searchSnapshotCache.keys.first);
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

  Future<MarkdownSearchSnapshot> _buildSearchSnapshotInternal({
    required String cacheKey,
    required String markdownContent,
    String? jsonPath,
  }) async {
    final headings = await _loadJsonHeadings(jsonPath);
    final blocksData = _buildSearchBlocks(markdownContent, headings);

    final snapshot = MarkdownSearchSnapshot(
      blocks: blocksData
          .map(
            (item) => MarkdownSearchBlock(
              heading: item['heading'] as String,
              plainText: item['plainText'] as String,
              charOffset: item['charOffset'] as int,
            ),
          )
          .toList(growable: false),
    );

    _writeSearchSnapshotCache(cacheKey, snapshot);
    return snapshot;
  }

  /// 从提取 JSON 中读取 paragraph_title 的 block_content 列表
  static Future<Set<String>> _loadJsonHeadings(String? jsonPath) async {
    if (jsonPath == null) return {};
    final file = File(jsonPath);
    if (!await file.exists()) return {};

    try {
      final raw = await file.readAsString();
      final pages = jsonDecode(raw) as List<dynamic>;
      final headings = <String>{};

      for (final page in pages) {
        final blocks = (page as Map<String, dynamic>)['prunedResult']
                ?['parsing_res_list'] as List<dynamic>? ??
            [];
        for (final block in blocks) {
          final b = block as Map<String, dynamic>;
          if (b['block_label'] == 'paragraph_title') {
            final content = (b['block_content'] as String?)?.trim() ?? '';
            if (content.isNotEmpty) headings.add(content);
          }
        }
      }

      return headings;
    } catch (_) {
      return {};
    }
  }
}

// ─── 搜索块构建 ───

final _atxHeadingRegex = RegExp(r'^\s{0,3}#{1,6}\s+(.+?)(?:\s+#+\s*)?$');

List<Map<String, Object>> _buildSearchBlocks(
  String markdown,
  Set<String> jsonHeadings,
) {
  final blocks = <Map<String, Object>>[];
  final lines = markdown.split('\n');
  var currentHeading = '';
  var blockBuffer = StringBuffer();
  var blockStartOffset = 0;
  var currentOffset = 0;

  void flushBlock() {
    if (blockBuffer.isEmpty) return;
    final rawText = blockBuffer.toString().trim();
    if (rawText.isNotEmpty) {
      blocks.add({
        'heading': currentHeading,
        'plainText': _stripMarkdown(rawText),
        'charOffset': blockStartOffset,
      });
    }
    blockBuffer = StringBuffer();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lineLength = line.length + 1;

    if (line.trim().isEmpty) {
      flushBlock();
      currentOffset += lineLength;
      blockStartOffset = currentOffset;
      continue;
    }

    final heading = _resolveHeading(line, jsonHeadings);
    if (heading != null) {
      flushBlock();
      currentHeading = heading;
      blockStartOffset = currentOffset;
    }

    if (blockBuffer.isEmpty) {
      blockStartOffset = currentOffset;
    }
    blockBuffer.writeln(line);
    currentOffset += lineLength;
  }

  flushBlock();
  return blocks;
}

/// 判断当前行是否为标题。
///
/// 优先使用 JSON paragraph_title 匹配（无需正则），
/// 回退到 ATX heading 检测。
String? _resolveHeading(String line, Set<String> jsonHeadings) {
  final atxMatch = _atxHeadingRegex.firstMatch(line);
  if (atxMatch != null) {
    final headingText = atxMatch.group(1)!.trim();
    // 有 JSON 时只认 paragraph_title 标记的标题
    if (jsonHeadings.isNotEmpty) {
      if (_matchesJsonHeading(headingText, jsonHeadings)) {
        return headingText;
      }
      // ATX heading 但不在 JSON 标题中 → 仍标记为段落标题
      return headingText;
    }
    return headingText;
  }
  return null;
}

/// 模糊匹配 JSON heading：去除编号前缀后比较
bool _matchesJsonHeading(String text, Set<String> jsonHeadings) {
  if (jsonHeadings.contains(text)) return true;
  // JSON 标题可能带编号前缀（如 "1. Introduction"），去除后比较
  final stripped = text.replaceFirst(
    RegExp(r'^(?:\d+(?:\.\d+)*|[ivxlcdm]+)\s*[:.)\-]?\s+', caseSensitive: false),
    '',
  );
  if (stripped != text && jsonHeadings.contains(stripped)) return true;
  // 反向：markdown 行无编号但 JSON 有
  for (final h in jsonHeadings) {
    final hStripped = h.replaceFirst(
      RegExp(r'^(?:\d+(?:\.\d+)*|[ivxlcdm]+)\s*[:.)\-]?\s+', caseSensitive: false),
      '',
    );
    if (hStripped == text) return true;
  }
  return false;
}

String _stripMarkdown(String text) {
  var result = text;
  result = result.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  result = result.replaceAll(RegExp(r'^[=-]{3,}\s*$', multiLine: true), '');
  result = result.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (m) => m.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (m) => m.group(1) ?? '',
  );
  result = result.replaceAll(RegExp(r'\*{1,3}([^*]+)\*{1,3}'), r'$1');
  result = result.replaceAll(RegExp(r'_{1,3}([^_]+)_{1,3}'), r'$1');
  result = result.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
  result = result.replaceAll(RegExp(r'<[^>]+>'), '');
  result = result.replaceAllMapped(
    RegExp(r'\$([^\$\n]+?)\$'),
    (m) => m.group(1) ?? '',
  );
  result = result.replaceAll(RegExp(r'\n+'), ' ');
  result = result.replaceAll(RegExp(r'\s{2,}'), ' ');
  return result.trim();
}
