import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../data/models/book/document.dart';
import '../core/app_logger.dart';

/// 元数据搜索源的抽象接口。
///
/// 每个实现对应一个学术数据库（CrossRef / CNKI / 万方等），
/// [MetadataSearchService] 按优先级依次尝试。
abstract class MetadataSearchSource {
  String get name;

  /// 该源是否适合搜索 [title]。
  /// 例如中文数据库应仅在标题含中文时返回 true。
  bool canSearch(String title);

  Future<List<Document>> search(
    String title, {
    required Dio dio,
    String? author,
    CancelToken? cancelToken,
  });
}

/// 通过标题搜索学术数据库来解析元数据。
///
/// 作为 [IdentifierResolver] 的平行接缝——
/// 后者依赖 DOI/PMID 等显式标识符，本服务在无标识符时用标题搜索回退。
class MetadataSearchService {
  MetadataSearchService._();
  static final MetadataSearchService instance = MetadataSearchService._();

  static const _minSimilarity = 0.55;
  static const _maxResults = 5;

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'OtterPad/0.1 (Flutter; mailto:dev@otterpad.app)',
      },
    ),
  );

  final List<MetadataSearchSource> _sources = [
    _CrossRefSearchSource(),
  ];

  void applyProxy(Enum mode, String host, int port) {
    final adapter = IOHttpClientAdapter();
    switch (mode.name) {
      case 'custom':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY $host:$port';
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        };
      case 'system':
        adapter.createHttpClient = () => HttpClient();
      case 'none':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'DIRECT';
          return client;
        };
    }
    _dio.httpClientAdapter = adapter;
  }

  /// 用标题（和可选作者）在学术数据库中搜索，返回最佳匹配的 Document。
  ///
  /// 多源按优先级尝试，找到高置信匹配即停止。
  /// 返回 null 表示所有源都未找到足够相似的结果。
  Future<Document?> searchByTitle(
    String title, {
    String? author,
    CancelToken? cancelToken,
  }) async {
    final normalizedQuery = _normalizeForComparison(title);
    if (normalizedQuery.length < 4) return null;

    for (final source in _sources) {
      if (!source.canSearch(title)) continue;
      try {
        final results = await source.search(
          title,
          dio: _dio,
          author: author,
          cancelToken: cancelToken,
        );
        final best = _findBestMatch(normalizedQuery, results);
        if (best != null) return best;
      } catch (e) {
        log.d('${source.name} 标题搜索失败: $e');
      }
    }
    return null;
  }

  Document? _findBestMatch(String normalizedQuery, List<Document> candidates) {
    Document? best;
    double bestScore = 0;

    for (final doc in candidates) {
      final normalizedTitle = _normalizeForComparison(doc.title);
      final score = diceCoefficient(normalizedQuery, normalizedTitle);
      if (score > bestScore && score >= _minSimilarity) {
        bestScore = score;
        best = doc;
      }
    }

    return best;
  }

  /// Sørensen–Dice 系数，基于字符 bigram 多重集。
  ///
  /// 对中英文均有效：英文 bigram 如 "ma","ac","ch"；
  /// 中文 bigram 如 "基于","于深","深度"，本身就是有意义的词组。
  @visibleForTesting
  static double diceCoefficient(String a, String b) {
    if (a == b) return 1.0;
    if (a.length < 2 || b.length < 2) return 0.0;

    final countsA = <String, int>{};
    for (int i = 0; i < a.length - 1; i++) {
      final bg = a.substring(i, i + 2);
      countsA[bg] = (countsA[bg] ?? 0) + 1;
    }

    final countsB = <String, int>{};
    for (int i = 0; i < b.length - 1; i++) {
      final bg = b.substring(i, i + 2);
      countsB[bg] = (countsB[bg] ?? 0) + 1;
    }

    int intersection = 0;
    for (final entry in countsA.entries) {
      final countB = countsB[entry.key];
      if (countB != null) {
        intersection += min(entry.value, countB);
      }
    }

    return 2 * intersection / (a.length - 1 + b.length - 1);
  }

  @visibleForTesting
  static String normalizeForComparison(String text) =>
      _normalizeForComparison(text);

  static String _normalizeForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(
          RegExp(r'[^a-z0-9一-鿿㐀-䶿]+'),
          ' ',
        )
        .trim();
  }
}

// ─── CrossRef 搜索源 ──────────────────────────────────────────────────────────

class _CrossRefSearchSource implements MetadataSearchSource {
  @override
  String get name => 'CrossRef';

  @override
  bool canSearch(String title) => true;

  @override
  Future<List<Document>> search(
    String title, {
    required Dio dio,
    String? author,
    CancelToken? cancelToken,
  }) async {
    final queryParams = <String, dynamic>{
      'query.bibliographic': title,
      'rows': MetadataSearchService._maxResults,
      'mailto': 'dev@otterpad.app',
    };
    if (author != null && author.isNotEmpty) {
      queryParams['query.author'] = author;
    }

    final resp = await dio.get(
      'https://api.crossref.org/works',
      queryParameters: queryParams,
      cancelToken: cancelToken,
    );

    final msg = resp.data['message'] as Map<String, dynamic>;
    final items = msg['items'] as List<dynamic>? ?? [];

    return items.map((item) {
      final map = item as Map<String, dynamic>;
      return Document(
        id: '',
        title: _extractFirst(map['title']) ?? '',
        authors: _extractAuthors(map['author']),
        journal: _extractFirst(map['container-title']) ??
            _extractFirst(map['short-container-title']),
        year: _extractYear(map),
        doi: (map['DOI'] as String?)?.toLowerCase(),
        addedAt: DateTime.now(),
      );
    }).where((doc) => doc.title.isNotEmpty).toList();
  }

  String? _extractFirst(dynamic list) {
    if (list is List && list.isNotEmpty) return list.first.toString();
    return null;
  }

  List<String> _extractAuthors(dynamic authorList) {
    if (authorList is! List) return [];
    return authorList
        .map((a) {
          final map = a as Map<String, dynamic>;
          final given = map['given'] as String? ?? '';
          final family = map['family'] as String? ?? '';
          return '$given $family'.trim();
        })
        .where((name) => name.isNotEmpty)
        .toList();
  }

  String? _extractYear(Map<String, dynamic> msg) {
    for (final key in ['published-print', 'published-online', 'published']) {
      final published = msg[key];
      if (published is Map && published['date-parts'] is List) {
        final parts = published['date-parts'] as List;
        if (parts.isNotEmpty && parts.first is List) {
          final year = (parts.first as List).firstOrNull;
          if (year != null) return year.toString();
        }
      }
    }
    return null;
  }
}
