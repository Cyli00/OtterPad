class MinerUParseOptions {
  MinerUParseOptions._();

  static const models = ['vlm', 'pipeline'];
  static const languages = [
    'ch',
    'ch_server',
    'en',
    'japan',
    'korean',
    'chinese_cht',
    'ta',
    'te',
    'ka',
    'el',
    'th',
    'latin',
    'arabic',
    'cyrillic',
    'east_slavic',
    'devanagari',
  ];
  static const extraFormats = ['docx', 'html', 'latex'];

  static String normalizePageRanges(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').replaceAll('，', ',');

  static bool isValidPageRanges(String value) {
    final normalized = normalizePageRanges(value);
    if (normalized.isEmpty) return true;
    final pattern = RegExp(r'^([1-9][0-9]*)(?:-(-?[1-9][0-9]*))?$');
    for (final part in normalized.split(',')) {
      final match = pattern.firstMatch(part);
      if (match == null) return false;
      final start = int.tryParse(match[1]!);
      final end = match[2] == null ? null : int.tryParse(match[2]!);
      if (start == null || (match[2] != null && end == null)) return false;
      if (end != null && end > 0 && end < start) return false;
    }
    return true;
  }
}
