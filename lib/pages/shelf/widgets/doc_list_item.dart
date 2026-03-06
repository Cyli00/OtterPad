import 'package:flutter/material.dart';
import '../../library/widgets/pdf_cover.dart';

/// 从资源路径中解析文献信息（年份、作者、标题）
///
/// 文件名格式示例：
/// "2022-Dong et al-Cortical regulation of two-stage rapid eye movement sleep.pdf"
({String title, String authors}) _parseDocInfo(String assetPath) {
  // 取文件名（去掉目录和 .pdf 后缀）
  final fileName = assetPath.split('/').last.replaceAll('.pdf', '');

  // 按 "-" 分割，尝试提取 "年份-作者-标题" 格式
  final parts = fileName.split('-');
  if (parts.length >= 3) {
    // 第一段可能是年份，第二段是作者，其余拼回标题
    final authorPart = parts[1].trim();
    final titlePart = parts.sublist(2).join('-').trim();
    if (titlePart.isNotEmpty) {
      return (title: titlePart, authors: authorPart);
    }
  }

  // 无法解析时用文件名作为标题
  // TODO: 替换为真实 PDF 元数据提取
  return (title: fileName, authors: '未知作者');
}

/// 收藏夹详情页中的文献列表项
class DocListItem extends StatelessWidget {
  final String assetPath;
  final String? comment;
  final VoidCallback onTap;

  const DocListItem({
    super.key,
    required this.assetPath,
    this.comment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = _parseDocInfo(assetPath);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 上部：缩略图 + 文献信息
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧 PDF 缩略图
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      height: 140,
                      child: PdfCoverRender(
                        assetPath: assetPath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 右侧文献信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        // 标题
                        Text(
                          info.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // 作者
                        Text(
                          info.authors,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // 评语区域（仅在有评语时展示）
              if (comment != null && comment!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 引号装饰
                    Icon(
                      Icons.format_quote_rounded,
                      size: 24,
                      color: colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        comment!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
