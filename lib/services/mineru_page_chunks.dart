import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 一次 MinerU 请求里的页码范围（1-based，含首尾）。
///
/// 精准解析单文件最多 200 页。更长的 PDF 拆成多段 `page_ranges`，
/// 每段的结果 ZIP 都从 `page_idx = 0` 重新编号，且都叫 `full.md`。
class MinerUPageChunk {
  final int index;
  final int startPage;
  final int endPage;

  /// 不超过单次页数上限时整份上传，不传 `page_ranges`。
  final bool wholeFile;

  const MinerUPageChunk({
    required this.index,
    required this.startPage,
    required this.endPage,
    required this.wholeFile,
  });

  /// `null` 表示不传 `page_ranges`（整份文件）。
  String? get pageRanges => wholeFile ? null : '$startPage-$endPage';

  String get label => pageRanges ?? 'all';

  int get pageCount =>
      startPage > 0 && endPage >= startPage ? endPage - startPage + 1 : 0;
}

/// [pageCount] 未知、非正、或不超过 [maxPages] 时返回一个整文件分片。
List<MinerUPageChunk> planMinerUPageChunks(
  int? pageCount, {
  int maxPages = 200,
}) {
  if (maxPages < 1) {
    throw ArgumentError.value(maxPages, 'maxPages');
  }
  if (pageCount == null || pageCount <= maxPages) {
    final known = pageCount != null && pageCount > 0;
    return [
      MinerUPageChunk(
        index: 0,
        startPage: known ? 1 : 0,
        endPage: known ? pageCount : 0,
        wholeFile: true,
      ),
    ];
  }
  final chunks = <MinerUPageChunk>[];
  var start = 1;
  var index = 0;
  while (start <= pageCount) {
    final end = math.min(start + maxPages - 1, pageCount);
    chunks.add(
      MinerUPageChunk(
        index: index,
        startPage: start,
        endPage: end,
        wholeFile: false,
      ),
    );
    start = end + 1;
    index++;
  }
  return chunks;
}

/// MinerU 与 PaddleOCR 共用的页段计划。两个服务商都按「每段从 0 重新编号」返回。
typedef ExtractPageChunk = MinerUPageChunk;

List<ExtractPageChunk> planExtractPageChunks(
  int? pageCount, {
  int maxPages = 200,
}) => planMinerUPageChunks(pageCount, maxPages: maxPages);

/// 按页码顺序拼接各分片 ZIP。
///
/// 不能按文件名覆盖：每段都有 `full.md` / `images/`，后写的一段会抹掉前一段。
/// 700 页按 200 页拆开时最后一段从第 601 页开始，覆盖之后阅读版就只剩这一段。
/// 分片可以乱序传入，结果仍按 [MinerUPageChunk.index] 排列。
Uint8List mergeMinerUResultZips(
  List<({MinerUPageChunk chunk, Uint8List bytes})> parts,
) {
  if (parts.isEmpty) {
    throw const FormatException('MinerU 没有可合并的分片');
  }
  final ordered = [...parts]
    ..sort((a, b) => a.chunk.index.compareTo(b.chunk.index));
  final seen = <int>{};
  for (final part in ordered) {
    if (!seen.add(part.chunk.index)) {
      throw FormatException('MinerU 分片序号重复: ${part.chunk.label}');
    }
  }

  final parsed = <_ChunkBody>[];
  for (final part in ordered) {
    parsed.add(_readChunk(part.chunk, part.bytes));
  }
  final missingMd = parsed.where((c) => c.markdown == null);
  if (missingMd.isNotEmpty) {
    throw FormatException(
      'MinerU 分片 ${missingMd.first.chunk.label} 缺少 full.md',
    );
  }
  final missingStructure = parsed.where(
    (c) => c.layout == null && c.v2 == null,
  );
  if (missingStructure.isNotEmpty) {
    throw FormatException(
      'MinerU 分片 ${missingStructure.first.chunk.label} 缺少结构化结果',
    );
  }
  final someLayout = parsed.any((c) => c.layout != null);
  final everyLayout = parsed.every((c) => c.layout != null);
  if (someLayout && !everyLayout) {
    final gap = parsed.firstWhere((c) => c.layout == null);
    throw FormatException('MinerU 分片 ${gap.chunk.label} 缺少 layout');
  }

  final stored = <String, Uint8List>{};
  final markdown = StringBuffer();
  final layoutPages = <Map<String, dynamic>>[];
  Map<String, dynamic>? layoutShell;
  final v2Pages = <dynamic>[];
  final everyV2 = parsed.every((c) => c.v2 != null);

  for (final chunk in parsed) {
    final renames = _storeImages(stored, chunk.images, chunk.chunk.index);
    final section = _applyRenames(chunk.markdown!, renames).trimRight();
    if (markdown.isNotEmpty) markdown.write('\n\n');
    markdown.write(section);
    if (chunk.layout != null) {
      layoutShell ??= Map<String, dynamic>.from(chunk.layout!);
      final info = chunk.layout!['pdf_info'];
      final pages = info is List ? info : const [];
      final globalStart = chunk.chunk.startPage > 0
          ? chunk.chunk.startPage - 1
          : layoutPages.length;
      final span = chunk.chunk.pageCount > 0
          ? chunk.chunk.pageCount
          : pages.length;
      for (var local = 0; local < pages.length; local++) {
        final raw = pages[local];
        if (raw is! Map) continue;
        final page = Map<String, dynamic>.from(
          _rewriteJson(raw, renames)! as Map,
        );
        page['page_idx'] = _globalPageIndex(
          declared: (raw['page_idx'] as num?)?.toInt(),
          local: local,
          globalStart: globalStart,
          span: span,
        );
        layoutPages.add(page);
      }
    }
    if (everyV2) {
      v2Pages.addAll(_rewriteJson(chunk.v2, renames)! as List);
    }
  }

  final archive = Archive()
    ..add(ArchiveFile.string('full.md', markdown.toString()));
  if (layoutShell != null) {
    layoutShell['pdf_info'] = layoutPages;
    archive.add(ArchiveFile.string('layout.json', jsonEncode(layoutShell)));
  }
  if (everyV2) {
    archive.add(
      ArchiveFile.string('merged_content_list_v2.json', jsonEncode(v2Pages)),
    );
  }
  final names = stored.keys.toList()..sort();
  for (final name in names) {
    archive.add(ArchiveFile.bytes(name, stored[name]!));
  }
  return ZipEncoder().encodeBytes(archive);
}

