import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newui_ai_demo/paper_surfaces.dart';
import 'package:newui_ai_demo/paper_theme.dart';

void main() {
  testWidgets('分段等宽通栏，切换保留文字位置，当前项不可取消', (tester) async {
    var selected = 'S3';
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => SizedBox(
              width: 600,
              child: PaperOptions(
                label: 'Backup',
                value: selected,
                options: const {'S3': 'S3', 'WebDAV': 'WebDAV'},
                onChanged: (v) => update(() => selected = v),
              ),
            ),
          ),
        ),
      ),
    );
    final s3 = find.widgetWithText(TextButton, 'S3');
    final dav = find.widgetWithText(TextButton, 'WebDAV');
    expect(tester.getSize(s3).width, 300);
    expect(tester.getSize(dav).width, 300);
    expect(tester.getSize(s3).height, greaterThanOrEqualTo(40));
    expect(
      tester.getCenter(find.text('WebDAV')).dx,
      closeTo(tester.getCenter(dav).dx, .5),
    );
    expect(
      tester.getCenter(find.text('S3')).dx,
      closeTo(tester.getCenter(s3).dx, .5),
    );
    final before = tester.getTopLeft(find.text('WebDAV'));
    await tester.tap(dav);
    await tester.pumpAndSettle();
    expect(selected, 'WebDAV');
    expect(tester.getTopLeft(find.text('WebDAV')), before);
    await tester.tap(dav);
    await tester.pumpAndSettle();
    expect(selected, 'WebDAV');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'S3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字纵向连体，禁用项不可操作', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: paperTheme(Brightness.dark),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const SizedBox(
              width: 300,
              child: PaperOptions(
                label: 'Minimum log level',
                value: 'error',
                options: {
                  'info': 'Info',
                  'warning': 'Warning',
                  'error': 'Error',
                },
                onChanged: null,
              ),
            ),
          ),
        ),
      ),
    );
    final segments = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(segments.direction, Axis.vertical);
    expect(segments.onSelectionChanged, isNull);
    final buttons = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(buttons.every((button) => button.onPressed == null), isTrue);
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Warning')).width,
      300,
    );
    expect(tester.takeException(), isNull);
  });
}
