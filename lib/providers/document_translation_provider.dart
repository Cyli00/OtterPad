import '../core/storage/storage_activity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/l10n.dart';
import '../router/app_router.dart';
import '../services/ai_settings_prompt.dart';
import '../services/document_translation_service.dart';
import '../services/markdown_paragraph_extractor.dart';
import '../services/reader/reader_document_index.dart';
import '../services/snackbar_service.dart';
import '../utils/markdown_translation_weaver.dart';
import 'agent_api_provider.dart';
import 'translation_config_provider.dart';

// ── 状态模型 ─────────────────────────────────────────────────────────

enum DocTranslationStatus { idle, loading, done, failed }

class DocumentTranslationState {
  final DocTranslationStatus status;
  final Map<String, String> translations;
  final List<TranslatableParagraph> paragraphs;
  final DocTranslationMode mode;
  final Object? error;

  const DocumentTranslationState({
    this.status = DocTranslationStatus.idle,
    this.translations = const {},
    this.paragraphs = const [],
    this.mode = DocTranslationMode.off,
    this.error,
  });

  /// 当前是否已有完整翻译结果（决定按钮形态：文本循环 vs 图标）。
  /// 必须同时要求 `translations` 非空——`translate()` 在全段失败时也会走到
  /// done 分支的历史已堵（见 translate 末尾的空 translations 判定），但这里
  /// 仍作防御：done + 空 translations 时不应让底栏露出失灵的模式按钮。
  bool get hasResult =>
      status == DocTranslationStatus.done && translations.isNotEmpty;

  DocumentTranslationState copyWith({
    DocTranslationStatus? status,
    Map<String, String>? translations,
    List<TranslatableParagraph>? paragraphs,
    DocTranslationMode? mode,
    Object? error,
    bool clearError = false,
  }) => DocumentTranslationState(
    status: status ?? this.status,
    translations: translations ?? this.translations,
    paragraphs: paragraphs ?? this.paragraphs,
    mode: mode ?? this.mode,
    error: clearError ? null : (error ?? this.error),
  );
}

// ── Notifier ─────────────────────────────────────────────────────────

