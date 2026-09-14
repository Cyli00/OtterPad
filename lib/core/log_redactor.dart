final _credentialValue = RegExp(
  r'''((?:["']?)(?:authorization|proxy-authorization|x-api-key|zotero-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret[_-]?access[_-]?key|password|passwd|token|cookie|set-cookie)(?:["']?)\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;}\]]+)''',
  caseSensitive: false,
);
final _authHeader = RegExp(
  r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);
final _knownToken = RegExp(
  r'\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b',
);
final _url = RegExp(r'''https?://[^\s"'<>]+''', caseSensitive: false);
final _userHome = RegExp(
  r'(?:[A-Za-z]:[/\\]Users[/\\][^/\\\s]+|/(?:home|Users)/[^/\s]+)',
);

/// 在日志进入控制台与文件输出之前，统一遮盖凭据、签名参数及本机用户名。
String redactLogText(String text) {
  var result = text.replaceAllMapped(_url, (match) {
    final uri = Uri.tryParse(match[0]!);
    if (uri == null) return '[REDACTED_URL]';
    if (uri.userInfo.isEmpty && !uri.hasQuery && !uri.hasFragment) {
      return match[0]!;
    }
    return uri
        .replace(
          userInfo: '',
          queryParameters: uri.hasQuery
              ? {
                  for (final key in uri.queryParametersAll.keys)
                    key: '[REDACTED]',
                }
              : null,
          fragment: '',
        )
        .toString();
  });
  result = result.replaceAllMapped(
    _authHeader,
    (match) => '${match[1]} [REDACTED]',
  );
  result = result.replaceAllMapped(
    _credentialValue,
    (match) => '${match[1]}[REDACTED]',
  );
  return result
      .replaceAll(_knownToken, '[REDACTED]')
      .replaceAll(_userHome, '<USER_HOME>');
}
