import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/animation_constants.dart';
import '../core/l10n.dart';
import '../providers/task_activity_provider.dart';
import '../router/app_router.dart';

export '../providers/task_activity_provider.dart' show ListenableProgress;

/// 全局 ScaffoldMessenger Key，挂载在 MaterialApp.router 上，
/// 使 SnackBar 跨页面导航持续显示。
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

final snackBarServiceProvider = Provider<SnackBarService>((ref) {
  return SnackBarService(scaffoldMessengerKey, ref);
});

/// 结果 SnackBar 的语义：只决定前导图标，不改变配色。
///
/// [info] 用于轻量确认（已复制、已保存）与中性提示，不带图标；
/// [success] 用于后台任务完成；[error] 用于失败。
enum SnackTone { info, success, error }

/// 统一 SnackBar 服务
///
/// 通过 [scaffoldMessengerKey] 访问根级 ScaffoldMessenger，
/// 不依赖页面级 BuildContext，确保 SnackBar 在任何导航状态下可用。
class SnackBarService {
  final GlobalKey<ScaffoldMessengerState> _key;
  final Ref _ref;

  SnackBarService(this._key, this._ref);

  /// snackbar surface 当前持有的活跃任务集合（由 [renderActiveTasks] 同步）。
  List<ActiveTask> _tasks = const [];

  /// 当前占槽的一次性结果（Transient Result）；非空时盖过进度，计时结束后回落。
  ({
    int id,
    String message,
    SnackTone tone,
    SnackBarAction? action,
    EdgeInsetsGeometry? margin,
  })?
  _result;
  int _resultSeq = 0;
  Timer? _resultTimer;

  /// 单槽 SnackBar 只在「空 ↔ 有内容」时进出场；进度推进、进度转结果、
  /// 任务数变化都只替换 [_content]，在条内淡入淡出，不再整条退场重进。
  final _content = ValueNotifier<Widget>(const SizedBox.shrink());
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _bar;
  EdgeInsetsGeometry? _barMargin;

  ScaffoldMessengerState? get _messenger => _key.currentState;

  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  bool get _isMobile {
    final ctx = _key.currentContext;
    if (ctx == null) return true;
    return MediaQuery.sizeOf(ctx).width < 600;
  }

  /// 结果/信息型 SnackBar（Transient Result）：文字消息 + 可选操作按钮。
  ///
  /// 占槽 [duration] 后自动让位（带按钮也一样），回落到仍在跑的 Active Task。
  void showResult({
    required String message,
    SnackTone tone = SnackTone.info,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
    EdgeInsetsGeometry? margin,
  }) {
    final id = ++_resultSeq;
    _resultTimer?.cancel();
    _resultTimer = Timer(duration, () => _dismissResult(id));
    _result = (
      id: id,
      message: message,
      tone: tone,
      action: action,
      margin: margin,
    );
    _render();
  }

  /// 隐藏当前 SnackBar
  void hide() {
    _messenger?.hideCurrentSnackBar();
  }

  /// 以 [ValueListenable] 驱动的进度任务：登记进 Task Activity，由
  /// [renderActiveTasks] 仲裁呈现（1 个显示完整进度，≥2 聚合）。
  ///
  /// 返回的 [SnackBarProgressHandle] 用于完成/失败时收尾——注销该任务，
  /// 完成消息以 Transient Result 形式短暂呈现。[duration] 仅为兼容旧签名保留。
  SnackBarProgressHandle showListenableProgress({
    required ValueListenable<ListenableProgress> listenable,
    VoidCallback? onCancel,
    Duration duration = const Duration(hours: 1),
    String title = '',
  }) {
    final activity = _ref.read(taskActivityProvider.notifier);
    final id = activity.report(
      progress: listenable,
      title: title,
      onCancel: onCancel,
    );
    return SnackBarProgressHandle._(() => activity.finish(id), (
      msg,
      tone,
      action,
      dur,
    ) {
      // 先占结果再注销任务：槽位直接从进度切到结果，中间不会先收起再弹出。
      if (msg != null) {
        showResult(
          message: msg,
          tone: tone,
          action: action,
          duration: dur ?? const Duration(seconds: 4),
        );
      }
      activity.finish(id);
    });
  }

