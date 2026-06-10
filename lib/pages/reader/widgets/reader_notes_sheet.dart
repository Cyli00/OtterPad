import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../data/models/book/highlight.dart';
import '../../../providers/highlight_provider.dart';
import '../../../services/haptics.dart';
import '../../../widgets/tactile_press.dart';

/// 笔记面板 body（含 [DraggableScrollableSheet] 包装），
/// 由 [ReaderSheetHost] 弹出。
///
/// [onEditStart]/[onEditEnd] 包裹单条笔记的编辑对话框：编辑期间 reader 冻结背景
/// WebView，使对话框跟随键盘的动画不被 HC WebView 的 insets 遍历拖卡。
class ReaderNotesSheetBody extends StatelessWidget {
  final String documentId;
  final Future<void> Function()? onEditStart;
  final VoidCallback? onEditEnd;

  const ReaderNotesSheetBody({
    super.key,
    required this.documentId,
    this.onEditStart,
    this.onEditEnd,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.3,
      maxChildSize: 1.0,
      expand: false,
      builder: (context, scrollController) => ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: _NotesSheetBody(
          documentId: documentId,
          scrollController: scrollController,
          onEditStart: onEditStart,
          onEditEnd: onEditEnd,
        ),
      ),
    );
  }
}

/// 笔记 sheet 内容容器。
///
/// 改造为 StatefulWidget 是为**键盘弹出期间的性能**：原 ConsumerWidget 在
/// viewInsets 每帧变化时整树 build，ListView 和所有 _HighlightTile 全部重建。
/// 现在把 list 子树构造一次缓存为字段，build 方法复用同一个 widget reference
/// → Flutter 比较时跳过 child.build，list 在 IME 动画期间不再级联重建。
/// header（标题计数）仍随 sheet rebuild 而更新——计数变化时父级 watch 触发。
class _NotesSheetBody extends StatefulWidget {
  final String documentId;
  final ScrollController scrollController;
  final Future<void> Function()? onEditStart;
  final VoidCallback? onEditEnd;

  const _NotesSheetBody({
    required this.documentId,
    required this.scrollController,
    this.onEditStart,
    this.onEditEnd,
  });

  @override
  State<_NotesSheetBody> createState() => _NotesSheetBodyState();
}

class _NotesSheetBodyState extends State<_NotesSheetBody> {
  late final Widget _listSubtree;

  @override
  void initState() {
    super.initState();
    // 缓存 list widget reference——viewport 重建时父级 build 复用此引用，
    // Flutter 比较新旧 widget 相同 → 不调用 _NotesList.build，避免树重绘。
    _listSubtree = _NotesList(
      documentId: widget.documentId,
      scrollController: widget.scrollController,
      onEditStart: widget.onEditStart,
      onEditEnd: widget.onEditEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Grabber(),
        _Header(documentId: widget.documentId),
        const SizedBox(height: 12),
        Expanded(child: _listSubtree),
      ],
    );
  }
}

