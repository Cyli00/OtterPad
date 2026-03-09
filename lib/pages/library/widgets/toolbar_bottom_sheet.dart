import 'dart:ui';
import 'package:flutter/material.dart';

enum ToolbarAction { addFile, addByIdentifier, rebuildLibrary }

/// 构建操作进度 SnackBar
///
/// 布局: [spinner] (current/total) fileName status  [取消]
SnackBar buildProgressSnackBar({
  int? current,
  int? total,
  required String fileName,
  String? status,
  required VoidCallback onCancel,
  Duration duration = const Duration(minutes: 5),
}) {
  return SnackBar(
    content: Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        if (current != null && total != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('($current/$total)'),
          ),
        Expanded(
          child: status != null && status.isNotEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        fileName,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      ' $status',
                      maxLines: 1,
                    ),
                  ],
                )
              : Text(
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
        ),
      ],
    ),
    action: SnackBarAction(
      label: '取消',
      onPressed: onCancel,
    ),
    duration: duration,
  );
}

/// 工具栏 Bottom Sheet
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
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽条
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
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 8),
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
              // 选项
              _SheetItem(
                icon: Icons.note_add_outlined,
                title: '添加文件',
                subtitle: '从本地选择 PDF 文件添加到文库',
                onTap: () =>
                    Navigator.pop(context, ToolbarAction.addFile),
              ),
              _SheetItem(
                icon: Icons.travel_explore_rounded,
                title: '通过标识符添加条目',
                subtitle: '输入 DOI、PMID、arXiv ID 等标识符',
                onTap: () =>
                    Navigator.pop(context, ToolbarAction.addByIdentifier),
              ),
              _SheetItem(
                icon: Icons.refresh_rounded,
                title: '重构文库',
                subtitle: '重新扫描目录，更新文献列表与元数据',
                onTap: () =>
                    Navigator.pop(context, ToolbarAction.rebuildLibrary),
              ),
              SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 16),
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
