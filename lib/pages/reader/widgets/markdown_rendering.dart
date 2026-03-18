import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart'
    show LatexBlockSyntax;
import 'package:markdown/markdown.dart' as md;

import '../../../utils/latex_syntax.dart';

Map<String, MarkdownElementBuilder> buildMarkdownBuilders({
  required TextStyle latexTextStyle,
  Map<String, MarkdownElementBuilder> extraBuilders = const {},
}) {
  return {
    'latex': NRLatexElementBuilder(textStyle: latexTextStyle),
    'emoji': NREmojiElementBuilder(),
    ...extraBuilders,
  };
}

List<md.InlineSyntax> buildMarkdownInlineSyntaxes({
  List<md.InlineSyntax> prefix = const [],
  List<md.InlineSyntax> suffix = const [],
}) {
  return [
    ...prefix,
    NRLatexInlineSyntax(),
    ...md.ExtensionSet.gitHubWeb.inlineSyntaxes,
    ...suffix,
  ];
}

md.ExtensionSet buildMarkdownExtensionSet(
  List<md.InlineSyntax> inlineSyntaxes,
) {
  return md.ExtensionSet([
    LatexBlockSyntax(),
    ...md.ExtensionSet.gitHubWeb.blockSyntaxes,
  ], inlineSyntaxes);
}

Widget buildMarkdownImage(
  Uri uri,
  String? title,
  String? alt, {
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(vertical: 8),
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final image = uri.scheme == 'file'
          ? Image.file(
              File(uri.toFilePath()),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _BrokenMarkdownImage(),
            )
          : Image.network(
              uri.toString(),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _BrokenMarkdownImage(),
            );

      return Padding(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: image,
            ),
          ),
        ),
      );
    },
  );
}

class NREmojiElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style =
        parentStyle ?? preferredStyle ?? DefaultTextStyle.of(context).style;
    return RichText(
      text: TextSpan(text: element.textContent, style: style),
    );
  }
}

class _BrokenMarkdownImage extends StatelessWidget {
  const _BrokenMarkdownImage();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.broken_image_rounded, size: 48);
  }
}
