import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/providers/document_task_provider.dart';
import 'package:otter_pad/providers/reader_session_provider.dart';
import 'package:otter_pad/providers/reader_settings_provider.dart';
import 'package:otter_pad/services/snackbar_service.dart';
import 'package:otter_pad/utils/doc_paths.dart';

class TestTasks extends DocumentTaskNotifier {
  TestTasks(super.ref);

  void finish(String documentId, String path) {
    final key = DocumentTaskKey(
      type: DocumentTaskType.extractDocument,
      documentId: documentId,
    );
    state = {
      key: DocumentTaskInfo(
        key: key,
        title: '文献',
        status: DocumentTaskStatus.completed,
        progress: const ListenableProgress(current: 1, total: 1, status: '完成'),
        cancelToken: CancelToken(),
        result: path,
      ),
    };
  }
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late ProviderContainer container;
  const args = ReaderSessionArgs(
    documentId: 'doc',
    title: '文献',
    defaultReadingMode: DefaultReadingMode.markdown,
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('reader_refresh_');
    db = AppDatabase(NativeDatabase.memory());
    await GStorage.initForTest(
      db,
      dbDirPath: temp.path,
      libraryDirPath: temp.path,
      logsDirPath: temp.path,
    );
    await File(DocPaths.md('doc')).create(recursive: true);
    await File(DocPaths.md('doc')).writeAsString('旧内容');
    container = ProviderContainer(
      overrides: [documentTaskProvider.overrideWith((ref) => TestTasks(ref))],
    );
    final ready = Completer<void>();
    container.listen(readerSessionProvider(args), (_, next) {
      if (next.markdownContent != null && !ready.isCompleted) ready.complete();
    }, fireImmediately: true);
    await ready.future;
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  test('相同文字重新排版也发布新内容版本', () {
    final notifier = container.read(readerSessionProvider(args).notifier);
    notifier.useExtractedMarkdown(
      markdownPath: DocPaths.md('doc'),
      markdownContent: '相同正文',
    );
    final oldKey = container.read(readerSessionProvider(args)).markdownCacheKey;
    notifier.useExtractedMarkdown(
      markdownPath: DocPaths.md('doc'),
      markdownContent: '相同正文',
    );
    expect(
      container.read(readerSessionProvider(args)).markdownCacheKey,
      isNot(oldKey),
    );
  });

  test('外部批量提取完成后已打开的阅读器加载最新内容', () async {
    await File(DocPaths.md('doc')).writeAsString('最新排版内容');
    (container.read(documentTaskProvider.notifier) as TestTasks).finish(
      'doc',
      DocPaths.md('doc'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      container.read(readerSessionProvider(args)).markdownContent,
      '最新排版内容',
    );
  });
}