  /// snackbar surface：观察 Task Activity，把单槽同步到当前活集合。
  /// 0 个 → 收起；1 个 → 完整进度；≥2 个 → 聚合"N 个任务进行中"。
  void renderActiveTasks(List<ActiveTask> tasks) {
    _tasks = tasks;
    _render();
  }

  void _dismissResult(int id) {
    if (_result?.id != id) return;
    _resultTimer?.cancel();
    _result = null;
    _render();
  }

  /// 依据结果与 [_tasks] 更新单槽：内容原地替换，必要时才让 SnackBar 进出场。
  void _render() {
    final messenger = _messenger;
    if (messenger == null) return;

    final content = _slotContent();
    if (content == null) {
      if (_bar != null) {
        _bar = null;
        messenger.clearSnackBars();
      }
      return;
    }
    _content.value = content;

    // margin 是 SnackBar 自身属性，结果要求不同的 margin 时只能换一条。
    final margin = _result?.margin;
    if (_bar != null && margin == _barMargin) return;
    _barMargin = margin;
    _showBar(messenger, margin);
  }

  Widget? _slotContent() {
    final result = _result;
    if (result != null) {
      final action = result.action;
      return _SlotRow(
        key: ValueKey(('result', result.id)),
        leading: switch (result.tone) {
          SnackTone.info => null,
          SnackTone.success => const _SlotIcon(Symbols.check_circle_rounded),
          SnackTone.error => const _SlotIcon(Symbols.error_rounded),
        },
        message: result.message,
        maxLines: 3,
        actionLabel: action?.label,
        onAction: action == null
            ? null
            : () {
                _dismissResult(result.id);
                action.onPressed();
              },
      );
    }

    final tasks = _tasks;
    if (tasks.isEmpty) return null;
    if (tasks.length == 1) {
      final task = tasks.single;
      return ValueListenableBuilder<ListenableProgress>(
        key: ValueKey(('task', task.id)),
        valueListenable: task.progress,
        builder: (context, info, _) => _SlotRow(
          // 有总数时画确定进度；完成态切成对勾，避免"完成但还在转圈"。
          leading: info.total > 0 && info.current >= info.total
              ? const _SlotIcon(Symbols.check_circle_rounded)
              : _SlotSpinner(
                  value: info.total > 0 ? info.current / info.total : null,
                ),
          // 生产者没给状态文字时退回任务名，避免只剩计数的空条。
          message: info.status.isNotEmpty ? info.status : task.title,
          count: info.total > 0 ? '${info.current} / ${info.total}' : null,
          actionLabel: task.onCancel == null ? null : _l10n?.cancel ?? '取消',
          onAction: task.onCancel,
        ),
      );
    }
    return _SlotRow(
      key: ValueKey(('aggregate', tasks.map((t) => t.id).join(','))),
      leading: const _SlotSpinner(),
      message: _l10n?.tasksInProgress(tasks.length) ?? '${tasks.length} 个任务进行中',
      actionLabel: _l10n?.cancelAll ?? '取消全部',
      onAction: () {
        for (final task in tasks) {
          task.onCancel?.call();
        }
      },
    );
  }

  void _showBar(ScaffoldMessengerState messenger, EdgeInsetsGeometry? margin) {
    final mobile = _isMobile;
    messenger.clearSnackBars();
    final bar = _bar = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: mobile ? null : 400,
        margin: mobile
            ? (margin ??
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0))
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        elevation: 6,
        // 收起时机由本服务决定：结果自带计时，进度随任务注销。
        persist: true,
        content: _SlotContent(_content),
      ),
    );
    bar.closed.then((reason) {
      if (!identical(_bar, bar)) return;
      // 被滑走或被 hide() 关掉：结果作废；滑走的是结果时回落到仍在跑的进度。
      _bar = null;
      final hadResult = _result != null;
      _resultTimer?.cancel();
      _result = null;
      if (hadResult && reason == SnackBarClosedReason.swipe) _render();
    });
  }
}

