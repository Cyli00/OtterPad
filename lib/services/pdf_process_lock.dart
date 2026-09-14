import '../core/storage/storage_activity.dart';
import 'dart:async';

/// 全局 PDF 处理锁：确保同一时刻仅打开一份 PDF 文件
///
/// PdfIdentifierExtractor 和 PdfThumbnailService 共享此锁，
/// 防止并发打开多份 PDF 导致内存暴胀（OOM）。
class PdfProcessLock {
  PdfProcessLock._();
  static final PdfProcessLock instance = PdfProcessLock._();

  Future<void> _lock = Future.value();

  /// 在串行队列中执行任务，保证同一时刻仅一个任务运行
  Future<T> run<T>(Future<T> Function() task) => StorageActivity.run(() async {
    final prev = _lock;
    final completer = Completer<void>();
    _lock = completer.future;

    try {
      await prev;
    } catch (_) {}

    try {
      return await task();
    } finally {
      completer.complete();
    }
  });
}
