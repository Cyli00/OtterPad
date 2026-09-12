import 'dart:async';
import 'dart:io';

enum ReaderHtmlWriteResult { written, reused, superseded }

class ReaderHtmlCache {
  ReaderHtmlCache._();

  static final _pending = <String, Future<ReaderHtmlWriteResult>>{};

  static Future<ReaderHtmlWriteResult> write({
    required String path,
    required FutureOr<String> Function() fingerprint,
    required Future<String> Function() buildHtml,
    bool allowReuse = true,
  }) async {
    final previous = _pending[path];
    late final Future<ReaderHtmlWriteResult> task;
    task = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // 上一次生成失败不能阻止后续新内容覆盖缓存。
        }
      }
      // 先让本次任务登记，再淘汰等待期间被新内容替代的版本；哈希也延后计算。
      await Future<void>.value();
      if (!identical(_pending[path], task)) {
        return ReaderHtmlWriteResult.superseded;
      }
      final expected = await fingerprint();
      if (!identical(_pending[path], task)) {
        return ReaderHtmlWriteResult.superseded;
      }
      final html = File(path);
      final marker = File('$path.fp');
      if (allowReuse && await html.exists() && await marker.exists()) {
        try {
          if (await marker.readAsString() == expected) {
            return ReaderHtmlWriteResult.reused;
          }
        } on FileSystemException {
          // 指纹不可读时重新生成。
        }
      }
      if (!identical(_pending[path], task)) {
        return ReaderHtmlWriteResult.superseded;
      }
      final content = await buildHtml();
      final staged = File('$path.pending');
      await staged.parent.create(recursive: true);
      await staged.writeAsString(content, flush: true);
      if (await marker.exists()) await marker.delete();
      await staged.rename(path);
      await marker.writeAsString(expected, flush: true);
      return ReaderHtmlWriteResult.written;
    }();
    _pending[path] = task;
    try {
      return await task;
    } finally {
      if (identical(_pending[path], task)) _pending.remove(path);
    }
  }
}
