import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/document_task_provider.dart';
import 'package:otter_pad/services/snackbar_service.dart';

void main() {
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
