import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/app_logger.dart';
import '../core/l10n.dart';
import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';
import '../router/app_router.dart';
import '../core/otter_error_text.dart';
import '../core/rust_backend.dart';
import '../services/snackbar_service.dart';
import '../src/rust/api.dart' show cancelTask;
import '../src/rust/api/sync.dart';
import '../src/rust/sync/archive.dart';
import 'sync_status_provider.dart';
import 'task_activity_provider.dart';

enum AutoBackupInterval {
  off,
  daily(Duration(days: 1)),
  weekly(Duration(days: 7));

  const AutoBackupInterval([this.period]);

  final Duration? period;
}

class AutoBackupState {
  final AutoBackupInterval interval;
  final BackupScope scope;

  const AutoBackupState({
    this.interval = AutoBackupInterval.off,
    this.scope = BackupScope.dataOnly,
  });

  AutoBackupState copyWith({AutoBackupInterval? interval, BackupScope? scope}) {
    return AutoBackupState(
      interval: interval ?? this.interval,
      scope: scope ?? this.scope,
    );
  }
}

class AutoBackupNotifier extends StateNotifier<AutoBackupState> {
  static const _intervalKey = SettingsKeys.autoBackupInterval;
  static const _scopeKey = SettingsKeys.autoBackupScope;

  AutoBackupNotifier() : super(_load());

  static AutoBackupState _load() {
    final box = GStorage.setting;
    return AutoBackupState(
      interval:
          AutoBackupInterval.values.asNameMap()[box.get(
            _intervalKey,
            defaultValue: AutoBackupInterval.off.name,
          )] ??
          AutoBackupInterval.off,
      scope:
          BackupScope.values.asNameMap()[box.get(
            _scopeKey,
            defaultValue: BackupScope.dataOnly.name,
          )] ??
          BackupScope.dataOnly,
    );
  }

  Future<void> setInterval(AutoBackupInterval interval) async {
    state = state.copyWith(interval: interval);
    await GStorage.setting.put(_intervalKey, interval.name);
  }

  Future<void> setScope(BackupScope scope) async {
    state = state.copyWith(scope: scope);
    await GStorage.setting.put(_scopeKey, scope.name);
  }

  void reload() {
    state = _load();
  }
}

final autoBackupProvider =
    StateNotifierProvider<AutoBackupNotifier, AutoBackupState>(
      (ref) => AutoBackupNotifier(),
    );

/// 自动备份：Rust 按设置中的周期、远端与文献变更自行判断（启动 2 分钟后首查，
/// 之后每小时）。这里只订阅事件，展示进度与失败提示。
class AutoBackupScheduler {
  AutoBackupScheduler(this._ref);

  final Ref _ref;
  StreamSubscription<SyncEvent>? _subscription;
  String? _taskId;
  int? _activity;
  ValueNotifier<ListenableProgress>? _progress;

  void start() {
    if (_subscription != null) return;
    final task = _taskId = rustTaskId('auto-backup');
    _subscription = RustBackend.instance
        .watchAutoBackup(device: Platform.localHostname, taskId: task)
        .listen(_onEvent);
  }

  void _onEvent(SyncEvent event) {
    final context = rootNavigatorKey.currentContext;
    final l10n = context == null ? null : AppLocalizations.of(context);
    switch (event) {
      case SyncEvent_Packing() || SyncEvent_Uploading():
        if (_activity != null) return;
        final progress = _progress = ValueNotifier(
          ListenableProgress(
            current: 0,
            total: 0,
            status: l10n?.autoBackupRunning ?? '正在自动备份',
          ),
        );
        _activity = _ref
            .read(taskActivityProvider.notifier)
            .report(progress: progress, title: l10n?.autoBackup ?? '自动备份');
      case SyncEvent_Uploaded():
        _finish();
        _ref.invalidate(syncStatusProvider);
        log.d('[AutoBackup] 完成');
      case SyncEvent_Skipped():
        _finish();
      case SyncEvent_Failed(:final error):
        _finish();
        log.w('[AutoBackup] 失败，下次调度重试：${error.code.name} ${error.detail}');
        if (l10n != null && context != null && context.mounted) {
          _ref
              .read(snackBarServiceProvider)
              .showResult(
                tone: SnackTone.error,
                message: l10n.autoBackupFailed(
                  otterErrorText(l10n, error.code),
                ),
              );
        }
    }
  }

  void _finish() {
    final activity = _activity;
    if (activity != null) {
      _ref.read(taskActivityProvider.notifier).finish(activity);
    }
    _activity = null;
    _progress?.dispose();
    _progress = null;
  }

  /// 恢复备份时 Rust 会取消其余任务（含本订阅），恢复后重新订阅。
  void restart() {
    dispose();
    _subscription = null;
    _taskId = null;
    start();
  }

  void dispose() {
    final task = _taskId;
    if (task != null) cancelTask(taskId: task);
    _subscription?.cancel();
    _finish();
  }
}

final autoBackupSchedulerProvider = Provider<AutoBackupScheduler>((ref) {
  final scheduler = AutoBackupScheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
