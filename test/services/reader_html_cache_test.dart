import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/reader/reader_html_cache.dart';

void main() {
  test('后发起的阅读文件覆盖先发起的生成，过期任务不能写回', () async {
    final dir = await Directory.systemTemp.createTemp('otter-html-cache-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/.reader.html';
    final firstHtml = Future<String>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return 'OLD';
    });
    final first = ReaderHtmlCache.write(
      path: path,
      fingerprint: () => 'old',
      buildHtml: () => firstHtml,
    );
    // 让第一次生成越过登记点，停在真正写文件之前。
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = ReaderHtmlCache.write(
      path: path,
      fingerprint: () => 'new',
      buildHtml: () async => 'NEW',
    );

    expect(await first, ReaderHtmlWriteResult.superseded);
    expect(await second, ReaderHtmlWriteResult.written);
    expect(await File(path).readAsString(), 'NEW');
    expect(await File('$path.fp').readAsString(), 'new');
  });
}
