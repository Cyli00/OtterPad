import '../l10n/app_localizations.dart';
import '../src/rust/error.dart';

/// Rust [OtterError] 的用户可见文案。`detail` 只进日志，不展示。
String otterErrorText(AppLocalizations l10n, ErrorCode code) => switch (code) {
  ErrorCode.invalidArgument => l10n.otterErrorInvalidArgument,
  ErrorCode.invalidData => l10n.otterErrorInvalidData,
  ErrorCode.io => l10n.otterErrorIo,
  ErrorCode.database => l10n.otterErrorDatabase,
  ErrorCode.conflict => l10n.otterErrorConflict,
  ErrorCode.unsupportedDatabase => l10n.otterErrorUnsupportedDatabase,
  ErrorCode.cancelled => l10n.otterErrorCancelled,
  ErrorCode.network => l10n.otterErrorNetwork,
  ErrorCode.authentication => l10n.otterErrorAuthentication,
  ErrorCode.rateLimited => l10n.otterErrorRateLimited,
  ErrorCode.quotaExceeded => l10n.otterErrorQuotaExceeded,
  ErrorCode.remote => l10n.otterErrorRemote,
  ErrorCode.notFound => l10n.otterErrorNotFound,
  ErrorCode.unsupported => l10n.otterErrorUnsupported,
  ErrorCode.pdf => l10n.otterErrorPdf,
  ErrorCode.layoutOverflow => l10n.otterErrorLayoutOverflow,
  ErrorCode.refused => l10n.otterErrorRefused,
  ErrorCode.incompleteResponse => l10n.otterErrorIncompleteResponse,
  ErrorCode.toolLimit => l10n.otterErrorToolLimit,
};

/// 任意异常的文案：Rust 错误按错误码映射，其他异常原样转成字符串。
String errorText(AppLocalizations l10n, Object error) =>
    error is OtterError ? otterErrorText(l10n, error.code) : '$error';
