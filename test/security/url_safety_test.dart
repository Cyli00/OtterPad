import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/utils/url_safety.dart';

void main() {
  group('isLaunchableUrl', () {
    test('允许 https scheme', () {
      expect(isLaunchableUrl('https://example.com'), isTrue);
      expect(isLaunchableUrl('https://platform.openai.com/api-keys'), isTrue);
    });

    test('允许 http scheme', () {
      expect(isLaunchableUrl('http://localhost:8080'), isTrue);
    });

    test('拒绝 javascript scheme', () {
      expect(isLaunchableUrl('javascript:alert(1)'), isFalse);
    });

    test('拒绝 file scheme', () {
      expect(isLaunchableUrl('file:///etc/passwd'), isFalse);
    });

    test('拒绝 data scheme', () {
      expect(
        isLaunchableUrl('data:text/html,<script>alert(1)</script>'),
        isFalse,
      );
    });

    test('拒绝空字符串', () {
      expect(isLaunchableUrl(''), isFalse);
    });

    test('拒绝无 scheme 的字符串', () {
      expect(isLaunchableUrl('example.com'), isFalse);
    });

    test('拒绝大小写变体绕过', () {
      expect(isLaunchableUrl('JAVASCRIPT:alert(1)'), isFalse);
      expect(isLaunchableUrl('JavaScript:void(0)'), isFalse);
    });
  });
}
