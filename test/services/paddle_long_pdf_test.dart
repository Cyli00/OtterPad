import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/data/models/ocr/doc_extract_config.dart';
import 'package:otter_pad/services/batch_extract_service.dart';
import 'package:otter_pad/services/doc_extract_service.dart';
import 'package:otter_pad/services/paddle_page_results.dart';
import 'package:otter_pad/utils/doc_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  const state = DocExtractApiState(provider: DocExtractProvider.paddle);

  test('restarted page_index does not drop pages before 601', () {
    final pages = [
      for (var i = 0; i < 720; i++) _page(i + 1, pageIndex: i % 200),
    ];
    final md = DocExtractService.replaceFigureRegions(
      jsonContent: jsonEncode(pages),
      figures: const [],
      mdDir: '/tmp',
    );
    expect(_markers(md), [for (var n = 1; n <= 720; n++) n]);
  });

  test('assemble keeps colliding image URLs from earlier pages', () {
    final result = assemblePaddlePages([
      _page(1, imageKey: 'imgs/fig.jpg', imageUrl: 'https://img.test/early'),
      _page(2, imageKey: 'imgs/fig.jpg', imageUrl: 'https://img.test/late'),
    ]);
    expect(result.images['imgs/fig.jpg'], 'https://img.test/early');
    expect(result.images['p1_imgs/fig.jpg'], 'https://img.test/late');
    expect(
      result.rawMarkdown.indexOf('OTTER_PAGE_0001'),
      lessThan(result.rawMarkdown.indexOf('OTTER_PAGE_0002')),
    );
    expect(result.rawMarkdown, contains('p1_imgs/fig.jpg'));
  });

  test('extractSingle keeps 720 restarted pages through saveResult', () async {
    final dir = await Directory.systemTemp.createTemp('otter_paddle720_');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File('${dir.path}/source.pdf');
    final original = buildMarkedPdf(1);
    await pdf.writeAsBytes(original, flush: true);
    final fake = _PaddleFake(
      jsonlFor: (range) => _jsonl([
        for (var n = 1; n <= 720; n++) _page(n, pageIndex: (n - 1) % 200),
      ]),
    )..install();

    final extracted = await fake.service.extractSingle(
      filePath: pdf.path,
      token: 'offline-token',
      state: state,
      pageCount: 720,
    );
    expect(fake.ranges, [null]);
    expect(_markers(extracted.rawMarkdown), [for (var n = 1; n <= 720; n++) n]);
    final saved = await DocExtractService.instance.saveResult(
      pdf.path,
      extracted,
      title: null,
    );
    final md = await File(saved).readAsString();
    final raw = await File(DocPaths.rawMd(pdf.path)).readAsString();
    final expected = [for (var n = 1; n <= 720; n++) n];
    expect(_markers(raw), expected, reason: 'raw.md keeps every page');
    expect(
      _markers(md),
      expected,
      reason: 'extract.md is what the reader loads',
    );
    expect(await pdf.readAsBytes(), original);
  });

  test(
    'jobs that finish out of order merge on pageRanges boundaries',
    () async {
      final dir = await Directory.systemTemp.createTemp('otter_paddle1001_');
      addTearDown(() => dir.delete(recursive: true));
      final pdf = File('${dir.path}/source.pdf');
      await pdf.writeAsBytes(buildMarkedPdf(1), flush: true);
      final fake = _PaddleFake(
        jsonlFor: (range) {
          final ends = range!.split('-');
          final start = int.parse(ends[0]);
          final end = int.parse(ends[1]);
          return _jsonl([
            for (var n = start; n <= end; n++) _page(n, pageIndex: n - start),
          ]);
        },
      )..install();

      final extracted = await fake.service.extractSingle(
        filePath: pdf.path,
        token: 'offline-token',
        state: state,
        pageCount: 1001,
      );
      expect(fake.pendingReplies, greaterThan(0));
      expect(fake.ranges, ['1-1000', '1001-1001']);
      expect(_markers(extracted.rawMarkdown).first, 1);
      expect(_markers(extracted.rawMarkdown), contains(1000));
      expect(_markers(extracted.rawMarkdown), contains(1001));
      expect(
        _markers(extracted.rawMarkdown).indexOf(1),
        lessThan(_markers(extracted.rawMarkdown).indexOf(1001)),
      );
    },
  );

  test(
    'a failed early Paddle range does not publish the finished tail',
    () async {
      final dir = await Directory.systemTemp.createTemp('otter_paddle_fail_');
      addTearDown(() => dir.delete(recursive: true));
      final pdf = File('${dir.path}/source.pdf');
      final original = buildMarkedPdf(1001);
      await pdf.writeAsBytes(original, flush: true);
      await File(
        DocPaths.md(pdf.path),
      ).writeAsString('KEEP_PREVIOUS_FULL_DOCUMENT');
      final fake = _PaddleFake(
        failRange: '1-1000',
        jsonlFor: (range) => _jsonl([_page(1001)]),
      )..install();

      final results = await fake.service.extractBatch(
        items: [
          BatchExtractItem(
            documentId: 'longdoc',
            filePath: pdf.path,
            title: 'Long',
          ),
        ],
        token: 'offline-token',
        state: state,
      );
      expect(results['longdoc'], isNull);
      expect(
        await File(DocPaths.md(pdf.path)).readAsString(),
        'KEEP_PREVIOUS_FULL_DOCUMENT',
      );
      expect(await pdf.readAsBytes(), original);
    },
  );
}

