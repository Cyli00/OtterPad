import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/task_provider.dart';

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
      final paths = List<String>.from(call.arguments as List);
      await _importFiles(paths);
    }
    return null;
  }

  Future<void> checkInitialSharedFiles() async {
    try {
      final result =
          await _channel.invokeMethod<List<Object?>>('getInitialSharedFiles');
      if (result != null && result.isNotEmpty) {
        await _importFiles(result.cast<String>());
      }
    } on MissingPluginException {
      // 桌面端无此 channel
    }
  }

  Future<void> _importFiles(List<String> paths) async {
    final pdfPaths =
        paths.where((p) => p.toLowerCase().endsWith('.pdf')).toList();
    if (pdfPaths.isEmpty) return;
    await _container.read(taskProvider.notifier).addFiles(pdfPaths);
    _cleanupTempFiles(pdfPaths);
  }

  void _cleanupTempFiles(List<String> paths) {
    for (final p in paths) {
      try {
        final file = File(p);
        if (file.existsSync() && file.path.contains('shared_pdfs')) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }
}
