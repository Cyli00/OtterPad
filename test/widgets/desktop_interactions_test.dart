import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:otter_pad/widgets/app_context_menu.dart';
import 'package:otter_pad/widgets/layout/adaptive_navigation.dart';

void main() {
  testWidgets('窄窗口右键菜单长标签仍可选择', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  selected = await showAppContextMenu<int>(
                    context: context,
                    globalPosition: const Offset(350, 300),
                    items: const [
                      AppContextMenuItem(
                        value: 1,
                        label: '这是一个用于验证桌面右键菜单在窄窗口中仍然完整可用的很长操作名称',
                        icon: Symbols.folder_rounded,
                      ),
                    ],
                  );
                },
                child: const Text('打开'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(PopupMenuItem<int>));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  for (final extended in [false, true]) {
    testWidgets('矮窗口侧栏可滚动到底部操作 extended=$extended', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 220);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var activated = false;
      const action = AdaptiveDestination(
        icon: Icon(Symbols.menu_rounded),
        selectedIcon: Icon(Symbols.menu_rounded),
        label: '切换标签',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                AdaptiveNavigationRail(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  extended: extended,
                  destinations: const [action, action, action],
                  bottomAction: const AdaptiveDestination(
                    icon: Icon(Symbols.settings_rounded),
                    selectedIcon: Icon(Symbols.settings_rounded),
                    label: '底部操作',
                  ),
                  onBottomAction: () => activated = true,
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final target = find.byIcon(Symbols.settings_rounded);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      expect(activated, isTrue);
    });
  }
}
