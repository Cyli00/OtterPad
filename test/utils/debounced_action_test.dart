import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/utils/debounced_action.dart';

void main() {
  group('DebouncedAction', () {
    test('延迟内多次 run 只执行最后一次', () async {
      final d = DebouncedAction(delay: const Duration(milliseconds: 30));
      var value = '';
      d.run(() => value = 'a');
      d.run(() => value = 'b');
      d.run(() => value = 'c');
      expect(value, '', reason: '延迟未到不应执行');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(value, 'c');
    });

    test('cancel 阻止挂起的执行', () async {
      final d = DebouncedAction(delay: const Duration(milliseconds: 30));
      var ran = false;
      d.run(() => ran = true);
      d.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(ran, isFalse);
    });

    test('间隔超过延迟的两次 run 都会执行', () async {
      final d = DebouncedAction(delay: const Duration(milliseconds: 20));
      final fired = <int>[];
      d.run(() => fired.add(1));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      d.run(() => fired.add(2));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(fired, [1, 2]);
    });
  });
}
