import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:share_plus/share_plus.dart';

/// Markdown 提取结果展示页
///
/// 支持两种加载方式：
/// - [markdown] 直接传入内存中的 Markdown 文本（刚提取的）
/// - [filePath] 从磁盘加载已保存的 .md 文件
class ExtractResultPage extends StatelessWidget {
  final String title;
  final String? markdown;
  final String? filePath;

  const ExtractResultPage({
    super.key,
    required this.title,
    this.markdown,
    this.filePath,
  }) : assert(markdown != null || filePath != null);

  Future<String> _loadContent() async {
    if (markdown != null) return markdown!;
    return File(filePath!).readAsString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: '复制全部',
            onPressed: () async {
              final content = await _loadContent();
              await Clipboard.setData(ClipboardData(text: content));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制到剪贴板'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          if (filePath != null)
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
              tooltip: '分享',
              onPressed: () {
                Share.shareXFiles([XFile(filePath!)]);
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
                  Icon(Icons.error_outline_rounded,
                      size: 48, color: cs.error),
                  const SizedBox(height: 16),
                  Text('加载失败', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final content = snapshot.data ?? '';
          if (content.isEmpty) {
            return Center(
              child: Text('提取结果为空',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: cs.onSurfaceVariant)),
            );
          }

          return Markdown(
            data: content,
            selectable: true,
            padding: const EdgeInsets.all(16),
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              h1: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              h2: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              h3: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              code: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                backgroundColor: cs.surfaceContainerHighest,
              ),
              codeblockDecoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: cs.primary, width: 3),
                ),
              ),
              tableBorder: TableBorder.all(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              tableHead: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }
}