Map<String, dynamic> _page(
  int number, {
  int? pageIndex,
  String? imageKey,
  String? imageUrl,
}) {
  final marker = 'OTTER_PAGE_${number.toString().padLeft(4, '0')}';
  return {
    if (pageIndex != null) 'page_index': pageIndex,
    'markdown': {
      'text': imageKey == null ? marker : '$marker ![]($imageKey)',
      'images': {if (imageKey != null) imageKey: imageUrl},
    },
    'prunedResult': {'parsing_res_list': <Map<String, dynamic>>[]},
  };
}

String _jsonl(List<Map<String, dynamic>> pages) => jsonEncode({
  'result': {'layoutParsingResults': pages},
});

List<int> _markers(String markdown) => [
  for (final match in RegExp(r'OTTER_PAGE_(\d+)').allMatches(markdown))
    int.parse(match.group(1)!),
];

Uint8List buildMarkedPdf(int pageCount) {
  final objects = <String>[];
  final pageIds = [for (var i = 0; i < pageCount; i++) 4 + i * 2];
  objects.add('<< /Type /Catalog /Pages 2 0 R >>');
  objects.add(
    '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] '
    '/Count $pageCount >>',
  );
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < pageCount; i++) {
    final label = 'OTTER_PAGE_${(i + 1).toString().padLeft(4, '0')}';
    final stream = 'BT /F1 12 Tf 72 700 Td ($label) Tj ET';
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << /Font << /F1 3 0 R >> >> '
      '/Contents ${pageIds[i] + 1} 0 R >>',
    );
    objects.add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  }
  final buf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buf.length);
    buf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buf.length;
  buf
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (var i = 1; i < offsets.length; i++) {
    buf.write('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  buf.write(
    'trailer << /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(buf.toString().codeUnits);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);

  @override
  void close({bool force = false}) {}
}

class _PaddleFake {
  _PaddleFake({required this.jsonlFor, this.failRange});
  final String Function(String? range) jsonlFor;
  final String? failRange;
  int polls = 0;
  int pendingReplies = 0;
  final ranges = <String?>[];
  final _seen = <String, int>{};
  late final BatchExtractService service;

  void install() {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter(_handle);
    service = BatchExtractService.forTesting(dio);
  }

  Future<ResponseBody> _handle(RequestOptions options) async {
    final method = options.method.toUpperCase();
    final url = options.uri.toString();
    if (method == 'POST' && url.endsWith('/api/v2/ocr/jobs')) {
      final form = options.data;
      String? range;
      if (form is FormData) {
        for (final field in form.fields) {
          if (field.key == 'pageRanges') range = field.value;
        }
      }
      ranges.add(range);
      final id = Uri.encodeComponent(range ?? 'all');
      return _json({
        'code': 0,
        'data': {'jobId': id},
      });
    }
    if (method == 'GET' && url.contains('/api/v2/ocr/jobs/')) {
      polls++;
      final id = Uri.decodeComponent(url.split('/').last);
      final range = id == 'all' ? null : id;
      final failed = failRange != null && range == failRange;
      final seen = _seen[id] = (_seen[id] ?? 0) + 1;
      final ready = range == null || range.startsWith('1001') || seen > 1;
      if (!ready) {
        pendingReplies++;
        return _json({
          'code': 0,
          'data': {'state': 'pending', 'jobId': id},
        });
      }
      if (failed) {
        return _json({
          'code': 0,
          'data': {'state': 'failed', 'jobId': id, 'errorMsg': 'range failed'},
        });
      }
      return _json({
        'code': 0,
        'data': {
          'state': 'done',
          'jobId': id,
          'resultUrl': {'jsonUrl': 'https://jsonl.test/$id'},
        },
      });
    }
    if (method == 'GET' && url.startsWith('https://jsonl.test/')) {
      final id = Uri.decodeComponent(url.split('/').last);
      final range = id == 'all' ? null : id;
      return ResponseBody.fromString(
        jsonlFor(range),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/plain'],
        },
      );
    }
    return ResponseBody.fromString('not found', 404);
  }
}

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);
