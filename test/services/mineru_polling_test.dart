import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/services/batch_extract_service.dart';
import 'package:otter_pad/services/mineru_extract_service.dart';

class PollAdapter implements HttpClientAdapter {
  int polls = 0;
  CancelToken? cancelOnPoll;
  bool downloadRequested = false;
  bool failPoll = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) await requestStream.drain<void>();
    final Map<String, Object?> body;
    if (options.method == 'POST') {
      body = {
        'code': 0,
        'data': {
          'batch_id': 'batch',
          'file_urls': ['https://upload.example/file'],
        },
      };
    } else if (options.method == 'PUT') {
      body = {};
    } else {
      if (options.path.contains('download.example')) {
        downloadRequested = true;
        return ResponseBody.fromString('zip', 200);
      }
      if (failPoll) {
        polls++;
        return ResponseBody.fromString(
          '{"code":-500,"msg":"测试错误"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      cancelOnPoll?.cancel();
      final states = ['pending', 'running', 'converting', 'failed'];
      final current = cancelOnPoll == null ? states[polls++] : 'done';
      body = {
        'code': 0,
        'data': {
          'extract_result': [
            {
              'data_id': 'doc',
              'state': current,
              'full_zip_url': 'https://download.example/result.zip',
              'err_msg': current == 'failed' ? '测试终态' : '',
            },
          ],
        },
      };
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('查询完成时取消单文件任务，不再下载结果', () async {
    final temp = await Directory.systemTemp.createTemp('mineru_cancel_');
    addTearDown(() => temp.delete(recursive: true));
    final pdf = await File('${temp.path}/source.pdf').writeAsString('测试');
    final token = CancelToken();
    final adapter = PollAdapter()..cancelOnPoll = token;
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close());
    final service = MinerUExtractService(
      client: dio,
      pollInterval: Duration.zero,
    );
    await expectLater(
      service.extractSingle(
        filePath: pdf.path,
        apiKey: '',
        state: const DocExtractApiState(provider: DocExtractProvider.mineru),
        cancelToken: token,
      ),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          '取消',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(adapter.downloadRequested, isFalse);
  });

  for (final cancelling in [true, false]) {
    test(cancelling ? '批量查询返回时取消，不发布结果' : '连续查询失败后结束批量任务', () async {
      final temp = await Directory.systemTemp.createTemp('mineru_batch_');
      addTearDown(() => temp.delete(recursive: true));
      final pdf = await File('${temp.path}/source.pdf').writeAsString('测试');
      final token = CancelToken();
      final adapter = PollAdapter()
        ..cancelOnPoll = cancelling ? token : null
        ..failPoll = !cancelling;
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close());
      final service = MinerUExtractService(
        client: dio,
        pollInterval: Duration.zero,
      );
      final updates = <BatchJobState>[];
      final results = await service.extractBatch(
        items: [
          BatchExtractItem(documentId: 'doc', filePath: pdf.path, title: '测试'),
        ],
        apiKey: '',
        state: const DocExtractApiState(provider: DocExtractProvider.mineru),
        cancelToken: token,
        onJobUpdate: (job) => updates.add(job.state),
      );
      expect(results, {'doc': null});
      expect(
        updates.last,
        cancelling ? BatchJobState.cancelled : BatchJobState.failed,
      );
      expect(adapter.downloadRequested, isFalse);
      if (!cancelling) expect(adapter.polls, 3);
    });
  }

  test('批量解析持续轮询排队、解析和格式转换状态直到终态', () async {
    final temp = await Directory.systemTemp.createTemp('mineru_poll_');
    addTearDown(() => temp.delete(recursive: true));
    final pdf = File('${temp.path}/source.pdf');
    await pdf.writeAsString('测试文件');
    final adapter = PollAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close());
    final service = MinerUExtractService(
      client: dio,
      pollInterval: Duration.zero,
    );
    final updates = <BatchJobState>[];
    await service.extractBatch(
      items: [
        BatchExtractItem(documentId: 'doc', filePath: pdf.path, title: '测试'),
      ],
      apiKey: '',
      state: const DocExtractApiState(provider: DocExtractProvider.mineru),
      onJobUpdate: (job) => updates.add(job.state),
    );
    expect(adapter.polls, 4);
    expect(updates.last, BatchJobState.failed);
  });
}
