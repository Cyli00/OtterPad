import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart'
    show LatexBlockSyntax;

import '../../utils/latex_syntax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/document.dart';
import '../../providers/api_provider.dart';
import '../../services/doc_extract_service.dart';
import '../library/widgets/toolbar_bottom_sheet.dart';
import '../setting/api_settings_page.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final Document document;

  const ReaderPage({
    super.key,
    required this.document,
  });

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  bool _extracting = false;
  bool _showPreview = false;
  String? _mdPath; // 已保存的 .md 路径
  String? _mdContent; // 图片路径已解析的 Markdown 内容
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _checkExistingResult();
  }

  /// 检查 PDF 同目录是否已有 .md 提取结果
  void _checkExistingResult() {
    final filePath = widget.document.filePath;
    if (filePath.isEmpty) return;
    final mdPath = p.join(
      p.dirname(filePath),
      '${p.basenameWithoutExtension(filePath)}.md',
    );
    if (File(mdPath).existsSync()) {
      _mdPath = mdPath;
    }
  }

  bool get _hasResult => _mdPath != null || _mdContent != null;

  void _showDocumentInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _DocumentInfoSheet(document: widget.document),
    );
  }

  Future<void> _onExtractPressed() async {
    final docState = ref.read(docExtractApiProvider);

    // 检查 API 配置
    if (docState.baseUrl.isEmpty || docState.apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置文档提取 API'),
          action: SnackBarAction(
            label: '前往设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ApiSettingsPage(),
              ),
            ),
          ),
        ),
      );
      return;
    }

    // 检查文件
    final filePath = widget.document.filePath;
    if (filePath.isEmpty || !File(filePath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        buildResultSnackBar(context: context, message: 'PDF 文件不存在'),
      );
      return;
    }

    // 开始提取
    setState(() => _extracting = true);
    _cancelToken = CancelToken();

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (!mounted) return;
    scaffoldMessenger.showSnackBar(
      buildProgressSnackBar(
        context: context,
        fileName: widget.document.title,
        status: '正在提取文档…',
        onCancel: () {
          _cancelToken?.cancel();
          scaffoldMessenger.hideCurrentSnackBar();
        },
        duration: const Duration(minutes: 10),
      ),
    );

    try {
      final result = await DocExtractService.instance.extract(
        filePath: filePath,
        apiUrl: docState.baseUrl,
        token: docState.apiKey,
        state: docState,
        cancelToken: _cancelToken,
      );

      if (!mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        return;
      }
      scaffoldMessenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          buildProgressSnackBar(
            context: context,
            fileName: widget.document.title,
            status: '正在保存结果…',
            onCancel: () {},
          ),
        );

      // 保存到磁盘（传入 token 以便图片下载可能需要认证）
      await DocExtractService.instance.saveResult(
        filePath,
        result,
        token: docState.apiKey,
      );

      if (!mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        return;
      }
      scaffoldMessenger.hideCurrentSnackBar();

      // 用原始 Markdown + 已下载的本地图片路径生成可渲染内容
      final mdPath = p.join(
        p.dirname(filePath),
        '${p.basenameWithoutExtension(filePath)}.md',
      );
      final resolvedMd = DocExtractService.resolveMarkdownImagePaths(
        result.markdown,
        result.imageDir ?? p.join(p.dirname(filePath), '${p.basenameWithoutExtension(filePath)}_images'),
      );

      setState(() {
        _mdPath = mdPath;
        _mdContent = resolvedMd;
        _showPreview = true;
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        scaffoldMessenger.hideCurrentSnackBar();
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(buildResultSnackBar(context: context, message: '已取消提取'));
        return;
      }
      scaffoldMessenger.hideCurrentSnackBar();
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(buildResultSnackBar(context: context, message: '网络错误: ${e.message}'));
    } on DocExtractException catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(buildResultSnackBar(context: context, message: e.message));
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(buildResultSnackBar(context: context, message: '提取失败: $e'));
    } finally {
      if (mounted) setState(() => _extracting = false);
      _cancelToken = null;
    }
  }

  void _togglePreview() {
    setState(() => _showPreview = !_showPreview);
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final fileExists =
        doc.filePath.isNotEmpty && File(doc.filePath).existsSync();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainerLowest,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          doc.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          _buildExtractButton(colorScheme),
          if (_hasResult && !_extracting)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: '重新提取',
              onPressed: _onExtractPressed,
            ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, size: 20),
            tooltip: '文献信息',
            onPressed: () => _showDocumentInfo(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: fileExists
          ? _buildBody(theme, colorScheme)
          : _buildFileNotFound(theme, colorScheme),
    );
  }

  /// 根据状态构建不同形态的按钮：提取中 / 切换预览 / 开始提取
  Widget _buildExtractButton(ColorScheme colorScheme) {
    if (_extracting) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_hasResult) {
      return IconButton(
        icon: Icon(
          _showPreview
              ? Icons.picture_as_pdf_rounded
              : Icons.article_rounded,
          size: 20,
        ),
        tooltip: _showPreview ? '查看 PDF' : '查看提取结果',
        onPressed: _togglePreview,
      );
    }

    return IconButton(
      icon: const Icon(Icons.document_scanner_rounded, size: 20),
      tooltip: '文档提取',
      onPressed: _onExtractPressed,
    );
  }

  /// 构建主体区域：PDF 视图 或 Markdown 预览
  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_showPreview && _hasResult) {
      return _buildMarkdownPreview(theme);
    }
    return PdfViewer.file(
      widget.document.filePath,
      params: const PdfViewerParams(
        backgroundColor: Colors.transparent,
      ),
    );
  }

  /// 从磁盘加载 .md 文件并解析图片路径
  Future<String> _loadAndResolveMarkdown() async {
    final raw = await File(_mdPath!).readAsString();
    final baseName = p.basenameWithoutExtension(_mdPath!);
    final dir = p.dirname(_mdPath!);
    final imageDir = p.join(dir, '${baseName}_images');
    return DocExtractService.resolveMarkdownImagePaths(raw, imageDir);
  }

  Widget _buildMarkdownPreview(ThemeData theme) {
    return FutureBuilder<String>(
      future: _mdContent != null
          ? Future.value(_mdContent!)
          : _loadAndResolveMarkdown(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
          return Center(
            child: Text('加载失败',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.error)),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MarkdownBody(
            data: snapshot.data!,
            builders: {
              'latex': NRLatexElementBuilder(
                textStyle: TextStyle(color: theme.colorScheme.onSurface),
              ),
            },
            extensionSet: md.ExtensionSet(
              [LatexBlockSyntax(), ...md.ExtensionSet.gitHubWeb.blockSyntaxes],
              [NRLatexInlineSyntax(), ...md.ExtensionSet.gitHubWeb.inlineSyntaxes],
            ),
            imageBuilder: (uri, title, alt) {
              if (uri.scheme == 'file') {
                final file = File(uri.toFilePath());
                if (file.existsSync()) {
                  return Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_rounded,
                      size: 48,
                    ),
                  );
                }
              }
              return Image.network(
                uri.toString(),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_rounded,
                  size: 48,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFileNotFound(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: colorScheme.error),
          const SizedBox(height: 16),
          Text('找不到该文献的 PDF 文件',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              widget.document.filePath,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentInfoSheet extends StatelessWidget {
  final Document document;

  const _DocumentInfoSheet({required this.document});

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '文献信息',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildInfoRow(
                        context, '作者', document.authors.join(', ')),
                    _buildInfoRow(context, '期刊', document.journal ?? ''),
                    _buildInfoRow(context, '年份', document.year ?? ''),
                    _buildInfoRow(context, 'DOI', document.doi ?? ''),
                    SizedBox(
                        height:
                            MediaQuery.of(context).padding.bottom + 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
