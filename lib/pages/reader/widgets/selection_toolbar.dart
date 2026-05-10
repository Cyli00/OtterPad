import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/models/book/highlight.dart';

/// 在选区附近显示阅读上下文菜单 Overlay（含可展开的笔记面板）。
OverlayEntry showReaderContextMenu({
  required BuildContext context,
  required Rect selectionRect,
  required String selectedText,
  Highlight? existingHighlight,
  required void Function(String color) onHighlight,
  required VoidCallback onCopy,
  required VoidCallback onTranslate,
  Highlight? Function()? onCreateForNote,
  void Function(String highlightId, String note)? onNoteChanged,
  VoidCallback? onDelete,
  VoidCallback? onDismiss,
}) {
  late OverlayEntry entry;
  // **幂等 close**：6 个 action callback + 全屏 tap-to-dismiss + 调用方
  // (`view.dart` 的 `_dismissSelectionToolbar`) 都会调 entry.remove()。
  // 任意两条路径在同一帧/相邻事件中触发——比如双击、按钮 onTap 与背景
  // GestureDetector 同帧命中、dispose 中 `_saveNoteIfDirty` 引发外部
  // setState 触发 listener 链——都会触发"OverlayEntry should be removed
  // only once" assertion。这里用 closure-local bool 守门，多次调用静默忽略。
  bool removed = false;
  void close() {
    if (removed) return;
    removed = true;
    entry.remove();
    onDismiss?.call();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      return _ContextMenuOverlay(
        selectionRect: selectionRect,
        existingHighlight: existingHighlight,
        onHighlight: (color) {
          onHighlight(color);
          close();
        },
        onCopy: () {
          onCopy();
          close();
        },
        onTranslate: () {
          onTranslate();
          close();
        },
        onCreateForNote: onCreateForNote,
        onNoteChanged: onNoteChanged,
        onDelete: onDelete != null
            ? () {
                onDelete();
                close();
              }
            : null,
        onClose: close,
      );
    },
  );
  Overlay.of(context).insert(entry);
  return entry;
}

// ─── Overlay 根组件（有状态，管理笔记面板展开） ───

class _ContextMenuOverlay extends StatefulWidget {
  final Rect selectionRect;
  final Highlight? existingHighlight;
  final void Function(String color) onHighlight;
  final VoidCallback onCopy;
  final VoidCallback onTranslate;
  final Highlight? Function()? onCreateForNote;
  final void Function(String highlightId, String note)? onNoteChanged;
  final VoidCallback? onDelete;
  final VoidCallback onClose;

  const _ContextMenuOverlay({
    required this.selectionRect,
    this.existingHighlight,
    required this.onHighlight,
    required this.onCopy,
    required this.onTranslate,
    this.onCreateForNote,
    this.onNoteChanged,
    this.onDelete,
    required this.onClose,
  });

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay> {
  bool _showNotePanel = false;
  Highlight? _activeHighlight;
  final _noteController = TextEditingController();
  bool _noteDirty = false;

  @override
  void initState() {
    super.initState();
    _activeHighlight = widget.existingHighlight;
  }

  @override
  void dispose() {
    _saveNoteIfDirty();
    _noteController.dispose();
    super.dispose();
  }

  void _saveNoteIfDirty() {
    if (!_noteDirty || _activeHighlight == null) return;
    widget.onNoteChanged?.call(
      _activeHighlight!.id,
      _noteController.text.trim(),
    );
    _noteDirty = false;
  }

  void _handleNoteTap() {
    if (_showNotePanel) {
      _saveNoteIfDirty();
      setState(() => _showNotePanel = false);
      return;
    }

    if (_activeHighlight != null) {
      _noteController.text = _activeHighlight!.note ?? '';
      _noteDirty = false;
      setState(() => _showNotePanel = true);
      return;
    }

    if (widget.onCreateForNote != null) {
      final hl = widget.onCreateForNote!();
      if (hl != null) {
        _activeHighlight = hl;
        _noteController.text = '';
        _noteDirty = false;
        setState(() => _showNotePanel = true);
      }
    }
  }

  void _handleNoteSave() {
    _saveNoteIfDirty();
    FocusScope.of(context).unfocus();
    setState(() => _noteDirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _activeHighlight?.color ?? widget.existingHighlight?.color;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onClose,
          ),
        ),
        CustomSingleChildLayout(
          delegate: _SelectionMenuDelegate(selectionRect: widget.selectionRect),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 6 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 操作栏
                _buildActionBar(activeColor),
                // 笔记面板（展开时显示）
                if (_showNotePanel) ...[
                  const SizedBox(height: 6),
                  _buildNotePanel(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(String? activeColor) {
    return Material(
      elevation: 6,
      color: const Color(0xF0282828),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionIcon(
              icon: Symbols.content_copy_rounded,
              tooltip: '复制',
              onTap: widget.onCopy,
            ),
            const _Divider(),
            for (final color in kHighlightColors)
              _ColorDot(
                hexColor: color,
                isActive: activeColor == color,
                onTap: () => widget.onHighlight(color),
              ),
            const _Divider(),
            _ActionIcon(
              icon: _showNotePanel
                  ? Symbols.edit_note_rounded
                  : Symbols.edit_note_rounded,
              tooltip: '笔记',
              onTap: _handleNoteTap,
              color: _showNotePanel
                  ? const Color(0xFF4FC3F7)
                  : Colors.white,
            ),
            _ActionIcon(
              icon: Symbols.translate_rounded,
              tooltip: '翻译',
              onTap: widget.onTranslate,
            ),
            if (widget.onDelete != null) ...[
              const _Divider(),
              _ActionIcon(
                icon: Symbols.delete_rounded,
                tooltip: '删除高亮',
                onTap: widget.onDelete!,
                color: const Color(0xFFEF5350),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotePanel() {
    return Material(
      elevation: 6,
      color: const Color(0xF0282828),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 160),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _noteController,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '写下你的想法...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (_) {
                    if (!_noteDirty) setState(() => _noteDirty = true);
                  },
                  onSubmitted: (_) => _handleNoteSave(),
                ),
              ),
              if (_noteDirty)
                IconButton(
                  icon: const Icon(
                    Symbols.check_circle_rounded,
                    color: Color(0xFF4FC3F7),
                    size: 22,
                  ),
                  onPressed: _handleNoteSave,
                  tooltip: '保存',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 子组件 ───

class _ColorDot extends StatelessWidget {
  final String hexColor;
  final bool isActive;
  final VoidCallback onTap;

  const _ColorDot({
    required this.hexColor,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse('0xFF$hexColor'));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(200),
            border:
                isActive ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: isActive
              ? const Icon(Symbols.check_rounded,
                  size: 13, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white24,
    );
  }
}

// ─── 定位代理 ───

class _SelectionMenuDelegate extends SingleChildLayoutDelegate {
  final Rect selectionRect;
  static const _gap = 8.0;

  _SelectionMenuDelegate({required this.selectionRect});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final cx = selectionRect.center.dx;
    final clampedX =
        (cx - childSize.width / 2).clamp(8.0, size.width - childSize.width - 8);

    if (selectionRect.bottom + _gap + childSize.height <= size.height) {
      return Offset(clampedX, selectionRect.bottom + _gap);
    }
    return Offset(
      clampedX,
      (selectionRect.top - _gap - childSize.height)
          .clamp(0.0, size.height - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_SelectionMenuDelegate oldDelegate) {
    return selectionRect != oldDelegate.selectionRect;
  }
}
