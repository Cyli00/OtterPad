import 'package:flutter/material.dart';
import 'appearance_palette.dart';
import 'l10n.dart';
import 'paper_theme.dart';
import 'paper_surfaces.dart';

class AppearanceReader extends StatelessWidget {
  const AppearanceReader({super.key, required this.paper, required this.pdf});
  final AppearancePaper paper;
  final bool pdf;

  @override
  Widget build(BuildContext context) {
    if (pdf) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: MediaQuery.withNoTextScaling(
          child: SizedBox(
            width: 560,
            child: DecoratedBox(
              key: const ValueKey('appearance-original-page'),
              decoration: const BoxDecoration(color: Colors.white),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _article(
                  context,
                  AppearancePaper.original,
                  original: true,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return _article(context, paper);
  }

  Widget _article(
    BuildContext context,
    AppearancePaper palette, {
    bool original = false,
  }) {
    final l = context.l10n;
    final text = original
        ? paperTheme(Brightness.light).textTheme
        : Theme.of(context).textTheme;
    final ink = palette.ink;
    final link = paperTheme(palette.brightness).colorScheme.primary;
    final body = text.bodyLarge!.copyWith(
      color: ink,
      fontSize: original ? 15 : 16,
      height: 1.85,
    );
    final muted = text.bodySmall!.copyWith(color: palette.muted);
    return DefaultTextStyle(
      style: body,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.appearanceArticleKicker, style: muted),
          const SizedBox(height: 12),
          Text(
            l.appearanceArticleTitle,
            style: text.titleLarge!.copyWith(
              color: ink,
              fontSize: original ? 30 : 24,
            ),
          ),
          const SizedBox(height: 10),
          Text(l.appearanceArticleByline, style: muted),
          const SizedBox(height: 24),
          SelectableText(l.appearanceArticleIntro, style: body),
          const SizedBox(height: 24),
          Text(
            l.appearanceArticleHeading,
            style: text.titleSmall!.copyWith(color: ink),
          ),
          const SizedBox(height: 12),
          SelectableText(l.appearanceArticleBody, style: body),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                link.withValues(alpha: .08),
                palette.background,
              ),
              border: Border(left: BorderSide(color: link, width: 2)),
            ),
            child: Text(
              l.appearanceQuote,
              style: body.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 24),
          _figure(context),
          const SizedBox(height: 8),
          Text(l.appearanceFigureCaption, style: muted),
          const SizedBox(height: 24),
          Text(l.appearanceArticleEnd, style: body),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => showPaperDialog<void>(
              context,
              (dialogContext) => PaperDialog(
                title: l.appearanceReference,
                children: [Text(l.appearanceSampleHelp)],
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(l.close),
                  ),
                ],
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: link,
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.zero,
            ),
            child: Text(l.appearanceReference),
          ),
        ],
      ),
    );
  }

  Widget _figure(BuildContext context) {
    final l = context.l10n;
    // 模拟文献嵌图：配色固定，不随应用强调色或纸面变化。
    return Container(
      key: const ValueKey('appearance-original-figure'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle(
        style: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: const Color(0xFF41433F)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.appearanceFigureTitle),
            const SizedBox(height: 16),
            for (final entry in [
              (l.appearanceFigureA, .78, const Color(0xFF53738B)),
              (l.appearanceFigureB, .56, const Color(0xFFB38458)),
              (l.appearanceFigureC, .66, const Color(0xFF68836B)),
            ]) ...[
              Text(entry.$1),
              const SizedBox(height: 5),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: entry.$2,
                child: Container(height: 12, color: entry.$3),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
