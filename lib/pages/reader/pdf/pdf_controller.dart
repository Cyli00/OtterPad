import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/app_logger.dart';
import '../../../core/rust_backend.dart';
import '../../../src/rust/api.dart';
import '../../../src/rust/pdf.dart';
import '../../../src/rust/pdf/geometry.dart' as geo;

/// 一个搜索命中：页码与该页上的矩形（PDF 点，左上原点）。
typedef PdfMatch = ({int page, List<geo.Rect> rects});

/// Rust PDF 视图的外部控制：搜索、命中跳转。视图挂载后由视图注入句柄与跳转回调。
class PdfViewController extends ChangeNotifier {
  BigInt? _handle;
  int _pageCount = 0;
  void Function(PdfMatch match)? _reveal;

  List<PdfMatch> matches = const [];
  int currentIndex = -1;

  int _generation = 0;
  String? _task;
  Timer? _debounce;

  void attach(BigInt handle, int pageCount, void Function(PdfMatch) reveal) {
    _handle = handle;
    _pageCount = pageCount;
    _reveal = reveal;
  }

  void detach() {
    _handle = null;
    _reveal = null;
    clearSearch();
  }

  /// 逐页搜索；输入中途变化时丢弃旧结果。第一条命中出现即跳过去。
  void search(String query) {
    clearSearch();
    final text = query.trim();
    if (text.isEmpty) return;
    final generation = _generation;
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_run(text, generation)),
    );
  }

  Future<void> _run(String query, int generation) async {
    final handle = _handle;
    if (handle == null) return;
    final found = <PdfMatch>[];
    for (var page = 0; page < _pageCount; page++) {
      if (generation != _generation) return;
      final id = rustTaskId('pdf-search');
      _task = id;
      List<geo.SearchHit> hits;
      try {
        hits = await RustBackend.instance.searchPdfPage(
          handle: handle,
          page: page,
          query: query,
          taskId: id,
        );
      } catch (e) {
        if (isCancellation(e) || generation != _generation) return;
        log.d('[PdfView] 第 ${page + 1} 页搜索失败：$e');
        continue;
      }
      if (generation != _generation || hits.isEmpty) continue;
      found.addAll(hits.map((h) => (page: page, rects: h.rectangles)));
      matches = List.unmodifiable(found);
      if (currentIndex < 0) {
        currentIndex = 0;
        _reveal?.call(matches.first);
      }
      notifyListeners();
    }
    _task = null;
  }

  void clearSearch() {
    _generation++;
    _debounce?.cancel();
    if (_task case final id?) cancelTask(taskId: id);
    _task = null;
    if (matches.isEmpty && currentIndex < 0) return;
    matches = const [];
    currentIndex = -1;
    notifyListeners();
  }

  void step(int delta) {
    if (matches.isEmpty) return;
    currentIndex = (currentIndex + delta) % matches.length;
    _reveal?.call(matches[currentIndex]);
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    if (_task case final id?) cancelTask(taskId: id);
    super.dispose();
  }
}

/// 打开文献 PDF，供视图与缩略图共用。
Future<DocumentInfo> openLibraryPdf(String documentId) => RustBackend.instance
    .openPdf(document: documentId, taskId: rustTaskId('pdf-open'));
