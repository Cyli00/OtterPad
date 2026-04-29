import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
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

  Future<DocumentSummaryImageResult> generate({
    required Document document,
    required AgentApiState agentState,
    required ImageGenerationConfig config,
    String? language,
    CancelToken? cancelToken,
  }) async {
    final modelId = agentState.imageModelId;
    if (modelId == null || modelId.isEmpty) {
      throw const DocumentSummaryImageException('请先在 AI 设置中选择生图模型');
    }
    if (agentState.apiKey.trim().isEmpty) {
      throw const DocumentSummaryImageException('请先在 AI 设置中填写生图模型 API Key');
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
    final prompt = _buildPrompt(
      document: document,
      markdown: _compactMarkdown(markdown),
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
    final hasNativeFidelity = provider == AgentApiProvider.openai ||
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

  String _compactMarkdown(String markdown) {
    final withoutRefs = markdown
        .split(
          RegExp(
            r'\n#{1,6}\s*(references|bibliography)\b',
            caseSensitive: false,
          ),
        )
        .first;
    final normalized = withoutRefs
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    const maxChars = 24000;
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars)}\n\n[Content truncated for image generation.]';
  }
}
