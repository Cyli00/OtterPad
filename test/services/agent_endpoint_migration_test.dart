import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/pages/setting/agent_model_tester.dart';
import 'package:otter_pad/providers/agent_api_provider.dart';
import 'package:otter_pad/services/agent_chat_service.dart';
import 'package:otter_pad/services/agent_http.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);
ResponseBody sseResponse(List<Map<String, dynamic>> events) =>
    ResponseBody.fromString(
      events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
      200,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late Directory temp;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('otter-endpoint-test-');
    await GStorage.initForTest(database, logsDirPath: temp.path);
    AgentHttp.instance.resetInstances();
  });
  tearDown(() async {
    AgentHttp.instance.resetInstances();
    await database.close();
    await temp.delete(recursive: true);
  });

  for (final base in [
    'https://fixture.invalid',
    'https://fixture.invalid/v1beta',
    'https://fixture.invalid/v1beta///',
  ]) {
    test('Gemini 测试、普通和流式回答地址一致：$base', () async {
      final paths = <String>[];
      final response = {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '回答'},
              ],
            },
          },
        ],
      };
      final adapter = FakeAdapter((request) async {
        paths.add(request.uri.path);
        return request.uri.queryParameters['alt'] == 'sse'
            ? sseResponse([response])
            : jsonResponse(response);
      });
      AgentHttp.instance.dio().httpClientAdapter = adapter;
      AgentHttp.instance
              .dio(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
              )
              .httpClientAdapter =
          adapter;
      expect(
        await testAgentModel(
          provider: AgentApiProvider.gemini,
          baseUrl: base,
          apiKey: 'fixture',
          modelId: 'gemini-test',
        ),
        isNull,
      );
      expect(
        await AgentChatService.send(
          provider: AgentApiProvider.gemini,
          baseUrl: base,
          apiKey: 'fixture',
          modelId: 'gemini-test',
          systemPrompt: '系统',
          userPrompt: '问题',
        ),
        '回答',
      );
      expect(
        await AgentChatService.sendStream(
          provider: AgentApiProvider.gemini,
          baseUrl: base,
          apiKey: 'fixture',
          modelId: 'gemini-test',
          systemPrompt: '系统',
          userPrompt: '问题',
          onDelta: (_) {},
        ),
        '回答',
      );
      expect(paths, [
        '/v1beta/models/gemini-test:generateContent',
        '/v1beta/models/gemini-test:generateContent',
        '/v1beta/models/gemini-test:streamGenerateContent',
      ]);
    });
  }

  test('其他协议继续使用原来的资源路径', () {
    expect(
      AgentApiProvider.openai.chatUrl('https://fixture.invalid/v1'),
      'https://fixture.invalid/v1/responses',
    );
    expect(
      AgentApiProvider.anthropic.chatUrl('https://fixture.invalid'),
      'https://fixture.invalid/v1/messages',
    );
    expect(
      AgentApiProvider.openAICompatible.chatUrl(
        'https://fixture.invalid/api/v4',
      ),
      'https://fixture.invalid/api/v4/chat/completions',
    );
    expect(
      AgentApiProvider.openAICompatible.chatUrl('https://api.x.ai/v1'),
      'https://api.x.ai/v1/responses',
    );
  });
}
