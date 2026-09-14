import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../utils/doc_paths.dart';
import '../core/l10n.dart';
import '../data/models/ocr/doc_extract_config.dart';
import '../router/app_router.dart';
import '../utils/markdown_preprocessor.dart';
import 'document_structure.dart';
import 'extraction_artifacts.dart';
import 'figure_extract_service.dart';
import 'pdf_process_lock.dart';
import 'pdf_caption_recovery.dart';

class MinerUConversionResult {
  final String mdPath;
  final String processedMarkdown;
  final int pageCount;
  const MinerUConversionResult({
    required this.mdPath,
    required this.processedMarkdown,
    required this.pageCount,
  });
}

/// Provider adaptation and source-bound replacement. Geometry and figure
/// ownership are shared with Paddle in FigureExtractService.
class MinerUResultConverter {
  MinerUResultConverter._();
  static final instance = MinerUResultConverter._();

  /// 服务层拿不到 BuildContext，按项目约定经 `rootNavigatorKey` 取 l10n；
  /// 取不到时（启动早期 / 测试）回落中文兜底串。
  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  static bool isMinerUExtractJson(String content) {
    try {
      final json = jsonDecode(content);
      return json is Map && json['_source'] == 'mineru';
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isMinerUDocument(String pdfPath) async {
    final file = File(DocPaths.json(pdfPath));
    return await file.exists() &&
        isMinerUExtractJson(await file.readAsString());
  }

  Future<MinerUConversionResult> convert({
    required String pdfPath,
    required File zipFile,
    String? title,
    CancelToken? cancelToken,
  }) async {
    final previous =
        await FigureExtractService.loadManifest(pdfPath) ??
        const <FigureManifestEntry>[];
    Directory? generation;
    var published = false;
    try {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      String? raw;
      List<dynamic>? v2;
      Map<String, dynamic>? layout;
      final images = <String, Uint8List>{};
      for (final file in archive.files.where((f) => f.isFile)) {
        final name = file.name.replaceAll('\\', '/');
        if (name == 'full.md') raw = utf8.decode(file.content);
        if (name.endsWith('_content_list_v2.json')) {
          v2 = jsonDecode(utf8.decode(file.content)) as List;
        }
        if (name == 'layout.json' || name.endsWith('_middle.json')) {
          final data = jsonDecode(utf8.decode(file.content));
          if (data is Map<String, dynamic> && data['pdf_info'] is List) {
            layout = data;
          }
        }
        if (name.startsWith('images/')) images[p.basename(name)] = file.content;
      }
      if (raw == null || (v2 == null && layout == null)) {
        throw FormatException(
          _l10n?.mineruErrResultPackageIncomplete ??
              'MinerU 结果包缺少 full.md 或结构化结果',
        );
      }
      final root = Directory(DocPaths.figuresDir(pdfPath));
      await root.create(recursive: true);
      generation = await createFigureGeneration(root.path);
      final assets = <String, String>{};
      for (final image in images.entries) {
        final path = p.join(generation.path, image.key);
        await File(path).writeAsBytes(image.value, flush: true);
        assets[image.key] = path;
      }
      var structure = layout != null
          ? DocumentStructure.fromMinerULayout(layout)
          : DocumentStructure.fromMinerUV2(
              v2!,
              pageSizes: await _pageSizes(pdfPath),
            );
      structure = await PdfCaptionRecovery.recover(structure, pdfPath);
      final tableSources = <String?>[];
      for (final page in v2 ?? const []) {
        for (final block in (page as List).whereType<Map>()) {
          if (block['type'] != 'table') continue;
          final source =
              ((block['content'] as Map?)?['image_source'] as Map?)?['path']
                  as String?;
          tableSources.add(source == null ? null : p.basename(source));
        }
      }
      if (v2 == null) {
        for (final page in structure.pages) {
          for (final block in page.blocks.where(
            (b) => b.blockLabel == 'table',
          )) {
            final source = block.sourceImage;
            tableSources.add(source == null ? null : p.basename(source));
          }
        }
      }
      final manifest = await _extract(
        structure,
        pdfPath,
        generation.path,
        assets,
      );
      final processed = buildReaderMarkdown(
        raw,
        manifest,
        assets: assets,
        tableSources: tableSources,
        structure: structure,
        title: title,
      );
      manifest.removeWhere(
        (e) => e.isDisplayFigure && !processed.contains(e.markdownAnchor),
      );
      final json = structure.toJson(source: 'mineru')
        ..addAll({
          '_mineru_table_sources': tableSources,
          '_mineru_assets': assets.map(
            (name, path) => MapEntry(
              name,
              p.relative(path, from: DocPaths.docDir(pdfPath)),
            ),
          ),
        });
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      await ExtractionArtifacts.publish(pdfPath, DocExtractProvider.mineru, {
        DocPaths.rawMd(pdfPath): raw,
        DocPaths.json(pdfPath): jsonEncode(json),
        DocPaths.figuresManifest(pdfPath): FigureExtractService.encodeManifest(
          manifest,
          pdfPath,
          source: 'mineru',
        ),
        DocPaths.md(pdfPath): processed,
      });
      published = true;
      if (archive.files.any(
        (f) =>
            f.isFile &&
            const [
              '.docx',
              '.html',
              '.tex',
            ].contains(p.extension(f.name).toLowerCase()),
      )) {
        await zipFile.copy(DocPaths.mineruExports(pdfPath));
      }
      await pruneFigureGenerations(root.path, [
        ...assets.values,
        ...manifest.map((e) => e.imagePath),
        ...previous.map((e) => e.imagePath),
      ]);
      return MinerUConversionResult(
        mdPath: DocPaths.md(pdfPath),
        processedMarkdown: processed,
        pageCount: structure.pages.length,
      );
    } finally {
      if (!published && generation != null) {
        await generation.delete(recursive: true);
      }
      if (await zipFile.exists()) await zipFile.delete();
    }
  }

  Future<(String mdPath, String content)> reprocess({
    required String pdfPath,
    String? title,
  }) async {
    final (jsonPath, rawPath) = await ExtractionArtifacts.inputs(
      pdfPath,
      DocExtractProvider.mineru,
    );
    final raw = await File(rawPath).readAsString();
    final jsonText = await File(jsonPath).readAsString();
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    final old =
        await FigureExtractService.loadManifest(
          pdfPath,
          source: DocExtractProvider.mineru,
        ) ??
        const <FigureManifestEntry>[];
    final assetData = json['_mineru_assets'];
    // Old extracts discarded the layout. Do not crop using synthetic boxes.
    if (assetData is! Map) {
      final assets = <String, String>{};
      for (final entry in old) {
        for (final name
            in entry.sourceImageNames ?? [p.basename(entry.imagePath)]) {
          assets[name] = p.join(DocPaths.figuresDir(pdfPath), name);
        }
      }
      final md = buildReaderMarkdown(raw, old, assets: assets, title: title);
      await ExtractionArtifacts.publish(pdfPath, DocExtractProvider.mineru, {
        DocPaths.rawMd(pdfPath): raw,
        DocPaths.json(pdfPath): jsonText,
        DocPaths.figuresManifest(pdfPath): FigureExtractService.encodeManifest(
          FigureManifestEntry.forDisplay(old),
          pdfPath,
          source: 'mineru',
        ),
        DocPaths.md(pdfPath): md,
      });
      return (DocPaths.md(pdfPath), md);
    }
    final assets = assetData.map(
      (name, path) => MapEntry(
        name.toString(),
        p.join(DocPaths.docDir(pdfPath), path as String),
      ),
    );
    final structure = await PdfCaptionRecovery.recover(
      DocumentStructure.parse(jsonText),
      pdfPath,
    );
    final recoveredJson = jsonEncode({
      ...json,
      ...structure.toJson(source: 'mineru'),
    });
    final generation = await createFigureGeneration(
      DocPaths.figuresDir(pdfPath),
    );
    var published = false;
    try {
      final manifest = await _extract(
        structure,
        pdfPath,
        generation.path,
        assets,
      );
      final md = buildReaderMarkdown(
        raw,
        manifest,
        assets: assets,
        tableSources: (json['_mineru_table_sources'] as List?)?.cast<String?>(),
        structure: structure,
        title: title,
      );
      manifest.removeWhere(
        (e) => e.isDisplayFigure && !md.contains(e.markdownAnchor),
      );
      await ExtractionArtifacts.publish(pdfPath, DocExtractProvider.mineru, {
        DocPaths.rawMd(pdfPath): raw,
        DocPaths.json(pdfPath): recoveredJson,
        DocPaths.figuresManifest(pdfPath): FigureExtractService.encodeManifest(
          manifest,
          pdfPath,
          source: 'mineru',
        ),
        DocPaths.md(pdfPath): md,
      });
      published = true;
      await pruneFigureGenerations(DocPaths.figuresDir(pdfPath), [
        ...assets.values,
        ...manifest.map((e) => e.imagePath),
        ...old.map((e) => e.imagePath),
      ]);
      return (DocPaths.md(pdfPath), md);
    } finally {
      if (!published) await generation.delete(recursive: true);
    }
  }

  static Future<List<List<double>>> _pageSizes(String pdfPath) async {
    if (!await _hasPdf(pdfPath)) return const [];
    return PdfProcessLock.instance.run(() async {
      final pdf = await PdfDocument.openFile(
        pdfPath,
        passwordProvider: () => '',
      );
      try {
        return [
          for (final page in pdf.pages) [page.width, page.height],
        ];
      } finally {
        pdf.dispose();
      }
    });
  }

  static Future<bool> _hasPdf(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() < 5) return false;
    final handle = await file.open();
    try {
      return ascii.decode(await handle.read(5), allowInvalid: true) == '%PDF-';
    } finally {
      await handle.close();
    }
  }

  Future<List<FigureManifestEntry>> _extract(
    DocumentStructure structure,
    String pdfPath,
    String outputDir,
    Map<String, String> assets,
  ) async {
    final service = FigureExtractService.instance;
    await service.init();
    final entries = <FigureManifestEntry>[];
    if (await _hasPdf(pdfPath)) {
      entries.addAll(
        (await service.extractStructureFigures(
          structure: structure,
          pdfPath: pdfPath,
          outputDir: outputDir,
        )).entries,
      );
    }
    final claimed = entries
        .expand((e) => e.sourceImageNames ?? const <String>[])
        .toSet();
    // Only a single explicitly captioned body is safe without rendering.
    for (final page in structure.pages) {
      final parents = <String, List<LayoutBlock>>{};
      for (final block in page.blocks) {
        if (block.parentId != null) {
          parents.putIfAbsent(block.parentId!, () => []).add(block);
        }
      }
      final numberedNearby = structure.pages
          .where((p) => (p.pageIndex - page.pageIndex).abs() <= 1)
          .any(
            (p) => p.blocks.any(
              (b) =>
                  FigureExtractService.instance.isMainCaption(b.blockContent),
            ),
          );
      for (final blocks in parents.values) {
        final visuals = blocks
            .where(
              (b) => const ['image', 'table', 'chart'].contains(b.blockLabel),
            )
            .toList();
        final captions = blocks
            .where(
              (b) =>
                  b.blockLabel == 'figure_title' &&
                  FigureManifestEntry.isUsableCaption(b.blockContent) &&
                  (!numberedNearby ||
                      FigureExtractService.instance.isMainCaption(
                        b.blockContent,
                      )),
            )
            .toList();
        if (visuals.length != 1 || captions.length != 1) continue;
        final name = visuals.single.sourceImage;
        if (name == null || claimed.contains(p.basename(name))) continue;
        final path = assets[p.basename(name)];
        if (path == null || !await File(path).exists()) continue;
        final ids = blocks.map((b) => b.blockId).toList();
        entries.add(
          FigureManifestEntry(
            id: FigureManifestEntry.identity(page.pageIndex, ids),
            imagePath: path,
            captionText: captions.single.blockContent,
            pageIndex: page.pageIndex,
            blockIds: ids,
            sourceImageNames: [p.basename(name)],
            kind: captions.single.captionKind,
            captionSource: CaptionSource.blockMatch.name,
            pairMethod: PairMethod.samePage.name,
          ),
        );
      }
    }
    final order = <String, int>{};
    for (final page in structure.pages) {
      for (final block in page.blocks) {
        order[block.blockId] = order.length;
      }
    }
    entries.sort(
      (a, b) => (order[a.blockIds.first] ?? 0).compareTo(
        order[b.blockIds.first] ?? 0,
      ),
    );
    return entries;
  }

  /// Table slots include missing images; uncertain references remain readable.
  static String buildReaderMarkdown(
    String raw,
    List<FigureManifestEntry> entries, {
    required Map<String, String> assets,
    List<String?>? tableSources,
    DocumentStructure? structure,
    String? title,
  }) {
    final bySource = <String, FigureManifestEntry>{};
    for (final entry in entries.where((e) => e.isDisplayFigure)) {
      for (final name
          in entry.sourceImageNames ?? [p.basename(entry.imagePath)]) {
        bySource[name] = entry;
      }
    }
    final imageRe = RegExp(r'!\[[^\]]*\]\((?:images/)?([^\s()]+)\)');
    final tableRe = RegExp(
      r'<table\b[^>]*>[\s\S]*?</table>',
      caseSensitive: false,
    );
    final tables = tableRe.allMatches(raw).toList();
    final replacements = <({int start, int end, String text})>[];
    final emitted = <FigureManifestEntry>{};
    final owned = <({int start, int end, FigureManifestEntry entry})>[];
    String tag(FigureManifestEntry e) =>
        '\n${e.markdownAnchor}\n\n![fig:${_normalize(e.captionText).replaceAll('[', r'\[').replaceAll(']', r'\]')}](${Uri.file(e.imagePath)})\n';
    void replace(int start, int end, FigureManifestEntry entry) {
      replacements.add((
        start: start,
        end: end,
        text: emitted.add(entry) ? tag(entry) : '',
      ));
      owned.add((start: start, end: end, entry: entry));
    }

    for (final image in imageRe.allMatches(raw)) {
      final name = p.basename(image[1]!);
      final entry = bySource[name];
      if (entry != null) {
        replace(image.start, image.end, entry);
      } else {
        replacements.add((start: image.start, end: image.end, text: ''));
      }
    }
    if (tableSources != null && tableSources.length == tables.length) {
      for (var i = 0; i < tables.length; i++) {
        final entry = bySource[tableSources[i]];
        if (entry != null && entry.kind == 'table') {
          replace(tables[i].start, tables[i].end, entry);
        }
      }
    }
    // Delete captions only at the source boundary, never by global text search.
    for (final span in owned) {
      final caption = _captionMatch(span.entry.captionText);
      final labels = <String>{
        if (span.entry.cropBbox != null && structure != null)
          for (final page in structure.pages)
            for (final block in page.blocks)
              if (span.entry.blockIds.contains(block.blockId) &&
                  FigureExtractService.instance.isSubfigureLabelBlock(block))
                _normalize(block.blockContent),
      };
      for (final before in [false, true]) {
        final boundary = before
            ? raw.substring(0, span.start)
            : raw.substring(span.end);
        final lines = boundary.split('\n');
        final ordered = before ? lines.reversed.toList() : lines;
        var consumed = 0;
        var probe = '';
        for (final line in ordered) {
          consumed += line.length + 1;
          final text = _captionMatch(line);
          if (text.isEmpty && probe.isEmpty) continue;
          if (probe.isEmpty && labels.contains(text)) {
            final length = consumed - 1;
            replacements.add((
              start: before ? span.start - length : span.end,
              end: before ? span.start : span.end + length,
              text: '',
            ));
            continue;
          }
          if (text.startsWith('![') ||
              text.startsWith('<') ||
              text.startsWith('#')) {
            break;
          }
          probe = before
              ? _normalize('$text $probe')
              : _normalize('$probe $text');
          if (probe == caption) {
            final length = consumed - 1;
            replacements.add((
              start: before ? span.start - length : span.end,
              end: before ? span.start : span.end + length,
              text: '',
            ));
            break;
          }
          if (before ? !caption.endsWith(probe) : !caption.startsWith(probe)) {
            break;
          }
        }
      }
    }
    if (structure != null) {
      final blocks = structure.pages.expand((p) => p.blocks).toList();
      final rawImages = imageRe.allMatches(raw).toList();
      for (final entry in emitted) {
        for (final ref in entry.captionRefs) {
          final page = structure.pages
              .where((p) => p.pageIndex == ref.pageIndex)
              .firstOrNull;
          final block = page?.blocks
              .where((b) => b.blockId == ref.blockId)
              .firstOrNull;
          if (block == null) continue;
          final index = blocks.indexOf(block);
          var start = 0;
          var end = raw.length;
          // 用结构中的前后图片限定原始题注位置，避免删除正文里的同名引用。
          for (final previous in blocks.take(index).toList().reversed) {
            if (previous.sourceImage == null) continue;
            final match = rawImages
                .where(
                  (m) => p.basename(m[1]!) == p.basename(previous.sourceImage!),
                )
                .firstOrNull;
            if (match != null) {
              start = match.end;
              break;
            }
          }
          for (final next in blocks.skip(index + 1)) {
            if (next.sourceImage == null) continue;
            final match = rawImages
                .where(
                  (m) => p.basename(m[1]!) == p.basename(next.sourceImage!),
                )
                .firstOrNull;
            if (match != null) {
              end = match.start;
              break;
            }
          }
          if (start >= end) continue;
          final target = _captionMatch(block.blockContent);
          final matches = RegExp(r'[^\n]+')
              .allMatches(raw.substring(start, end))
              .where((m) => _captionMatch(m[0]!) == target)
              .toList();
          if (matches.length == 1) {
            replacements.add((
              start: start + matches.single.start,
              end: start + matches.single.end,
              text: '',
            ));
          }
        }
      }
    }
    replacements.sort((a, b) {
      final start = a.start.compareTo(b.start);
      return start != 0 ? start : b.end.compareTo(a.end);
    });
    final out = StringBuffer();
    var cursor = 0;
    for (final replacement in replacements) {
      if (replacement.start < cursor || replacement.end > raw.length) continue;
      out.write(raw.substring(cursor, replacement.start));
      out.write(replacement.text);
      cursor = replacement.end;
    }
    out.write(raw.substring(cursor));
    return MarkdownPreprocessor.filterBeforeTitle(
      MarkdownPreprocessor.process(out.toString()),
      title,
    );
  }

  static String _normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');
  static String _captionMatch(String text) => _normalize(
    text
        .replaceAll(r'\~', '~')
        .replaceAllMapped(RegExp(r'(\w)-\s+(\w)'), (m) => '${m[1]}${m[2]}')
        .replaceAll(RegExp(r'<[^>]+>|\$'), ''),
  );
}
