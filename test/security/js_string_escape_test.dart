import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/utils/js_string_escape.dart';

void main() {
  group('escapeJsLiteral', () {
    test('反斜杠转义', () {
      expect(escapeJsLiteral(r'path\to\file'), equals(r'path\\to\\file'));
    });

    test('单引号转义', () {
      expect(escapeJsLiteral("it's"), equals(r"it\'s"));
    });

    test('换行符转义', () {
      expect(escapeJsLiteral('line1\nline2'), equals(r'line1\nline2'));
    });

    test('回车符移除', () {
      expect(escapeJsLiteral('line1\r\nline2'), equals(r'line1\nline2'));
    });

    test('空字符串保持不变', () {
      expect(escapeJsLiteral(''), equals(''));
    });

    test('复合边界：多种特殊字符组合', () {
      expect(
        escapeJsLiteral("it's a 'test'\nwith\\path\r"),
        equals(r"it\'s a \'test\'\nwith\\path"),
      );
    });

    test('Unicode 字符不受影响', () {
      expect(escapeJsLiteral('中文测试 🎉'), equals('中文测试 🎉'));
    });

    test('null byte 不影响其他字符', () {
      expect(escapeJsLiteral('a\x00b'), equals('a\x00b'));
    });
  });
}
