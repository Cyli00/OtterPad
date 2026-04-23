import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/storage.dart';
import '../providers/api_provider.dart';
import '../providers/translation_config_provider.dart';
import 'markdown_paragraph_extractor.dart';
import 'translation_service.dart';

/// 文档级批量翻译服务。
///
/// 特性：
/// 1. **段落级缓存**（7 天，Hive，按目标语言 + 段 hash 索引）；
/// 2. **批次合并**：每批 ≤[_kBatchMaxChars]/≤[_kBatchMaxParas]，用 `%%%%` 分隔；
/// 3. **段数鲁棒性**：返回的分段数容忍头尾空段；严格相等才算成功，
///    不等时整批 fallback（调用方保留原文）+ debugPrint 诊断；
/// 4. **增量回调**：每批完成立即 `onResult`，缓存逐批写入；
/// 5. **上下文依赖 LLM 自身能力**：批内多段天然处于同一 prompt 里，
///    术语 / 语气的一致性交给模型处理，不做段落合并。
class DocumentTranslationService {
  DocumentTranslationService._();

  static const _cacheBoxKey = 'document_translation_cache';
  static const _kBatchMaxChars = 6000; // 累计原文字符上限 / 批（≈ 1500 token）
  static const _kBatchMaxParas = 10;
  static const _kSeparator = '\n\n%%%%\n\n';
  static final _kSplitPattern = RegExp(r'\n*%%%%\n*');
  static const _kCacheTtl = Duration(days: 7);

  /// 核心入口。参见类注释。
  ///
  /// [cancelToken] 在每批之间检查——单批请求一旦开始就不可中断，
  /// 但后续批次会被阻止，符合用户取消的直觉体感。
  ///
  /// [useCache] 为 false 时跳过查询 Hive 的步骤，所有段落都进入 pending
  /// 重新请求 LLM——专供"重新翻译"使用。写入缓存仍然执行（给下次非
  /// 强制翻译使用）。
  static Future<void> translate({
    required List<TranslatableParagraph> paragraphs,
    required AgentApiState agentState,
    required TranslationConfig config,
    required void Function(String hash, String translation) onResult,
    required void Function(int done, int total) onProgress,
    TranslationCancelToken? cancelToken,
    bool useCache = true,
  }) async {
    final total = paragraphs.length;
    if (total == 0) {
      onProgress(0, 0);
      return;
    }
    onProgress(0, total);

    final cacheMap = _loadCacheMap();
    final pending = <TranslatableParagraph>[];
    int done = 0;

    if (useCache) {
      for (final p in paragraphs) {
        final key = _cacheKey(p.hash, config.targetLanguage);
        final cached = _readCache(cacheMap, key);
        if (cached != null) {
          onResult(p.hash, cached);
          done++;
        } else {
          pending.add(p);
        }
      }
    } else {
      // 跳过缓存：所有段落强制重新翻译
      pending.addAll(paragraphs);
    }
    onProgress(done, total);

    if (pending.isEmpty) return;

    // ── 分批翻译 ──
    final batches = _splitBatches(pending);
    for (final batch in batches) {
      if (cancelToken?.isCancelled == true) return;

      final results = await _translateBatch(
        batch: batch,
        agentState: agentState,
        config: config,
        useCache: useCache,
      );

      for (int i = 0; i < batch.length; i++) {
        final p = batch[i];
        final t = results[i];
        if (t != null && t.isNotEmpty) {
          _writeCache(cacheMap, _cacheKey(p.hash, config.targetLanguage), t);
          onResult(p.hash, t);
        }
        done++;
      }
      _saveCacheMap(cacheMap);
      onProgress(done, total);
    }
  }

  // ── 批次切分 ─────────────────────────────────────────────────────────

