import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// 从 PDF 正文中提取 DOI 的服务
///
/// 使用串行队列锁防止并发打开大量 PDF 导致 OOM
class PdfDoiExtractor {
  PdfDoiExtractor._();
  static final PdfDoiExtractor instance = PdfDoiExtractor._();

  // 串行队列锁，同一时刻仅打开一份 PDF
  Future<void> _processLock = Future.value();

  // 非锚定 DOI 正则，用于在散文文本中搜索
  static final _doiRegExp = RegExp(r'10\.\d{4,}/[^\s<>"{}|\\^`\[\]]+');

  // 需要清理的尾部标点
  static final _trailingPunctuation = RegExp(r'[.,;)\]]+$');

  /// 从 PDF 前 2 页文本中提取 DOI，找不到返回 null
  Future<String?> extractDoi(String filePath) async {
    final lock = _processLock;
    final completer = Completer<void>();
    _processLock = completer.future;

    await lock;

    PdfDocument? document;
    try {
      final bytes = await File(filePath).readAsBytes();
      document = await PdfDocument.openData(
        bytes,
        passwordProvider: () => '',
      );

      if (document.pages.isEmpty) return null;

      final pageCount = document.pages.length.clamp(0, 2);
      final buffer = StringBuffer();

      for (int i = 0; i < pageCount; i++) {
        final page = document.pages[i];
        await page.ensureLoaded();
        final text = await page.loadText();
        buffer.write(text?.fullText ?? '');
        buffer.write(' ');
      }

      final fullText = buffer.toString();
      final match = _doiRegExp.firstMatch(fullText);
      if (match == null) return null;

      var doi = match.group(0)!;
      doi = doi.replaceAll(_trailingPunctuation, '');
      return doi;
    } catch (e) {
      debugPrint('提取 DOI 失败 ($filePath): $e');
      return null;
    } finally {
      document?.dispose();
      completer.complete();
    }
  }
}
