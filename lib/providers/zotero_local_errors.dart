import '../core/l10n.dart';
import '../src/rust/error.dart';

/// 本地 Zotero 导入失败的文案：按 Rust 错误码对应到连接、兼容性和数据问题。
String zoteroLocalErrorMessage(AppLocalizations l10n, Object error) {
  if (error is! OtterError) return l10n.zoteroLocalFailed;
  return switch (error.code) {
    ErrorCode.network => l10n.zoteroLocalUnavailable,
    ErrorCode.authentication ||
    ErrorCode.remote ||
    ErrorCode.refused => l10n.zoteroLocalDisabled,
    ErrorCode.unsupported => l10n.zoteroLocalIncompatible,
    ErrorCode.conflict => l10n.zoteroLocalChanged,
    ErrorCode.invalidData => l10n.zoteroLocalInvalidResponse,
    ErrorCode.io || ErrorCode.notFound => l10n.zoteroLocalInvalidFile,
    _ => l10n.zoteroLocalFailed,
  };
}
