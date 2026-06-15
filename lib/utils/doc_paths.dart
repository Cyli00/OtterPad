import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage.dart';

/// 文献文件路径中心工具——所有衍生文件路径从此处派生。
///
/// 核心约定：每篇文献存放在以稳定 documentId 命名的独立目录中，
/// PDF 固定为 `library/{documentId}/source.pdf`。
class DocPaths {
  DocPaths._();

  static const pdfName = 'source.pdf';

  /// 文献目录。主入口传 documentId；为降低底层 PDF 处理改造面，临时兼容
  /// 已经是绝对 PDF 路径的调用。
  static String docDir(String documentIdOrPdfPath) {
    if (_looksLikePdfPath(documentIdOrPdfPath)) {
      return p.dirname(documentIdOrPdfPath);
    }
    return p.join(GStorage.libraryDirPath, documentIdOrPdfPath);
  }

  static String pdf(String documentId) => p.join(docDir(documentId), pdfName);

  static String rawMd(String documentIdOrPdfPath) =>
      p.join(docDir(documentIdOrPdfPath), 'extract.raw.md');

  static String md(String documentIdOrPdfPath) =>
      p.join(docDir(documentIdOrPdfPath), 'extract.md');

  static String json(String documentIdOrPdfPath) =>
      p.join(docDir(documentIdOrPdfPath), 'extract.json');

  static String translations(String documentIdOrPdfPath) =>
      p.join(docDir(documentIdOrPdfPath), 'translations.json');

  static String figuresDir(String documentIdOrPdfPath) =>
      p.join(docDir(documentIdOrPdfPath), 'figures');

  static String figuresManifest(String documentIdOrPdfPath) =>
      p.join(figuresDir(documentIdOrPdfPath), 'figures.json');

  static String chatsDir(String documentIdOrPdfPath) =>
      p.join(docDir(documentIdOrPdfPath), 'chats');

  static String chatSession(String documentIdOrPdfPath, String sessionId) =>
      p.join(chatsDir(documentIdOrPdfPath), '$sessionId.json');

  static String summaryDir(String documentIdOrPdfPath) =>
      p.join(docDir(documentIdOrPdfPath), 'summary');

  static String summaryImage(String documentIdOrPdfPath) =>
      p.join(summaryDir(documentIdOrPdfPath), 'summary.png');

  static String summaryMeta(String documentIdOrPdfPath) =>
      p.join(summaryDir(documentIdOrPdfPath), 'summary.meta.json');

  static bool _looksLikePdfPath(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return false;
    return p.isAbsolute(normalized) ||
        normalized.endsWith('/$pdfName') ||
        normalized.endsWith('\\$pdfName') ||
        p.extension(normalized).toLowerCase() == '.pdf';
  }

  /// 计算文件内容的 SHA-256 哈希，取前 12 字节 hex 编码（24 字符）。
  static Future<String> computeHash(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.bytes
        .sublist(0, 12)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
