import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/share_receiver_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otterpad_share_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('接受具有 PDF 文件头的文件', () async {
    final file = File('${tempDir.path}/valid.pdf');
    await file.writeAsBytes([...'%PDF-'.codeUnits, 0x31, 0x2E, 0x37]);

    expect(await ShareReceiverService.hasPdfHeader(file.path), isTrue);
  });

  test('拒绝仅使用 PDF 扩展名的非 PDF 文件', () async {
    final file = File('${tempDir.path}/fake.pdf');
    await file.writeAsString('not a pdf');

    expect(await ShareReceiverService.hasPdfHeader(file.path), isFalse);
  });

  test('拒绝不存在或文件头不完整的文件', () async {
    final shortFile = File('${tempDir.path}/short.pdf');
    await shortFile.writeAsBytes('%PDF'.codeUnits);

    expect(await ShareReceiverService.hasPdfHeader(shortFile.path), isFalse);
    expect(
      await ShareReceiverService.hasPdfHeader('${tempDir.path}/missing.pdf'),
      isFalse,
    );
  });
}