/// 顶部小条——纯静态，const 化避免 rebuild。
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant.withAlpha(80),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 标题行：图标 + "标注与笔记" + 计数。
///
/// 自管 watch——只在 highlights 长度变化时重建，不受父 viewport 重建影响。
class _Header extends ConsumerWidget {
  final String documentId;
  const _Header({required this.documentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      highlightProvider(documentId).select((list) => list.length),
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(Symbols.bookmark_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 8),
          Text(
            context.l10n.highlightsAndNotes,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            context.l10n.highlightCount(count),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 笔记列表本身——自治 Consumer，只在 highlights 变化时重建。
///
/// 由 [_NotesSheetBodyState] 在 initState 一次性构造，引用稳定。
/// 父级 sheet 在 IME viewport 变化时 build，Flutter 比较 widget 引用相同
/// → 跳过此处 build → list 不被键盘动画拖累。
class _NotesList extends ConsumerStatefulWidget {
  final String documentId;
  final ScrollController scrollController;
  final Future<void> Function()? onEditStart;
  final VoidCallback? onEditEnd;

  const _NotesList({
    required this.documentId,
    required this.scrollController,
    this.onEditStart,
    this.onEditEnd,
  });

  @override
  ConsumerState<_NotesList> createState() => _NotesListState();
}

class _NotesListState extends ConsumerState<_NotesList> {
  /// 把 callback 提取为 instance method——itemBuilder 中使用 closure
  /// `() => method(hl)` 时 closure 每次 build 都新建，但 Tile 持有 callback
  /// 字段差异不会触发 didUpdateWidget 之外的开销；method 路径更稳。
  Future<void> _onEdit(Highlight hl) async {
    // 编辑期间冻结背景 WebView：对话框跟随键盘上移时，背后不再有 HC WebView 被
    // insets 动画逐帧遍历。解冻在对话框关闭时发生，此刻笔记 sheet 仍盖在上面，
    // WebView 重挂载的刷新被遮住，用户不可见。
    await widget.onEditStart?.call();
    if (!mounted) {
      widget.onEditEnd?.call(); // 已冻结则必须解冻，否则 WebView 卡死在冻结态
      return;
    }
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _EditNoteDialog(highlight: hl),
    );
    widget.onEditEnd?.call();
    if (note == null || !mounted) return;
    ref
        .read(highlightProvider(widget.documentId).notifier)
        .updateNote(hl.id, note);
  }

  void _onDelete(Highlight hl) {
    ref.read(highlightProvider(widget.documentId).notifier).remove(hl.id);
  }

  @override
  Widget build(BuildContext context) {
    final highlights = ref.watch(highlightProvider(widget.documentId));
    if (highlights.isEmpty) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.highlight_rounded, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              context.l10n.noHighlights,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.noHighlightsHint,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: highlights.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final hl = highlights[index];
        return RepaintBoundary(
          child: _HighlightTile(
            key: ValueKey(hl.id),
            highlight: hl,
            onEditNote: () => _onEdit(hl),
            onDelete: () => _onDelete(hl),
          ),
        );
      },
    );
  }
}

/// 编辑笔记对话框。
///
/// `TextEditingController` 必须由本 StatefulWidget 的 State 持有并 dispose——
/// 之前的实现把 controller 定义在外部闭包、通过 `showDialog().then(...)` 异步
/// dispose，会和 dialog 子树 unmount 形成竞态：`.then` microtask 可能在 TextField
/// unmount 前先 fire，导致 TextField 持有的 listener 引用 disposed controller，
/// 后续 InheritedWidget 依赖解除顺序错乱，触发 `_dependents.isEmpty` 断言失败。
class _EditNoteDialog extends StatefulWidget {
  final Highlight highlight;
  const _EditNoteDialog({required this.highlight});

  @override
  State<_EditNoteDialog> createState() => _EditNoteDialogState();
}

class _EditNoteDialogState extends State<_EditNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.highlight.note ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hl = widget.highlight;
    return AlertDialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      title: Text(
        context.l10n.editNoteTitle,
        style: theme.textTheme.titleLarge?.copyWith(
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
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Text(
                hl.text.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration(
              filled: true,
              fillColor: cs.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              hintText: context.l10n.writeYourThoughts,
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
          onPressed: () {
            Haptics.soft();
            Navigator.pop(context);
          },
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () {
            Haptics.soft();
            Navigator.pop(context, _controller.text);
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
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
      child: TactilePress(
        onTap: () => setState(() => _expanded = !_expanded),
        baseColor: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedSize(
          duration: kAnim,
          curve: kAnimCurve,
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
                      _formatTime(context, hl.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.outline,
                      ),
                    ),
                    const Spacer(),
                    _MiniButton(
                      icon: Symbols.edit_note_rounded,
                      tooltip: context.l10n.editNote,
                      onTap: widget.onEditNote,
                    ),
                    const SizedBox(width: 4),
                    _MiniButton(
                      icon: Symbols.delete_rounded,
                      tooltip: context.l10n.delete,
                      onTap: widget.onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime dt) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.hoursAgo(diff.inHours);
    if (diff.inDays < 30) return l10n.daysAgo(diff.inDays);
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
      child: TactilePress(
        onTap: onTap,
        baseColor: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
      ),
    );
  }
}
