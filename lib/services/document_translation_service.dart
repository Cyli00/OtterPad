import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../providers/api_provider.dart';
import '../providers/translation_config_provider.dart';
import '../utils/doc_paths.dart';
import 'markdown_paragraph_extractor.dart';
import 'translation_service.dart';

/// 文档级翻译服务（**单段并发**版）。
///
/// 设计原则（参考 anx-reader 的"单段独立"模型 + Dart 协程并发）：
/// 1. **段粒度独立**：每段一次 LLM 请求，**不再用 `%%%%` 合批**——彻底
///    消除"LLM 漏分隔符 → 整批失败"的塌陷模式（之前一段错全批废）；
/// 2. **N=[_kConcurrency] 协程池并发**：worker 抢占式从队列取段，吃满
///    LLM API 的 RPM 配额，相比之前批次串行可提速 5-10 倍；
/// 3. **指数退避重试**：单段失败重试 2 次（200ms / 400ms 退避），单段
///    最终失败仅丢这一段、不影响其他；
/// 4. **写盘串行化 + 节流**：所有 `translations.json` 写入通过
///    [_saveLock] Future 链顺序执行（避免并发 read-modify-write race），
///    每 [_kSaveEveryN] 段触发一次中间保存，结束时强制最终保存；
/// 5. **段落级持久化** & **多语言共存**：同一 JSON 文件内按目标语言分层。
class DocumentTranslationService {
  DocumentTranslationService._();

  /// 并发请求数。受 LLM provider 的 RPM 限制约束；
  /// 实测 OpenAI / Anthropic / Gemini fast model 都能撑 8。
  static const _kConcurrency = 8;

  /// 每完成多少段触发一次中间写盘。
  /// 太小：fsync 频繁拖慢；太大：意外退出丢失最近段。
  static const _kSaveEveryN = 8;

  /// 单段失败的最大重试次数（首次 + maxRetries 次重试 = 总尝试次数）。
  static const _kMaxRetries = 2;

  // ── 翻译文件 I/O ────────────────────────────────────────────────────

  /// 翻译产物文件路径，与 .md / .json / _figures/ 同级。
  ///
  /// 例：`path/to/paper.pdf` → `path/to/paper.translations.json`
  static String translationFilePath(String pdfPath) =>
      DocPaths.translations(pdfPath);

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

  /// 并发翻译文档段落。
  ///
  /// 实现要点：
  /// - **取段抢占**：所有 worker 共享 [pending] 列表 + `nextIdx` 游标；
  ///   worker 在事件循环空隙读取并自增游标取走下一段。Dart 单线程下
  ///   `nextIdx++` 与读取之间无 await，多 worker 间天然原子；
  /// - **写盘串行**：所有 `translations.json` 写都通过 `saveLock` Future
  ///   链顺序执行。任何 worker 都不直接 await 写盘，避免阻塞；
  /// - **取消语义**：worker 在循环顶检查 [cancelToken]——已在飞的最多
  ///   [_kConcurrency] 个请求会跑完（dio 单次最长 60s），但不再启动新段。
  ///
  /// [useCache] 为 false 时跳过文件缓存查询，所有段都进入 pending（专供
  /// "重新翻译"用）；写入仍执行。
  ///
  /// 返回值：`true` 表示"所有段都命中文件缓存、未向 LLM 发任何请求"（即
  /// 用户其实是在看上次翻译的快照）。调用方据此提示"使用了缓存"；其他
  /// 情况（部分命中、空文档、取消、useCache=false）均返回 `false`。
  static Future<bool> translate({
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
      return false;
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

    // 全部命中文件缓存：直接返回 true，调用方据此提示"使用了缓存"。
    // 此分支仅在 useCache=true 时可能成立（useCache=false 时 pending 必非空）。
    if (pending.isEmpty) return true;

    // ── 并发翻译 ──
    int nextIdx = 0;
    int sinceLastSave = 0;
    Future<void> saveLock = Future.value();

    // 触发一次"按当前 all 快照写盘"——通过 saveLock 链串行化。
    // 用 `Map.from(all)` 拍快照；后续 worker 改 `all` 不影响这次写入内容。
    // 用 catchError 把单次写盘异常隔离在链外——否则一次磁盘错会污染整条
    // future 链，让最终 `await saveLock` 把无关错误抛给上层。
    void scheduleSave() {
      final snapshot = Map<String, String>.from(all);
      saveLock = saveLock
          .then((_) => _saveTranslations(pdfPath, targetLang, snapshot))
          .catchError((Object e) {
        debugPrint('[DocumentTranslation] mid-save failed (ignored): $e');
      });
    }

    Future<void> worker() async {
      while (true) {
        if (cancelToken?.isCancelled == true) return;
        if (nextIdx >= pending.length) return;
        final p = pending[nextIdx++];

        final translation = await _translateOne(
          paragraph: p,
          agentState: agentState,
          config: config,
          useCache: useCache,
        );

        if (translation != null && translation.isNotEmpty) {
          all[p.hash] = translation;
          onResult(p.hash, translation);
        }
        // 这一段无论翻成功与否都计入 done——失败的段会保留原文，
        // 让用户看到的总进度跟段数对齐。
        done++;
        onProgress(done, total);

        sinceLastSave++;
        if (sinceLastSave >= _kSaveEveryN) {
          sinceLastSave = 0;
          scheduleSave();
        }
      }
    }

    final workers = List.generate(_kConcurrency, (_) => worker());
    await Future.wait(workers);

    // 等所有中间写盘任务清空，再做一次最终全量保存。
    await saveLock;
    await _saveTranslations(pdfPath, targetLang, all);
    return false;
  }

  // ── 单段翻译（含重试）────────────────────────────────────────────────

  /// 单段翻译 + 指数退避重试。
  ///
  /// - 成功 → 返回译文（非空字符串）；
  /// - 全部 [_kMaxRetries]+1 次都失败 → 返回 null（这一段保留原文，
  ///   不抛出，避免连累其他并发 worker）。
  ///
  /// 退避：200ms × 2^attempt（200 / 400 ms）。失败原因仅 debugPrint，
  /// 不向上抛——并发场景下任何单点抛错都会让 `Future.wait` 整体失败。
  static Future<String?> _translateOne({
    required TranslatableParagraph paragraph,
    required AgentApiState agentState,
    required TranslationConfig config,
    bool useCache = true,
  }) async {
    Object? lastErr;
    for (int attempt = 0; attempt <= _kMaxRetries; attempt++) {
      try {
        final result = await TranslationService.translate(
          text: paragraph.text,
          agentState: agentState,
          translationConfig: config,
          useCache: useCache,
        );
        if (result.trim().isNotEmpty) return result;
        // 空译文也按失败处理，触发重试
        lastErr = Exception('empty translation result');
      } catch (e) {
        lastErr = e;
      }

      if (attempt < _kMaxRetries) {
        final backoffMs = 200 * (1 << attempt);
        await Future.delayed(Duration(milliseconds: backoffMs));
      }
    }
    debugPrint(
      '[DocumentTranslation] paragraph "${paragraph.hash}" failed '
      'after ${_kMaxRetries + 1} attempts: $lastErr',
    );
    return null;
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
