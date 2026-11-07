import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/l10n.dart';
import '../core/otter_error_text.dart';
import '../core/rust_ai.dart';
import '../core/rust_backend.dart';
import '../router/app_router.dart';
import '../services/ai_settings_prompt.dart';
import '../services/snackbar_service.dart';
import '../src/rust/api.dart' show cancelTask;
import '../src/rust/api/translate.dart';
import '../src/rust/error.dart';
import '../src/rust/translate.dart';
import 'agent_api_provider.dart';
import 'translation_config_provider.dart';

/// 全文译文的展示方式。
enum DocTranslationMode {
  /// 只显示原文。
  off,

  /// 每段原文后接译文。
  bilingual,

  /// 只显示译文。
  translated,
}

enum DocTranslationStatus { idle, loading, done, failed }

class DocumentTranslationState {
  final DocTranslationStatus status;

  /// 译文键（见 `ReaderDocument.translationKeys`）→ 译文。
  final Map<String, String> translations;
  final DocTranslationMode mode;
  final Object? error;

  const DocumentTranslationState({
    this.status = DocTranslationStatus.idle,
    this.translations = const {},
    this.mode = DocTranslationMode.off,
    this.error,
  });

  bool get hasResult =>
      status == DocTranslationStatus.done && translations.isNotEmpty;

  DocumentTranslationState copyWith({
    DocTranslationStatus? status,
    Map<String, String>? translations,
    DocTranslationMode? mode,
    Object? error,
    bool clearError = false,
  }) => DocumentTranslationState(
    status: status ?? this.status,
    translations: translations ?? this.translations,
    mode: mode ?? this.mode,
    error: clearError ? null : (error ?? this.error),
  );
}

