import 'dart:async';
import 'dart:io';

class ReaderHtmlCache {
  ReaderHtmlCache._();

  static final _pending = <String, Future<bool>>{};

  static Future<bool> write({
    required String path,
    required FutureOr<String> fingerprint,
    required Future<String> Function() buildHtml,
    bool allowReuse = true,
  }) async {
    final previous = _pending[path];
    final task = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // 上一次生成失败不能阻止后续新内容覆盖缓存。
        }
      }
      final expected = await fingerprint;
      final html = File(path);
      final marker = File('$path.fp');
      if (allowReuse && await html.exists() && await marker.exists()) {
        try {
          if (await marker.readAsString() == expected) return true;
        } on FileSystemException {
          // 指纹不可读时重新生成。
        }
      }
      final content = await buildHtml();
      final staged = File('$path.pending');
      await staged.parent.create(recursive: true);
      await staged.writeAsString(content, flush: true);
      if (await marker.exists()) await marker.delete();
      await staged.rename(path);
      await marker.writeAsString(expected, flush: true);
      return false;
    }();
    _pending[path] = task;
    try {
      return await task;
    } finally {
      if (identical(_pending[path], task)) _pending.remove(path);
    }
  }
}
