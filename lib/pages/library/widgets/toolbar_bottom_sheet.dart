import 'dart:ui';

import 'package:flutter/material.dart';

enum ToolbarAction { addFile, addByIdentifier, rebuildLibrary, batchExtract }

SnackBar buildProgressSnackBar({
  BuildContext? context,
  int? current,
  int? total,
  required String fileName,
  String? status,
  required VoidCallback onCancel,
  Duration duration = const Duration(minutes: 5),
}) {
  final isMobile = context != null
      ? MediaQuery.sizeOf(context).width < 600
      : true;

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    width: isMobile ? null : 400,
    margin: isMobile
        ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)
        : null,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
    elevation: 6,
    content: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      status ?? '处理中...',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (current != null && total != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        '$current / $total',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fileName,
                style: const TextStyle(fontSize: 12, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
    action: SnackBarAction(label: '取消', onPressed: onCancel),
    duration: duration,
  );
}

SnackBar buildResultSnackBar({
  BuildContext? context,
  required String message,
  Duration duration = const Duration(seconds: 4),
}) {
  final isMobile = context != null
      ? MediaQuery.sizeOf(context).width < 600
      : true;

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    width: isMobile ? null : 400,
    margin: isMobile
        ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)
        : null,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
    elevation: 6,
    content: Text(message, style: const TextStyle(fontSize: 14)),
    duration: duration,
  );
}

Future<ToolbarAction?> showToolbarSheet(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  return showModalBottomSheet<ToolbarAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '工具',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              _SheetItem(
                icon: Icons.note_add_outlined,
                title: '添加文件',
                subtitle: '导入本地 PDF，并提取标题、作者、期刊、年份与 DOI',
                onTap: () => Navigator.pop(context, ToolbarAction.addFile),
              ),
              _SheetItem(
                icon: Icons.travel_explore_rounded,
                title: '通过标识符添加',
                subtitle: '输入 DOI、PMID、arXiv ID 或 ISBN 直接创建条目',
                onTap: () =>
                    Navigator.pop(context, ToolbarAction.addByIdentifier),
              ),
              _SheetItem(
                icon: Icons.refresh_rounded,
                title: '重构文库',
                subtitle: '重新扫描目录，补回 PDF 并重试提取核心元数据',
                onTap: () =>
                    Navigator.pop(context, ToolbarAction.rebuildLibrary),
              ),
              _SheetItem(
                icon: Icons.auto_awesome_rounded,
                title: '批量文献提取',
                subtitle: '选择文献，使用 AI 将 PDF 转为带排版的 HTML',
                onTap: () =>
                    Navigator.pop(context, ToolbarAction.batchExtract),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      );
    },
  );
}

class _SheetItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant.withAlpha(120),
            ),
          ],
        ),
      ),
    );
  }
}
