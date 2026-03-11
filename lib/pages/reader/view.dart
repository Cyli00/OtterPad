import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/document.dart';
import '../../providers/api_provider.dart';
import '../../services/doc_extract_service.dart';
import 'extract_result_page.dart';

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
  CancelToken? _cancelToken;

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
            onPressed: () => Navigator.of(context).pushNamed('/settings/api'),
          ),
        ),
      );
      return;
    }

    // 检查文件是否存在
    final filePath = widget.document.filePath;
    if (filePath.isEmpty || !File(filePath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF 文件不存在')),
      );
      return;
    }

    // 检查是否已有提取结果
    final mdPath = p.join(
      p.dirname(filePath),
      '${p.basenameWithoutExtension(filePath)}.md',
    );
    if (File(mdPath).existsSync()) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExtractResultPage(
          title: widget.document.title,
          filePath: mdPath,
        ),
      ));
      return;
    }

    // 开始提取
    setState(() => _extracting = true);
    _cancelToken = CancelToken();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('正在提取文档内容…'),
        duration: const Duration(minutes: 10),
        action: SnackBarAction(
          label: '取消',
          onPressed: () => _cancelToken?.cancel(),
        ),
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

      // 保存到磁盘
      await DocExtractService.instance.saveResult(filePath, result);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExtractResultPage(
          title: widget.document.title,
          markdown: result.markdown,
          filePath: result.savedPath,
        ),
      ));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('已取消提取')));
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('网络错误: ${e.message}')));
    } on DocExtractException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('提取失败: $e')));
    } finally {
      if (mounted) setState(() => _extracting = false);
      _cancelToken = null;
    }
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
          _extracting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.document_scanner_rounded, size: 20),
                  tooltip: '文档提取',
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
          ? PdfViewer.file(
              doc.filePath,
              params: const PdfViewerParams(
                backgroundColor: Colors.transparent,
              ),
            )
          : Center(
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
                      doc.filePath,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
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
