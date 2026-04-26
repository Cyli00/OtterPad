import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../providers/api_provider.dart';
import '../providers/translation_config_provider.dart';
import 'markdown_paragraph_extractor.dart';
import 'translation_service.dart';

/// 文档级批量翻译服务。
///
/// 特性：
/// 1. **段落级持久化**（JSON 文件，与 .md / .json / _figures/ 同级）；
/// 2. **多语言共存**：同一文件内按目标语言分层存储；
/// 3. **批次合并**：每批 ≤[_kBatchMaxChars]/≤[_kBatchMaxParas]，用 `%%%%` 分隔；
/// 4. **段数鲁棒性**：返回的分段数容忍头尾空段；严格相等才算成功，
///    不等时整批 fallback（调用方保留原文）+ debugPrint 诊断；
/// 5. **增量回调**：每批完成立即 `onResult`，翻译结果逐批写入文件。
class DocumentTranslationService {
  DocumentTranslationService._();

  static const _kBatchMaxChars = 6000;
  static const _kBatchMaxParas = 10;
  static const _kSeparator = '\n\n%%%%\n\n';
  static final _kSplitPattern = RegExp(r'\n*%%%%\n*');

  // ── 翻译文件 I/O ────────────────────────────────────────────────────

  /// 翻译产物文件路径，与 .md / .json / _figures/ 同级。
  ///
  /// 例：`path/to/paper.pdf` → `path/to/paper.translations.json`
  static String translationFilePath(String pdfPath) {
    final dotIdx = pdfPath.lastIndexOf('.');
    final stem = dotIdx > 0 ? pdfPath.substring(0, dotIdx) : pdfPath;
    return '$stem.translations.json';
  }

  /// 从文件加载指定语言的翻译结果；文件不存在或格式异常返回空 map。
  static Map<String, String> loadTranslations(
    String pdfPath,
    String targetLang,
  ) {
    final file = File(translationFilePath(pdfPath));
    if (!file.existsSync()) return {};
    try {
      final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final langMap = root[targetLang] as Map<String, dynamic>?;
      if (langMap == null) return {};
      return langMap.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  /// 保存翻译结果到文件，保留其他语言的已有翻译。
  static Future<void> _saveTranslations(
    String pdfPath,
    String targetLang,
    Map<String, String> translations,
  ) async {
    final file = File(translationFilePath(pdfPath));
    Map<String, dynamic> root = {};
    if (file.existsSync()) {
      try {
        root = Map<String, dynamic>.from(
          jsonDecode(file.readAsStringSync()) as Map,
        );
      } catch (_) {}
    }
    root[targetLang] = translations;
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(root));
  }

  /// 清除指定语言的翻译。文件中无其他语言时删除整个文件。
  static Future<void> clearTranslations(
    String pdfPath,
    String targetLang,
  ) async {
    final file = File(translationFilePath(pdfPath));
    if (!file.existsSync()) return;
    try {
      final root = Map<String, dynamic>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
      root.remove(targetLang);
      if (root.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(root),
        );
      }
    } catch (_) {}
    debugPrint('[DocumentTranslation] cleared translations: lang="$targetLang"');
  }

  // ── 核心入口 ─────────────────────────────────────────────────────────

  /// 批量翻译文档段落。
  ///
  /// [cancelToken] 在每批之间检查——单批请求一旦开始就不可中断，
  /// 但后续批次会被阻止，符合用户取消的直觉体感。
  ///
  /// [useCache] 为 false 时跳过查询文件缓存，所有段落都进入 pending
  /// 重新请求 LLM——专供"重新翻译"使用。写入文件仍然执行。
  static Future<void> translate({
    required String pdfPath,
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

    final targetLang = config.targetLanguage;
    final cached = useCache
        ? loadTranslations(pdfPath, targetLang)
        : <String, String>{};
    final all = Map<String, String>.from(cached);
    final pending = <TranslatableParagraph>[];
    int done = 0;

    if (useCache) {
      for (final p in paragraphs) {
        final t = cached[p.hash];
        if (t != null && t.isNotEmpty) {
          onResult(p.hash, t);
          done++;
        } else {
          pending.add(p);
        }
      }
    } else {
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
          all[p.hash] = t;
          onResult(p.hash, t);
        }
        done++;
      }
      await _saveTranslations(pdfPath, targetLang, all);
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

    final parts = raw.split(_kSplitPattern).map((s) => s.trim()).toList();
    while (parts.isNotEmpty && parts.first.isEmpty) {
      parts.removeAt(0);
    }
    while (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }

    if (parts.length != batch.length) {
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
}

// ── 取消令牌 ───────────────────────────────────────────────────────────

/// 翻译取消令牌——简单布尔闭包，不与 dio.CancelToken 混用。
/// 单批请求一旦发出就不可中断；cancel 只阻止后续批次。
class TranslationCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
