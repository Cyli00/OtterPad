import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import 'identifier_parser.dart';
import 'pdf_process_lock.dart';

/// 从 PDF 正文中提取标识符的服务
///
/// 使用全局 [PdfProcessLock] 防止并发打开大量 PDF 导致 OOM
class PdfIdentifierExtractor {
  PdfIdentifierExtractor._();
  static final PdfIdentifierExtractor instance = PdfIdentifierExtractor._();

  /// 单次 PDF 提取超时时间
  static const _extractTimeout = Duration(seconds: 30);

  // 非锚定 DOI 正则，用于在散文文本中搜索
  static final _doiRegExp = RegExp(r'10\.\d{4,}/[^\s<>"{}|\\^`\[\]]+');

  // arXiv ID 正则（新格式 YYMM.NNNNN，含可选版本号）
  static final _arxivRegExp = RegExp(r'arXiv:\s*(\d{4}\.\d{4,5}(?:v\d+)?)');

  // ISBN-13 正则（带可选连字符，保守匹配避免纯数字误匹配）
  static final _isbnRegExp = RegExp(r'(?:ISBN[:\s-]*)(97[89]-?\d-?\d{2,7}-?\d{2,7}-?\d)');

  // 需要清理的尾部标点
  static final _trailingPunctuation = RegExp(r'[.,;)\]]+$');

  /// 从 PDF 前 2 页提取文本（带超时保护）
  Future<String?> _extractText(String filePath) async {
    return PdfProcessLock.instance.run(() async {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(
          filePath,
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

        return buffer.toString();
      } catch (e) {
        debugPrint('提取 PDF 文本失败 ($filePath): $e');
        return null;
      } finally {
        document?.dispose();
      }
    }).timeout(
      _extractTimeout,
      onTimeout: () {
        debugPrint('提取 PDF 文本超时 ($filePath)');
        return null;
      },
    );
  }

  /// 从 PDF 前 2 页提取最佳标识符（DOI > arXiv > ISBN）
  Future<ParsedIdentifier?> extractIdentifier(String filePath) async {
    final fullText = await _extractText(filePath);
    if (fullText == null) return null;

    // 优先级 1: DOI
    final doiMatch = _doiRegExp.firstMatch(fullText);
    if (doiMatch != null) {
      var doi = doiMatch.group(0)!;
      doi = doi.replaceAll(_trailingPunctuation, '');
      return ParsedIdentifier(IdentifierType.doi, doi);
    }

    // 优先级 2: arXiv ID
    final arxivMatch = _arxivRegExp.firstMatch(fullText);
    if (arxivMatch != null) {
      return ParsedIdentifier(IdentifierType.arxiv, arxivMatch.group(1)!);
    }

    // 优先级 3: ISBN-13
    final isbnMatch = _isbnRegExp.firstMatch(fullText);
    if (isbnMatch != null) {
      final isbn = isbnMatch.group(1)!.replaceAll('-', '');
      return ParsedIdentifier(IdentifierType.isbn, isbn);
    }

    return null;
  }
}
