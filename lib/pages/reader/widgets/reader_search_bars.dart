import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class ReaderPdfSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const ReaderPdfSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onBack,
    required this.onClear,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Symbols.chevron_left_rounded,
                size: 28,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '返回',
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(color: cs.onSurface, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '搜索 PDF 内容',
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant.withAlpha(160),
                      fontSize: 15,
                    ),
                    prefixIcon: Icon(
                      Symbols.search_rounded,
                      size: 20,
                      fill: 1,
                      color: cs.onSurfaceVariant,
                    ),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Symbols.cancel_rounded,
                              size: 18,
                              fill: 1,
                              color: cs.onSurfaceVariant,
                            ),
                            onPressed: onClear,
                          )
                        : null,
                    filled: true,
                    fillColor: cs.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: onSubmitted,
                  onChanged: onChanged,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Symbols.close_rounded,
                size: 22,
                fill: 1,
                color: cs.onSurfaceVariant,
              ),
              tooltip: '退出搜索',
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

class ReaderHighlightSearchBar extends StatelessWidget {
  final String query;
  final VoidCallback onBack;
  final VoidCallback onOpenSearch;
  final VoidCallback onClear;

  const ReaderHighlightSearchBar({
    super.key,
    required this.query,
    required this.onBack,
    required this.onOpenSearch,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Symbols.chevron_left_rounded,
                size: 28,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '返回',
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: onOpenSearch,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.search_rounded,
                        size: 18,
                        fill: 1,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          query,
                          style: TextStyle(color: cs.onSurface, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Symbols.close_rounded,
                size: 22,
                fill: 1,
                color: cs.onSurfaceVariant,
              ),
              tooltip: '退出搜索',
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}
