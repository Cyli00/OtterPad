import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../providers/api_provider.dart';
import '../providers/translation_config_provider.dart';
import '../utils/doc_paths.dart';
import 'markdown_paragraph_extractor.dart';
import 'translation_service.dart';
import '../core/app_logger.dart';

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
      // 文件损坏：改名留档而非静默吞掉——里面是用户付费翻译的唯一副本，
      // 留档至少还有人工恢复的余地。
      try {
        file.renameSync('${file.path}.corrupt');
      } catch (_) {}
      return {};
    }
  }

  /// 原子写 JSON：先写 `.tmp`（flush 落盘）再 rename 覆盖。写入中途进程
  /// 被杀时旧文件完好，不会留下半截 JSON 让 [loadTranslations] 解析失败、
  /// 全部已翻译内容静默归零。
  static Future<void> _writeJsonAtomic(
    File file,
    Map<String, dynamic> root,
  ) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(root),
      flush: true,
    );
    await tmp.rename(file.path);
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
    await _writeJsonAtomic(file, root);
  }

  /// 保存单条翻译（figure title 等外部来源单独翻译后写回共享缓存）。
  static Future<void> saveSingleTranslation(
    String pdfPath,
    String targetLang,
    String hash,
    String translation,
  ) async {
    final existing = loadTranslations(pdfPath, targetLang);
    existing[hash] = translation;
    await _saveTranslations(pdfPath, targetLang, existing);
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
        await _writeJsonAtomic(file, root);
      }
    } catch (_) {}
    log.d(
      '[DocumentTranslation] cleared translations: lang="$targetLang"',
    );
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

    // 接缝 1（缓存分流）：纯函数决定"哪些段要翻、哪些直接用缓存"。
    final partition = partitionParagraphs(
      paragraphs: paragraphs,
      cached: cached,
      useCache: useCache,
    );

    // all 从完整缓存起步（保留当前段集合之外的历史译文），逐段累积新译文。
    final all = Map<String, String>.from(cached);
    var done = 0;
    partition.cachedHits.forEach((hash, translation) {
      onResult(hash, translation);
      done++;
    });
    onProgress(done, total);

    // 全部命中文件缓存：直接返回 true，调用方据此提示"使用了缓存"。
    // 仅在 useCache=true 时可能成立（useCache=false 时 pending 必非空）。
    if (partition.pending.isEmpty) return true;

    // ── 写盘节流 + 接缝 3（并发池）──
    var sinceLastSave = 0;
    Future<void> saveLock = Future.value();

    // 触发一次"按当前 all 快照写盘"——通过 saveLock 链串行化。
    // 用 `Map.from(all)` 拍快照；后续 worker 改 `all` 不影响本次写入内容。
    // catchError 把单次写盘异常隔离在链外，避免污染最终 `await saveLock`。
    void scheduleSave() {
      final snapshot = Map<String, String>.from(all);
      saveLock = saveLock
          .then((_) => _saveTranslations(pdfPath, targetLang, snapshot))
          .catchError((Object e) {
            log.d('[DocumentTranslation] mid-save failed (ignored): $e');
          });
    }

    Future<String> translateOne(String text) => TranslationService.translate(
      text: text,
      agentState: agentState,
      translationConfig: config,
      useCache: useCache,
    );

    await runConcurrent<TranslatableParagraph>(
      items: partition.pending,
      concurrency: _kConcurrency,
      isCancelled: () => cancelToken?.isCancelled == true,
      task: (p) async {
        // 接缝 2（重试策略）：单段失败重试 + 退避，最终失败仅丢该段、保留原文。
        final translation = await translateWithRetry(
          text: p.text,
          translator: translateOne,
          debugLabel: p.hash,
        );
        if (translation != null && translation.isNotEmpty) {
          all[p.hash] = translation;
          onResult(p.hash, translation);
        }
        // 无论成功与否都计入 done——失败段保留原文，进度与段数对齐。
        done++;
        onProgress(done, total);

        sinceLastSave++;
        if (sinceLastSave >= _kSaveEveryN) {
          sinceLastSave = 0;
          scheduleSave();
        }
      },
    );

    // 等所有中间写盘清空，再做一次最终全量保存（失败会上抛给调用方）。
    await saveLock;
    await _saveTranslations(pdfPath, targetLang, all);
    return false;
  }

  // ── 内部接缝（@visibleForTesting，可脱离 LLM / 磁盘单测）─────────────────

  /// 接缝 1：缓存分流（纯函数）。useCache=false 时全部进 pending。
  @visibleForTesting
  static TranslationPartition partitionParagraphs({
    required List<TranslatableParagraph> paragraphs,
    required Map<String, String> cached,
    required bool useCache,
  }) {
    if (!useCache) {
      return TranslationPartition(
        pending: List<TranslatableParagraph>.of(paragraphs),
        cachedHits: const {},
      );
    }
    final pending = <TranslatableParagraph>[];
    final cachedHits = <String, String>{};
    for (final p in paragraphs) {
      final t = cached[p.hash];
      if (t != null && t.isNotEmpty) {
        cachedHits[p.hash] = t;
      } else {
        pending.add(p);
      }
    }
    return TranslationPartition(pending: pending, cachedHits: cachedHits);
  }

  /// 接缝 2：单段翻译 + 指数退避重试。注入 [translator] 以便无 LLM 单测；
  /// [backoff] 默认 200ms × 2^attempt，测试可注入 no-op 跳过等待。空译文按失败重试。
  /// 全部尝试失败返回 null（保留原文，不抛，避免连累并发池里的其他 worker）。
  @visibleForTesting
  static Future<String?> translateWithRetry({
    required String text,
    required ParagraphTranslator translator,
    int maxRetries = _kMaxRetries,
    Future<void> Function(int attempt)? backoff,
    String? debugLabel,
  }) async {
    Object? lastErr;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final result = await translator(text);
        if (result.trim().isNotEmpty) return result;
        lastErr = Exception('empty translation result');
      } catch (e) {
        lastErr = e;
      }
      if (attempt < maxRetries) {
        await (backoff?.call(attempt) ??
            Future<void>.delayed(Duration(milliseconds: 200 * (1 << attempt))));
      }
    }
    log.d(
      '[DocumentTranslation] paragraph "${debugLabel ?? ''}" failed '
      'after ${maxRetries + 1} attempts: $lastErr',
    );
    return null;
  }

  /// 接缝 3：N 协程并发池——worker 抢占 `nextIdx` 取 item，吃满 RPM 配额。
  /// `nextIdx++` 与读取之间无 await，Dart 单线程下天然原子。
  @visibleForTesting
  static Future<void> runConcurrent<T>({
    required List<T> items,
    required int concurrency,
    required Future<void> Function(T item) task,
    bool Function()? isCancelled,
  }) async {
    var nextIdx = 0;
    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        if (nextIdx >= items.length) return;
        final item = items[nextIdx++];
        await task(item);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
  }
}

// ── 内部接缝的值类型 ───────────────────────────────────────────────────

/// 注入式单段翻译函数——生产用 [TranslationService.translate]，测试可注入桩。
typedef ParagraphTranslator = Future<String> Function(String text);

/// [DocumentTranslationService.partitionParagraphs] 的结果：
/// `pending` = 需请求 LLM 的段；`cachedHits` = 命中文件缓存、直接复用的 hash→译文。
class TranslationPartition {
  final List<TranslatableParagraph> pending;
  final Map<String, String> cachedHits;
  const TranslationPartition({required this.pending, required this.cachedHits});
}

// ── 取消令牌 ───────────────────────────────────────────────────────────

/// 翻译取消令牌——简单布尔闭包，不与 dio.CancelToken 混用。
/// 单批请求一旦发出就不可中断；cancel 只阻止后续批次。
class TranslationCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