int _globalPageIndex({
  required int? declared,
  required int local,
  required int globalStart,
  required int span,
}) {
  // 第一段的 page_idx 从 0 起，和全局页码重合；后面的段若也从 0 起，
  // 必须加上该段在原文中的起点，否则 601 页以后的内容会写进前面的页号。
  if (declared != null &&
      declared >= globalStart &&
      declared < globalStart + span) {
    return declared;
  }
  return globalStart + local;
}

Map<String, String> _storeImages(
  Map<String, Uint8List> stored,
  Map<String, Uint8List> images,
  int chunkIndex,
) {
  final renames = <String, String>{};
  for (final entry in images.entries) {
    final path = entry.key;
    final existing = stored[path];
    if (existing == null) {
      stored[path] = entry.value;
      continue;
    }
    if (_bytesEqual(existing, entry.value)) continue;
    final base = path.split('/').last;
    var renamed = 'images/c${chunkIndex}_$base';
    var n = 2;
    while (stored.containsKey(renamed) &&
        !_bytesEqual(stored[renamed]!, entry.value)) {
      renamed = 'images/c${chunkIndex}_${n}_$base';
      n++;
    }
    stored[renamed] = entry.value;
    renames[path] = renamed;
  }
  return renames;
}

String _applyRenames(String input, Map<String, String> renames) {
  if (renames.isEmpty) return input;
  var out = input;
  final keys = renames.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    out = out.replaceAll(key, renames[key]!);
  }
  return out;
}

Object? _rewriteJson(Object? node, Map<String, String> renames) {
  if (renames.isEmpty || node == null) return node;
  if (node is String) return renames[node] ?? node;
  if (node is List) {
    return [for (final item in node) _rewriteJson(item, renames)];
  }
  if (node is Map) {
    return {
      for (final entry in node.entries)
        entry.key.toString(): _rewriteJson(entry.value, renames),
    };
  }
  return node;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _ChunkBody {
  final MinerUPageChunk chunk;
  final String? markdown;
  final Map<String, dynamic>? layout;
  final List<dynamic>? v2;
  final Map<String, Uint8List> images;
  const _ChunkBody({
    required this.chunk,
    required this.markdown,
    required this.layout,
    required this.v2,
    required this.images,
  });
}

_ChunkBody _readChunk(MinerUPageChunk chunk, Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String? markdownName;
  for (final file in archive.files.where((f) => f.isFile)) {
    final name = file.name.replaceAll('\\', '/');
    if (name.split('/').last != 'full.md' || name.contains('..')) continue;
    if (markdownName == null || name.length < markdownName.length) {
      markdownName = name;
    }
  }
  if (markdownName == null) {
    return _ChunkBody(
      chunk: chunk,
      markdown: null,
      layout: null,
      v2: null,
      images: const {},
    );
  }
  final slash = markdownName.lastIndexOf('/');
  final root = slash < 0 ? '' : markdownName.substring(0, slash + 1);
  String? markdown;
  Map<String, dynamic>? layout;
  Map<String, dynamic>? middle;
  List<dynamic>? v2;
  final images = <String, Uint8List>{};
  for (final file in archive.files.where((f) => f.isFile)) {
    final name = file.name.replaceAll('\\', '/');
    if (!name.startsWith(root) || name.contains('..')) continue;
    final rel = name.substring(root.length);
    if (rel == 'full.md') {
      markdown = utf8.decode(file.content);
    } else if (rel == 'layout.json') {
      final data = jsonDecode(utf8.decode(file.content));
      if (data is Map<String, dynamic>) layout = data;
    } else if (!rel.contains('/') && rel.endsWith('_middle.json')) {
      final data = jsonDecode(utf8.decode(file.content));
      if (data is Map<String, dynamic>) middle = data;
    } else if (!rel.contains('/') && rel.endsWith('_content_list_v2.json')) {
      final data = jsonDecode(utf8.decode(file.content));
      if (data is List) v2 = data;
    } else if (rel.startsWith('images/') && !rel.endsWith('/')) {
      images[rel] = Uint8List.fromList(file.content);
    }
  }
  return _ChunkBody(
    chunk: chunk,
    markdown: markdown,
    layout: layout ?? middle,
    v2: v2,
    images: images,
  );
}
