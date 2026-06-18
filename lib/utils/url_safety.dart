/// URL 安全验证——仅允许 http/https scheme 的 URL 被外部启动。
bool isLaunchableUrl(String url) {
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}
