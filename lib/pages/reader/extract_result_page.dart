import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart'
    show LatexBlockSyntax;
import 'package:markdown/markdown.dart' as md;

import '../../utils/latex_syntax.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../services/doc_extract_service.dart';

class _EmojiElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style =
        parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style;
    return RichText(
      text: TextSpan(text: element.textContent, style: style),
    );
  }
}

/// Markdown 提取结果展示页
///
/// 支持两种加载方式：
/// - [markdownContent] 直接传入已解析图片路径的 Markdown（刚提取的）
/// - [filePath] 从磁盘加载已保存的 .md 文件（图片路径需要解析）
class ExtractResultPage extends StatelessWidget {
  final String title;
  final String? markdownContent;
  final String? filePath;

  const ExtractResultPage({
    super.key,
    required this.title,
    this.markdownContent,
    this.filePath,
  }) : assert(markdownContent != null || filePath != null);

  /// 加载并解析 Markdown 内容（图片路径替换为绝对路径）
  Future<String> _loadContent() async {
    if (markdownContent != null) return markdownContent!;

    final raw = await File(filePath!).readAsString();
    final baseName = p.basenameWithoutExtension(filePath!);
    final dir = p.dirname(filePath!);
    final imageDir = p.join(dir, '${baseName}_images');
    return DocExtractService.resolveMarkdownImagePaths(raw, imageDir);
  }

  /// 获取对应的 .html 文件路径（用于分享）
  String? get _htmlPath {
    if (filePath == null) return null;
    final html = p.join(
      p.dirname(filePath!),
      '${p.basenameWithoutExtension(filePath!)}.html',
    );
    return File(html).existsSync() ? html : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sharePath = _htmlPath ?? filePath;

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
          if (sharePath != null)
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
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
                  Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(
              data: content,
              builders: {
                'latex': NRLatexElementBuilder(
                  textStyle: TextStyle(color: cs.onSurface),
                ),
                'emoji': _EmojiElementBuilder(),
              },
              extensionSet: md.ExtensionSet(
                [
                  LatexBlockSyntax(),
                  ...md.ExtensionSet.gitHubWeb.blockSyntaxes,
                ],
                [
                  NRLatexInlineSyntax(),
                  ...md.ExtensionSet.gitHubWeb.inlineSyntaxes,
                ],
              ),
              imageBuilder: (uri, title, alt) {
                if (uri.scheme == 'file') {
                  final file = File(uri.toFilePath());
                  if (file.existsSync()) {
                    return Center(
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_rounded, size: 48),
                      ),
                    );
                  }
                }
                return Center(
                  child: Image.network(
                    uri.toString(),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_rounded, size: 48),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
