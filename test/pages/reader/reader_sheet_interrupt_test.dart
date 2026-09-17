import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/pages/reader/widgets/reader_sheet_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await GStorage.initForTest(database);
  });
  tearDown(() => database.close());
  testWidgets('关闭途中再次打开时，上一轮 Future 和恢复回调仍应完成', (tester) async {
    final key = GlobalKey<ReaderSheetHostState>();
    var firstCompleted = false;
    var firstResumed = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ReaderSheetHost(key: key)),
        ),
      ),
    );
    key.currentState!
        .show<Object?>(
          builder: (_) => const Text('first'),
          onResume: () => firstResumed++,
        )
        .then((_) => firstCompleted = true);
    await tester.pumpAndSettle();
    key.currentState!.close();
    await tester.pump(const Duration(milliseconds: 60));
    key.currentState!.show<Object?>(builder: (_) => const Text('second'));
    await tester.pumpAndSettle();
    key.currentState!.close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      (firstCompleted, firstResumed),
      (true, 1),
      reason: '旧面板 Future 和暂停／恢复必须配对完成',
    );
  });
  for (final mode in ['立即关闭', '卸载', '减少动态效果']) {
    testWidgets('$mode 仍恰好完成结果与恢复回调一次', (tester) async {
      final key = GlobalKey<ReaderSheetHostState>();
      var resumed = 0;
      Widget host(bool reduce) => ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(body: ReaderSheetHost(key: key)),
          ),
        ),
      );
      await tester.pumpWidget(host(false));
      final result = key.currentState!.show<int>(
        builder: (_) => const SizedBox(height: 200, child: Text('内容')),
        onResume: () => resumed++,
      );
      if (mode == '立即关闭') {
        key.currentState!.close(7);
      } else {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        if (mode == '卸载') {
          await tester.pumpWidget(const SizedBox());
        } else {
          key.currentState!.close(7);
          await tester.pumpWidget(host(true));
        }
      }
      await tester.pumpAndSettle();
      expect(await result, mode == '卸载' ? null : 7);
      expect(resumed, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
