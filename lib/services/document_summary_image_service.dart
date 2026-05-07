import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../data/models/book/document.dart';
import '../providers/api_provider.dart';
import '../providers/image_generation_config_provider.dart';
import '../utils/doc_paths.dart';
import 'figure_extract_service.dart';
import 'image_generation_service.dart';

class DocumentSummaryImageResult {
  final String imagePath;
  final String metadataPath;
  final int referenceImageCount;

  const DocumentSummaryImageResult({
    required this.imagePath,
    required this.metadataPath,
    required this.referenceImageCount,
  });
}

class DocumentSummaryImageException implements Exception {
  final String message;
  const DocumentSummaryImageException(this.message);

  @override
  String toString() => message;
}

class DocumentSummaryImageService {
  DocumentSummaryImageService._();
  static final DocumentSummaryImageService instance =
      DocumentSummaryImageService._();

  static String outputDirFor(String pdfPath) => DocPaths.summaryDir(pdfPath);

  static String imagePathFor(String pdfPath) => DocPaths.summaryImage(pdfPath);

  // ── 后置材料模式缓存 ──────────────────────────────────────────────────────

  static Map<String, List<String>>? _cachedPatterns;

  static Future<Map<String, List<String>>> _loadBackMatterPatterns() async {
    if (_cachedPatterns != null) return _cachedPatterns!;
    final raw = await rootBundle.loadString(
      'assets/config/back_matter_sections.json',
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;
    _cachedPatterns = {
      'l1': (data['l1']['patterns'] as List).cast<String>(),
      'l2': (data['l2']['patterns'] as List).cast<String>(),
      'l3': (data['l3']['patterns'] as List).cast<String>(),
    };
    return _cachedPatterns!;
  }

  // ── 生成入口 ──────────────────────────────────────────────────────────────

  Future<DocumentSummaryImageResult> generate({
    required Document document,
    required AgentApiState agentState,
    required ImageGenerationConfig config,
    String? language,
    CancelToken? cancelToken,
  }) async {
    final modelId = agentState.imageModelId;
    if (modelId == null || modelId.isEmpty) {
      throw const DocumentSummaryImageException('请先在「AI 设置」中选择生图模型');
    }
    if (agentState.apiKey.trim().isEmpty) {
      throw const DocumentSummaryImageException('请先在「AI 设置」中填写生图模型 API Key');
    }
    if (document.filePath.isEmpty) {
      throw const DocumentSummaryImageException('当前文献没有关联 PDF 文件');
    }

    final mdPath = DocPaths.md(document.filePath);
    final mdFile = File(mdPath);
    if (!await mdFile.exists()) {
      throw const DocumentSummaryImageException('请先完成文档提取，再生成总结图');
    }

    final results = await Future.wait([
      mdFile.readAsString(),
      _collectReferenceImages(
        document.filePath,
        maxCount: _maxReferencesForProvider(
          agentState.provider,
          config.maxReferenceImages,
        ),
      ),
    ]);
    final markdown = results[0] as String;
    final references = results[1] as List<String>;
    final compactResult = await _compactMarkdown(markdown);
    final prompt = _buildPrompt(
      document: document,
      markdown: compactResult.markdown,
      config: config,
      provider: agentState.provider,
      language: language,
    );

    final result = await ImageGenerationService.instance.generate(
      ImageGenerationRequest(
        provider: agentState.provider,
        baseUrl: agentState.effectiveBaseUrl,
        apiKey: agentState.apiKey,
        modelId: modelId,
        prompt: prompt,
        referenceImagePaths: references,
        aspectRatio: config.aspectRatio,
        fidelity: config.fidelity,
        cancelToken: cancelToken,
      ),
    );

    final outDir = Directory(outputDirFor(document.filePath));
    await outDir.create(recursive: true);
    final imagePath = p.join(outDir.path, 'summary.png');
    final metadataPath = p.join(outDir.path, 'summary.meta.json');

    await Future.wait([
      File(imagePath).writeAsBytes(result.bytes, flush: true),
      File(metadataPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'documentId': document.id,
          'title': document.title,
          'provider': agentState.provider.name,
          'modelId': modelId,
          'aspectRatio': config.aspectRatio,
          'fidelity': config.fidelity,
          'referenceImageCount': references.length,
          'requestId': result.requestId,
          'providerText': result.providerText,
          'createdAt': DateTime.now().toIso8601String(),
          if (compactResult.backMatterOffset != null)
            'backMatterOffset': compactResult.backMatterOffset,
        }),
        flush: true,
      ),
    ]);

