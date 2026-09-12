import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/selection_provider.dart';

/// 选择模式下拦截系统返回：返回键退出选择而非弹出路由。
class SelectionPopScope extends ConsumerWidget {
  final String sourceContext;
  final Widget child;

  const SelectionPopScope({
    super.key,
    required this.sourceContext,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(
      selectionProvider.select(
        (s) => s.isActive && s.sourceContext == sourceContext,
      ),
    );

    return PopScope(
      canPop: !isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(selectionProvider.notifier).exit();
      },
      child: child,
    );
  }
}
