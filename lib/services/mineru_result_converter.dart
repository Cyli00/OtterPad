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
import 'figure_markdown.dart';
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
        if (name.startsWith('images/')) {
          final safe = FigureMarkdown.sourcePath(name);
          if (!safe.startsWith('images/') || safe.contains('../')) {
            throw const FormatException('unsafe_asset');
          }
          images[safe] = file.content;
        }
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
        await Directory(p.dirname(path)).create(recursive: true);
        await File(path).writeAsBytes(image.value, flush: true);
        assets[image.key] = path;
      }
      var structure = layout != null
          ? DocumentStructure.fromMinerULayout(layout)
          : DocumentStructure.fromMinerUV2(
              v2!,
              pageSizes: await _pageSizes(pdfPath),
            );
      if (structure.isEmpty ||
          !structure.pages.any((page) => page.blocks.isNotEmpty)) {
        throw const FormatException('unsupported_mineru_structure');
      }
      structure = await PdfCaptionRecovery.recover(structure, pdfPath);
      final tableSources = <String?>[];
      for (final page in v2 ?? const []) {
        for (final block in (page as List).whereType<Map>()) {
          if (block['type'] != 'table') continue;
          final source =
              ((block['content'] as Map?)?['image_source'] as Map?)?['path']
                  as String?;
          tableSources.add(
            source == null ? null : FigureMarkdown.sourcePath(source),
          );
        }
      }
      if (v2 == null) {
        for (final page in structure.pages) {
          for (final block in page.blocks.where(
            (b) => b.blockLabel == 'table',
          )) {
            final source = block.sourceImage;
            tableSources.add(
              source == null ? null : FigureMarkdown.sourcePath(source),
            );
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
        recordReferences: true,
      );
      manifest.removeWhere(
        (e) => e.isDisplayFigure && !processed.contains(e.markdownAnchor),
      );
      final json = structure.toJson(source: 'mineru')
        ..addAll({
          '_mineru_raw_layout': layout,
          '_mineru_raw_v2': v2,
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
        recordReferences: true,
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
    FigureMarkdown.retainSourceFigures(structure, assets, entries);
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

  static String buildReaderMarkdown(
    String raw,
    List<FigureManifestEntry> entries, {
    required Map<String, String> assets,
    List<String?>? tableSources,
    DocumentStructure? structure,
    String? title,
    bool recordReferences = false,
  }) {
    final result = FigureMarkdown.replace(
      raw,
      entries,
      assets: assets,
      structure: structure ?? DocumentStructure.empty,
    );
    if (recordReferences) {
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        entries[i] = FigureManifestEntry.fromJson({
          ...entry.toJson(),
          'replacement_refs': result.replacements[entry] ?? const [],
        });
      }
    }
    return MarkdownPreprocessor.filterBeforeTitle(
      MarkdownPreprocessor.process(result.markdown),
      title,
    );
  }
}
