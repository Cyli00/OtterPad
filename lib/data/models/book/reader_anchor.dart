import 'dart:convert';

class ReaderAnchor {
  final List<ReaderAnchorRange> ranges;
  const ReaderAnchor(this.ranges);

  Map<String, dynamic> toJson() => {
    'version': 1,
    'ranges': ranges.map((r) => r.toJson()).toList(),
  };

  static ReaderAnchor? parse(Object? value) {
    try {
      final json = value is String ? jsonDecode(value) : value;
      if (json is! Map || json['version'] != 1) return null;
      final ranges = (json['ranges'] as List)
          .map(
            (r) =>
                ReaderAnchorRange.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
      if (ranges.isEmpty ||
          ranges.any((r) => r.start < 0 || r.end <= r.start)) {
        return null;
      }
      return ReaderAnchor(ranges);
    } catch (_) {
      return null;
    }
  }
}

class ReaderAnchorRange {
  final String paragraphId;
  final String language;
  final String revision;
  final int start;
  final int end;
  final String quote;
  final String prefix;
  final String suffix;

  const ReaderAnchorRange({
    required this.paragraphId,
    required this.language,
    required this.revision,
    required this.start,
    required this.end,
    required this.quote,
    this.prefix = '',
    this.suffix = '',
  });

  factory ReaderAnchorRange.fromJson(Map<String, dynamic> json) =>
      ReaderAnchorRange(
        paragraphId: json['paragraphId'] as String,
        language: json['language'] as String,
        revision: json['revision'] as String,
        start: json['start'] as int,
        end: json['end'] as int,
        quote: json['quote'] as String,
        prefix: json['prefix'] as String? ?? '',
        suffix: json['suffix'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'paragraphId': paragraphId,
    'language': language,
    'revision': revision,
    'start': start,
    'end': end,
    'quote': quote,
    'prefix': prefix,
    'suffix': suffix,
  };

  ({int start, int end})? resolve(String text, String currentRevision) {
    if (revision == currentRevision &&
        start >= 0 &&
        end > start &&
        end <= text.length &&
        text.substring(start, end) == quote) {
      return (start: start, end: end);
    }
    final matches = <int>[];
    var cursor = 0;
    while (quote.isNotEmpty && cursor <= text.length) {
      final at = text.indexOf(quote, cursor);
      if (at < 0) break;
      if (text.substring(0, at).endsWith(prefix) &&
          text.substring(at + quote.length).startsWith(suffix)) {
        matches.add(at);
      }
      cursor = at + 1;
    }
    if (matches.length != 1) return null;
    return (start: matches.single, end: matches.single + quote.length);
  }
}
