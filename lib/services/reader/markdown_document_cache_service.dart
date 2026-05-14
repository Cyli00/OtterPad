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

/// Markdown 内容搜索结果。
class SearchResult {
  final String heading;
  final String plainText;
  final int charOffset;

  const SearchResult({
    required this.heading,
    required this.plainText,
    required this.charOffset,
  });
}

class MarkdownDocumentCacheService {
  MarkdownDocumentCacheService._();

  static final MarkdownDocumentCacheService instance =
      MarkdownDocumentCacheService._();

  static const _maxEntries = 4;

  final _contentCache = <String, String>{};
  final _searchSnapshotCache = <String, MarkdownSearchSnapshot>{};
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

  MarkdownSearchSnapshot getSearchSnapshot({
    required String cacheKey,
    required String markdownContent,
  }) {
    final cached = _readSearchSnapshotCache(cacheKey);
    if (cached != null) return cached;
    return _buildSearchSnapshotInternal(
      cacheKey: cacheKey,
      markdownContent: markdownContent,
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

  MarkdownSearchSnapshot _buildSearchSnapshotInternal({
    required String cacheKey,
    required String markdownContent,
  }) {
    final blocksData = _buildSearchBlocks(markdownContent);

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
}

// ─── LaTeX → Unicode 映射 ───

const _latexUnicode = <String, String>{
  // 希腊字母
  r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
  r'\epsilon': 'ε', r'\varepsilon': 'ε', r'\zeta': 'ζ', r'\eta': 'η',
  r'\theta': 'θ', r'\iota': 'ι', r'\kappa': 'κ', r'\lambda': 'λ',
  r'\mu': 'μ', r'\nu': 'ν', r'\xi': 'ξ', r'\pi': 'π',
  r'\rho': 'ρ', r'\sigma': 'σ', r'\tau': 'τ', r'\upsilon': 'υ',
  r'\phi': 'φ', r'\varphi': 'φ', r'\chi': 'χ', r'\psi': 'ψ', r'\omega': 'ω',
  r'\Gamma': 'Γ', r'\Delta': 'Δ', r'\Theta': 'Θ', r'\Lambda': 'Λ',
  r'\Xi': 'Ξ', r'\Pi': 'Π', r'\Sigma': 'Σ', r'\Phi': 'Φ',
  r'\Psi': 'Ψ', r'\Omega': 'Ω',
  // 运算符
  r'\pm': '±', r'\mp': '∓', r'\times': '×', r'\div': '÷', r'\cdot': '·',
  r'\approx': '≈', r'\sim': '∼', r'\simeq': '≃', r'\neq': '≠',
  r'\leq': '≤', r'\geq': '≥', r'\ll': '≪', r'\gg': '≫',
  r'\propto': '∝', r'\equiv': '≡', r'\cong': '≅',
  // 其他
  r'\infty': '∞', r'\partial': '∂', r'\nabla': '∇',
  r'\in': '∈', r'\notin': '∉', r'\subset': '⊂', r'\supset': '⊃',
  r'\cup': '∪', r'\cap': '∩', r'\forall': '∀', r'\exists': '∃',
  r'\rightarrow': '→', r'\leftarrow': '←', r'\Rightarrow': '⇒',
  r'\sum': '∑', r'\prod': '∏', r'\int': '∫',
};

// ─── 搜索块构建 ───

/// saveResult 已将 paragraph_title 归一化为 ##，直接匹配二级标题
final _h2Regex = RegExp(r'^\s{0,3}##\s+(.+?)(?:\s+#+\s*)?$');

List<Map<String, Object>> _buildSearchBlocks(String markdown) {
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

    final h2Match = _h2Regex.firstMatch(line);
    if (h2Match != null) {
      flushBlock();
      currentHeading = h2Match.group(1)!.trim();
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
  // 剥离 $ 定界符，将常见 LaTeX 命令转为 Unicode
  result = result.replaceAllMapped(
    RegExp(r'\$([^\$\n]+?)\$'),
    (m) => m.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'\\text\{([^}]+)\}'),
    (m) => m.group(1)!,
  );
  for (final e in _latexUnicode.entries) {
    result = result.replaceAll(e.key, e.value);
  }
  result = result.replaceAll(RegExp(r'\n+'), ' ');
  result = result.replaceAll(RegExp(r'\s{2,}'), ' ');
  return result.trim();
}
