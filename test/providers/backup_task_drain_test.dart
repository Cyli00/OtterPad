import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/storage_exception.dart';
import 'package:otter_pad/providers/backup_orchestrator.dart';
import 'package:otter_pad/providers/document_task_provider.dart';
import 'package:otter_pad/services/backup_restore_service.dart';
import 'package:otter_pad/services/snackbar_service.dart';

class PendingWriteTask extends DocumentTaskNotifier {
  PendingWriteTask(super.ref) {
    const key = DocumentTaskKey(
      type: DocumentTaskType.extractDocument,
      documentId: 'doc',
    );
    state = {
      key: DocumentTaskInfo(
        key: key,
        title: '测试',
        status: DocumentTaskStatus.running,
        progress: const ListenableProgress(current: 0, total: 0, status: ''),
        cancelToken: CancelToken(),
      ),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('无进度条的文献任务尚未退出时拒绝恢复', () async {
    final container = ProviderContainer(
      overrides: [
        documentTaskProvider.overrideWith((ref) => PendingWriteTask(ref)),
      ],
    );
    addTearDown(container.dispose);
    final provider = Provider((ref) => BackupOrchestrator(ref));
    final token = container
        .read(documentTaskProvider)
        .values
        .single
        .cancelToken;
    await expectLater(
      container
          .read(provider)
          .restoreFromArchive(
            archivePath: 'unused.zip',
            scope: BackupRestoreScope.full,
            mode: RestoreMode.overwrite,
          ),
      throwsA(
        isA<StorageException>().having(
          (e) => e.reason,
          '原因',
          StorageFailure.activeTasks,
        ),
      ),
    );
    expect(token.isCancelled, isTrue);
  });
}
