import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/models/book/highlight.dart';
import '../../../providers/highlight_provider.dart';
import 'reader_background.dart';

Future<void> showReaderNotesSheet(
  BuildContext context, {
  required String documentId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ReaderLocalTheme(
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _NotesSheetBody(
          documentId: documentId,
          scrollController: scrollController,
        ),
      ),
    ),
  );
}

class _NotesSheetBody extends ConsumerWidget {
  final String documentId;
  final ScrollController scrollController;

  const _NotesSheetBody({
    required this.documentId,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlights = ref.watch(highlightProvider(documentId));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        // Grabber
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // 标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(Symbols.bookmark_rounded, color: cs.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                '标注与笔记',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${highlights.length} 条',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 列表
        Expanded(
          child: highlights.isEmpty
              ? _buildEmptyState(theme, cs)
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: highlights.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final hl = highlights[index];
                    return _HighlightTile(
                      key: ValueKey(hl.id),
                      highlight: hl,
                      onEditNote: () =>
                          _showEditNoteDialog(context, ref, documentId, hl),
                      onDelete: () => ref
                          .read(highlightProvider(documentId).notifier)
                          .remove(hl.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.highlight_rounded, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            '还没有标注',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '选中文本后点击颜色圆点即可创建',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }

  void _showEditNoteDialog(
    BuildContext context,
    WidgetRef ref,
    String documentId,
    Highlight hl,
  ) {
    final controller = TextEditingController(text: hl.note ?? '');
    showDialog<String>(
      context: context,
      builder: (ctx) {
        final dTheme = Theme.of(ctx);
        final dCs = dTheme.colorScheme;
        return AlertDialog(
          backgroundColor: dCs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          title: Text(
            '编辑笔记',
            style: dTheme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 60),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: dCs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    hl.text.trim(),
                    style: dTheme.textTheme.bodySmall?.copyWith(
                      color: dCs.onSurfaceVariant,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: dCs.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: dCs.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: dCs.primary, width: 2),
                  ),
                  hintText: '写下你的想法...',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    ).then((note) {
      controller.dispose();
      if (note == null) return;
      ref.read(highlightProvider(documentId).notifier).updateNote(hl.id, note);
    });
  }
}

// ─── 可展开的高亮卡片 ───

class _HighlightTile extends StatefulWidget {
  final Highlight highlight;
  final VoidCallback onEditNote;
  final VoidCallback onDelete;

  const _HighlightTile({
    super.key,
    required this.highlight,
    required this.onEditNote,
    required this.onDelete,
  });

  @override
  State<_HighlightTile> createState() => _HighlightTileState();
}

class _HighlightTileState extends State<_HighlightTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hl = widget.highlight;
    final hasNote = hl.note != null && hl.note!.isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hl.text.trim(),
                    style: theme.textTheme.bodyMedium,
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                  ),
                  if (hasNote) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 中性引用线：仅作"笔记块"的视觉层级标记，
                        // 不携带高亮颜色——避免列表卡片整体色彩噪音。
                        Container(
                          width: 2,
                          constraints: const BoxConstraints(minHeight: 16),
                          margin: const EdgeInsets.only(right: 10),
                          color: cs.outlineVariant,
                        ),
                        Expanded(
                          child: Text(
                            hl.note!,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: _expanded ? null : 2,
                            overflow: _expanded ? null : TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _formatTime(hl.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.outline,
                        ),
                      ),
                      const Spacer(),
                      _MiniButton(
                        icon: Symbols.edit_note_rounded,
                        tooltip: '编辑笔记',
                        onTap: widget.onEditNote,
                      ),
                      const SizedBox(width: 4),
                      _MiniButton(
                        icon: Symbols.delete_rounded,
                        tooltip: '删除',
                        onTap: widget.onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
