import 'dart:async';

import 'package:flutter/foundation.dart';

/// 输入抖动器——[delay] 内连续 [run] 只执行最后一次。
///
/// 设置页的凭据 / 地址输入在停止输入后才落盘，避免每个字符都触发
/// `setApiKey` / `setBaseUrl` 等持久化。原先在多个设置页里以
/// `Timer? _xxTimer` + `cancel()` + `Timer(...)` 重复手写，收敛到此处。
///
/// 作为 State 字段持有；`State.dispose` 必须调用 [cancel] 释放挂起计时器。
class DebouncedAction {
  DebouncedAction({this.delay = const Duration(milliseconds: 600)});

  final Duration delay;
  Timer? _timer;

  /// 安排一次延迟执行；上一次未触发则取消重排。
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// 取消挂起的执行。
  void cancel() => _timer?.cancel();
}
