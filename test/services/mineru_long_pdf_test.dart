import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/data/models/ocr/doc_extract_config.dart';
import 'package:otter_pad/services/batch_extract_service.dart';
import 'package:otter_pad/services/mineru_extract_service.dart';
import 'package:otter_pad/services/mineru_page_chunks.dart';
import 'package:otter_pad/services/mineru_result_converter.dart';
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

  test(
    '720 pages split on the 200-page boundary, last range starts at 601',
    () {
      final chunks = planMinerUPageChunks(720);
      expect(chunks.map((c) => c.pageRanges).toList(), [
        '1-200',
        '201-400',
        '401-600',
        '601-720',
      ]);
      expect(planMinerUPageChunks(200).single.wholeFile, isTrue);
      expect(planMinerUPageChunks(201).map((c) => c.pageRanges).toList(), [
        '1-200',
        '201-201',
      ]);
      expect(planMinerUPageChunks(230).last.pageRanges, '201-230');
    },
  );

  test(
    'out-of-order chunk zips merge in page order without filename overwrite',
    () {
      final chunks = planMinerUPageChunks(720);
      final parts = [
        for (final chunk in chunks.reversed)
          (
            chunk: chunk,
            bytes: _chunkZip(
              start: chunk.startPage,
              end: chunk.endPage,
              root: 'nested/',
            ),
          ),
      ];
      final merged = ZipDecoder().decodeBytes(mergeMinerUResultZips(parts));
      final markdown = _zipText(merged, 'full.md');
      expect(_markers(markdown), [for (var n = 1; n <= 720; n++) n]);
      final layout =
          jsonDecode(_zipText(merged, 'layout.json')) as Map<String, dynamic>;
      final pages = layout['pdf_info'] as List;
      expect(pages.length, 720);
      expect((pages.first as Map)['page_idx'], 0);
      expect((pages[600] as Map)['page_idx'], 600);
      expect((pages.last as Map)['page_idx'], 719);
      final firstText =
          (((pages.first as Map)['para_blocks'] as List).first as Map)['lines'];
      expect(jsonEncode(firstText), contains('OTTER_PAGE_0001'));
      final lateText =
          (((pages[600] as Map)['para_blocks'] as List).first as Map)['lines'];
      expect(jsonEncode(lateText), contains('OTTER_PAGE_0601'));
    },
  );

  test('same image name in an early and late chunk keeps both payloads', () {
    final early = planMinerUPageChunks(400).first;
    final late = planMinerUPageChunks(400)[1];
    final merged = ZipDecoder().decodeBytes(
      mergeMinerUResultZips([
        (
          chunk: late,
          bytes: _chunkZip(
            start: late.startPage,
            end: late.endPage,
            images: {
              'images/fig.jpg': [9, 9, 9],
            },
            markdownPrefix: 'LATE ![](images/fig.jpg)\n',
          ),
        ),
        (
          chunk: early,
          bytes: _chunkZip(
            start: early.startPage,
            end: early.endPage,
            images: {
              'images/fig.jpg': [1, 2, 3],
            },
            markdownPrefix: 'EARLY ![](images/fig.jpg)\n',
          ),
        ),
      ]),
    );
    final markdown = _zipText(merged, 'full.md');
    expect(markdown.indexOf('EARLY'), lessThan(markdown.indexOf('LATE')));
    expect(markdown, contains('images/c1_fig.jpg'));
    expect(_zipBytes(merged, 'images/fig.jpg'), [1, 2, 3]);
    expect(_zipBytes(merged, 'images/c1_fig.jpg'), [9, 9, 9]);
  });

  test('a missing middle chunk is not replaced by the tail', () {
    final chunks = planMinerUPageChunks(720);
    expect(
      () => mergeMinerUResultZips([
        for (final chunk in chunks)
          (
            chunk: chunk,
            bytes: _chunkZip(
              start: chunk.startPage,
              end: chunk.endPage,
              omitMarkdown: chunk.index == 2,
            ),
          ),
      ]),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('401-600'),
        ),
      ),
    );
  });

  test(
    'extractSingle waits for every range and publishes pages in order',
    () async {
      final dir = await Directory.systemTemp.createTemp('otter720_');
      addTearDown(() => dir.delete(recursive: true));
      final pdf = File('${dir.path}/source.pdf');
      final original = buildMarkedPdf(720);
      await pdf.writeAsBytes(original, flush: true);
      expect(_pdfCount(original), 720);

      final fake = _MinerUFake()..install();
      final zip = await fake.service.extractSingle(
        filePath: pdf.path,
        apiKey: 'offline-token',
        state: const DocExtractApiState(provider: DocExtractProvider.mineru),
      );
      expect(fake.polls, greaterThan(1));
      expect(fake.files.map((f) => f['page_ranges']).toList(), [
        '1-200',
        '201-400',
        '401-600',
        '601-720',
      ]);
      expect(
        _markers(
          _zipText(
            ZipDecoder().decodeBytes(await zip.readAsBytes()),
            'full.md',
          ),
        ),
        [for (var n = 1; n <= 720; n++) n],
      );

      final converted = await MinerUResultConverter.instance.convert(
        pdfPath: pdf.path,
        zipFile: zip,
      );
      expect(converted.pageCount, 720);
      final raw = await File(DocPaths.rawMd(pdf.path)).readAsString();
      final md = await File(converted.mdPath).readAsString();
      final expected = [for (var n = 1; n <= 720; n++) n];
      expect(
        _markers(raw),
        expected,
        reason:
            'raw.md is the merged provider text before reader preprocessing',
      );
      expect(
        _markers(md),
        expected,
        reason: 'extract.md is what the reader loads, with no tail slice',
      );
      expect(await pdf.readAsBytes(), original);
    },
  );

  test('a failed early range does not publish the finished tail', () async {
    final dir = await Directory.systemTemp.createTemp('otter_fail_');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File('${dir.path}/source.pdf');
    final original = buildMarkedPdf(4);
    await pdf.writeAsBytes(original, flush: true);
    await File(
      DocPaths.md(pdf.path),
    ).writeAsString('KEEP_PREVIOUS_FULL_DOCUMENT');
    final fake = _MinerUFake(failRange: '1-200')..install();

    await expectLater(
      fake.service.extractSingle(
        filePath: pdf.path,
        apiKey: 'offline-token',
        state: const DocExtractApiState(provider: DocExtractProvider.mineru),
        pageCount: 720,
      ),
      throwsA(
        isA<MinerUExtractException>().having(
          (e) => e.message,
          'message',
          contains('1-200'),
        ),
      ),
    );
    expect(
      await File(DocPaths.md(pdf.path)).readAsString(),
      'KEEP_PREVIOUS_FULL_DOCUMENT',
    );
    expect(await File('${dir.path}/extract.mineru.zip').exists(), isFalse);
    expect(await pdf.readAsBytes(), original);
  });

  test(
    'batch keeps an early document when a later long-file chunk fails',
    () async {
      final root = await Directory.systemTemp.createTemp('otter_batch_');
      addTearDown(() => root.delete(recursive: true));
      final shortPdf = File('${root.path}/short/source.pdf');
      final longPdf = File('${root.path}/long/source.pdf');
      await shortPdf.parent.create(recursive: true);
      await longPdf.parent.create(recursive: true);
      await shortPdf.writeAsBytes(buildMarkedPdf(1), flush: true);
      final longBytes = buildMarkedPdf(230);
      await longPdf.writeAsBytes(longBytes, flush: true);
      await File(DocPaths.md(longPdf.path)).writeAsString('KEEP_LONG');

      final fake = _MinerUFake(failRange: '1-200')..install();
      final results = await fake.service.extractBatch(
        items: [
          BatchExtractItem(
            documentId: 'shortdoc',
            filePath: shortPdf.path,
            title: 'Short',
          ),
          BatchExtractItem(
            documentId: 'longdoc',
            filePath: longPdf.path,
            title: 'Long',
          ),
        ],
        apiKey: 'offline-token',
        state: const DocExtractApiState(provider: DocExtractProvider.mineru),
      );
      expect(results['longdoc'], isNull);
      expect(await File(DocPaths.md(longPdf.path)).readAsString(), 'KEEP_LONG');
      expect(await longPdf.readAsBytes(), longBytes);
      final shortMd = await File(results['shortdoc']!).readAsString();
      expect(_markers(shortMd), [1]);
      expect(
        fake.files.map((f) => f['page_ranges']).toList(),
        containsAll(['1-200', '201-230']),
      );
    },
  );
}

