import 'dart:async';
import 'package:pdfrx/pdfrx.dart';

import 'identifier_parser.dart';
import 'pdf_process_lock.dart';
import '../core/app_logger.dart';

/// 从 PDF 正文中提取标识符的服务
///
/// 使用全局 [PdfProcessLock] 防止并发打开大量 PDF 导致 OOM
class PdfIdentifierExtractor {
  PdfIdentifierExtractor._();
  static final PdfIdentifierExtractor instance = PdfIdentifierExtractor._();

  /// 单次 PDF 提取超时时间
  static const _extractTimeout = Duration(seconds: 30);

  // 非锚定 DOI 正则，用于在散文文本中搜索
  static final _doiRegExp = RegExp(
    r'10\.\d{4,}/[^\s"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  // arXiv ID 正则（新格式 YYMM.NNNNN，含可选版本号）
  static final _arxivNewRegExp = RegExp(
    r'(?:arXiv:\s*|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}(?:v\d+)?)',
    caseSensitive: false,
  );

  // arXiv 旧格式：archive[.subject]/YYMMNNN，历史分类会出现大小写混排。
  static final _arxivOldRegExp = RegExp(
    r'(?:arXiv:\s*|arxiv\.org/(?:abs|pdf)/)?([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)?/\d{7}(?:v\d+)?)',
    caseSensitive: false,
  );

  // ISBN 正则：必须带 ISBN 标签，避免把普通页码或编号误识别成图书标识符。
  static final _isbnRegExp = RegExp(
    r'(?:ISBN(?:-1[03])?[:\s-]*)([0-9Xx][0-9Xx\s-]{8,20})',
    caseSensitive: false,
  );

  /// 从 PDF 前 2 页提取文本（带超时保护）
  ///
  /// 公开以便标识符提取与中文正文元数据提取复用同一次文本读取，
  /// 避免对同一 PDF 重复加锁打开。
  Future<String?> extractText(String filePath) async {
    return PdfProcessLock.instance
        .run(() async {
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
            log.d('提取 PDF 文本失败 ($filePath): $e');
            return null;
          } finally {
            document?.dispose();
          }
        })
        .timeout(
          _extractTimeout,
          onTimeout: () {
            log.d('提取 PDF 文本超时 ($filePath)');
            return null;
          },
        );
  }

  /// 从 PDF 前 2 页提取最佳标识符（DOI > arXiv > ISBN）
  Future<ParsedIdentifier?> extractIdentifier(String filePath) async {
    final fullText = await extractText(filePath);
    return extractIdentifierFromText(fullText);
  }

  /// 从已提取的文本中识别标识符，供复用同一次文本读取的调用方使用
  /// （例如元数据修复流程同时跑标识符提取与中文正文解析）。
  static ParsedIdentifier? extractIdentifierFromText(String? fullText) {
    if (fullText == null) return null;

    // 优先级 1: DOI
    final doiMatch = _doiRegExp.firstMatch(fullText);
    if (doiMatch != null) {
      final doi = IdentifierParser.normalizeDoi(doiMatch.group(0)!);
      if (doi != null) return ParsedIdentifier(IdentifierType.doi, doi);
    }

    // 优先级 2: arXiv ID
    final arxivNewMatch = _arxivNewRegExp.firstMatch(fullText);
    if (arxivNewMatch != null) {
      return ParsedIdentifier(IdentifierType.arxiv, arxivNewMatch.group(1)!);
    }
    final arxivOldMatch = _arxivOldRegExp.firstMatch(fullText);
    if (arxivOldMatch != null) {
      return ParsedIdentifier(IdentifierType.arxiv, arxivOldMatch.group(1)!);
    }

    // 优先级 3: ISBN-10 / ISBN-13
    final isbnMatch = _isbnRegExp.firstMatch(fullText);
    if (isbnMatch != null) {
      final parsed = IdentifierParser.parse(isbnMatch.group(1)!);
      if (parsed.type == IdentifierType.isbn) return parsed;
    }

    return null;
  }
}
