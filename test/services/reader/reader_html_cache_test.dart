import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/reader/reader_html_cache.dart';

void main() {
  late Directory temp;
  late String path;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('reader_html_');
    path = '${temp.path}/.reader.html';
  });
  tearDown(() => temp.delete(recursive: true));

  test('连续生成时最后一次请求的 HTML 和指纹成对覆盖旧文件', () async {
    final oldGate = Completer<String>();
    final first = ReaderHtmlCache.write(
      path: path,
      fingerprint: 'old',
      buildHtml: () => oldGate.future,
    );
    final second = ReaderHtmlCache.write(
      path: path,
      fingerprint: 'new',
      buildHtml: () async => '<html>最新排版</html>',
    );
    oldGate.complete('<html>旧排版</html>');
    await Future.wait([first, second]);
    expect(await File(path).readAsString(), '<html>最新排版</html>');
    expect(await File('$path.fp').readAsString(), 'new');
    expect(await File('$path.pending').exists(), isFalse);
  });

  test('同指纹复用，版本变化后重新生成；生成失败保留旧 HTML', () async {
    await ReaderHtmlCache.write(
      path: path,
      fingerprint: '1',
      buildHtml: () async => '第一版',
    );
    expect(
      await ReaderHtmlCache.write(
        path: path,
        fingerprint: '1',
        buildHtml: () async => throw StateError('不应生成'),
      ),
      isTrue,
    );
    await expectLater(
      ReaderHtmlCache.write(
        path: path,
        fingerprint: '2',
        buildHtml: () async => throw StateError('生成失败'),
      ),
      throwsStateError,
    );
    expect(await File(path).readAsString(), '第一版');
    await ReaderHtmlCache.write(
      path: path,
      fingerprint: '3',
      buildHtml: () async => '最新版',
    );
    expect(await File(path).readAsString(), '最新版');
    expect(await File('$path.fp').readAsString(), '3');
  });
}
