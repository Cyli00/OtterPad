import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/services/batch_extract_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/document_task_provider.dart';
import 'package:otter_pad/services/snackbar_service.dart';

class TestTasks extends DocumentTaskNotifier {
  TestTasks(super.ref);
  void seed(DocumentTaskInfo task) => state = {task.key: task};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('等待上传的批量任务取消真实请求，完成退场前保持活跃', () {
    final container = ProviderContainer(
      overrides: [documentTaskProvider.overrideWith((ref) => TestTasks(ref))],
    );
    addTearDown(container.dispose);
    final notifier = container.read(documentTaskProvider.notifier) as TestTasks;
    const key = DocumentTaskKey(
      type: DocumentTaskType.extractDocument,
      documentId: 'doc',
    );
    final token = CancelToken();
    notifier.seed(
      DocumentTaskInfo(
        key: key,
        title: '测试',
        status: DocumentTaskStatus.queued,
        progress: const ListenableProgress(current: 0, total: 0, status: ''),
        cancelToken: token,
      ),
    );
    notifier.cancelTask(key);
    expect(token.isCancelled, isTrue);
    expect(notifier.isActive(key), isTrue);
  });

  test('批量预检发现文件缺失时结束为失败，不向调用方抛异常', () async {
    final temp = await Directory.systemTemp.createTemp('extract_missing_');
    addTearDown(() => temp.delete(recursive: true));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final results = await container
        .read(documentTaskProvider.notifier)
        .extractBatch(
          items: [
            BatchExtractItem(
              documentId: 'missing',
              filePath: '${temp.path}/missing.pdf',
              title: '测试',
            ),
          ],
          apiState: const DocExtractApiState(paddleApiKey: 'fixture'),
        );
    expect(results, {'missing': null});
    expect(
      container.read(documentTaskProvider).values.single.status,
      DocumentTaskStatus.failed,
    );
  });

  group('DocumentTask', () {
    test('任务 Key 使用文献与类型共同区分', () {
      const left = DocumentTaskKey(
        type: DocumentTaskType.extractDocument,
        documentId: 'doc-a',
      );
      const same = DocumentTaskKey(
        type: DocumentTaskType.extractDocument,
        documentId: 'doc-a',
      );
      const differentType = DocumentTaskKey(
        type: DocumentTaskType.generateSummaryImage,
        documentId: 'doc-a',
      );

      expect(left, same);
      expect(left, isNot(differentType));
    });

    test('排队和运行态都属于活跃任务', () {
      final key = const DocumentTaskKey(
        type: DocumentTaskType.extractDocument,
        documentId: 'doc-a',
      );
      final queued = DocumentTaskInfo(
        key: key,
        title: '文献',
        status: DocumentTaskStatus.queued,
        progress: const ListenableProgress(current: 0, total: 0, status: '等待'),
        cancelToken: CancelToken(),
      );
      final completed = queued.copyWith(status: DocumentTaskStatus.completed);

      expect(queued.isActive, isTrue);
      expect(completed.isActive, isFalse);
      expect(DocumentTaskNotifier.maxConcurrent, 5);
    });
  });
}