    return DocumentSummaryImageResult(
      imagePath: imagePath,
      metadataPath: metadataPath,
      referenceImageCount: references.length,
    );
  }

  Future<List<String>> _collectReferenceImages(
    String pdfPath, {
    required int maxCount,
  }) async {
    final paths = <String>[];
    final manifest = await FigureExtractService.loadManifest(pdfPath);
    if (manifest != null) {
      for (final entry in manifest) {
        if (paths.length >= maxCount) break;
        if (await File(entry.imagePath).exists()) paths.add(entry.imagePath);
      }
    }
    if (paths.isNotEmpty) return paths;

    final figuresDir = Directory(DocPaths.figuresDir(pdfPath));
    if (!await figuresDir.exists()) return const [];

    final files = <File>[];
    await for (final entity in figuresDir.list()) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.webp')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.take(maxCount).map((f) => f.path).toList();
  }

  int _maxReferencesForProvider(AgentApiProvider provider, int configured) {
    final normalized = configured.clamp(1, 14).toInt();
    return switch (provider) {
      AgentApiProvider.gemini => normalized,
      AgentApiProvider.openai => normalized.clamp(1, 10),
      AgentApiProvider.openAICompatible => normalized.clamp(1, 10),
      AgentApiProvider.anthropic => 0,
    };
  }

  String _buildPrompt({
    required Document document,
    required String markdown,
    required ImageGenerationConfig config,
    required AgentApiProvider provider,
    String? language,
  }) {
    final authors = document.authors.isEmpty
        ? 'Unknown'
        : document.authors.join(', ');

    final constraints = StringBuffer();
    constraints.writeln('Required output aspect ratio: ${config.aspectRatio}.');
    if (language != null && language.isNotEmpty) {
      constraints.writeln(
        'All visible text labels, titles, and annotations in the infographic must be in $language.',
      );
    }
    final hasNativeFidelity =
        provider == AgentApiProvider.openai ||
        provider == AgentApiProvider.gemini;
    if (!hasNativeFidelity && config.fidelity != 'auto') {
      constraints.writeln(
        'Image quality: ${config.fidelity}. Render at the highest resolution available for this quality tier.',
      );
    }

    return '''
${config.prompt.trim()}

${constraints.toString().trim()}

Use the following paper material to create the infographic.

Title:
${document.title}

Metadata:
Authors: $authors
Journal: ${document.journal ?? 'Unknown'}
Year: ${document.year ?? 'Unknown'}
DOI: ${document.doi ?? 'Unknown'}
Keywords: ${document.keywords.join(', ')}

Processed Markdown:
$markdown

Reference figures:
The attached images are extracted figures from the paper. Use them as scientific visual references, but redraw the final result as a clean editorial infographic. Do not copy dense text from the source figures verbatim.
''';
  }

  // ── Markdown 压缩 ─────────────────────────────────────────────────────────

  Future<({String markdown, int? backMatterOffset})> _compactMarkdown(
    String markdown,
  ) async {
    final patterns = await _loadBackMatterPatterns();

    int? backMatterOffset = _detectBackMatterViaRegex(markdown, patterns);
    backMatterOffset ??= _detectBackMatterViaPosition(markdown);

    final bodyMarkdown = backMatterOffset != null
        ? markdown.substring(0, backMatterOffset)
        : markdown;

    final normalized = bodyMarkdown
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    const maxChars = 24000;
    final truncated = normalized.length <= maxChars
        ? normalized
        : '${normalized.substring(0, maxChars)}\n\n[Content truncated for image generation.]';
    return (markdown: truncated, backMatterOffset: backMatterOffset);
  }

  // ── Regex 检测 ────────────────────────────────────────────────────────────

  int? _detectBackMatterViaRegex(
    String markdown,
    Map<String, List<String>> patterns,
  ) {
    final l1 = patterns['l1']!.join('|');
    final l2 = patterns['l2']!.join('|');
    final l3 = patterns['l3']!.join('|');

    final regex = RegExp(
      [
        r'^\s*#{1,6}\s*',
        r'(?:\d+(?:\.\d+)*[\.)]?\s*)?',
        r'(?:(?<l1>',
        l1,
        r')|(?<l2>',
        l2,
        r')|(?<l3>',
        l3,
        r'))',
        r'\s*(?:[:：\-–—].*)?$',
      ].join(),
      multiLine: true,
      caseSensitive: false,
      unicode: true,
    );

    final halfPoint = (markdown.length * 0.5).floor();
    final latePoint = (markdown.length * 0.6).floor();

    for (final match in regex.allMatches(markdown)) {
      if (match.namedGroup('l1') != null) return match.start;
      if (match.namedGroup('l2') != null && match.start >= halfPoint) {
        return match.start;
      }
      if (match.namedGroup('l3') != null && match.start >= latePoint) {
        return match.start;
      }
    }
    return null;
  }

  // ── 位置比例兜底 ─────────────────────────────────────────────────────────

  int? _detectBackMatterViaPosition(String markdown) {
    if (markdown.length <= 8000) return null;

    final tailStart = (markdown.length * 0.8).floor();
    final headingRegex = RegExp(r'^#{1,2}\s+.+$', multiLine: true);
    for (final match in headingRegex.allMatches(markdown)) {
      if (match.start >= tailStart) return match.start;
    }
    return null;
  }
}