  static List<List<TranslatableParagraph>> _splitBatches(
    List<TranslatableParagraph> pending,
  ) {
    final batches = <List<TranslatableParagraph>>[];
    var current = <TranslatableParagraph>[];
    var currentChars = 0;

    for (final p in pending) {
      // 单段超预算：独立一批，避免切碎语义
      if (p.text.length > _kBatchMaxChars) {
        if (current.isNotEmpty) {
          batches.add(current);
          current = [];
          currentChars = 0;
        }
        batches.add([p]);
        continue;
      }

      if (current.length >= _kBatchMaxParas ||
          currentChars + p.text.length > _kBatchMaxChars) {
        batches.add(current);
        current = [];
        currentChars = 0;
      }

      current.add(p);
      currentChars += p.text.length;
    }

    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  // ── 单批翻译 ─────────────────────────────────────────────────────────

  /// 返回与 [batch] 等长的译文列表。
  ///
  /// 失败语义分两类：
  /// - **网络 / API 层异常**（鉴权失败、超时、模型返回错等）→ **抛出**。
  ///   让外层 translate 的 try-catch 捕获并把 state 设为 failed——UI 会
  ///   显示"翻译失败"消息，而不是静默假装"翻完了"。
  /// - **段数不匹配**（LLM 没严格遵守 `%%%%` 分隔规则）→ 整批 fallback 为
  ///   null 列表，调用方保留这一批的原文，其他批次继续。
  static Future<List<String?>> _translateBatch({
    required List<TranslatableParagraph> batch,
    required AgentApiState agentState,
    required TranslationConfig config,
    bool useCache = true,
  }) async {
    if (batch.length == 1) {
      final single = await TranslationService.translate(
        text: batch[0].text,
        agentState: agentState,
        translationConfig: config,
        useCache: useCache,
      );
      return [single];
    }

    final input = batch.map((p) => p.text).join(_kSeparator);

    final raw = await TranslationService.translate(
      text: input,
      agentState: agentState,
      translationConfig: config,
      useCache: useCache,
    );

    // LLM 可能在整个返回的开头/结尾额外加 `%%%%` 或空行——trim 每段
    // 并剥除头尾空元素，再做段数校验。
    final parts = raw.split(_kSplitPattern).map((s) => s.trim()).toList();
    while (parts.isNotEmpty && parts.first.isEmpty) {
      parts.removeAt(0);
    }
    while (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }

    if (parts.length != batch.length) {
      // 只有段数对不上才 fallback——网络 / API 错误已在上方抛出
      final preview = raw.length > 240 ? '${raw.substring(0, 240)}…' : raw;
      debugPrint(
        '[DocumentTranslation] batch size mismatch: '
        'expected ${batch.length}, got ${parts.length}. '
        'Raw preview: $preview',
      );
      return List<String?>.filled(batch.length, null);
    }
    return parts;
  }

  // ── 缓存失效（供"重新翻译"调用）──────────────────────────────────────

  /// 清除指定段落集合对应的 Hive 缓存条目。
  /// 目标语言作为 key 前缀，不会误清其他语种的缓存。
  static void clearCacheFor(
    List<TranslatableParagraph> paragraphs,
    String targetLang,
  ) {
    final map = _loadCacheMap();
    int cleared = 0;
    for (final p in paragraphs) {
      final key = _cacheKey(p.hash, targetLang);
      if (map.remove(key) != null) cleared++;
    }
    if (cleared > 0) {
      GStorage.setting.put(_cacheBoxKey, jsonEncode(map));
    }
    debugPrint(
      '[DocumentTranslation] clearCacheFor: '
      '$cleared / ${paragraphs.length} entries removed '
      '(lang="$targetLang")',
    );
  }

  // ── Hive 缓存（7 天 TTL）─────────────────────────────────────────────

  static String _cacheKey(String hash, String targetLang) =>
      'dtr_${targetLang}_$hash';

  static Map<String, dynamic> _loadCacheMap() {
    final raw = GStorage.setting.get(_cacheBoxKey);
    if (raw is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return {};
  }

  static String? _readCache(Map<String, dynamic> map, String key) {
    final entry = map[key];
    if (entry is Map<String, dynamic>) {
      final ts = entry['ts'] as int? ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age < _kCacheTtl.inMilliseconds) {
        return entry['translation'] as String?;
      }
    }
    return null;
  }

  static void _writeCache(
      Map<String, dynamic> map, String key, String translation) {
    map[key] = {
      'translation': translation,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
  }

  static void _saveCacheMap(Map<String, dynamic> map) {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _kCacheTtl.inMilliseconds;
    map.removeWhere((_, v) {
      if (v is Map<String, dynamic>) {
        return (v['ts'] as int? ?? 0) < cutoff;
      }
      return true;
    });
    GStorage.setting.put(_cacheBoxKey, jsonEncode(map));
  }
}

// ── 取消令牌 ───────────────────────────────────────────────────────────

/// 翻译取消令牌——简单布尔闭包，不与 dio.CancelToken 混用。
/// 单批请求一旦发出就不可中断；cancel 只阻止后续批次。
class TranslationCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
