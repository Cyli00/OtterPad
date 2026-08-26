import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/utils/responsive.dart';

void main() {
  group('readerSidebarWidth', () {
    test('门槛为 bodyMin + sidebarMin', () {
      expect(Responsive.kReaderDockMinWidth, 640);
    });

    test('低于门槛时调用方不应计算 dock 宽', () {
      expect(600 < Responsive.kReaderDockMinWidth, isTrue);
    });

    test('640 → sidebar 280', () {
      expect(Responsive.readerSidebarWidth(640), 280);
    });

    test('720 → sidebar 360', () {
      expect(Responsive.readerSidebarWidth(720), 360);
    });

    test('1280 → sidebar 360', () {
      expect(Responsive.readerSidebarWidth(1280), 360);
    });
  });
}
