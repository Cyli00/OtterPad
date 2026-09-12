import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/task_provider.dart';
import '../core/app_logger.dart';
import '../core/l10n.dart';
import '../router/app_router.dart';
import 'snackbar_service.dart';

/// 接收移动端分享/打开 PDF 文件的 intent。
///
/// Android：ACTION_SEND / ACTION_SEND_MULTIPLE / ACTION_VIEW
/// iOS：CFBundleDocumentTypes "Open In"
class ShareReceiverService {
  static const _channel = MethodChannel('io.github.cyli00.otterpad/share');

  final ProviderContainer _container;

  ShareReceiverService(this._container) {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'onSharedFiles') {
      try {
        final paths = List<String>.from(call.arguments as List);
        await _importFiles(paths);
      } catch (e, st) {
        _reportFailure(e, st);
      }
    }
    return null;
  }

  Future<void> checkInitialSharedFiles() async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'getInitialSharedFiles',
      );
      if (result != null && result.isNotEmpty) {
        await _importFiles(result.cast<String>());
      }
    } on MissingPluginException {
      // 桌面端无此 channel
    } catch (e, st) {
      _reportFailure(e, st);
    }
  }

  void _reportFailure(Object error, StackTrace stackTrace) {
    log.w('[ShareReceiver] 导入失败', error: error, stackTrace: stackTrace);
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _container
        .read(snackBarServiceProvider)
        .showResult(message: context.l10n.sharedFilesImportFailed);
  }

  Future<void> _importFiles(List<String> paths) async {
    final pdfPaths = <String>[];
    for (final path in paths) {
      if (path.toLowerCase().endsWith('.pdf') && await hasPdfHeader(path)) {
        pdfPaths.add(path);
      }
    }

    try {
      if (pdfPaths.isNotEmpty) {
        await _container.read(taskProvider.notifier).addFiles(pdfPaths);
      }
      if (pdfPaths.length != paths.length) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          _container
              .read(snackBarServiceProvider)
              .showResult(message: context.l10n.sharedFilesSkipped);
        }
      }
    } finally {
      _cleanupTempFiles(paths);
    }
  }

  static Future<bool> hasPdfHeader(String path) async {
    RandomAccessFile? handle;
    try {
      handle = await File(path).open();
      final bytes = await handle.read(5);
      return bytes.length == 5 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46 &&
          bytes[4] == 0x2D;
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  void _cleanupTempFiles(List<String> paths) {
    for (final p in paths) {
      try {
        final file = File(p);
        if (file.existsSync() && file.path.contains('shared_pdfs')) {
          file.deleteSync();
        }
      } catch (e, st) {
        log.w('[ShareReceiver] 临时文件清理失败', error: e, stackTrace: st);
      }
    }
  }
}
