import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/task_activity_provider.dart';
import 'package:otter_pad/services/snackbar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('任务条显示时滑动页面不会被 SnackBar 抢走，卸载也不抛错', (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    final container = ProviderContainer(
      overrides: [
        snackBarServiceProvider.overrideWith(
          (ref) => SnackBarService(messengerKey, ref),
        ),
      ],
    );
    addTearDown(container.dispose);
    final progress = ValueNotifier<ListenableProgress>(
      const ListenableProgress(current: 0, total: 4, status: '正在翻译'),
    );
    addTearDown(progress.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 48, child: Text('第 $i 页')),
              ],
            ),
          ),
        ),
      ),
    );
    final service = container.read(snackBarServiceProvider);

    service.showListenableProgress(
      listenable: progress,
      title: '翻译',
      onCancel: () {},
    );
    service.renderActiveTasks(container.read(taskActivityProvider));
    await tester.pump();
    await tester.pump();
    expect(find.text('正在翻译'), findsOneWidget);

    await tester.drag(find.text('第 0 页'), const Offset(-240, 0));
    await tester.pump();
    await tester.drag(find.text('第 0 页'), const Offset(0, -240));
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
    expect(find.text('正在翻译'), findsOneWidget);
    expect(tester.takeException(), isNull);

    container
        .read(taskActivityProvider.notifier)
        .finish(container.read(taskActivityProvider).single.id);
    service.renderActiveTasks(container.read(taskActivityProvider));
    service.showResult(message: '已完成翻译');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
