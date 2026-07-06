import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/update_service.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('远程版本更新返回正数', () {
      expect(UpdateService.compareVersions('0.2.0', '0.1.0'), greaterThan(0));
    });

    test('版本相同返回 0', () {
      expect(UpdateService.compareVersions('0.1.0', '0.1.0'), 0);
    });

    test('远程版本更旧返回负数', () {
      expect(UpdateService.compareVersions('0.1.0', '0.2.0'), lessThan(0));
    });

    test('主版本号优先比较', () {
      expect(UpdateService.compareVersions('1.0.0', '0.9.9'), greaterThan(0));
    });

    test('缺失的版本段按 0 处理', () {
      expect(UpdateService.compareVersions('0.1', '0.1.0'), 0);
    });
  });

  group('UpdateService.extractChangelogLines', () {
    test('提取所有以 "- " 开头的行并去掉前缀', () {
      const body =
          '<div>html noise</div>\n\n- feat: 加了个功能\n- fix: 修了个 bug\n';
      expect(
        UpdateService.extractChangelogLines(body),
        ['feat: 加了个功能', 'fix: 修了个 bug'],
      );
    });

    test('没有匹配行返回空列表', () {
      expect(UpdateService.extractChangelogLines('just some text'), isEmpty);
    });

    test('兼容 \\r\\n 换行', () {
      const body = 'header\r\n\r\n- one\r\n- two\r\n';
      expect(UpdateService.extractChangelogLines(body), ['one', 'two']);
    });
  });

  group('UpdateInfo.fromGithubRelease', () {
    Map<String, dynamic> releaseJson({
      required String tagName,
      List<Map<String, dynamic>> assets = const [],
      String body = '',
    }) {
      return {
        'tag_name': tagName,
        'html_url': 'https://github.com/Cyli00/OtterPad/releases/tag/$tagName',
        'body': body,
        'assets': assets,
      };
    }

    test('远程版本更新时 hasUpdate 为 true', () {
      final info = UpdateInfo.fromGithubRelease(
        releaseJson(tagName: 'v0.2.0'),
        currentVersion: '0.1.0',
      );
      expect(info.hasUpdate, isTrue);
      expect(info.remoteVersion, '0.2.0');
    });

    test('版本相同时 hasUpdate 为 false', () {
      final info = UpdateInfo.fromGithubRelease(
        releaseJson(tagName: 'v0.1.0'),
        currentVersion: '0.1.0',
      );
      expect(info.hasUpdate, isFalse);
    });

    test('从 assets 中挑出 arm64-v8a 的 apk', () {
      final info = UpdateInfo.fromGithubRelease(
        releaseJson(
          tagName: 'v0.2.0',
          assets: [
            {
              'name': 'OtterPad-0.2.0-android-armeabi-v7a.apk',
              'browser_download_url': 'https://example.com/v7a.apk',
              'size': 100,
            },
            {
              'name': 'OtterPad-0.2.0-android-arm64-v8a.apk',
              'browser_download_url': 'https://example.com/v8a.apk',
              'size': 200,
            },
          ],
        ),
        currentVersion: '0.1.0',
      );
      expect(info.arm64Asset, isNotNull);
      expect(info.arm64Asset!.downloadUrl, 'https://example.com/v8a.apk');
      expect(info.arm64Asset!.size, 200);
    });

    test('没有匹配的 apk 时 arm64Asset 为 null', () {
      final info = UpdateInfo.fromGithubRelease(
        releaseJson(tagName: 'v0.2.0'),
        currentVersion: '0.1.0',
      );
      expect(info.arm64Asset, isNull);
    });
  });
}
