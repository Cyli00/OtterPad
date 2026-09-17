import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import 'document_structure.dart';
import 'figure_extract_service.dart';

class _SourceNode {
  final int start, end;
  final String type, value;
  const _SourceNode(this.start, this.end, this.type, this.value);
}

class FigureMarkdownResult {
  final String markdown;
  final Map<FigureManifestEntry, List<Map<String, dynamic>>> replacements;
  const FigureMarkdownResult(this.markdown, this.replacements);
}

/// 先建立底稿跨度与物理块的对应，再一次性应用无冲突的替换计划。
class FigureMarkdown {
  static const _furnitureLabels = {
    'header',
    'footer',
    'page_header',
    'page_footer',
    'number',
    'page_number',
    'header_image',
    'footer_image',
  };

  /// 无可信裁剪坐标时保留单个源图，不用虚构几何关系拼接多个资源。
  static void retainSourceFigures(
    DocumentStructure structure,
    Map<String, String> assets,
    List<FigureManifestEntry> entries,
  ) {
    final version = sha256
        .convert(utf8.encode(jsonEncode(structure.toJson())))
        .toString();
    for (final page in structure.pages) {
      for (final block in page.blocks.where(
        (b) => const ['image', 'chart', 'table'].contains(b.blockLabel),
      )) {
        if (entries.any(
          (e) => e.blocksOnPage(page.pageIndex).contains(block.blockId),
        )) {
          continue;
        }
        var source = block.sourceImage;
        if (source == null && block.rawBbox.length == 4) {
          final suffix = '_${block.rawBbox.join('_')}';
          final matches = assets.keys
              .where(
                (key) => p.posix
                    .basenameWithoutExtension(sourcePath(key))
                    .endsWith(suffix),
              )
              .toList();
          if (matches.isNotEmpty &&
              matches.map((key) => assets[key]).toSet().length == 1) {
            source = matches.first;
          }
        }
        if (source == null) continue;
        final path = asset(assets, source);
        if (path == null || !File(path).existsSync()) continue;
        final siblings = block.parentId == null
            ? <LayoutBlock>[]
            : page.blocks.where((b) => b.parentId == block.parentId).toList();
        final singleBody =
            siblings
                .where(
                  (b) =>
                      const ['image', 'chart', 'table'].contains(b.blockLabel),
                )
                .length ==
            1;
        final captions = singleBody
            ? siblings
                  .where(
                    (b) =>
                        b.blockLabel == 'figure_title' &&
                        FigureManifestEntry.isUsableCaption(b.blockContent),
                  )
                  .toList()
            : <LayoutBlock>[];
        final caption = captions.length == 1 ? captions.single : null;
        if (caption == null) continue;
        final notes = singleBody
            ? siblings.where((b) => b.blockLabel == 'vision_footnote').toList()
            : <LayoutBlock>[];
        final ids = [
          block.blockId,
          caption.blockId,
          ...notes.map((b) => b.blockId),
        ];
        entries.add(
          FigureManifestEntry(
            id: FigureManifestEntry.identity(page.pageIndex, ids),
            imagePath: path,
            captionText: caption.blockContent,
            pageIndex: page.pageIndex,
            blockIds: ids,
            kind: block.blockLabel == 'image' ? 'figure' : block.blockLabel,
            visualRegions: [
              FigureVisualRegion(
                pageIndex: page.pageIndex,
                bbox: const [],
                blockIds: ids,
                imagePath: path,
              ),
            ],
            sourceImageNames: [source],
            sourceVersion: version,
            assignment: 'confirmed',
            sourceRefs: [
              {
                'page_idx': page.pageIndex,
                'block_id': block.blockId,
                'path': source,
              },
            ],
            captionRefs: [
              FigureCaptionRef(
                pageIndex: page.pageIndex,
                text: caption.blockContent,
                blockId: caption.blockId,
              ),
            ],
            notes: notes.map((b) => b.blockContent).toList(),
            captionSource: CaptionSource.blockMatch.name,
            pairMethod: PairMethod.samePage.name,
          ),
        );
      }
    }
  }

