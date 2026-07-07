import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../data/models/book/document.dart';
import '../providers/api_provider.dart';
import '../providers/image_generation_config_provider.dart';
import '../utils/doc_paths.dart';
import 'back_matter_detector.dart';
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

  static String outputDirFor(String documentId) =>
      DocPaths.summaryDir(documentId);

  static String imagePathFor(String documentId) =>
      DocPaths.summaryImage(documentId);

  // ── 生成入口 ──────────────────────────────────────────────────────────────

  /// 仅构造生图提示词，不调用任何远端 API。
  ///
  /// 用于"官方 App 生图"分支：用户把提示词复制到 ChatGPT / Gemini 官方 App 内手动生图，
  /// 因此不依赖任何 `AgentApiState`/Key 配置，仅按 [provider] 决定与生图能力相关的
  /// 文案细节（如保真度约束）。
  ///
  /// 复制路径**不嵌入 markdown 正文**——用户会在官方 App 内手动上传通过
  /// "保存文献 Markdown" 导出的 .md 文件作为附件，避免剪贴板里塞几万字。
  Future<String> composePrompt({
    required Document document,
    required ImageGenerationConfig config,
    AgentApiProvider provider = AgentApiProvider.openai,
    String? language,
  }) async {
    if (document.contentHash == null) {
      throw const DocumentSummaryImageException('当前文献没有关联 PDF 文件');
    }
    final mdPath = DocPaths.md(document.id);
    if (!await File(mdPath).exists()) {
      throw const DocumentSummaryImageException('请先完成文档提取，再生成总结图');
    }
    return _buildPrompt(
      document: document,
      markdown: null,
      config: config,
      provider: provider,
      language: language,
    );
  }

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
    if (document.contentHash == null) {
      throw const DocumentSummaryImageException('当前文献没有关联 PDF 文件');
    }

    final mdPath = DocPaths.md(document.id);
    final mdFile = File(mdPath);
    if (!await mdFile.exists()) {
      throw const DocumentSummaryImageException('请先完成文档提取，再生成总结图');
    }

    final results = await Future.wait([
      mdFile.readAsString(),
      _collectReferenceImages(
        document.id,
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

    final outDir = Directory(outputDirFor(document.id));
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
    final primary = <String>[];
    final supplementary = <String>[];
    final manifest = await FigureExtractService.loadManifest(pdfPath);
    if (manifest != null) {
      await FigureExtractService.instance.init();
      final extractor = FigureExtractService.instance;
      for (final entry in manifest) {
        if (!await File(entry.imagePath).exists()) continue;
        if (extractor.isSupplementaryCaption(entry.captionText)) {
          supplementary.add(entry.imagePath);
        } else {
          primary.add(entry.imagePath);
        }
      }
      final selected = <String>[
        ...primary.take(maxCount),
        if (primary.length < maxCount)
          ...supplementary.take(maxCount - primary.length),
      ];
      if (selected.isNotEmpty) return selected;
    }

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
    if (provider == AgentApiProvider.anthropic) return 0;
    return configured
        .clamp(kSummaryReferenceImageMin, kSummaryReferenceImageMax)
        .toInt();
  }

  String _buildPrompt({
    required Document document,
    required String? markdown,
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

    // markdown == null：复制到剪贴板路径，用户会手动把 .md 文件作为附件上传。
    // markdown != null：API 调用路径，模型无法读取附件，必须把正文嵌进 prompt。
    final bodySection = markdown == null
        ? 'Paper full text:\nThe full paper Markdown is attached separately by the user. Read it to ground the infographic in the paper\'s actual content.'
        : 'Processed Markdown:\n$markdown';

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

$bodySection

Reference figures:
The attached images are extracted figures from the paper. Use them as scientific visual references, but redraw the final result as a clean editorial infographic. Do not copy dense text from the source figures verbatim.
''';
  }

  // ── Markdown 压缩 ─────────────────────────────────────────────────────────

  Future<({String markdown, int? backMatterOffset})> _compactMarkdown(
    String markdown,
  ) async {
    // back-matter 检测统一走 [BackMatterDetector]，与翻译跳过共享数据源。
    // detector 已封装 L1/L2/L3 + 位置约束逻辑，这里只取首个命中 offset。
    int? backMatterOffset = BackMatterDetector.instance.detectFirstOffset(
      markdown,
    );
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
