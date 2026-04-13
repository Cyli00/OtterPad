import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../providers/reader_settings_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/reader/markdown_document_cache_service.dart';
import '../../services/snackbar_service.dart';
import 'widgets/md_widget/nr_markdown_config.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Markdown 提取结果展示页
///
/// 支持两种加载方式：
/// - [markdownContent] 直接传入已保存的阅读版 Markdown
/// - [filePath] 从磁盘加载已保存的 .md 文件
class ExtractResultPage extends ConsumerWidget {
  final String title;
  final String? markdownContent;
  final String? filePath;

  const ExtractResultPage({
    super.key,
    required this.title,
    this.markdownContent,
    this.filePath,
  }) : assert(markdownContent != null || filePath != null);

  /// 加载 Markdown 内容。
  Future<String> _loadContent() async {
    if (markdownContent != null) {
      return markdownContent!;
    }
    final resolved = await MarkdownDocumentCacheService.instance.loadDocument(
      mdPath: filePath!,
      title: title,
    );
    return resolved.content;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sharePath = filePath;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Symbols.content_copy_rounded, size: 20),
            tooltip: '复制全部',
            onPressed: () async {
              final content = await _loadContent();
              await Clipboard.setData(ClipboardData(text: content));
              ref.read(snackBarServiceProvider).showResult(
                    message: '已复制到剪贴板',
                    duration: const Duration(seconds: 2),
                  );
            },
          ),
          if (sharePath != null)
            IconButton(
              icon: const Icon(Symbols.share_rounded, size: 20),
              tooltip: '分享',
              onPressed: () {
                Share.shareXFiles([XFile(sharePath)]);
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<String>(
        future: _loadContent(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.error_rounded, size: 48, color: cs.error),
                  const SizedBox(height: 16),
                  Text('加载失败', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final content = snapshot.data ?? '';
          if (content.isEmpty) {
            return Center(
              child: Text(
                '提取结果为空',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            );
          }

          const defaultSettings = ReaderSettingsState();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MarkdownBlock(
              data: content,
              selectable: true,
              config: buildReaderMarkdownConfig(
                settings: defaultSettings,
                colorScheme: cs,
              ),
              generator: buildReaderMarkdownGenerator(
                settings: defaultSettings,
              ),
            ),
          );
        },
      ),
    );
  }
}
