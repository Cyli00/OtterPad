import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/utils/desktop.dart';

void main() {
  test('desktopActivator 默认不允许连发', () {
    expect(desktopActivator(LogicalKeyboardKey.keyF).includeRepeats, isFalse);
  });

  test('desktopActivator 可关闭键盘连发', () {
    final activator = desktopActivator(
      LogicalKeyboardKey.digit1,
      includeRepeats: false,
    );
    expect(activator.includeRepeats, isFalse);
  });
}
