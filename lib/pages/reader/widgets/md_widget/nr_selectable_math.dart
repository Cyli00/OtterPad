import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

InlineSpan buildNrSelectableMathSpan({
  required String source,
  required String equation,
  required TextStyle style,
  required MathStyle mathStyle,
  required ValueListenable<String?>? selectedTextListenable,
  bool display = false,
  String? trailingText,
}) {
  return TextSpan(
    children: [
      WidgetSpan(
        alignment: display
            ? PlaceholderAlignment.bottom
            : PlaceholderAlignment.middle,
        child: _SelectableMath(
          source: source,
          equation: equation,
          style: style,
          mathStyle: mathStyle,
          selectedTextListenable: selectedTextListenable,
          display: display,
          trailingText: trailingText,
        ),
      ),
      nrInvisibleSourceSpan(source, style),
    ],
  );
}

TextSpan nrInvisibleSourceSpan(String source, TextStyle baseStyle) {
  return TextSpan(
    text: source,
    style: baseStyle.copyWith(
      fontSize: 0.01,
      color: const Color(0x00000000),
      height: 0,
      letterSpacing: 0,
      wordSpacing: 0,
      shadows: const <Shadow>[],
      decoration: TextDecoration.none,
    ),
  );
}

class _SelectableMath extends StatelessWidget {
  final String source;
  final String equation;
  final TextStyle style;
  final MathStyle mathStyle;
  final ValueListenable<String?>? selectedTextListenable;
  final bool display;
  final String? trailingText;

  const _SelectableMath({
    required this.source,
    required this.equation,
    required this.style,
    required this.mathStyle,
    required this.selectedTextListenable,
    required this.display,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final listenable = selectedTextListenable;
    if (listenable == null) {
      return _buildMath(context, selected: false);
    }
    return ValueListenableBuilder<String?>(
      valueListenable: listenable,
      builder: (context, selectedText, _) {
        return _buildMath(
          context,
          selected:
              selectedText != null &&
              selectedText.isNotEmpty &&
              selectedText.contains(source),
        );
      },
    );
  }

  Widget _buildMath(BuildContext context, {required bool selected}) {
    final math = Math.tex(
      equation,
      textStyle: style,
      mathStyle: mathStyle,
      textScaleFactor: 1,
      onErrorFallback: (e) => Text(
        '\$$equation\$',
        style: style.copyWith(
          fontStyle: FontStyle.italic,
          fontSize: (style.fontSize ?? 14) * 0.9,
        ),
      ),
    );

    final body = trailingText == null || trailingText!.isEmpty
        ? math
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                math,
                Text(trailingText!, style: style),
              ],
            ),
          );

    final selectedBody = DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? _selectionColor(context) : Colors.transparent,
      ),
      child: body,
    );

    if (!display) return selectedBody;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Center(child: selectedBody),
          ),
        );
      },
    );
  }

  Color _selectionColor(BuildContext context) {
    return DefaultSelectionStyle.of(context).selectionColor ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.28);
  }
}
