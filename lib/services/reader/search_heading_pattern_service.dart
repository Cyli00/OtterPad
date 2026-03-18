import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SearchHeadingPatternConfig {
  final RegExp atxHeadingPattern;
  final RegExp setextUnderlinePattern;
  final RegExp numberingPrefixPattern;
  final List<SectionHeadingPatternEntry> headingPatterns;
  final List<RegExp> resetPatterns;

  const SearchHeadingPatternConfig({
    required this.atxHeadingPattern,
    required this.setextUnderlinePattern,
    required this.numberingPrefixPattern,
    required this.headingPatterns,
    required this.resetPatterns,
  });

  factory SearchHeadingPatternConfig.fromJson(Map<String, dynamic> json) {
    final parsing =
        (json['parsing'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final headingPatterns = (json['heading_patterns'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (entry) => SectionHeadingPatternEntry.fromJson(
            entry.cast<String, dynamic>(),
          ),
        )
        .toList();
    final resetPatterns = (json['reset_patterns'] as List? ?? const [])
        .whereType<String>()
        .map((pattern) => RegExp(pattern, caseSensitive: false))
        .toList();

    return SearchHeadingPatternConfig(
      atxHeadingPattern: RegExp(
        parsing['atx_heading'] as String? ?? r'^\s{0,3}#{1,6}\s*(.+?)\s*#*\s*$',
      ),
      setextUnderlinePattern: RegExp(
        parsing['setext_underline'] as String? ?? r'^\s{0,3}(?:=+|-+)\s*$',
      ),
      numberingPrefixPattern: RegExp(
        parsing['numbering_prefix'] as String? ??
            r'^(?:section\s+)?(?:\d+(?:\.\d+)*|[ivxlcdm]+)\s*[:.)-]?\s+',
        caseSensitive: false,
      ),
      headingPatterns: headingPatterns,
      resetPatterns: resetPatterns,
    );
  }

  factory SearchHeadingPatternConfig.fallback() {
    return SearchHeadingPatternConfig.fromJson({
      'parsing': {
        'atx_heading': r'^\s{0,3}#{1,6}\s*(.+?)\s*#*\s*$',
        'setext_underline': r'^\s{0,3}(?:=+|-+)\s*$',
        'numbering_prefix':
            r'^(?:section\s+)?(?:\d+(?:\.\d+)*|[ivxlcdm]+)\s*[:.)-]?\s+',
      },
      'heading_patterns': [
        {'display': 'Abstract', 'pattern': r'^abstract$'},
        {'display': 'Summary', 'pattern': r'^summary$'},
        {'display': 'In Brief', 'pattern': r'^in brief$'},
        {
          'display': 'Introduction',
          'pattern': r'^(?:introduction|background)$',
        },
        {
          'display': 'Methods',
          'pattern': r'^(?:materials? and methods?|methods?|methodology)$',
        },
        {
          'display': 'Methods',
          'pattern':
              r'^(?:experimental (?:section|procedures?|design)|study design)$',
        },
        {'display': 'Results', 'pattern': r'^(?:results?|findings)$'},
        {
          'display': 'Results and Discussion',
          'pattern': r'^results? and discussion$',
        },
        {'display': 'Discussion', 'pattern': r'^(?:discussion|analysis)$'},
        {
          'display': 'Conclusion',
          'pattern': r'^(?:conclusions?|concluding remarks?)$',
        },
        {'display': 'Conclusion', 'pattern': r'^(?:future work|outlook)$'},
      ],
      'reset_patterns': [
        r'^(?:keywords?|acknowledg(?:e)?ments?|funding|author contributions?|'
            r'data availability|ethics statement|ethics approval|'
            r'conflicts? of interest|references?|bibliography|appendix|appendices|'
            r'supplementary(?: materials?| information)?)$',
      ],
    });
  }
}

class SectionHeadingPatternEntry {
  final RegExp pattern;
  final String display;

  const SectionHeadingPatternEntry({
    required this.pattern,
    required this.display,
  });

  factory SectionHeadingPatternEntry.fromJson(Map<String, dynamic> json) {
    return SectionHeadingPatternEntry(
      pattern: RegExp(
        json['pattern'] as String? ?? '',
        caseSensitive: json['case_sensitive'] as bool? ?? false,
      ),
      display: json['display'] as String? ?? '',
    );
  }
}

class SearchHeadingPatternService {
  static const String assetPath = 'assets/config/search_heading_patterns.json';
  static Future<SearchHeadingPatternConfig>? _cachedConfig;

  static Future<SearchHeadingPatternConfig> load() {
    return _cachedConfig ??= _loadInternal();
  }

  static Future<SearchHeadingPatternConfig> _loadInternal() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('章节规则配置格式无效');
      }
      return SearchHeadingPatternConfig.fromJson(decoded);
    } catch (error, stackTrace) {
      debugPrint('加载章节规则配置失败，已回退到内置规则: $error');
      debugPrintStack(stackTrace: stackTrace);
      return SearchHeadingPatternConfig.fallback();
    }
  }
}