class DocumentTranslationNotifier
    extends StateNotifier<DocumentTranslationState> {
  DocumentTranslationNotifier(this._ref, this.documentId)
    : super(const DocumentTranslationState()) {
    // 目标语言变更：已有结果的情况下清空并提示"请重新翻译"
    _ref.listen<String>(
      translationConfigProvider.select((c) => c.targetLanguage),
      (prev, next) {
        if (prev == null || prev == next) return;
        if (state.hasResult || _activeTranslation != null) {
          cancel();
          _reset();
          _ref
              .read(snackBarServiceProvider)
              .showResult(
                message:
                    _l10n?.targetLanguageChangedRetranslate ?? '目标语言已变更，请重新翻译',
              );
        }
      },
    );
  }

  final Ref _ref;
  final String documentId;

  DocumentTranslationState get currentState => state;

  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  TranslationCancelToken? _cancelToken;
  Future<bool>? _activeTranslation;
  bool _retranslating = false;
  SnackBarProgressHandle? _progressHandle;

  /// 翻译进度——直接复用 Task Activity 的 [ListenableProgress]，由本 notifier
  /// 在 [translate] 内 report 到 taskActivityProvider；所有呈现处（snackbar
  /// surface / 多文档面板）共享同一真值。高频更新只刷新 value，不触发 state 变更。
  final ValueNotifier<ListenableProgress> _progress = ValueNotifier(
    const ListenableProgress(current: 0, total: 0, status: ''),
  );
  ValueListenable<ListenableProgress> get progress => _progress;
  int _restoreEpoch = 0;

  Future<void> restoreAfterCurrent(
    String markdown,
    ReaderDocumentIndex index,
  ) async {
    final epoch = ++_restoreEpoch;
    final current = _activeTranslation;
    if (current != null) {
      try {
        await current;
      } catch (_) {
        // 任务失败不应阻止重新解析后恢复已保存的段落结果。
      }
    }
    if (mounted && epoch == _restoreEpoch) restoreCached(markdown, index);
  }

  void restoreCached(String markdown, ReaderDocumentIndex index) {
    if (!mounted || _activeTranslation != null || !index.hasStructure) return;
    final config = _ref.read(translationConfigProvider);
    final eligible = index.translationParagraphs(
      markdown,
      config.ignoreSections,
    );
    final cached = DocumentTranslationService.loadTranslations(
      documentId,
      config.targetLanguage,
    );
    final hashes = {
      ...eligible.map((p) => p.hash),
      ...index.figureParagraphs.map((p) => p.hash),
    };
    final translations = {
      for (final hash in hashes)
        if (cached[hash]?.isNotEmpty == true) hash: cached[hash]!,
    };
    final paragraphs =
        eligible
            .where((p) => p.markdownStart != null)
            .map((p) => p.translatable)
            .toList()
          ..sort((a, b) => a.offset.compareTo(b.offset));
    state = state.copyWith(
      paragraphs: paragraphs,
      translations: translations,
      status: translations.isNotEmpty && hashes.every(translations.containsKey)
          ? DocTranslationStatus.done
          : DocTranslationStatus.idle,
    );
  }

  /// 启动一次完整的文档翻译。
  ///
  /// [useCache] 为 false 时强制跳过 Hive 缓存查询——所有段都重新请求 LLM。
  /// 供 [retranslate] 使用作为"清缓存"之外的双保险：即便 clearCacheFor
  /// 因为某种异常未完全清除，也不会命中残留的旧译文。
  ///
  /// 返回值：`true` 表示"所有段都命中文件缓存、未向 LLM 发任何请求"。
  /// view 层据此切换 SnackBar 文案（提示"使用了缓存，如需重翻请…"）。
  /// 其他情况（loading 已被复用、AI 设置缺失、空段落、取消、失败、
  /// useCache=false 等）均返回 `false`。
  Future<bool> translate(String markdown, {bool useCache = true}) {
    if (_retranslating) return Future.value(false);
    return _startTranslation(markdown, useCache: useCache);
  }

  Future<bool> _startTranslation(String markdown, {bool useCache = true}) {
    if (!mounted || _activeTranslation != null) return Future.value(false);
    final token = TranslationCancelToken();
    _cancelToken = token;
    final run = StorageActivity.run(
      () => _translate(markdown, token, useCache: useCache),
      cancel: () => token.cancel(),
    );
    final settled = run.whenComplete(() {
      if (identical(_cancelToken, token)) {
        _cancelToken = null;
        _activeTranslation = null;
      }
    });
    _activeTranslation = settled;
    return settled;
  }

  Future<bool> _translate(
    String markdown,
    TranslationCancelToken token, {
    required bool useCache,
  }) async {
    final agentState = _ref.read(effectiveAgentApiProvider);
    final config = _ref.read(translationConfigProvider);
    final snackBar = _ref.read(snackBarServiceProvider);

    if (!await AiSettingsPrompt.ensureTextModelConfigured(
      agentState: agentState,
    )) {
      return false;
    }
    if (!mounted || token.isCancelled) return false;

    final index = await ReaderDocumentIndex.load(documentId, markdown);
    if (!mounted || token.isCancelled) return false;
    final indexed = index.translationParagraphs(
      markdown,
      config.ignoreSections,
    );
    final paragraphs = index.hasStructure
        ? indexed
              .where((p) => p.markdownStart != null)
              .map((p) => p.translatable)
              .toList()
        : MarkdownParagraphExtractor.extract(
            markdown,
            ignoreSections: config.ignoreSections,
          );
    final figureTitleParagraphs = [
      ...indexed
          .where((p) => p.markdownStart == null)
          .map((p) => p.translatable),
      ...index.figureParagraphs,
    ];
    if (paragraphs.isEmpty && figureTitleParagraphs.isEmpty) {
      snackBar.showResult(
        message: _l10n?.noTranslatableParagraphs ?? '未检测到可翻译段落',
      );
      return false;
    }

    // 收集 figure title 作为额外翻译段落（共享 translations.json 缓存）
    if (!mounted || token.isCancelled) return false;
    final allParagraphs = {
      for (final p in [...paragraphs, ...figureTitleParagraphs]) p.hash: p,
    }.values.toList();
    paragraphs.sort((a, b) => a.offset.compareTo(b.offset));

    // 初始态：loading + 默认进入双语模式（翻完无需二次点击就能看到结果）
    // state.paragraphs 仅保留 markdown 段落（weaver 用），figure title 不参与 weave
    state = DocumentTranslationState(
      status: DocTranslationStatus.loading,
      paragraphs: paragraphs,
      translations: const {},
      mode: DocTranslationMode.bilingual,
    );
    _progress.value = ListenableProgress(
      current: 0,
      total: allParagraphs.length,
      status: '翻译中',
    );

    // 登记进 Task Activity（单一真值源）：无论从哪个入口触发翻译，进度都进同一
    // 活集合，由 snackbar surface 仲裁呈现（≥2 任务自动聚合）。完成/缓存/失败的
    // 用户文案仍由调用方按需 showResult——本 notifier 只负责任务的注册与注销。
    final handle = _ref
        .read(snackBarServiceProvider)
        .showListenableProgress(
          listenable: _progress,
          title: '翻译',
          onCancel: cancel,
        );
    _progressHandle = handle;

    final translations = <String, String>{};

    try {
      final fullyCached = await DocumentTranslationService.translate(
        pdfPath: documentId,
        paragraphs: allParagraphs,
        agentState: agentState,
        config: config,
        cancelToken: token,
        useCache: useCache,
        onResult: (hash, translation) {
          translations[hash] = translation;
          if (mounted && !token.isCancelled) {
            state = state.copyWith(translations: Map.of(translations));
          }
        },
        onProgress: (done, total) {
          if (!mounted || token.isCancelled) return;
          _progress.value = ListenableProgress(
            current: done,
            total: total,
            status: done >= total ? '翻译完成' : '翻译中',
          );
        },
      );

      // 等到下一帧 finalizeTree 结束：LLM 调用横跨多秒，调用方 widget 可能
      // 在 await 期间被 pop。Riverpod 3.x 的 ConsumerStatefulElement 在
      // unmount() 中先把 Element 标为 defunct + state.dispose()，再 close
      // 订阅；若此时同步写 state，listener `(_, _) => markNeedsBuild()` 会
      // 命中 defunct Element 的断言。等帧结束后所有 in-flight unmount 已完
      // 成，订阅被清理，写入安全。参见 commit 7bb7fac 对 reprocess 路径的
      // 同款修复。
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return false;

      if (token.isCancelled) return false;

      // 全段失败兜底：没有任何「markdown 段」翻出来时（零缓存命中 + 所有段重试
      // 后仍失败；figure title 即便侥幸成功也不参与 weave），weaver 会对每段
      // continue 返回原文 → effectiveMd 不变 → 一直原文、模式按钮失灵。若仍走
      // done，hasResult=true 会让底栏显示模式按钮、_handleTranslate 弹「翻译完成」，
      // 用户感受到「翻译完成却看不到译文」。改走 failed 把真实失败暴露：
      // _reportTranslationFailure 弹错误文案，底栏回到「翻译」入口。
      final anyMarkdownTranslated = allParagraphs.any(
        (p) => translations[p.hash]?.isNotEmpty == true,
      );
      if (!anyMarkdownTranslated) {
        state = state.copyWith(
          status: DocTranslationStatus.failed,
          error: Exception('所有段落翻译均失败，请检查 AI 设置与网络（可能为接口限流）'),
        );
        return false;
      }

      final missing = allParagraphs
          .where((p) => translations[p.hash]?.isNotEmpty != true)
          .length;
      state = state.copyWith(
        status: missing == 0
            ? DocTranslationStatus.done
            : DocTranslationStatus.failed,
        translations: translations,
        error: missing == 0
            ? null
            : Exception(
                _l10n?.readerTranslationIncomplete(missing) ??
                    '还有 $missing 个段落未翻译',
              ),
        clearError: missing == 0,
      );
      return fullyCached;
    } catch (e) {
      // 仅更新 state——错误消息交给 UI 层根据 state.error 决定如何展示。
      // 不在这里直接 showResult：那会和 view.dart 的进度 SnackBar 生命周期
      // 抢 scaffold messenger，导致错误消息被 handle.dismiss 误关。
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return false;
      if (token.isCancelled && token.failure == null) return false;
      state = state.copyWith(status: DocTranslationStatus.failed, error: e);
      return false;
    } finally {
      // 注销 Task Activity 任务（完成/缓存/失败的用户文案由调用方按需 showResult）。
      if (identical(_progressHandle, handle)) {
        _progressHandle = null;
        handle.dismiss();
      }
    }
  }

  /// 三态循环：双语 → 译文 → 原文 → 双语 …
  /// 只在 [hasResult] 时可用，其它状态点击无效。
  void cycleMode() {
    if (!state.hasResult) return;
    final next = switch (state.mode) {
      DocTranslationMode.bilingual => DocTranslationMode.translated,
      DocTranslationMode.translated => DocTranslationMode.off,
      DocTranslationMode.off => DocTranslationMode.bilingual,
    };
    state = state.copyWith(mode: next);
  }

  /// 显式设置模式（目前内部用）
  void setMode(DocTranslationMode mode) {
    state = state.copyWith(mode: mode);
  }

  /// 取消当前进行中的翻译。已完成的段落保留。
  void cancel({bool updateState = true}) {
    if (_cancelToken == null) return;
    _cancelToken!.cancel();
    if (updateState &&
        mounted &&
        state.status == DocTranslationStatus.loading) {
      state = state.copyWith(status: DocTranslationStatus.idle);
    }
  }

  /// 使正在等待文档索引/翻译完成的恢复回调失效。
  void invalidateRestore() {
    _restoreEpoch++;
  }

  /// 重新翻译：清文件缓存 + reset state + 以 `useCache: false` 重新请求。
  Future<void> retranslate(String markdown) async {
    if (!mounted || _retranslating) return;
    _retranslating = true;
    try {
      cancel();
      // 等旧任务把已完成段落保存好，再清缓存，避免旧任务写回新一轮结果。
      try {
        await _activeTranslation;
      } catch (_) {}
      if (!mounted) return;

      final config = _ref.read(translationConfigProvider);
      await DocumentTranslationService.clearTranslations(
        documentId,
        config.targetLanguage,
      );

      // 与 translate() 同款保护：clearTranslations 的 await 跨过 widget unmount
      // 时，_reset() 同步写 state 会撞 defunct listener 的 markNeedsBuild。
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      _reset();
      await _startTranslation(markdown, useCache: false);
    } finally {
      _retranslating = false;
    }
  }

  void _reset() {
    state = const DocumentTranslationState();
    _progress.value = const ListenableProgress(
      current: 0,
      total: 0,
      status: '准备中',
    );
  }

  void acceptFigureTranslation(
    String hash,
    String translation,
    String language,
  ) {
    if (!mounted ||
        language != _ref.read(translationConfigProvider).targetLanguage) {
      return;
    }
    state = state.copyWith(
      translations: {...state.translations, hash: translation},
    );
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _progressHandle?.dismiss();
    _progressHandle = null;
    _progress.dispose();
    super.dispose();
  }
}

// ── Provider ─────────────────────────────────────────────────────────

/// 按稳定 documentId 隔离翻译状态——同时打开多份文档时互不串扰。
final documentTranslationProvider =
    StateNotifierProvider.family<
      DocumentTranslationNotifier,
      DocumentTranslationState,
      String
    >((ref, documentId) => DocumentTranslationNotifier(ref, documentId));
