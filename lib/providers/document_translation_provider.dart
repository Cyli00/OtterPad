import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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
  }) =>
      DocumentTranslationState(
        status: status ?? this.status,
        translations: translations ?? this.translations,
        paragraphs: paragraphs ?? this.paragraphs,
        mode: mode ?? this.mode,
        error: clearError ? null : (error ?? this.error),
      );
}

// ── 进度信息 ─────────────────────────────────────────────────────────

class TranslationProgress {
  final int current;
  final int total;
  final String status;

  const TranslationProgress({
    required this.current,
    required this.total,
    required this.status,
  });

  static const zero =
      TranslationProgress(current: 0, total: 0, status: '准备中');
}

// ── Notifier ─────────────────────────────────────────────────────────

class DocumentTranslationNotifier
    extends StateNotifier<DocumentTranslationState> {
  DocumentTranslationNotifier(this._ref, this.pdfPath)
      : super(const DocumentTranslationState()) {
    // 目标语言变更：已有结果的情况下清空并提示"请重新翻译"
    _ref.listen<String>(
      translationConfigProvider.select((c) => c.targetLanguage),
      (prev, next) {
        if (prev == null || prev == next) return;
        if (state.hasResult) {
          _reset();
          _ref.read(snackBarServiceProvider).showResult(
                message: '目标语言已变更，请重新翻译',
              );
        }
      },
    );
  }

  final Ref _ref;
  final String pdfPath;

  TranslationCancelToken? _cancelToken;

  /// 外部可订阅的进度——SnackBar 用 ValueListenableBuilder 绑定。
  /// 高频更新只刷新 notifier.value，不触发 state 变更，避免文档级 rebuild。
  final ValueNotifier<TranslationProgress> _progress =
      ValueNotifier(TranslationProgress.zero);
  ValueListenable<TranslationProgress> get progress => _progress;

  /// 启动一次完整的文档翻译。
  ///
  /// [useCache] 为 false 时强制跳过 Hive 缓存查询——所有段都重新请求 LLM。
  /// 供 [retranslate] 使用作为"清缓存"之外的双保险：即便 clearCacheFor
  /// 因为某种异常未完全清除，也不会命中残留的旧译文。
  Future<void> translate(String markdown, {bool useCache = true}) async {
    if (state.status == DocTranslationStatus.loading) return;

    final agentState = _ref.read(effectiveAgentApiProvider);
    final config = _ref.read(translationConfigProvider);
    final snackBar = _ref.read(snackBarServiceProvider);

    if (!AiSettingsPrompt.ensureTextModelConfigured(
      agentState: agentState,
      snackBar: snackBar,
      onOpenSettings: () =>
          _ref.read(routerProvider).push(AppRoutes.settingsApi),
    )) {
      return;
    }

    final paragraphs = MarkdownParagraphExtractor.extract(
      markdown,
      ignoreSections: config.ignoreSections,
    );
    if (paragraphs.isEmpty) {
      snackBar.showResult(message: '未检测到可翻译段落');
      return;
    }

    final cancel = TranslationCancelToken();
    _cancelToken = cancel;

    // 初始态：loading + 默认进入双语模式（翻完无需二次点击就能看到结果）
    state = DocumentTranslationState(
      status: DocTranslationStatus.loading,
      paragraphs: paragraphs,
      translations: const {},
      mode: DocTranslationMode.bilingual,
    );
    _progress.value = TranslationProgress(
      current: 0,
      total: paragraphs.length,
      status: '翻译中',
    );

    final translations = <String, String>{};

    try {
      await DocumentTranslationService.translate(
        pdfPath: pdfPath,
        paragraphs: paragraphs,
        agentState: agentState,
        config: config,
        cancelToken: cancel,
        useCache: useCache,
        onResult: (hash, translation) {
          translations[hash] = translation;
          // 复制一份避免外部引用未来被替换——StateNotifier 等值比较依赖身份判断
          state = state.copyWith(translations: Map.of(translations));
        },
        onProgress: (done, total) {
          _progress.value = TranslationProgress(
            current: done,
            total: total,
            status: done >= total ? '翻译完成' : '翻译中',
          );
        },
      );

      if (cancel.isCancelled) {
        // 已取消：不改 done 态，保留已翻译片段但状态回 idle
        state = state.copyWith(status: DocTranslationStatus.idle);
        return;
      }

      state = state.copyWith(
        status: DocTranslationStatus.done,
        translations: translations,
        clearError: true,
      );
    } catch (e) {
      // 仅更新 state——错误消息交给 UI 层根据 state.error 决定如何展示。
      // 不在这里直接 showResult：那会和 view.dart 的进度 SnackBar 生命周期
      // 抢 scaffold messenger，导致错误消息被 handle.dismiss 误关。
      state = state.copyWith(
        status: DocTranslationStatus.failed,
        error: e,
      );
    } finally {
      _cancelToken = null;
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
      pdfPath,
      config.targetLanguage,
    );

    _reset();
    await translate(markdown, useCache: false);
  }

  void _reset() {
    state = const DocumentTranslationState();
    _progress.value = TranslationProgress.zero;
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _progress.dispose();
    super.dispose();
  }
}

// ── Provider ─────────────────────────────────────────────────────────

/// 按文档路径隔离翻译状态——同时打开多份文档时互不串扰。
final documentTranslationProvider = StateNotifierProvider.family<
    DocumentTranslationNotifier, DocumentTranslationState, String>(
  (ref, pdfPath) => DocumentTranslationNotifier(ref, pdfPath),
);