int _pdfCount(List<int> bytes) => int.parse(
  RegExp(r'/Count (\d+)').firstMatch(latin1.decode(bytes))!.group(1)!,
);

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

Uint8List _chunkZip({
  required int start,
  required int end,
  String root = '',
  bool omitMarkdown = false,
  String markdownPrefix = '',
  Map<String, List<int>> images = const {},
}) {
  final prefix = root.isEmpty ? '' : (root.endsWith('/') ? root : '$root/');
  final lines = <String>[
    if (markdownPrefix.isNotEmpty) markdownPrefix.trimRight(),
    for (var n = start; n <= end; n++)
      'OTTER_PAGE_${n.toString().padLeft(4, '0')}',
  ];
  final pages = [
    for (var n = start; n <= end; n++)
      {
        'page_idx': n - start,
        'page_size': [612, 792],
        'para_blocks': [
          {
            'type': 'text',
            'bbox': [0, 0, 10, 10],
            'lines': [
              {
                'bbox': [0, 0, 10, 10],
                'spans': [
                  {
                    'type': 'text',
                    'content': 'OTTER_PAGE_${n.toString().padLeft(4, '0')}',
                  },
                ],
              },
            ],
          },
        ],
      },
  ];
  final archive = Archive();
  if (!omitMarkdown) {
    archive.add(ArchiveFile.string('${prefix}full.md', lines.join('\n')));
  }
  archive.add(
    ArchiveFile.string('${prefix}layout.json', jsonEncode({'pdf_info': pages})),
  );
  for (final image in images.entries) {
    archive.add(ArchiveFile.bytes('$prefix${image.key}', image.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

String _zipText(Archive archive, String name) {
  final file = archive.files.firstWhere(
    (f) => f.isFile && f.name.replaceAll('\\', '/').endsWith(name),
  );
  return utf8.decode(file.content);
}

List<int> _zipBytes(Archive archive, String name) {
  final file = archive.files.firstWhere(
    (f) => f.isFile && f.name.replaceAll('\\', '/') == name,
  );
  return List<int>.from(file.content);
}

List<int> _markers(String markdown) => [
  for (final match in RegExp(r'OTTER_PAGE_(\d+)').allMatches(markdown))
    int.parse(match.group(1)!),
];

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

class _MinerUFake {
  _MinerUFake({this.failRange});
  final String? failRange;
  int polls = 0;
  List<Map<String, dynamic>> files = const [];
  late final MinerUExtractService service;

  void install() {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter(_handle);
    service = MinerUExtractService(client: dio, pollInterval: Duration.zero);
  }

  Future<ResponseBody> _handle(RequestOptions options) async {
    final method = options.method.toUpperCase();
    final url = options.uri.toString();
    if (method == 'POST' && url.contains('/file-urls/batch')) {
      final body = _jsonBody(options.data);
      files = [
        for (final file in body['files'] as List)
          Map<String, dynamic>.from(file as Map),
      ];
      return _json(200, {
        'code': 0,
        'data': {
          'batch_id': 'batch_offline',
          'file_urls': [
            for (final file in files) 'https://upload.test/${file['data_id']}',
          ],
        },
      });
    }
    if (method == 'PUT') return ResponseBody.fromString('', 200);
    if (method == 'GET' && url.contains('/extract-results/batch/')) {
      polls++;
      final ordered = files.reversed.toList();
      return _json(200, {
        'code': 0,
        'data': {
          'extract_result': [
            for (var i = 0; i < ordered.length; i++)
              _resultEntry(ordered[i], ready: polls > 1 || i == 0),
          ],
        },
      });
    }
    if (method == 'GET' && url.startsWith('https://zip.test/')) {
      final id = url.split('/').last;
      final file = files.firstWhere((f) => f['data_id'] == id);
      final range = (file['page_ranges'] as String?) ?? '1-1';
      final ends = range.split('-');
      return ResponseBody.fromBytes(
        _chunkZip(start: int.parse(ends[0]), end: int.parse(ends[1])),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/zip'],
        },
      );
    }
    return ResponseBody.fromString('not found', 404);
  }

  Map<String, dynamic> _resultEntry(
    Map<String, dynamic> file, {
    required bool ready,
  }) {
    final range = file['page_ranges'] as String?;
    final failed = ready && failRange != null && range == failRange;
    if (!ready) {
      return {'data_id': file['data_id'], 'state': 'pending'};
    }
    if (failed) {
      return {
        'data_id': file['data_id'],
        'state': 'failed',
        'err_msg': 'chunk failed',
      };
    }
    return {
      'data_id': file['data_id'],
      'state': 'done',
      'full_zip_url': 'https://zip.test/${file['data_id']}',
    };
  }
}

Map<String, dynamic> _jsonBody(Object? data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is String) return jsonDecode(data) as Map<String, dynamic>;
  throw StateError('unexpected request body ${data.runtimeType}');
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);
