import 'dart:async';

import 'storage_exception.dart';

/// 恢复先关闭入口，再等待真实 Future 退出；取消状态不等于文件句柄已释放。
class StorageActivity {
  static final _ownerKey = Object();
  static final _restoreKey = Object();
  static final _active = <_Activity>{};
  static bool _restoring = false;
  static Object? _restoreOwner;
  static int generation = 0;
  static Completer<void>? _changed;

  static bool get isRestoring => _restoring;

  static Future<T> run<T>(
    Future<T> Function() action, {
    void Function()? cancel,
  }) async {
    final parent = Zone.current[_ownerKey] as _Activity?;
    if (_restoring &&
        Zone.current[_restoreKey] != _restoreOwner &&
        (parent == null || !_active.contains(parent))) {
      throw const StorageException(StorageFailure.operationInProgress);
    }
    final activity = _Activity(cancel);
    _active.add(activity);
    try {
      if (_restoring) cancel?.call();
      return await runZoned(action, zoneValues: {_ownerKey: activity});
    } finally {
      _active.remove(activity);
      _changed?.complete();
      _changed = null;
    }
  }

  static Future<T> restore<T>(
    Future<T> Function() action, {
    Future<void> Function()? drain,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_restoreOwner != null && Zone.current[_restoreKey] == _restoreOwner) {
      return action();
    }
    if (_restoring) {
      throw const StorageException(StorageFailure.operationInProgress);
    }
    _restoring = true;
    generation++;
    _restoreOwner = Object();
    try {
      for (final activity in _active.toList()) {
        activity.cancel?.call();
      }
      await (() async {
        await drain?.call();
        while (_active.isNotEmpty) {
          _changed ??= Completer<void>();
          await _changed!.future;
        }
      })().timeout(
        timeout,
        onTimeout: () {
          throw const StorageException(StorageFailure.activeTasks);
        },
      );
      return await runZoned(action, zoneValues: {_restoreKey: _restoreOwner});
    } finally {
      _restoring = false;
      _restoreOwner = null;
    }
  }
}

class _Activity {
  _Activity(this.cancel);
  final void Function()? cancel;
}