/// 单篇文献的全文翻译：Rust 按块翻译并保存，取消后保留已完成的段落。
class DocumentTranslationNotifier
    extends StateNotifier<DocumentTranslationState> {
  DocumentTranslationNotifier(this._ref, this.documentId)
    : super(const DocumentTranslationState()) {
    _ref.listen<String>(
      translationConfigProvider.select((c) => c.targetLanguage),
      (prev, next) {
        if (prev == null || prev == next) return;
        cancel();
        state = const DocumentTranslationState();
        unawaited(restoreCached());
      },
    );
    unawaited(restoreCached());
  }

  final Ref _ref;
  final String documentId;

  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  String? _task;
  Future<bool>? _active;
  bool _retranslating = false;

  final ValueNotifier<ListenableProgress> _progress = ValueNotifier(
    const ListenableProgress(current: 0, total: 0, status: ''),
  );
  ValueListenable<ListenableProgress> get progress => _progress;

  String get _language => _ref.read(translationConfigProvider).targetLanguage;

  /// 读出已保存的译文；有结果时进入完成态，展示方式保持原文。
  Future<void> restoreCached() async {
    if (_active != null) return;
    final language = _language;
    try {
      final values = await RustBackend.instance.translations(
        document: documentId,
        language: language,
      );
      if (!mounted || _active != null || language != _language) return;
      if (values.isEmpty) return;
      state = state.copyWith(
        status: DocTranslationStatus.done,
        translations: {for (final v in values) v.hash: v.text},
      );
    } catch (e) {
      // 没有 OCR 结果的文献没有译文，不算错误。
      if (e is! OtterError || e.code != ErrorCode.notFound) {
        debugPrint('[Translation] 读取已保存译文失败：$e');
      }
    }
  }

  /// 全文翻译。返回 `true` 表示全部命中已保存的译文、没有发出请求。
  Future<bool> translate({bool useCache = true}) {
    if (_retranslating || !mounted || _active != null) {
      return Future.value(false);
    }
    final run = _translate(useCache: useCache);
    _active = run.whenComplete(() => _active = null);
    return _active!;
  }

  Future<bool> _translate({required bool useCache}) async {
    final agentState = _ref.read(effectiveAgentApiProvider);
    if (!await AiSettingsPrompt.ensureTextModelConfigured(
      agentState: agentState,
    )) {
      return false;
    }
    final model = textModelSelection(_ref.read(agentApiProvider));
    if (model == null || !mounted) return false;
    final config = _ref.read(translationConfigProvider);

    final translations = Map.of(state.translations);
    state = DocumentTranslationState(
      status: DocTranslationStatus.loading,
      translations: translations,
      mode: DocTranslationMode.bilingual,
    );
    _progress.value = ListenableProgress(
      current: 0,
      total: 0,
      status: _l10n?.translatingDocument ?? '正在翻译',
    );
    final handle = _ref
        .read(snackBarServiceProvider)
        .showListenableProgress(
          listenable: _progress,
          title: _l10n?.translatingDocument ?? '翻译',
          onCancel: cancel,
        );
    final task = rustTaskId('translate');
    _task = task;
    try {
      TranslationReport? report;
      await for (final event in RustBackend.instance.translateDocument(
        options: TranslateDocument(
          documentId: documentId,
          model: model,
          config: translationConfig(config),
          ignoredSections: config.ignoreSections,
          useCache: useCache,
        ),
        taskId: task,
      )) {
        if (!mounted) return false;
        switch (event) {
          case TranslateEvent_Paragraph(
            event: TranslationEvent_Result(:final hash, :final text),
          ):
            translations[hash] = text;
            state = state.copyWith(translations: Map.of(translations));
          case TranslateEvent_Paragraph(
            event: TranslationEvent_Progress(:final completed, :final total),
          ):
            _progress.value = ListenableProgress(
              current: completed.toInt(),
              total: total.toInt(),
              status: completed >= total
                  ? _l10n?.translationDone ?? '已完成翻译'
                  : _l10n?.translatingDocument ?? '正在翻译',
            );
          case TranslateEvent_Completed(report: final r):
            report = r;
          case TranslateEvent_Failed(:final error):
            throw error;
          default:
        }
      }
      if (!mounted || report == null) return false;
      final missing = report.failures.length;
      if (translations.isEmpty) {
        state = state.copyWith(
          status: DocTranslationStatus.failed,
          error: missing > 0
              ? OtterError(code: report.failures.first.code, detail: '')
              : null,
        );
        if (missing == 0) {
          _ref
              .read(snackBarServiceProvider)
              .showResult(
                message: _l10n?.noTranslatableParagraphs ?? '未检测到可翻译段落',
              );
        }
        return false;
      }
      state = state.copyWith(
        status: missing == 0
            ? DocTranslationStatus.done
            : DocTranslationStatus.failed,
        error: missing == 0
            ? null
            : Exception(
                _l10n?.readerTranslationIncomplete(missing) ??
                    '还有 $missing 个段落未翻译',
              ),
        clearError: missing == 0,
      );
      return report.cached == report.total && report.total > BigInt.zero;
    } catch (e) {
      if (!mounted) return false;
      if (isCancellation(e)) {
        state = state.copyWith(
          status: translations.isEmpty
              ? DocTranslationStatus.idle
              : DocTranslationStatus.done,
        );
        return false;
      }
      state = state.copyWith(status: DocTranslationStatus.failed, error: e);
      return false;
    } finally {
      if (_task == task) _task = null;
      handle.dismiss();
    }
  }

  /// 双语 → 译文 → 原文 → 双语；只在有结果时可用。
  void cycleMode() {
    if (!state.hasResult) return;
    state = state.copyWith(
      mode: switch (state.mode) {
        DocTranslationMode.bilingual => DocTranslationMode.translated,
        DocTranslationMode.translated => DocTranslationMode.off,
        DocTranslationMode.off => DocTranslationMode.bilingual,
      },
    );
  }

  void setMode(DocTranslationMode mode) {
    state = state.copyWith(mode: mode);
  }

  /// 取消进行中的翻译；已完成的段落已由 Rust 保存。
  void cancel() {
    final task = _task;
    if (task != null) cancelTask(taskId: task);
  }

  /// 清除当前语言的译文后不使用缓存重新翻译。
  Future<void> retranslate() async {
    if (!mounted || _retranslating) return;
    _retranslating = true;
    try {
      cancel();
      try {
        await _active;
      } catch (_) {}
      if (!mounted) return;
      await RustBackend.instance.clearTranslations(
        document: documentId,
        language: _language,
      );
      if (!mounted) return;
      state = const DocumentTranslationState();
    } finally {
      _retranslating = false;
    }
    await translate(useCache: false);
  }

  /// 题注等单段翻译完成后并入当前语言的译文。
  void acceptTranslation(String key, String translation, String language) {
    if (!mounted || language != _language) return;
    state = state.copyWith(
      translations: {...state.translations, key: translation},
    );
  }

  @override
  void dispose() {
    cancel();
    _progress.dispose();
    super.dispose();
  }
}

/// 文案：翻译失败原因。
String translationErrorText(AppLocalizations l10n, Object? error) =>
    l10n.translationFailed(error == null ? '' : errorText(l10n, error));

final documentTranslationProvider =
    StateNotifierProvider.family<
      DocumentTranslationNotifier,
      DocumentTranslationState,
      String
    >((ref, documentId) => DocumentTranslationNotifier(ref, documentId));
