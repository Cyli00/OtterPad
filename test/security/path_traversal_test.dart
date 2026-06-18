import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:otter_pad/services/reader_localhost_server.dart';

/// 通过原始 Socket 发送 HTTP 请求，绕过 Dart Uri 的路径规范化。
Future<int> rawHttp(int port, String method, String rawPath) async {
  final socket = await Socket.connect('127.0.0.1', port);
  socket.write(
    '$method $rawPath HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
  );
  await socket.flush();
  final response = await utf8.decoder.bind(socket).join();
  socket.destroy();
  return int.parse(response.split('\r\n').first.split(' ')[1]);
}

void main() {
  late Directory tempRoot;
  late File testFile;
  final server = ReaderLocalhostServer.instance;

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('path_traversal_test_');
    testFile = File('${tempRoot.path}/doc/hello.txt');
    await testFile.create(recursive: true);
    await testFile.writeAsString('ok');
    await server.start(documentRoot: tempRoot.path);
  });

  tearDownAll(() async {
    await server.close();
    await tempRoot.delete(recursive: true);
  });

  // ── urlForPath 路径验证 ──

  group('urlForPath 路径穿越防护', () {
    test('root 下正常路径返回合法 URL', () {
      final url = server.urlForPath(testFile.path);
      expect(url, isNotNull);
      expect(url, contains('http://localhost:'));
      expect(url, contains('doc/hello.txt'));
    });

    test('../ 穿越路径返回 null', () {
      final traversal = '${tempRoot.path}/../etc/passwd';
      expect(server.urlForPath(traversal), isNull);
    });

    test('绝对路径（非 root 子目录）返回 null', () {
      expect(server.urlForPath('/tmp/other/secret.txt'), isNull);
      expect(server.urlForPath('C:\\Windows\\System32\\config'), isNull);
    });
  });

  // ── HTTP 请求级防护 ──

  group('HTTP 请求路径穿越防护', () {
    test('正常路径返回 200', () async {
      expect(await rawHttp(server.port, 'GET', '/doc/hello.txt'), 200);
    });

    // Dart 的 HttpServer URI 解析会规范化 `..` 段，因此 /../ 到达
    // handler 时已被简化。urlForPath 的测试覆盖了路径级 `..` 防御；
    // 此处验证 asset 路由的字符串级 `..` 拒绝。
    test('asset 路径含 .. 返回 403', () async {
      expect(
        await rawHttp(server.port, 'GET', '/_assets/..%2Fsecret.txt'),
        403,
      );
    });

    test('不存在的路径返回 404', () async {
      expect(await rawHttp(server.port, 'GET', '/nonexistent.txt'), 404);
    });

    test('POST 方法返回 405', () async {
      expect(await rawHttp(server.port, 'POST', '/doc/hello.txt'), 405);
    });
  });
}
