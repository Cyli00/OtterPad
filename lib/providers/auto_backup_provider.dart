import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/app_logger.dart';
import '../core/l10n.dart';
import '../core/storage/storage.dart';
import '../router/app_router.dart';
import '../services/backup_fingerprint.dart';
import '../services/backup_restore_service.dart';
import 'backup_orchestrator.dart';
import 'documents_provider.dart';
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
  static const _intervalKey = 'auto_backup_interval';
  static const _scopeKey = 'auto_backup_scope';

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

/// 自动备份调度器。[start] 由 main 初始化链路调用：启动 2 分钟后首查，
/// 之后每小时 tick 一次（覆盖应用长驻不重启的场景）。
///
/// 每次 tick 的闸门：开启了自动备份 → 远端已配置 → 距上次备份超过周期
/// → 文献指纹相对快照有变化。零变化不上传（不浪费流量也不刷新快照，
/// 比对本身是毫秒级纯本地计算）。失败只记日志，下一个 tick 自然重试。
class AutoBackupScheduler {
  AutoBackupScheduler(this._ref);

  final Ref _ref;
  Timer? _initial;
  Timer? _periodic;
  bool _running = false;

  void start() {
    _initial ??= Timer(const Duration(minutes: 2), _tick);
    _periodic ??= Timer.periodic(const Duration(hours: 1), (_) => _tick());
  }

  void dispose() {
    _initial?.cancel();
    _periodic?.cancel();
  }

  Future<void> _tick() async {
    if (_running) return;
    final config = _ref.read(autoBackupProvider);
    final period = config.interval.period;
    if (period == null) return;

    final orchestrator = _ref.read(backupOrchestratorProvider);
    if (orchestrator.remote == null) return;

    final snapshot = BackupFingerprintService.loadSnapshot();
    if (snapshot != null && DateTime.now().difference(snapshot.at) < period) {
      return;
    }
    if (snapshot != null && !await _hasChanges(snapshot)) return;

    _running = true;
    final activity = _ref.read(taskActivityProvider.notifier);
    final progress = ValueNotifier(
      const ListenableProgress(current: 0, total: 0, status: ''),
    );
    final ctx = rootNavigatorKey.currentContext;
    final title = ctx != null
        ? (AppLocalizations.of(ctx)?.autoBackup ?? '自动备份')
        : '自动备份';
    final taskId = activity.report(progress: progress, title: title);
    try {
      await orchestrator.backupToRemote(scope: config.scope);
      log.d('[AutoBackup] 完成（${config.scope.name}）');
    } catch (e) {
      log.w('[AutoBackup] 失败：$e');
    } finally {
      activity.finish(taskId);
      progress.dispose();
      _running = false;
    }
  }

  Future<bool> _hasChanges(BackupSnapshot snapshot) async {
    final docs = _ref.read(documentsProvider);
    if (docs.length != snapshot.docs.length) return true;
    final current = await BackupFingerprintService.compute(docs);
    for (final entry in current.entries) {
      final previous = snapshot.docs[entry.key];
      if (previous == null || !previous.sameAs(entry.value)) return true;
    }
    return false;
  }
}

final autoBackupSchedulerProvider = Provider<AutoBackupScheduler>((ref) {
  final scheduler = AutoBackupScheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
