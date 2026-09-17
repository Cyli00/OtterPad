import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/pages/reader/coordinators/reader_dock_window.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Rect bounds;
  late List<Display> displays;
  late bool maximized;
  late bool fullScreen;
  late List<Rect> writes;
  Completer<void>? displayQuery;

  setUp(() {
    bounds = const Rect.fromLTWH(100, 80, 1000, 800);
    displays = [
      const Display(
        id: 'main',
        size: Size(1920, 1080),
        visiblePosition: Offset.zero,
        visibleSize: Size(1920, 1040),
      ),
    ];
    maximized = false;
    fullScreen = false;
    writes = [];
    displayQuery = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        switch (call.method) {
          case 'isMaximized':
            return maximized;
          case 'isFullScreen':
            return fullScreen;
          case 'getBounds':
            return {
              'x': bounds.left,
              'y': bounds.top,
              'width': bounds.width,
              'height': bounds.height,
            };
          case 'setBounds':
            final args = call.arguments as Map;
            bounds = Rect.fromLTWH(
              args['x'],
              args['y'],
              args['width'],
              args['height'],
            );
            writes.add(bounds);
            return null;
        }
        throw MissingPluginException();
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
      (_) async {
        await displayQuery?.future;
        return {'displays': displays.map((d) => d.toJson()).toList()};
      },
    );
  });

  tearDown(() {
    for (final name in [
      'window_manager',
      'dev.leanflutter.plugins/screen_retriever',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        null,
      );
    }
  });

  test('向右展开保留左边缘，收起恢复原宽度', () async {
    final dock = ReaderDockWindow();
    expect(await dock.expand(360), isTrue);
    expect(bounds, const Rect.fromLTWH(100, 80, 1360, 800));
    await dock.restore();
    expect(bounds, const Rect.fromLTWH(100, 80, 1000, 800));
  });

  test('右侧放不下时不移动窗口，恰好放下时可展开', () async {
    bounds = const Rect.fromLTWH(561, 80, 1000, 800);
    expect(await ReaderDockWindow().expand(360), isFalse);
    expect(writes, isEmpty);
    bounds = const Rect.fromLTWH(560, 80, 1000, 800);
    expect(await ReaderDockWindow().expand(360), isTrue);
    expect(bounds.right, 1920);
  });

  test('副屏使用自身工作区，支持负坐标', () async {
    displays.add(
      const Display(
        id: 'left',
        size: Size(1600, 1000),
        visiblePosition: Offset(-1600, 0),
        visibleSize: Size(1600, 960),
      ),
    );
    bounds = const Rect.fromLTWH(-1550, 50, 900, 800);
    expect(await ReaderDockWindow().expand(360), isTrue);
    expect(bounds.right, -290);
  });

  test('跨屏窗口按主要所在屏幕判断右侧空间', () async {
    displays.add(
      const Display(
        id: 'right',
        size: Size(1920, 1080),
        visiblePosition: Offset(1920, 0),
        visibleSize: Size(1920, 1040),
      ),
    );
    bounds = const Rect.fromLTWH(1500, 80, 1000, 800);
    expect(await ReaderDockWindow().expand(360), isTrue);
    expect(bounds, const Rect.fromLTWH(1500, 80, 1360, 800));
  });

  test('左边缘略超出工作区不妨碍向右展开', () async {
    bounds = const Rect.fromLTWH(-8, 80, 1000, 800);
    expect(await ReaderDockWindow().expand(360), isTrue);
    expect(bounds.left, -8);
  });

  test('最大化和全屏时在窗口内展开', () async {
    maximized = true;
    expect(await ReaderDockWindow().expand(360), isFalse);
    maximized = false;
    fullScreen = true;
    expect(await ReaderDockWindow().expand(360), isFalse);
    expect(writes, isEmpty);
  });

  test('缺少屏幕工作区时保守回退', () async {
    displays = const [Display(id: 'unknown', size: Size(1920, 1080))];
    expect(await ReaderDockWindow().expand(360), isFalse);
    expect(writes, isEmpty);
  });

  test('用户移动窗口后收起只改宽度', () async {
    final dock = ReaderDockWindow();
    await dock.expand(360);
    bounds = bounds.shift(const Offset(120, 40));
    await dock.restore();
    expect(bounds, const Rect.fromLTWH(220, 120, 1000, 800));
  });

  test('用户手动调宽后收起保留窗口尺寸', () async {
    final dock = ReaderDockWindow();
    await dock.expand(360);
    bounds = const Rect.fromLTWH(100, 80, 1500, 800);
    await dock.restore();
    expect(bounds.width, 1500);
    expect(writes, hasLength(1));
  });

  test('展开后最大化，收起不解除最大化', () async {
    final dock = ReaderDockWindow();
    await dock.expand(360);
    maximized = true;
    await dock.restore();
    expect(writes, hasLength(1));
  });

  test('查询过程中退出，等待展开完成后撤回，重复恢复无副作用', () async {
    final dock = ReaderDockWindow();
    displayQuery = Completer<void>();
    final expanding = dock.expand(360);
    final restoring = dock.restore();
    displayQuery!.complete();
    expect(await expanding, isTrue);
    await restoring;
    await dock.restore();
    expect(bounds.width, 1000);
    expect(writes, hasLength(2));
  });
}