  static String sourcePath(String path) {
    var value = path.replaceAll('\\', '/');
    try {
      value = Uri.decodeComponent(value);
    } on FormatException {
      // 不合法的百分号编码仍按原始路径定位，不能中断整篇导入。
    }
    return p.posix.normalize(value).replaceFirst(RegExp(r'^\./'), '');
  }

  static String? asset(Map<String, String> assets, String name) {
    final normalized = sourcePath(name);
    for (final entry in assets.entries) {
      if (sourcePath(entry.key) == normalized) return entry.value;
    }
    // 旧清单只有 basename；只在资源表内唯一且请求也为 basename 时兼容。
    if (normalized.contains('/')) return null;
    final matches = assets.entries
        .where((e) => p.posix.basename(sourcePath(e.key)) == normalized)
        .toList();
    return matches.length == 1 ? matches.single.value : null;
  }

  static String _text(String value) => (html.parseFragment(value).text ?? '')
      .replaceAll(RegExp(r'(?<=\w)-\s+(?=\w)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _tableKey(String value) {
    value = value.replaceAllMapped(
      RegExp(r'<eq>([\s\S]*?)</eq>'),
      (m) => ' \$${m[1]}\$ ',
    );
    final fragment = html.parseFragment(value);
    final cells = fragment.querySelectorAll('td,th');
    if (cells.isNotEmpty) {
      return cells.map((c) => _text(c.innerHtml)).join('\u001f');
    }
    final parsed = md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
    ).parseLines(value.split('\n'));
    final content = <String>[];
    void walk(md.Node node) {
      if (node is md.Element && (node.tag == 'td' || node.tag == 'th')) {
        content.add(_text(node.textContent));
      } else if (node is md.Element) {
        for (final child in node.children ?? <md.Node>[]) {
          walk(child);
        }
      }
    }

    for (final node in parsed) {
      walk(node);
    }
    return content.isEmpty ? _text(value) : content.join('\u001f');
  }

