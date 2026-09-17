import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otter_pad/pages/reader/widgets/reader_background.dart';
import 'package:otter_pad/pages/reader/widgets/webview_markdown_reader.dart';
import 'package:otter_pad/providers/reader_settings_provider.dart';

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'fixture'),
      );
  Future<Uint8List?> Function() screenshot = () async => null;
  final handlers = <String, JavaScriptHandlerCallback>{};
  int pauses = 0;
  int mounts = 0;
  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) => handlers[handlerName] = callback;
  @override
  Future<Uint8List?> takeScreenshot({
    ScreenshotConfiguration? screenshotConfiguration,
  }) => screenshot();
  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> resume() async {}
  @override
  Future<void> disposeKeepAlive(InAppWebViewKeepAlive keepAlive) async {}
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => null;
}

class _Platform extends InAppWebViewPlatform {
  final controller = _Controller();
  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      controller;
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _PlatformWidget(params, controller);
}

class _PlatformWidget extends PlatformInAppWebViewWidget {
  _PlatformWidget(super.params, this.controller) : super.implementation();
  final _Controller controller;
  @override
  Widget build(BuildContext context) =>
      _Surface(params: params, controller: controller);
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

class _Surface extends StatefulWidget {
  const _Surface({required this.params, required this.controller});
  final PlatformInAppWebViewWidgetCreationParams params;
  final _Controller controller;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  @override
  void initState() {
    super.initState();
    widget.controller.mounts++;
    widget.params.onWebViewCreated?.call(
      widget.params.controllerFromPlatform!(widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late Directory temp;
  late _Platform platform;
  late InAppWebViewPlatform? original;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otter-webview-life-');
    original = InAppWebViewPlatform.instance;
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() async {
    if (original != null) InAppWebViewPlatform.instance = original!;
    await temp.delete(recursive: true);
  });

  for (final mode in ['超时', '失败', '空结果', '正常', '卸载']) {
    testWidgets('截图$mode时正确结束冻结等待', (tester) async {
      final key = GlobalKey<WebViewMarkdownReaderState>();
      await tester.pumpWidget(
        MaterialApp(
          home: WebViewMarkdownReader(
            key: key,
            markdownData: '本地测试正文',
            documentDir: temp.path,
            settings: const ReaderSettingsState(),
            palette: const ReaderPalette(
              background: Colors.white,
              text: Colors.black,
              secondaryText: Colors.grey,
              link: Colors.blue,
              divider: Colors.grey,
              codeBlock: Colors.white,
            ),
          ),
        ),
      );
      // 等待真实 HTML 写入，平台视图以本地替身替代，不启动原生浏览器。
      for (var i = 0; i < 100 && platform.controller.mounts == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(platform.controller.mounts, 1);
      platform.controller.handlers['onContentReady']!([]);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(platform.controller.mounts, 1, reason: '揭幕后不重新挂载原生视图');
      final pending = Completer<Uint8List?>();
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aV1cAAAAASUVORK5CYII=',
      );
      platform.controller.screenshot = switch (mode) {
        '失败' => () => Future.error(StateError('fixture')),
        '空结果' => () async => null,
        '正常' => () async => png,
        _ => () => pending.future,
      };
      var completed = false;
      key.currentState!.freeze(capture: true).then((_) => completed = true);
      await tester.pump();
      if (mode == '卸载') {
        await tester.pumpWidget(const SizedBox());
        pending.complete(png);
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(completed, isTrue);
      expect(platform.controller.pauses, mode == '正常' ? 1 : 0);
      if (mode != '正常' && mode != '卸载') {
        expect(find.byType(InAppWebView), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
