import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'search_heading_pattern_service.dart';

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
  }) {
    unawaited(
      getSearchSnapshot(
        cacheKey: cacheKey,
        markdownContent: markdownContent,
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
    final content = await _loadMarkdownDocumentMain(
      mdPath: mdPath,
      title: title,
    );
    _writeContentCache(key, content);
    return content;
  }

  Future<MarkdownSearchSnapshot> _buildSearchSnapshotInternal({
    required String cacheKey,
    required String markdownContent,
  }) async {
    final patternConfig = await SearchHeadingPatternService.load();
    final configData = _serializePatternConfig(patternConfig);
    final blocksData = _buildSearchSnapshotMain(markdownContent, configData);

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

  static Future<String> _loadMarkdownDocumentMain({
    required String mdPath,
    required String title,
  }) async {
    return await File(mdPath).readAsString();
  }

  static List<Map<String, Object>> _buildSearchSnapshotMain(
    String markdownContent,
    Map<String, Object> configData,
  ) {
    return _buildSearchBlocks(markdownContent, configData);
  }

  static Map<String, Object> _serializePatternConfig(
    SearchHeadingPatternConfig config,
  ) {
    return {
      'atxHeadingPattern': config.atxHeadingPattern.pattern,
      'setextUnderlinePattern': config.setextUnderlinePattern.pattern,
      'numberingPrefixPattern': config.numberingPrefixPattern.pattern,
      'headingPatterns': config.headingPatterns
          .map(
            (entry) => {
              'display': entry.display,
              'pattern': entry.pattern.pattern,
              'caseSensitive': entry.pattern.isCaseSensitive,
            },
          )
          .toList(growable: false),
      'resetPatterns': config.resetPatterns
          .map((pattern) => pattern.pattern)
          .toList(growable: false),
    };
  }

}

List<Map<String, Object>> _buildSearchBlocks(
  String markdown,
  Map<String, Object> configData,
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

    final sectionHeading = _resolveSectionHeading(
      lines: lines,
      index: i,
      configData: configData,
    );
    if (sectionHeading != null) {
      flushBlock();
      currentHeading = sectionHeading;
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

String? _resolveSectionHeading({
  required List<String> lines,
  required int index,
  required Map<String, Object> configData,
}) {
  final line = lines[index];
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  final atxHeadingPattern = RegExp(configData['atxHeadingPattern'] as String);
  final setextUnderlinePattern =
      RegExp(configData['setextUnderlinePattern'] as String);
  final numberingPrefixPattern = RegExp(
    configData['numberingPrefixPattern'] as String,
    caseSensitive: false,
  );
  final headingPatterns =
      (configData['headingPatterns'] as List).cast<Map>().map((entry) {
    return (
      display: entry['display'] as String,
      pattern: RegExp(
        entry['pattern'] as String,
        caseSensitive: entry['caseSensitive'] as bool? ?? false,
      ),
    );
  }).toList(growable: false);
  final resetPatterns = (configData['resetPatterns'] as List)
      .cast<String>()
      .map((pattern) => RegExp(pattern, caseSensitive: false))
      .toList(growable: false);

  final candidates = <String>{};
  final atxHeading = atxHeadingPattern.firstMatch(line);
  if (atxHeading != null) {
    candidates.add(atxHeading.group(1)!.trim());
  }

  final nextLine = index + 1 < lines.length ? lines[index + 1].trim() : null;
  if (nextLine != null && setextUnderlinePattern.hasMatch(nextLine)) {
    candidates.add(trimmed);
  }

  if (_canBeStandaloneSectionHeading(trimmed)) {
    candidates.add(trimmed);
  }

  for (final candidate in candidates) {
    final normalized = _normalizeSectionCandidate(
      candidate,
      numberingPrefixPattern,
    );
    if (normalized.isEmpty) continue;

    for (final pattern in headingPatterns) {
      if (pattern.pattern.hasMatch(normalized)) {
        return pattern.display;
      }
    }

    if (resetPatterns.any((pattern) => pattern.hasMatch(normalized))) {
      return '';
    }
  }

  return null;
}

bool _canBeStandaloneSectionHeading(String text) {
  if (text.length > 80) return false;
  return !text.contains(RegExp(r'[.!?]'));
}

String _normalizeSectionCandidate(String raw, RegExp numberingPrefixPattern) {
  var text = raw.trim();
  text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*'), '');
  text = text.replaceAll(RegExp(r'\s*#*\s*$'), '');
  text = text.replaceAll(RegExp(r'^(?:\*\*?|__?)\s*'), '');
  text = text.replaceAll(RegExp(r'\s*(?:\*\*?|__?)$'), '');
  text = text.replaceAll(RegExp(r'^`+|`+$'), '');
  text = text.replaceAll(numberingPrefixPattern, '');
  text = text.replaceAll(RegExp(r'\s*[:.-]\s*$'), '');
  text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
  return text.trim();
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