/// 单槽内容：换内容时交叉淡化，高度随内容平滑伸缩。
class _SlotContent extends StatelessWidget {
  const _SlotContent(this.content);

  final ValueListenable<Widget> content;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kAnim;
    return AnimatedSize(
      duration: duration,
      curve: kAnimCurve,
      child: ValueListenableBuilder<Widget>(
        valueListenable: content,
        builder: (context, child, _) => AnimatedSwitcher(
          duration: duration,
          switchInCurve: kAnimCurve,
          switchOutCurve: kAnimCurveReverse,
          child: child,
        ),
      ),
    );
  }
}

/// 槽内一行：20px 前导位（进度 / 状态图标）、文字、计数与操作按钮。
///
/// 底色是 SnackBar 默认的 inverseSurface；文字与图标一律 onInverseSurface，
/// 唯一的强调色 inversePrimary 只给进度指示和操作按钮。
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    super.key,
    this.leading,
    required this.message,
    this.maxLines = 1,
    this.count,
    this.actionLabel,
    this.onAction,
  });

  final Widget? leading;
  final String message;

  /// 进度文字单行省略，避免状态推进时条高跳动；结果最多 3 行。
  final int maxLines;
  final String? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = actionLabel;
    final action = onAction;
    return ConstrainedBox(
      // 与按钮同高，有无按钮的内容互切时条高不跳。
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox.square(dimension: 20, child: Center(child: leading)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onInverseSurface,
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Text(
                count!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onInverseSurface.withValues(alpha: 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (label != null && action != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: _SlotAction(label: label, onPressed: action),
            ),
        ],
      ),
    );
  }
}

/// 进度指示：有 [value] 时为确定进度并带轨道，否则为不确定 spinner。
class _SlotSpinner extends StatelessWidget {
  const _SlotSpinner({this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: 2.5,
        color: cs.inversePrimary,
        backgroundColor: value == null
            ? null
            : cs.onInverseSurface.withValues(alpha: 0.2),
      ),
    );
  }
}

/// 状态图标：与文字同色，只用形状区分成功 / 失败。
class _SlotIcon extends StatelessWidget {
  const _SlotIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(
    icon,
    size: 20,
    fill: 1,
    color: Theme.of(context).colorScheme.onInverseSurface,
  );
}

/// 与 [SnackBarAction] 同色的按钮；按下后即禁用，防止重复触发，
/// 但不像它那样顺手收起整条——收起与否由槽位内容决定。
class _SlotAction extends StatefulWidget {
  const _SlotAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_SlotAction> createState() => _SlotActionState();
}

class _SlotActionState extends State<_SlotAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: cs.inversePrimary,
        disabledForegroundColor: cs.onInverseSurface.withValues(alpha: 0.38),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: _pressed
          ? null
          : () {
              setState(() => _pressed = true);
              widget.onPressed();
            },
      child: Text(widget.label),
    );
  }
}

/// 进度 SnackBar 的生命周期句柄。
class SnackBarProgressHandle {
  final VoidCallback _dismiss;
  final void Function(
    String? finishMessage,
    SnackTone finishTone,
    SnackBarAction? finishAction,
    Duration? finishDuration,
  )
  _finish;

  SnackBarProgressHandle._(this._dismiss, this._finish);

  /// 关闭 SnackBar 但不展示结果（例如中途取消）。
  void dismiss() => _dismiss();

  /// 结束进度态。若 [message] 非空，关闭后以结果态展示一条短消息；
  /// [action] 用于给结果 SnackBar 附加按钮（如"前往设置"/"去添加"）。
  void finish({
    String? message,
    SnackTone tone = SnackTone.info,
    SnackBarAction? action,
    Duration? duration,
  }) => _finish(message, tone, action, duration);
}
