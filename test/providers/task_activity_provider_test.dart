import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/task_activity_provider.dart';

ValueNotifier<ListenableProgress> _progress() =>
    ValueNotifier(const ListenableProgress(current: 0, total: 0, status: ''));

void main() {
  group('TaskActivityNotifier', () {
    test('report 追加任务并分配自增 id', () {
      final notifier = TaskActivityNotifier();
      final a = notifier.report(progress: _progress(), title: 'A');
      final b = notifier.report(progress: _progress(), title: 'B');

      expect(a, isNot(b));
      expect(notifier.state.map((t) => t.id), [a, b]);
      expect(notifier.state.map((t) => t.title), ['A', 'B']);
    });

    test('finish 按 id 移除，且对不存在的 id 幂等', () {
      final notifier = TaskActivityNotifier();
      final a = notifier.report(progress: _progress());
      final b = notifier.report(progress: _progress());

      final before = notifier.state;
      notifier.finish(9999); // 不存在
      expect(identical(notifier.state, before), isTrue); // 未触发新状态

      notifier.finish(a);
      expect(notifier.state.map((t) => t.id), [b]);

      notifier.finish(b);
      expect(notifier.state, isEmpty);
    });

    test('cancelAll 触发每个任务的 onCancel', () {
      final notifier = TaskActivityNotifier();
      var cancelledA = false;
      var cancelledB = false;
      notifier.report(progress: _progress(), onCancel: () => cancelledA = true);
      notifier.report(progress: _progress(), onCancel: () => cancelledB = true);

      notifier.cancelAll();

      expect(cancelledA, isTrue);
      expect(cancelledB, isTrue);
    });

    test('id 不复用：finish 后再 report 仍是新 id', () {
      final notifier = TaskActivityNotifier();
      final a = notifier.report(progress: _progress());
      notifier.finish(a);
      final b = notifier.report(progress: _progress());

      expect(b, isNot(a));
      expect(notifier.state.single.id, b);
    });
  });
}
