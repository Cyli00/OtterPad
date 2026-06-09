import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/l10n.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';
import '../services/ai_settings_prompt.dart';
import '../services/document_translation_service.dart';
import '../services/markdown_paragraph_extractor.dart';
import '../services/snackbar_service.dart';
import '../utils/markdown_translation_weaver.dart';
import 'api_provider.dart';
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

  /// 当前是否已有完整翻译结果（决定按钮形态：文本循环 vs 图标）
  bool get hasResult => status == DocTranslationStatus.done;

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
        if (state.hasResult) {
          _reset();
          _ref
              .read(snackBarServiceProvider)
              .showResult(message: _l10n?.targetLanguageChangedRetranslate ?? '目标语言已变更，请重新翻译');
        }
      },
    );
  }

  final Ref _ref;
  final String documentId;

  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  TranslationCancelToken? _cancelToken;

  /// 翻译进度——直接复用 Task Activity 的 [ListenableProgress]，由本 notifier
  /// 在 [translate] 内 report 到 taskActivityProvider；所有呈现处（snackbar
  /// surface / 多文档面板）共享同一真值。高频更新只刷新 value，不触发 state 变更。
  final ValueNotifier<ListenableProgress> _progress = ValueNotifier(
    const ListenableProgress(current: 0, total: 0, status: ''),
  );
  ValueListenable<ListenableProgress> get progress => _progress;

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
  Future<bool> translate(String markdown, {bool useCache = true}) async {
    if (state.status == DocTranslationStatus.loading) return false;

    final agentState = _ref.read(effectiveAgentApiProvider);
    final config = _ref.read(translationConfigProvider);
    final snackBar = _ref.read(snackBarServiceProvider);

    if (!AiSettingsPrompt.ensureTextModelConfigured(
      agentState: agentState,
      snackBar: snackBar,
      onOpenSettings: () =>
          _ref.read(routerProvider).push(AppRoutes.settingsApi),
    )) {
      return false;
    }

    final paragraphs = MarkdownParagraphExtractor.extract(
      markdown,
      ignoreSections: config.ignoreSections,
    );
    if (paragraphs.isEmpty) {
      snackBar.showResult(message: _l10n?.noTranslatableParagraphs ?? '未检测到可翻译段落');
      return false;
    }

    final token = TranslationCancelToken();
    _cancelToken = token;

    // 初始态：loading + 默认进入双语模式（翻完无需二次点击就能看到结果）
    state = DocumentTranslationState(
      status: DocTranslationStatus.loading,
      paragraphs: paragraphs,
      translations: const {},
      mode: DocTranslationMode.bilingual,
    );
    _progress.value = ListenableProgress(
      current: 0,
      total: paragraphs.length,
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

    final translations = <String, String>{};

    try {
      final fullyCached = await DocumentTranslationService.translate(
        pdfPath: documentId,
        paragraphs: paragraphs,
        agentState: agentState,
        config: config,
        cancelToken: token,
        useCache: useCache,
        onResult: (hash, translation) {
          translations[hash] = translation;
        },
        onProgress: (done, total) {
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

      if (token.isCancelled) {
        state = state.copyWith(
          status: DocTranslationStatus.idle,
          translations: translations,
        );
        return false;
      }

      state = state.copyWith(
        status: DocTranslationStatus.done,
        translations: translations,
        clearError: true,
      );
      return fullyCached;
    } catch (e) {
      // 仅更新 state——错误消息交给 UI 层根据 state.error 决定如何展示。
      // 不在这里直接 showResult：那会和 view.dart 的进度 SnackBar 生命周期
      // 抢 scaffold messenger，导致错误消息被 handle.dismiss 误关。
      await SchedulerBinding.instance.endOfFrame;
      state = state.copyWith(status: DocTranslationStatus.failed, error: e);
      return false;
    } finally {
      _cancelToken = null;
      // 注销 Task Activity 任务（完成/缓存/失败的用户文案由调用方按需 showResult）。
      handle.dismiss();
    }
  }

  /// 三态循环：双语 → 原文 → 译文 → 双语 …
  /// 只在 [hasResult] 时可用，其它状态点击无效。
  void cycleMode() {
    if (!state.hasResult) return;
    final next = switch (state.mode) {
      DocTranslationMode.bilingual => DocTranslationMode.off,
      DocTranslationMode.off => DocTranslationMode.translated,
      DocTranslationMode.translated => DocTranslationMode.bilingual,
    };
    state = state.copyWith(mode: next);
  }

  /// 显式设置模式（目前内部用）
  void setMode(DocTranslationMode mode) {
    state = state.copyWith(mode: mode);
  }

  /// 取消当前进行中的翻译。已完成的段落保留。
  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
    if (state.status == DocTranslationStatus.loading) {
      state = state.copyWith(status: DocTranslationStatus.idle);
    }
  }

  /// 重新翻译：清文件缓存 + reset state + 以 `useCache: false` 重新请求。
  Future<void> retranslate(String markdown) async {
    cancel();

    final config = _ref.read(translationConfigProvider);
    await DocumentTranslationService.clearTranslations(
      documentId,
      config.targetLanguage,
    );

    // 与 translate() 同款保护：clearTranslations 的 await 跨过 widget unmount
    // 时，_reset() 同步写 state 会撞 defunct listener 的 markNeedsBuild。
    await SchedulerBinding.instance.endOfFrame;
    _reset();
    await translate(markdown, useCache: false);
  }

  void _reset() {
    state = const DocumentTranslationState();
    _progress.value = const ListenableProgress(
      current: 0,
      total: 0,
      status: '准备中',
    );
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
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
