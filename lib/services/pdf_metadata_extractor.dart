import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'document_metadata_parser.dart';

class PdfMetadataExtractor {
  PdfMetadataExtractor._();
  static final PdfMetadataExtractor instance = PdfMetadataExtractor._();

  static final RegExp _xmpPattern = RegExp(
    r'<x:xmpmeta[\s\S]*?</x:xmpmeta>',
    caseSensitive: false,
  );

  Future<DocumentMetadata> extract(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return const DocumentMetadata();

    final bytes = await file.readAsBytes();
    final raw = latin1.decode(bytes);
    final infoMetadata = _extractFromInfoDictionary(raw);
    final xmpMetadata = _extractFromXmp(raw);
    return infoMetadata.merge(xmpMetadata);
  }

  DocumentMetadata _extractFromInfoDictionary(String raw) {
    final titleValue = _extractPdfString(raw, 'Title');
    final authorValue = _extractPdfString(raw, 'Author');
    final subjectValue = _extractPdfString(raw, 'Subject');
    final keywordsValue = _extractPdfString(raw, 'Keywords');

    // pdfTeX 会把 EPS/DVI 临时文件路径塞进 /Title，必须先过一遍 plausibility 检查，
    // 否则脏 title 会一路冒泡到 UI（参考 `DocumentMetadataParser.isPlausibleTitle`）。
    final cleanedTitle = _cleanText(titleValue);
    final acceptedTitle = DocumentMetadataParser.isPlausibleTitle(cleanedTitle)
        ? cleanedTitle
        : null;
    final rawTitleMetadata = DocumentMetadata(title: acceptedTitle);
    final parsedTitleMetadata = acceptedTitle == null
        ? const DocumentMetadata()
        : DocumentMetadataParser.parseText(acceptedTitle);

    // metadataText 用于 regex 抓 DOI / 年份，让脏 title 留在里面也没用（路径串
    // 不匹配 DOI/年份模式），但移除可以省点正则匹配成本。
    final metadataText = [
      acceptedTitle,
      subjectValue,
      keywordsValue,
    ].whereType<String>().join(' ');

    return rawTitleMetadata
        .merge(parsedTitleMetadata)
        .merge(
          DocumentMetadata(
            authors: _parseAuthors(authorValue),
            journal: _cleanJournal(subjectValue),
            year: DocumentMetadataParser.extractYear(metadataText),
            doi: DocumentMetadataParser.extractDoi(metadataText),
          ),
        );
  }

  DocumentMetadata _extractFromXmp(String raw) {
    final match = _xmpPattern.firstMatch(raw);
    if (match == null) return const DocumentMetadata();

    try {
      final document = XmlDocument.parse(match.group(0)!);
      final title = _firstListValue(document, 'title');
      final authors = _listValues(document, 'creator');
      final journal =
          _firstText(document, 'publicationName') ??
          _firstText(document, 'source');
      final year = DocumentMetadataParser.extractYear(
        _firstText(document, 'publicationDate') ??
            _firstText(document, 'coverDate') ??
            _firstText(document, 'date'),
      );
      final doi = DocumentMetadataParser.extractDoi(
        _firstText(document, 'doi') ?? _firstText(document, 'identifier'),
      );

      final cleanedXmpTitle = _cleanText(title);
      final acceptedXmpTitle =
          DocumentMetadataParser.isPlausibleTitle(cleanedXmpTitle)
          ? cleanedXmpTitle
          : null;
      final rawTitleMetadata = DocumentMetadata(title: acceptedXmpTitle);
      final parsedTitleMetadata = acceptedXmpTitle == null
          ? const DocumentMetadata()
          : DocumentMetadataParser.parseText(acceptedXmpTitle);

      return rawTitleMetadata
          .merge(parsedTitleMetadata)
          .merge(
            DocumentMetadata(
              authors: authors,
              journal: _cleanJournal(journal),
              year: year,
              doi: doi,
            ),
          );
    } catch (_) {
      final rawXmp = match.group(0)!;
      return DocumentMetadata(
        year: DocumentMetadataParser.extractYear(rawXmp),
        doi: DocumentMetadataParser.extractDoi(rawXmp),
      );
    }
  }

  String? _extractPdfString(String raw, String fieldName) {
    final token = '/$fieldName';
    var start = raw.indexOf(token);
    while (start >= 0) {
      var cursor = start + token.length;
      while (cursor < raw.length && _isWhitespace(raw.codeUnitAt(cursor))) {
        cursor++;
      }
      if (cursor >= raw.length) return null;

      final marker = raw[cursor];
      if (marker == '(') {
        final literal = _readLiteralString(raw, cursor);
        return _cleanText(_decodePdfBytes(_unescapePdfLiteral(literal)));
      }
      if (marker == '<' &&
          (cursor + 1 >= raw.length || raw[cursor + 1] != '<')) {
        final hex = _readHexString(raw, cursor);
        return _cleanText(_decodePdfBytes(_decodeHex(hex)));
      }

      start = raw.indexOf(token, cursor);
    }
    return null;
  }

