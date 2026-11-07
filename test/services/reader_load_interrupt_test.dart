import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/providers/reader_session_provider.dart';
import 'package:otter_pad/providers/reader_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('刷新后的正文不会被仍在读取的旧文件覆盖', () async {
    final root = await Directory.systemTemp.createTemp('otter-reader-load-');
    addTearDown(() => root.delete(recursive: true));
    final library = Directory('${root.path}/library')..createSync();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await GStorage.initForTest(database, libraryDirPath: library.path);

    const docId = 'doc-load';
    final docDir = Directory('${library.path}/$docId')..createSync();
    final fifo = File('${docDir.path}/extract.md');
    final created = await Process.run('mkfifo', [fifo.path]);
    expect(created.exitCode, 0, reason: created.stderr);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    const args = ReaderSessionArgs(
      documentId: docId,
      title: '加载中的文献',
      defaultReadingMode: DefaultReadingMode.markdown,
    );
    final notifier = container.read(readerSessionProvider(args).notifier);

    final started = DateTime.now();
    while (!container.read(readerSessionProvider(args)).markdownLoading) {
      if (DateTime.now().difference(started) > const Duration(seconds: 2)) {
        fail('阅读文件没有进入加载');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    notifier.useExtractedMarkdown(
      markdownPath: '${docDir.path}/extract.md',
      markdownContent: 'NEW',
    );
    // 旧读取还堵在管道上。写入后它会完成，但必须丢掉结果。
    await fifo.writeAsString('OLD').timeout(const Duration(seconds: 3));

    final settled = DateTime.now();
    while (DateTime.now().difference(settled) <
        const Duration(milliseconds: 200)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final state = container.read(readerSessionProvider(args));
      expect(state.markdownContent, 'NEW');
      expect(state.markdownLoading, isFalse);
    }
  });
}
