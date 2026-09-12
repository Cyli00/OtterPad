const kTranslationMarkerOpen = '[[tr]]';
const kTranslationMarkerClose = '[[/tr]]';

class TranslationStyle {
  final String id;

  const TranslationStyle(this.id);
}

const kTranslationStyles = <TranslationStyle>[
  TranslationStyle('themed'),
  TranslationStyle('bold'),
  TranslationStyle('italic'),
  TranslationStyle('weakened'),
  TranslationStyle('dashed'),
  TranslationStyle('highlight'),
  TranslationStyle('blur'),
  TranslationStyle('quote'),
];

const kDefaultTranslationStyleId = 'themed';

TranslationStyle resolveTranslationStyle(String? id) =>
    kTranslationStyles.firstWhere(
      (style) => style.id == id,
      orElse: () => kTranslationStyles.first,
    );
