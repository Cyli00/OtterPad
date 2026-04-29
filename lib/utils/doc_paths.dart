import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 文献文件路径中心工具——所有衍生文件路径从此处派生。
///
/// 核心约定：每篇文献存放在以内容哈希命名的独立目录中，
/// `pdfPath` 始终指向 `docs/{hash}/source.pdf`，
/// 所有衍生路径从 `p.dirname(pdfPath)` 推导。
class DocPaths {
  DocPaths._();

  static const pdfName = 'source.pdf';

  static String docDir(String pdfPath) => p.dirname(pdfPath);

  static String rawMd(String pdfPath) =>
      p.join(docDir(pdfPath), 'extract.raw.md');

  static String md(String pdfPath) =>
      p.join(docDir(pdfPath), 'extract.md');

  static String json(String pdfPath) =>
      p.join(docDir(pdfPath), 'extract.json');

  static String translations(String pdfPath) =>
      p.join(docDir(pdfPath), 'translations.json');

  static String figuresDir(String pdfPath) =>
      p.join(docDir(pdfPath), 'figures');

  static String figuresManifest(String pdfPath) =>
      p.join(figuresDir(pdfPath), 'figures.json');

  static String summaryDir(String pdfPath) =>
      p.join(docDir(pdfPath), 'summary');

  static String summaryImage(String pdfPath) =>
      p.join(summaryDir(pdfPath), 'summary.png');

  static String summaryMeta(String pdfPath) =>
      p.join(summaryDir(pdfPath), 'summary.meta.json');

  /// 计算文件内容的 SHA-256 哈希，取前 12 字节 hex 编码（24 字符）。
  static Future<String> computeHash(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.bytes
        .sublist(0, 12)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
