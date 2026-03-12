import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/document.dart';
import '../../providers/api_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../services/doc_extract_service.dart';
import '../library/widgets/toolbar_bottom_sheet.dart';
import '../setting/api_settings_page.dart';
import 'widgets/appearance_panel.dart';
import 'widgets/markdown_reader.dart';
import 'widgets/search_overlay.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final Document document;

  const ReaderPage({super.key, required this.document});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  bool _extracting = false;
  bool _showPreview = false;
  String? _mdPath;
  String? _mdContent;
  CancelToken? _cancelToken;

  // 搜索
  bool _searchActive = false;
  String? _highlightQuery;
  int? _targetCharOffset;

  // Markdown 滚动控制
  final _scrollController = ScrollController();

  // 外观面板
  final _appearanceKey = GlobalKey();
  OverlayEntry? _appearanceEntry;

  @override
  void initState() {
    super.initState();
    _checkExistingResult();
  }

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

  // ─── 提取逻辑 ───

  Future<void> _onExtractPressed() async {
    final docState = ref.read(docExtractApiProvider);

    if (docState.baseUrl.isEmpty || docState.apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中配置文档提取 API'),
          action: SnackBarAction(
            label: '前往设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ApiSettingsPage()),
            ),
          ),
        ),
      );
      return;
    }

    final filePath = widget.document.filePath;
    if (filePath.isEmpty || !File(filePath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        buildResultSnackBar(context: context, message: 'PDF 文件不存在'),
      );
      return;
    }

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

      final mdPath = p.join(
        p.dirname(filePath),
        '${p.basenameWithoutExtension(filePath)}.md',
      );
      final resolvedMd = DocExtractService.resolveMarkdownImagePaths(
        result.markdown,
        result.imageDir ??
            p.join(
              p.dirname(filePath),
              '${p.basenameWithoutExtension(filePath)}_images',
            ),
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
        scaffoldMessenger.showSnackBar(
          buildResultSnackBar(context: context, message: '已取消提取'),
        );
        return;
      }
      scaffoldMessenger.hideCurrentSnackBar();
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        buildResultSnackBar(context: context, message: '网络错误: ${e.message}'),
      );
    } on DocExtractException catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        buildResultSnackBar(context: context, message: e.message),
      );
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        buildResultSnackBar(context: context, message: '提取失败: $e'),
      );
    } finally {
      if (mounted) setState(() => _extracting = false);
      _cancelToken = null;
    }
  }

  void _togglePreview() {
    _clearHighlight();
    setState(() => _showPreview = !_showPreview);
  }

  // ─── 搜索 ───

  Future<void> _openSearch() async {
    // 确保 Markdown 内容已加载（供搜索使用）
    if (_mdContent == null && _mdPath != null) {
      _mdContent = await _loadAndResolveMarkdown();
    }
    if (!mounted) return;
    _clearHighlight();
    setState(() => _searchActive = true);
  }

  void _closeSearch() {
    setState(() => _searchActive = false);
  }

  void _onSearchResultTap(int charOffset, String query) {
    setState(() {
      _searchActive = false;
      _showPreview = true;
      _highlightQuery = query;
      _targetCharOffset = charOffset;
    });
  }

  void _clearHighlight() {
    if (_highlightQuery != null || _targetCharOffset != null) {
      setState(() {
        _highlightQuery = null;
        _targetCharOffset = null;
      });
    }
  }

  // ─── 外观面板 ───

  void _toggleAppearancePanel() {
    if (_appearanceEntry != null) {
      _appearanceEntry!.remove();
      _appearanceEntry = null;
      return;
    }
    _appearanceEntry = showAppearancePanel(
      context: context,
      anchorKey: _appearanceKey,
      ref: ref,
      onDismiss: () => _appearanceEntry = null,
    );
  }

  void _showDocumentInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DocumentInfoSheet(document: widget.document),
    );
  }

  Future<String> _loadAndResolveMarkdown() async {
    final raw = await File(_mdPath!).readAsString();
    final baseName = p.basenameWithoutExtension(_mdPath!);
    final dir = p.dirname(_mdPath!);
    final imageDir = p.join(dir, '${baseName}_images');
    return DocExtractService.resolveMarkdownImagePaths(raw, imageDir);
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _scrollController.dispose();
    _appearanceEntry?.remove();
    super.dispose();
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final fileExists =
        doc.filePath.isNotEmpty && File(doc.filePath).existsSync();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final readerSettings = ref.watch(readerSettingsProvider);

    final contentBg = (_showPreview && _hasResult)
        ? readerSettings.backgroundColor
        : cs.surface;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // ── 主内容层 ──
            Column(
              children: [
                _buildToolbar(theme, cs),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    color: contentBg,
                    child: fileExists
                        ? _buildBody(theme, cs, readerSettings)
                        : _buildFileNotFound(theme, cs),
                  ),
                ),
              ],
            ),
            // ── 搜索遮罩层 ──
            if (_searchActive && _mdContent != null)
              Positioned.fill(
                child: SearchOverlay(
                  markdownContent: _mdContent!,
                  readerSettings: readerSettings,
                  onResultTap: _onSearchResultTap,
                  onDismiss: _closeSearch,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 工具栏：返回 / 搜索 / PDF切换 / 刷新 / 信息 / 外观
  Widget _buildToolbar(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            // 返回按钮
            IconButton(
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 28,
                color: cs.onSurface,
              ),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            // 搜索（有提取结果时可用）
            if (_hasResult)
              IconButton(
                icon: Icon(
                  Icons.search_rounded,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: '搜索',
                onPressed: _openSearch,
              ),
            // 提取/切换按钮
            _buildExtractButton(cs),
            // 重新提取
            if (_hasResult && !_extracting)
              IconButton(
                icon: Icon(
                  Icons.sync_rounded,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: '重新提取',
                onPressed: _onExtractPressed,
              ),
            // 文献信息
            IconButton(
              icon: Icon(
                Icons.info_outline_rounded,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
              tooltip: '文献信息',
              onPressed: () => _showDocumentInfo(context),
            ),
            // 外观设置（仅 Markdown 预览模式下显示）
            if (_showPreview && _hasResult)
              IconButton(
                key: _appearanceKey,
                icon: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.onSurfaceVariant, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'A',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                tooltip: '外观设置',
                onPressed: _toggleAppearancePanel,
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractButton(ColorScheme cs) {
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
          _showPreview ? Icons.picture_as_pdf_rounded : Icons.article_rounded,
          size: 22,
          color: cs.onSurfaceVariant,
        ),
        tooltip: _showPreview ? '查看 PDF' : '查看提取结果',
        onPressed: _togglePreview,
      );
    }

    return IconButton(
      icon: Icon(
        Icons.document_scanner_rounded,
        size: 22,
        color: cs.onSurfaceVariant,
      ),
      tooltip: '文档提取',
      onPressed: _onExtractPressed,
    );
  }

  Widget _buildBody(
    ThemeData theme,
    ColorScheme cs,
    ReaderSettingsState readerSettings,
  ) {
    if (_showPreview && _hasResult) {
      return _buildMarkdownPreview(theme, readerSettings);
    }
    return PdfViewer.file(
      widget.document.filePath,
      params: const PdfViewerParams(backgroundColor: Colors.transparent),
    );
  }

  Widget _buildMarkdownPreview(
    ThemeData theme,
    ReaderSettingsState settings,
  ) {
    return FutureBuilder<String>(
      future: _mdContent != null
          ? Future.value(_mdContent!)
          : _loadAndResolveMarkdown(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: settings.textColor.withAlpha(120),
            ),
          );
        }
        if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
          return Center(
            child: Text(
              '加载失败',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          );
        }
        return ReaderMarkdownBody(
          data: snapshot.data!,
          settings: settings,
          scrollController: _scrollController,
          highlightQuery: _highlightQuery,
          targetCharOffset: _targetCharOffset,
        );
      },
    );
  }

  Widget _buildFileNotFound(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text('找不到该文献的 PDF 文件', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              widget.document.filePath,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 文献信息底部弹窗 ───

class _DocumentInfoSheet extends StatelessWidget {
  final Document document;

  const _DocumentInfoSheet({required this.document});

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
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
    final cs = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                  color: cs.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '文献信息',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
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
                      height: MediaQuery.of(context).padding.bottom + 16,
                    ),
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
