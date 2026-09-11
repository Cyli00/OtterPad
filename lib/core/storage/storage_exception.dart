enum StorageFailure {
  invalidBackup,
  unsupportedBackup,
  pendingRestore,
  activeTasks,
  changedDuringBackup,
  operationInProgress,
}

class StorageException implements Exception {
  const StorageException(this.reason);

  final StorageFailure reason;

  @override
  String toString() => reason.name;
}