  String _readLiteralString(String raw, int start) {
    final buffer = StringBuffer();
    var depth = 0;
    for (int i = start; i < raw.length; i++) {
      final current = raw[i];
      if (i == start) {
        depth = 1;
        continue;
      }
      if (current == r'\') {
        buffer.write(current);
        if (i + 1 < raw.length) {
          i++;
          buffer.write(raw[i]);
        }
        continue;
      }
      if (current == '(') {
        depth++;
        buffer.write(current);
        continue;
      }
      if (current == ')') {
        depth--;
        if (depth == 0) break;
        buffer.write(current);
        continue;
      }
      buffer.write(current);
    }
    return buffer.toString();
  }

  String _readHexString(String raw, int start) {
    final buffer = StringBuffer();
    for (int i = start + 1; i < raw.length; i++) {
      final current = raw[i];
      if (current == '>') break;
      buffer.write(current);
    }
    return buffer.toString();
  }

  List<int> _unescapePdfLiteral(String text) {
    final bytes = <int>[];
    for (int i = 0; i < text.length; i++) {
      final current = text.codeUnitAt(i);
      if (current != 0x5c) {
        bytes.add(current);
        continue;
      }
      if (i + 1 >= text.length) break;
      final next = text.codeUnitAt(++i);
      switch (next) {
        case 0x6e:
          bytes.add(0x0a);
          break;
        case 0x72:
          bytes.add(0x0d);
          break;
        case 0x74:
          bytes.add(0x09);
          break;
        case 0x62:
          bytes.add(0x08);
          break;
        case 0x66:
          bytes.add(0x0c);
          break;
        case 0x28:
        case 0x29:
        case 0x5c:
          bytes.add(next);
          break;
        case 0x0d:
          if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0a) i++;
          break;
        case 0x0a:
          break;
        default:
          if (_isOctalDigit(next)) {
            final octal = StringBuffer()..writeCharCode(next);
            for (int count = 0; count < 2 && i + 1 < text.length; count++) {
              final candidate = text.codeUnitAt(i + 1);
              if (!_isOctalDigit(candidate)) break;
              i++;
              octal.writeCharCode(candidate);
            }
            bytes.add(int.parse(octal.toString(), radix: 8));
          } else {
            bytes.add(next);
          }
      }
    }
    return bytes;
  }

  List<int> _decodeHex(String hexText) {
    final normalized = hexText.replaceAll(RegExp(r'\s+'), '');
    final padded = normalized.length.isOdd ? '${normalized}0' : normalized;
    final bytes = <int>[];
    for (int i = 0; i < padded.length; i += 2) {
      bytes.add(int.parse(padded.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  String _decodePdfBytes(List<int> bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xfe && bytes[1] == 0xff) {
        return _decodeUtf16(bytes.sublist(2), bigEndian: true);
      }
      if (bytes[0] == 0xff && bytes[1] == 0xfe) {
        return _decodeUtf16(bytes.sublist(2), bigEndian: false);
      }
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  String _decodeUtf16(List<int> bytes, {required bool bigEndian}) {
    final codeUnits = <int>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      codeUnits.add(
        bigEndian
            ? (bytes[i] << 8) | bytes[i + 1]
            : bytes[i] | (bytes[i + 1] << 8),
      );
    }
    return String.fromCharCodes(codeUnits);
  }

  List<String> _parseAuthors(String? rawAuthor) {
    final cleaned = _cleanText(rawAuthor);
    if (cleaned == null) return const [];

    final authors = cleaned
        .split(RegExp(r'\s*(?:;|\band\b)\s*', caseSensitive: false))
        .map(_cleanText)
        .whereType<String>()
        .where((author) => author.isNotEmpty)
        .toList();
    return authors.isEmpty ? [cleaned] : authors;
  }

  String? _firstText(XmlDocument document, String localName) {
    for (final node in document.descendants.whereType<XmlElement>()) {
      if (node.name.local == localName) {
        final value = _cleanText(node.innerText);
        if (value != null) return value;
      }
    }
    return null;
  }

  String? _firstListValue(XmlDocument document, String localName) {
    final values = _listValues(document, localName);
    return values.isEmpty ? null : values.first;
  }

  List<String> _listValues(XmlDocument document, String localName) {
    for (final node in document.descendants.whereType<XmlElement>()) {
      if (node.name.local != localName) continue;
      final values = node.descendants
          .whereType<XmlElement>()
          .where((child) => child.name.local == 'li')
          .map((child) => _cleanText(child.innerText))
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toList();
      if (values.isNotEmpty) return values;
    }
    return const [];
  }

  String? _cleanJournal(String? value) {
    final cleaned = _cleanText(value);
    if (cleaned == null) return null;
    if (DocumentMetadataParser.extractDoi(cleaned) != null) return null;
    return cleaned;
  }

  String? _cleanText(String? value) {
    if (value == null) return null;
    final cleaned = DocumentMetadataParser.normalizeWhitespace(value);
    return cleaned.isEmpty ? null : cleaned;
  }

  bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x0a ||
        codeUnit == 0x0d ||
        codeUnit == 0x09;
  }

  bool _isOctalDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x37;
}
