import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/selection_provider.dart';

void main() {
  late SelectionNotifier notifier;

  setUp(() {
    notifier = SelectionNotifier();
  });

  test('selectRange 含两端点', () {
    notifier.enter('b', 'library');
    notifier.selectRange(orderedIds: const ['a', 'b', 'c', 'd'], toId: 'd');
    expect(notifier.state.selectedIds, {'b', 'c', 'd'});
    expect(notifier.state.anchorId, 'b');
  });

  test('selectRange 反向同样含端点', () {
    notifier.enter('d', 'library');
    notifier.selectRange(orderedIds: const ['a', 'b', 'c', 'd'], toId: 'b');
    expect(notifier.state.selectedIds, {'b', 'c', 'd'});
  });

  test('selectRange 与已选集合求并', () {
    notifier.enter('a', 'library');
    notifier.toggle('d');
    notifier.selectRange(orderedIds: const ['a', 'b', 'c', 'd'], toId: 'c');
    expect(notifier.state.selectedIds, {'a', 'b', 'c', 'd'});
  });

  test('copyWith 省略 anchorId 时不丢锚点', () {
    const state = SelectionState(
      isActive: true,
      selectedIds: {'a'},
      sourceContext: 'library',
      anchorId: 'anchor',
    );
    final next = state.copyWith(selectedIds: {'a', 'b'});
    expect(next.anchorId, 'anchor');
    expect(next.selectedIds, {'a', 'b'});
  });

  test('copyWith 可用 sentinel 把 anchorId 置空', () {
    const state = SelectionState(anchorId: 'anchor');
    expect(state.copyWith(anchorId: null).anchorId, isNull);
  });

  test('toggle 不改锚点', () {
    notifier.enter('a', 'library');
    notifier.toggle('b');
    expect(notifier.state.anchorId, 'a');
    expect(notifier.state.selectedIds, {'a', 'b'});
  });

  test('toggleAll 不改锚点', () {
    notifier.enter('a', 'library');
    notifier.toggleAll({'a', 'b', 'c'});
    expect(notifier.state.anchorId, 'a');
    expect(notifier.state.selectedIds, {'a', 'b', 'c'});
  });

  test('exit 整份重置', () {
    notifier.enter('a', 'library');
    notifier.exit();
    expect(notifier.state.isActive, isFalse);
    expect(notifier.state.selectedIds, isEmpty);
    expect(notifier.state.sourceContext, isNull);
    expect(notifier.state.anchorId, isNull);
  });
}
