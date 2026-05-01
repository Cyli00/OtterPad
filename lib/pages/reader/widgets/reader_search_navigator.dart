import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class ReaderPdfResultNavigator extends StatelessWidget {
  final int currentIndex;
  final int total;
  final double? progress;
  final bool searching;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const ReaderPdfResultNavigator({
    super.key,
    required this.currentIndex,
    required this.total,
    required this.progress,
    required this.searching,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = currentIndex + 1;

    return Material(
      elevation: 2,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _navButton(
            cs,
            icon: Symbols.expand_less_rounded,
            tooltip: '上一个结果',
            onPressed: total > 0 ? onPrevious : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Text(
                  total > 0 ? '$current/$total' : '0/0',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (searching && progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 28,
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: 2,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _navButton(
            cs,
            icon: Symbols.expand_more_rounded,
            tooltip: '下一个结果',
            onPressed: total > 0 ? onNext : null,
          ),
        ],
      ),
    );
  }
}

class ReaderTextResultNavigator extends StatelessWidget {
  final int currentIndex;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const ReaderTextResultNavigator({
    super.key,
    required this.currentIndex,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = currentIndex + 1;

    return Material(
      elevation: 2,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _navButton(
            cs,
            icon: Symbols.expand_less_rounded,
            tooltip: '上一个结果',
            onPressed: onPrevious,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$current/$total',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _navButton(
            cs,
            icon: Symbols.expand_more_rounded,
            tooltip: '下一个结果',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

Widget _navButton(
  ColorScheme cs, {
  required IconData icon,
  required String tooltip,
  required VoidCallback? onPressed,
}) {
  return SizedBox(
    width: 48,
    height: 48,
    child: IconButton(
      icon: Icon(icon, size: 24, fill: 1, color: cs.onSurface),
      tooltip: tooltip,
      onPressed: onPressed,
    ),
  );
}
