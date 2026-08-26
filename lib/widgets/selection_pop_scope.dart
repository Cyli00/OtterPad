import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/selection_provider.dart';
import '../shortcuts/app_intents.dart';
import '../utils/desktop.dart';

/// 选择模式下拦截系统返回：返回键退出选择而非弹出路由。
class SelectionPopScope extends ConsumerStatefulWidget {
  final String sourceContext;
  final Widget child;
  final VoidCallback? onSelectAll;
  final VoidCallback? onDeleteSelected;

  const SelectionPopScope({
    super.key,
    required this.sourceContext,
    required this.child,
    this.onSelectAll,
    this.onDeleteSelected,
  });

  @override
  ConsumerState<SelectionPopScope> createState() => _SelectionPopScopeState();
}

class _SelectionPopScopeState extends ConsumerState<SelectionPopScope> {
  final _focusNode = FocusNode(debugLabel: 'selectionShortcuts');
  bool _wasActive = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final isActive =
        selection.isActive && selection.sourceContext == widget.sourceContext;

    Widget result = PopScope(
      canPop: !isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(selectionProvider.notifier).exit();
      },
      child: widget.child,
    );

    if (isDesktopOs && isActive) {
      // 进多选会卸掉 header 焦点；把焦点收到本 Shortcuts 子树，Esc/A/Delete 才找得到。
      if (!_wasActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
      result = Shortcuts(
        shortcuts: {
          const SingleActivator(
            LogicalKeyboardKey.escape,
            includeRepeats: false,
          ): const ExitSelectionIntent(),
          desktopActivator(LogicalKeyboardKey.keyA): const SelectAllIntent(),
          const SingleActivator(
            LogicalKeyboardKey.delete,
            includeRepeats: false,
          ): const DeleteSelectedIntent(),
          const SingleActivator(
            LogicalKeyboardKey.backspace,
            includeRepeats: false,
          ): const DeleteSelectedIntent(),
        },
        child: Actions(
          actions: {
            ExitSelectionIntent: EnabledCallbackAction<ExitSelectionIntent>(
              enabled: () => !isEditingText(),
              onInvoke: (_) {
                ref.read(selectionProvider.notifier).exit();
                return null;
              },
            ),
            SelectAllIntent: EnabledCallbackAction<SelectAllIntent>(
              enabled: () => !isEditingText() && widget.onSelectAll != null,
              onInvoke: (_) {
                widget.onSelectAll?.call();
                return null;
              },
            ),
            DeleteSelectedIntent: EnabledCallbackAction<DeleteSelectedIntent>(
              enabled: () =>
                  !isEditingText() &&
                  widget.onDeleteSelected != null &&
                  selection.selectedIds.isNotEmpty,
              onInvoke: (_) {
                widget.onDeleteSelected?.call();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _focusNode,
            canRequestFocus: true,
            skipTraversal: true,
            child: result,
          ),
        ),
      );
    }
    _wasActive = isActive;

    return result;
  }
}
