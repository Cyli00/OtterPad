import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../widgets/tactile_press.dart';

class ChatFigureAttachment extends StatelessWidget {
  final String imagePath;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;
  const ChatFigureAttachment({
    super.key,
    required this.imagePath,
    required this.onOpen,
    this.onRemove,
  });

  Widget _image(BuildContext context, {int? cacheWidth}) => Image.file(
    File(imagePath),
    fit: BoxFit.contain,
    cacheWidth: cacheWidth,
    errorBuilder: (_, _, _) => Center(
      child: Tooltip(
        message: context.l10n.chatImageUnavailable,
        child: const Icon(Symbols.broken_image_rounded),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        children: [
          Positioned.fill(
            child: Tooltip(
              message: context.l10n.chatPreviewFigure,
              child: TactilePress(
                baseColor: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                onTap: onOpen,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _image(context, cacheWidth: 312),
                  ),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filledTonal(
                tooltip: context.l10n.chatRemoveQuote,
                onPressed: onRemove,
                icon: const Icon(Symbols.close_rounded, size: 18),
                style: IconButton.styleFrom(
                  minimumSize: const Size(32, 32),
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
