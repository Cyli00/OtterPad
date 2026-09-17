import '../core/storage/extraction_publication.dart';
import 'dart:io';
import 'dart:convert';

import '../data/models/ocr/doc_extract_config.dart';
import '../utils/doc_paths.dart';

import 'package:path/path.dart' as p;

class ExtractionArtifacts {
  static Future<DocExtractProvider> activeSource(String pdfPath) async {
    final file = File(DocPaths.json(pdfPath));
    if (!await file.exists()) return DocExtractProvider.paddle;
    final data = jsonDecode(await file.readAsString());
    return data is Map && data['_source'] == 'mineru'
        ? DocExtractProvider.mineru
        : DocExtractProvider.paddle;
  }

  static Future<List<DocExtractProvider>> availableSources(
    String pdfPath,
  ) async {
    final sources = <DocExtractProvider>[];
    for (final source in DocExtractProvider.values) {
      if (await File(
        DocPaths.json(pdfPath, source: source.artifactKey),
      ).exists()) {
        sources.add(source);
      }
    }
    if (await File(DocPaths.json(pdfPath)).exists()) {
      final legacy = await activeSource(pdfPath);
      if (!sources.contains(legacy)) sources.add(legacy);
    }
    return sources;
  }

  static Future<(String json, String raw)> inputs(
    String pdfPath,
    DocExtractProvider source,
  ) async {
    final named = DocPaths.json(pdfPath, source: source.artifactKey);
    if (await File(named).exists()) {
      return (named, DocPaths.rawMd(pdfPath, source: source.artifactKey));
    }
    if (await activeSource(pdfPath) != source) {
      throw StateError('extraction_source_not_found');
    }
    return (DocPaths.json(pdfPath), DocPaths.rawMd(pdfPath));
  }

  static Future<void> publish(
    String pdfPath,
    DocExtractProvider source,
    Map<String, String> contents,
  ) async {
    await Directory(DocPaths.figuresDir(pdfPath)).create(recursive: true);
    Map<String, String> destinations(DocExtractProvider provider) => {
      DocPaths.json(pdfPath): DocPaths.json(
        pdfPath,
        source: provider.artifactKey,
      ),
      DocPaths.rawMd(pdfPath): DocPaths.rawMd(
        pdfPath,
        source: provider.artifactKey,
      ),
      DocPaths.figuresManifest(pdfPath): DocPaths.figuresManifest(
        pdfPath,
        source: provider.artifactKey,
      ),
    };
    final all = <String, String>{};
    // 第一次切换提供商前保留旧版单份产物，避免另一种 OCR 覆盖唯一底稿。
    if (await File(DocPaths.json(pdfPath)).exists()) {
      final previous = await activeSource(pdfPath);
      for (final entry in destinations(previous).entries) {
        if (!await File(entry.value).exists() &&
            await File(entry.key).exists()) {
          all[entry.value] = await File(entry.key).readAsString();
        }
      }
    }
    all.addAll(contents);
    for (final entry in destinations(source).entries) {
      if (contents.containsKey(entry.key)) {
        all[entry.value] = contents[entry.key]!;
      }
    }
    await publishExtractionArtifacts(all);
  }

  static Future<List<String>?> retainedImages(String pdfPath) async {
    final retained = <String>[];
    try {
      for (final source in DocExtractProvider.values) {
        final manifest = File(
          DocPaths.figuresManifest(pdfPath, source: source.artifactKey),
        );
        if (await manifest.exists()) {
          final data = jsonDecode(await manifest.readAsString());
          final figures = data is List
              ? data
              : (data as Map)['figures'] as List;
          for (final figure in figures) {
            for (final region in figure['visual_regions'] as List? ?? []) {
              final path = region['img'] as String;
              retained.add(
                p.isAbsolute(path)
                    ? path
                    : p.join(DocPaths.figuresDir(pdfPath), path),
              );
            }
            final image = figure['img'] as String;
            retained.add(
              p.isAbsolute(image)
                  ? image
                  : p.join(DocPaths.figuresDir(pdfPath), image),
            );
          }
        }
        final json = File(DocPaths.json(pdfPath, source: source.artifactKey));
        if (await json.exists()) {
          final data = jsonDecode(await json.readAsString());
          if (data is Map) {
            for (final key in ['_mineru_assets', '_paddle_assets']) {
              if (data[key] is! Map) continue;
              for (final image in (data[key] as Map).values) {
                retained.add(p.join(DocPaths.docDir(pdfPath), image as String));
              }
            }
          }
        }
      }
      return retained;
    } catch (_) {
      // 快照损坏时不能确定引用范围，保留各代图片等待后续重试。
      return null;
    }
  }
}

Future<Directory> createFigureGeneration(String root) async {
  await Directory(root).create(recursive: true);
  final generation = await Directory(root).createTemp('generation_');
  await File(p.join(generation.path, '.otter-generation')).writeAsString('2');
  return generation;
}

/// Retain current sources and the previous reader generation. Only directories
/// marked by this implementation are eligible for cleanup.
Future<void> pruneFigureGenerations(
  String root,
  Iterable<String> retained,
) async {
  final snapshots = await ExtractionArtifacts.retainedImages(
    p.join(p.dirname(root), DocPaths.pdfName),
  );
  if (snapshots == null) return;
  final paths = [...retained, ...snapshots].map(p.normalize).toList();
  try {
    await for (final item in Directory(root).list(followLinks: false)) {
      if (item is! Directory ||
          !p.basename(item.path).startsWith('generation_')) {
        continue;
      }
      if (!await File(p.join(item.path, '.otter-generation')).exists()) {
        continue;
      }
      if (paths.any(
        (path) => p.equals(path, item.path) || p.isWithin(item.path, path),
      )) {
        continue;
      }
      await item.delete(recursive: true);
    }
  } on FileSystemException {
    // A viewer may still hold a file on Windows. Retry on the next publication.
  }
}

/// 多文件产物通过持久化日志发布，启动时恢复未完成的发布。
Future<void> publishExtractionArtifacts(Map<String, String> contents) =>
    ExtractionPublication.publish(contents);