  static List<_SourceNode> _nodes(String raw) {
    final nodes = <_SourceNode>[];
    final fragment = html.parseFragment(raw, generateSpans: true);
    for (final table in fragment.querySelectorAll('table')) {
      final start = table.sourceSpan?.start.offset,
          end = table.endSourceSpan?.end.offset;
      if (start != null && end != null) {
        nodes.add(
          _SourceNode(
            start,
            end,
            'html_table',
            _tableKey(raw.substring(start, end)),
          ),
        );
      }
    }
    for (final image in fragment.querySelectorAll('img')) {
      final span = image.sourceSpan, source = image.attributes['src'];
      if (span != null && source != null) {
        nodes.add(
          _SourceNode(
            span.start.offset,
            span.end.offset,
            'image',
            sourcePath(source),
          ),
        );
      }
    }
    for (final match in RegExp(r'!\[(?:\\.|[^\]])*\]\(').allMatches(raw)) {
      var end = match.end, depth = 1;
      for (; end < raw.length; end++) {
        if (raw[end] == '\\') {
          end++;
          continue;
        }
        if (raw[end] == '(') depth++;
        if (raw[end] == ')') {
          depth--;
          if (depth == 0) break;
        }
      }
      if (depth != 0) continue;
      var source = raw.substring(match.end, end).trim();
      if (source.startsWith('<') && source.contains('>')) {
        source = source.substring(1, source.indexOf('>'));
      } else {
        source = source.replaceFirst(RegExp(r'\s+["\x27].*$'), '');
      }
      nodes.add(_SourceNode(match.start, end + 1, 'image', sourcePath(source)));
    }
    final lines = raw.split('\n');
    var offset = 0;
    String? fence;
    final fenced = <(int, int)>[];
    var fenceStart = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final marker = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line)?.group(1);
      if (marker != null) {
        if (fence == null) {
          fence = marker[0];
          fenceStart = offset;
        } else if (marker[0] == fence) {
          fenced.add((fenceStart, offset + line.length));
          fence = null;
        }
      }
      if (fence == null &&
          i + 1 < lines.length &&
          line.contains('|') &&
          RegExp(
            r'^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$',
          ).hasMatch(lines[i + 1])) {
        var j = i + 2;
        while (j < lines.length &&
            lines[j].trim().isNotEmpty &&
            lines[j].contains('|')) {
          j++;
        }
        final text = lines.sublist(i, j).join('\n');
        nodes.add(
          _SourceNode(
            offset,
            offset + text.length,
            'pipe_table',
            _tableKey(text),
          ),
        );
      }
      offset += line.length + 1;
    }
    if (fence != null) fenced.add((fenceStart, raw.length));
    nodes.removeWhere(
      (n) => fenced.any((f) => n.start >= f.$1 && n.start < f.$2),
    );
    nodes.addAll(fenced.map((f) => _SourceNode(f.$1, f.$2, 'protected', '')));
    nodes.sort((a, b) => a.start.compareTo(b.start));
    return nodes;
  }

  /// 比较用文本和原文偏移分开保存，格式差异不能导致整段正文被删除。
  static ({String text, List<int> offsets}) _indexedText(String value) {
    final text = StringBuffer(), offsets = <int>[];
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (RegExp(r'[\s*_\\]').hasMatch(c)) continue;
      if (c == '-' &&
          i > 0 &&
          i + 1 < value.length &&
          RegExp(r'\s').hasMatch(value[i + 1])) {
        continue;
      }
      text.write(c);
      offsets.add(i);
    }
    return (text: text.toString(), offsets: offsets);
  }

  static List<_SourceNode> _textSpans(String raw, String text) {
    final haystack = _indexedText(raw), needle = _indexedText(text).text;
    if (needle.isEmpty) return [];
    final result = <_SourceNode>[];
    for (
      var at = haystack.text.indexOf(needle);
      at >= 0;
      at = haystack.text.indexOf(needle, at + needle.length)
    ) {
      var start = haystack.offsets[at],
          end = haystack.offsets[at + needle.length - 1] + 1;
      // 一起消费题注外围的 Markdown 强调符，避免留下空强调节点。
      while (start > 0 && raw[start - 1] == '*') {
        start--;
      }
      while (end < raw.length && raw[end] == '*') {
        end++;
      }
      result.add(_SourceNode(start, end, 'caption', text));
    }
    return result;
  }

  /// 注记只能消费完整可见文本，不能命中正文词语、HTML 属性或留下空包装。
  static List<_SourceNode> _annotationSpans(
    String raw,
    String text,
    List<dom.Element> elements,
  ) {
    final key = _indexedText(_text(text)).text;
    if (key.isEmpty) return [];
    final result = <_SourceNode>[];
    for (final element in elements) {
      if (!const {
            'div',
            'p',
            'figcaption',
            'h1',
            'h2',
            'h3',
            'h4',
            'h5',
            'h6',
          }.contains(element.localName) ||
          _indexedText(element.text).text != key ||
          element.querySelector('img,table,pre,code') != null) {
        continue;
      }
      final start = element.sourceSpan?.start.offset;
      final end = element.endSourceSpan?.end.offset;
      if (start == null || end == null) continue;
      if (result.any((n) => n.start <= start && end <= n.end)) continue;
      var inCode = false;
      for (
        var parent = element.parent;
        parent != null;
        parent = parent.parent
      ) {
        if (const {'pre', 'code'}.contains(parent.localName)) inCode = true;
      }
      result.add(
        _SourceNode(start, end, inCode ? 'protected' : 'annotation', text),
      );
    }
    for (final match in _textSpans(raw, text)) {
      final lineStart = match.start == 0
          ? 0
          : raw.lastIndexOf('\n', match.start - 1) + 1;
      final newline = raw.indexOf('\n', match.end);
      final lineEnd = newline < 0 ? raw.length : newline;
      if (raw.substring(lineStart, match.start).trim().isNotEmpty ||
          raw.substring(match.end, lineEnd).trim().isNotEmpty) {
        continue;
      }
      if (elements.any((e) {
        final start = e.sourceSpan?.start.offset;
        final end = e.endSourceSpan?.end.offset ?? e.sourceSpan?.end.offset;
        return start != null &&
            end != null &&
            start < match.end &&
            match.start < end;
      })) {
        continue;
      }
      result.add(_SourceNode(match.start, match.end, 'annotation', text));
    }
    return result..sort((a, b) => a.start.compareTo(b.start));
  }

  static FigureMarkdownResult replace(
    String raw,
    List<FigureManifestEntry> entries, {
    required DocumentStructure structure,
    Map<String, String> assets = const {},
    int? pageIndex,
    Set<FigureManifestEntry>? emitted,
  }) {
    final nodes = _nodes(raw),
        plans = <FigureManifestEntry, Set<_SourceNode>>{};
    final annotationElements = html
        .parseFragment(raw, generateSpans: true)
        .querySelectorAll('*');
    final blocks = <({int page, LayoutBlock block})>[
      for (final page in structure.pages)
        if (pageIndex == null || pageIndex == page.pageIndex)
          for (final block in page.blocks) (page: page.pageIndex, block: block),
    ];
    final images = nodes.where((n) => n.type == 'image').toList();
    final protected = <_SourceNode>{};
    final service = FigureExtractService.instance;
    final captionsByPage = {
      if (service.isInitialized)
        for (final page in structure.pages)
          if (pageIndex == null || pageIndex == page.pageIndex)
            page.pageIndex: service.collectCaptionCandidatesPublic(
              page.blocks,
              page.markdown,
              page.pageIndex,
            ),
    };
    final captionBlocks = <(int, String)>{
      for (final entry in entries)
        for (final ref in entry.captionRefs)
          if (ref.blockId != null) (ref.pageIndex, ref.blockId!),
      for (final captions in captionsByPage.values)
        for (final caption in captions)
          for (final ref in caption.sourceRefs)
            if (ref.blockId != null) (ref.pageIndex, ref.blockId!),
    };

    int? missingCaptionOffset(List<FigureCaptionRef> refs) {
      final ref = refs.firstOrNull;
      if (ref == null || (pageIndex != null && ref.pageIndex != pageIndex)) {
        return null;
      }
      // 已存在但位于代码或图片节点中的文本不是“源 Markdown 遗漏”。
      if (refs.any((r) => _textSpans(raw, r.text).isNotEmpty)) return null;
      final index = blocks.indexWhere(
        (b) => b.page == ref.pageIndex && b.block.blockId == ref.blockId,
      );
      if (index < 0) return null;
      // 只按源块阅读顺序寻找可见邻居，不把题注放回图片页或按图号猜位置。
      for (var distance = 1; distance < blocks.length; distance++) {
        for (final i in [index + distance, index - distance]) {
          if (i < 0 || i >= blocks.length) continue;
          final neighbor = blocks[i];
          if (_furnitureLabels.contains(neighbor.block.blockLabel) ||
              captionBlocks.contains((neighbor.page, neighbor.block.blockId))) {
            continue;
          }
          final matches = _textSpans(raw, neighbor.block.blockContent)
              .where(
                (m) => !nodes.any((n) => n.start < m.end && m.start < n.end),
              )
              .toList();
          if (matches.length == 1) {
            return i > index ? matches.single.start : matches.single.end;
          }
        }
      }
      return pageIndex != null || structure.pages.length == 1
          ? raw.length
          : null;
    }

    List<_SourceNode> imageMatches(LayoutBlock block) {
      if (block.sourceImage != null) {
        final path = sourcePath(block.sourceImage!);
        final exact = images.where((n) => n.value == path).toList();
        if (exact.isNotEmpty || path.contains('/')) return exact;
        final candidates = images
            .where((n) => p.posix.basename(n.value) == path)
            .toList();
        return candidates.map((n) => n.value).toSet().length == 1
            ? candidates
            : [];
      }
      if (block.rawBbox.length != 4) return [];
      final suffix = '_${block.rawBbox.join('_')}';
      return images
          .where(
            (n) => p.posix.basenameWithoutExtension(n.value).endsWith(suffix),
          )
          .toList();
    }

    for (final entry in entries.where((e) => e.isDisplayFigure)) {
      final owned = <_SourceNode>{};
      final sourceBlocks = blocks
          .where((b) => entry.blocksOnPage(b.page).contains(b.block.blockId))
          .toList();
      for (final source in sourceBlocks) {
        final block = source.block;
        if (!const ['image', 'chart', 'table'].contains(block.blockLabel)) {
          continue;
        }
        final matching = imageMatches(block);
        if (matching.length == 1) {
          owned.add(matching.single);
        } else if (matching.length > 1) {
          final peers = blocks
              .where(
                (b) =>
                    imageMatches(b.block).map((n) => n.start).join(',') ==
                    matching.map((n) => n.start).join(','),
              )
              .toList();
          if (peers.length == matching.length) {
            owned.add(matching[peers.indexOf(source)]);
          }
        }
        if (block.blockLabel == 'table' &&
            block.blockContent.trim().isNotEmpty) {
          final key = _tableKey(block.blockContent);
          final tables = nodes
              .where((n) => n.type.endsWith('_table') && n.value == key)
              .toList();
          final peers = blocks
              .where(
                (b) =>
                    b.block.blockLabel == 'table' &&
                    _tableKey(b.block.blockContent) == key,
              )
              .toList();
          if (tables.length == 1 && peers.length == 1) {
            owned.add(tables.single);
          } else if (peers.length == 1 &&
              tables.length == 2 &&
              tables.map((n) => n.type).toSet().length == 2 &&
              raw
                  .substring(tables.first.end, tables.last.start)
                  .trim()
                  .isEmpty) {
            owned.addAll(tables);
          } else if (tables.isNotEmpty) {
            final linked = tables
                .where(
                  (t) => owned.any((n) => n.start >= t.start && n.end <= t.end),
                )
                .toList();
            if (linked.length == 1) owned.add(linked.single);
          }
        }
      }
      // 旧格式缺结构时只消费唯一资源引用，重复路径不推断为同一次出现。
      if (sourceBlocks.isEmpty) {
        for (final path in entry.sourceImageNames ?? <String>[]) {
          final matches = images
              .where(
                (n) =>
                    n.value == sourcePath(path) ||
                    (!path.contains('/') && p.posix.basename(n.value) == path),
              )
              .toList();
          final owners = entries
              .where((e) => (e.sourceImageNames ?? []).contains(path))
              .length;
          if (matches.length == 1 && owners == 1) owned.add(matches.single);
        }
      }
      if (!File(entry.imagePath).existsSync()) {
        // 已有题注但裁图资源缺失时保留原始有题注视觉，不把资源错误当作装饰图。
        protected.addAll(owned);
        continue;
      }
      final texts = <String>{
        if (entry.captionRefs.isEmpty) entry.captionText,
        for (final ref in entry.captionRefs)
          if (pageIndex == null || ref.pageIndex == pageIndex) ref.text,
      };
      for (final source in sourceBlocks) {
        final block = source.block;
        if (captionBlocks.contains((source.page, block.blockId)) ||
            (service.isInitialized &&
                service.isMainCaption(block.blockContent)) ||
            !(service.isSubfigureLabelBlock(block) ||
                entry.sourceRefs.any(
                  (r) =>
                      r['page_idx'] == source.page &&
                      r['block_id'] == block.blockId &&
                      r['label'] == 'figure_annotation',
                ))) {
          continue;
        }
        final matches = _annotationSpans(
          raw,
          block.blockContent,
          annotationElements,
        );
        final key = _indexedText(_text(block.blockContent)).text;
        final peers = blocks
            .where((b) => _indexedText(_text(b.block.blockContent)).text == key)
            .toList();
        // 代码和未归属的同文块也参与计数；数量不一致时不猜测删除目标。
        final owner = peers.indexOf(source);
        if (owner < 0 || matches.length != peers.length) continue;
        final match = matches[owner];
        if (match.type != 'protected' &&
            !nodes.any((n) => n.start < match.end && match.start < n.end)) {
          owned.add(match);
        }
      }
      var ambiguousCaption = false;
      for (final text in texts.where((t) => t.trim().isNotEmpty)) {
        final matches = _textSpans(raw, text)
            .where((m) => !nodes.any((n) => n.start < m.end && m.start < n.end))
            .toList();
        if (matches.length == 1) {
          owned.add(matches.single);
        } else if (matches.length > 1) {
          // 相同文字的两次出现只能由各自源块顺序消歧，不能按图号去重。
          final peers = blocks
              .where(
                (b) =>
                    _indexedText(b.block.blockContent).text ==
                    _indexedText(text).text,
              )
              .toList();
          final owner = peers.indexWhere(
            (b) => entry.captionRefs.any(
              (r) => r.pageIndex == b.page && r.blockId == b.block.blockId,
            ),
          );
          if (peers.length == matches.length && owner >= 0) {
            owned.add(matches[owner]);
          } else if (entry.captionRefs.any((r) => r.text == text) ||
              text == entry.captionText) {
            ambiguousCaption = true;
          }
        }
      }
      if (ambiguousCaption) continue;
      if (!owned.any((n) => n.type == 'caption')) {
        final offset = missingCaptionOffset(entry.captionRefs);
        if (offset != null) {
          owned.add(
            _SourceNode(offset, offset, 'caption_insert', entry.captionText),
          );
        }
      }
      if (owned.isNotEmpty) plans[entry] = owned;
    }
    final conflicts = <FigureManifestEntry>{};
    for (final a in plans.entries) {
      for (final b in plans.entries) {
        if (identical(a.key, b.key)) continue;
        if (a.value.any(
          (x) => b.value.any((y) => x.start < y.end && y.start < x.end),
        )) {
          conflicts.add(a.key);
          conflicts.add(b.key);
        }
      }
    }
    for (final conflict in conflicts) {
      plans.remove(conflict);
    }
    final replacements = <(int, int, String)>[],
        refs = <FigureManifestEntry, List<Map<String, dynamic>>>{};
    final version = sha256.convert(utf8.encode(raw)).toString();
    final outputs = emitted ?? <FigureManifestEntry>{};
    for (final plan in plans.entries) {
      final spans = plan.value.toList()
        ..sort(
          (a, b) => a.start != b.start
              ? a.start.compareTo(b.start)
              : b.end.compareTo(a.end),
        );
      final merged = <(int, int)>[];
      for (final node in spans) {
        if (merged.isNotEmpty && node.start < merged.last.$2) {
          final last = merged.removeLast();
          merged.add((last.$1, mathMax(last.$2, node.end)));
        } else {
          merged.add((node.start, node.end));
        }
      }
      final entry = plan.key;
      final caption = entry.captionText
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('[', r'\[')
          .replaceAll(']', r'\]');
      final tag =
          '\n${entry.markdownAnchor}\n\n![fig:$caption](${Uri.file(entry.imagePath)})\n';
      final captionSpans = spans
          .where((s) => s.type.startsWith('caption'))
          .toList();
      final onCaptionPage =
          pageIndex == null ||
          entry.captionRefs.isEmpty ||
          entry.captionRefs.first.pageIndex == pageIndex;
      final anchor =
          captionSpans.firstOrNull?.start ??
          (onCaptionPage ? spans.firstOrNull?.start : null);
      final canEmit = onCaptionPage && anchor != null;
      final first = canEmit && outputs.add(entry);
      for (final span in merged) {
        replacements.add((
          span.$1,
          span.$2,
          first &&
                  span.$1 <= anchor &&
                  (anchor < span.$2 || span.$1 == span.$2 && anchor == span.$1)
              ? tag
              : '',
        ));
      }
      refs[entry] = [
        for (final span in merged)
          {
            'raw_version': version,
            'page_idx': ?pageIndex,
            'start': span.$1,
            'end': span.$2,
          },
      ];
    }
    // 未配到视觉的题注仍独立成段；从源块子范围定位，不删除正文前后缀。
    if (service.isInitialized) {
      for (final page in structure.pages) {
        if (pageIndex != null && page.pageIndex != pageIndex) continue;
        for (final caption
            in captionsByPage[page.pageIndex] ?? <CaptionCandidateInfo>[]) {
          // 已绑定题注由实体统一渲染，不能再以无图题注重复补入。
          if (entries.any(
            (e) =>
                e.isDisplayFigure &&
                File(e.imagePath).existsSync() &&
                e.captionRefs.any(
                  (r) => caption.sourceRefs.any(
                    (c) =>
                        c.pageIndex == r.pageIndex &&
                        c.blockId == r.blockId &&
                        (c.start ?? 0) == (r.start ?? 0),
                  ),
                ),
          )) {
            continue;
          }
          final spans = <_SourceNode>[];
          for (final text
              in caption.sourceRefs.isEmpty
                  ? [caption.text]
                  : caption.sourceRefs.map((r) => r.text)) {
            final matches = _textSpans(raw, text)
                .where(
                  (m) => !nodes.any((n) => n.start < m.end && m.start < n.end),
                )
                .toList();
            if (matches.length == 1) spans.add(matches.single);
          }
          if (spans.isEmpty) {
            final offset = missingCaptionOffset(caption.sourceRefs);
            if (offset != null) {
              spans.add(
                _SourceNode(offset, offset, 'caption_insert', caption.text),
              );
            }
          }
          if (spans.isEmpty ||
              spans.any(
                (s) => replacements.any((r) => r.$1 < s.end && s.start < r.$2),
              )) {
            continue;
          }
          spans.sort((a, b) => a.start.compareTo(b.start));
          final id = FigureManifestEntry.identity(page.pageIndex, [
            caption.blockId ??
                'line:${caption.sourceRefs.firstOrNull?.lineIndex ?? caption.text}',
            '${caption.sourceRefs.firstOrNull?.start ?? 0}',
          ]);
          for (var i = 0; i < spans.length; i++) {
            final span = spans[i];
            replacements.add((
              span.start,
              span.end,
              i == 0
                  ? '\n\n<!-- otter-caption:$id -->\n\n${caption.text}\n\n'
                  : '',
            ));
          }
        }
      }
    }
    // 展示层才移除普通页眉页脚；确认题注及其续行不受原始标签影响。
    // 限定整行，避免删除正文中与期刊名或页码相同的文字。
    for (final source in blocks) {
      if (!_furnitureLabels.contains(source.block.blockLabel) ||
          captionBlocks.contains((source.page, source.block.blockId))) {
        continue;
      }
      for (final span in _textSpans(raw, source.block.blockContent)) {
        final start =
            raw.lastIndexOf('\n', span.start == 0 ? 0 : span.start - 1) + 1;
        final next = raw.indexOf('\n', span.end);
        final end = next < 0 ? raw.length : next;
        if (!RegExp(r'^[\s#*_]*$').hasMatch(raw.substring(start, span.start)) ||
            !RegExp(r'^[\s*_]*$').hasMatch(raw.substring(span.end, end)) ||
            nodes.any((n) => n.start < span.end && span.start < n.end) ||
            replacements.any((r) => r.$1 < end && start < r.$2)) {
          continue;
        }
        replacements.add((start, end, ''));
      }
    }
    // 原始视觉只作为匹配素材；未被确认题注认领的图、表不回流到阅读文件。
    for (final node in nodes) {
      if (node.type == 'protected') continue;
      if (protected.any((n) => n.start <= node.start && n.end >= node.end)) {
        continue;
      }
      if (replacements.any((r) => r.$1 < node.end && node.start < r.$2)) {
        continue;
      }
      replacements.add((node.start, node.end, ''));
    }
    // 同一边界先插入再删除；多个零宽插入保持源计划顺序。
    final ordered = replacements.indexed.toList()
      ..sort((a, b) {
        final start = a.$2.$1.compareTo(b.$2.$1);
        if (start != 0) return start;
        final end = a.$2.$2.compareTo(b.$2.$2);
        return end != 0 ? end : a.$1.compareTo(b.$1);
      });
    final out = StringBuffer();
    var cursor = 0;
    for (final (_, r) in ordered) {
      if (r.$1 < cursor) continue;
      out.write(raw.substring(cursor, r.$1));
      out.write(r.$3);
      cursor = r.$2;
    }
    out.write(raw.substring(cursor));
    return FigureMarkdownResult(out.toString(), refs);
  }

  static int mathMax(int a, int b) => a > b ? a : b;
}
