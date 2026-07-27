import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';

/// GitHub release 里匹配到的 arm64-v8a APK 资源。
class ApkAsset {
  final String downloadUrl;
  final int size;

  const ApkAsset({required this.downloadUrl, required this.size});
}

/// 一次版本检查的结果。
class UpdateInfo {
  final String currentVersion;
  final String remoteVersion;
  final bool hasUpdate;
  final String releaseUrl;
  final List<String> changelogLines;
  final ApkAsset? arm64Asset;

  const UpdateInfo({
    required this.currentVersion,
    required this.remoteVersion,
    required this.hasUpdate,
    required this.releaseUrl,
    required this.changelogLines,
    this.arm64Asset,
  });

  /// 从 GitHub `GET /repos/{owner}/{repo}/releases/latest` 的响应体解析。
  factory UpdateInfo.fromGithubRelease(
    Map<String, dynamic> json, {
    required String currentVersion,
  }) {
    final tagName = json['tag_name'] as String;
    final remoteVersion = tagName.startsWith('v')
        ? tagName.substring(1)
        : tagName;
    final releaseUrl = json['html_url'] as String;
    final body = json['body'] as String? ?? '';
    final assets = json['assets'] as List<dynamic>? ?? [];

    ApkAsset? arm64Asset;
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith('.apk') && name.contains('arm64-v8a')) {
        arm64Asset = ApkAsset(
          downloadUrl: asset['browser_download_url'] as String,
          size: asset['size'] as int? ?? 0,
        );
        break;
      }
    }

    return UpdateInfo(
      currentVersion: currentVersion,
      remoteVersion: remoteVersion,
      hasUpdate: UpdateService.compareVersions(remoteVersion, currentVersion) > 0,
      releaseUrl: releaseUrl,
      changelogLines: UpdateService.extractChangelogLines(body),
      arm64Asset: arm64Asset,
    );
  }
}

/// 检查 GitHub 最新 release，并持久化"已忽略的版本号"。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _repoOwner = 'Cyli00';
  static const _repoName = 'OtterPad';
  static const _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const _kIgnoredVersionKey = SettingsKeys.ignoredUpdateVersion;

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'OtterPad/0.1 (Flutter; mailto:dev@otterpad.app)',
      },
    ),
  );

  /// 更新代理配置，与其它联网服务共用 `ProxyProvider` 总线。
  /// [mode] 收 `Enum` 便于跨包传 `ProxyMode`（按 name 匹配）。
  void applyProxy(Enum mode, String host, int port) {
    final adapter = IOHttpClientAdapter();
    switch (mode.name) {
      case 'custom':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY $host:$port';
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        };
      case 'system':
        adapter.createHttpClient = () => HttpClient();
      case 'none':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'DIRECT';
          return client;
        };
    }
    _dio.httpClientAdapter = adapter;
  }

  Future<UpdateInfo> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final response = await _dio.get<Map<String, dynamic>>(_apiUrl);
    return UpdateInfo.fromGithubRelease(
      response.data!,
      currentVersion: packageInfo.version,
    );
  }

  /// 逐段比较点分版本号；缺失的段按 0 处理，非数字段按 0 处理。
  static int compareVersions(String a, String b) {
    final partsA = a.split('.');
    final partsB = b.split('.');
    final length = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < length; i++) {
      final numA = i < partsA.length ? int.tryParse(partsA[i]) ?? 0 : 0;
      final numB = i < partsB.length ? int.tryParse(partsB[i]) ?? 0 : 0;
      if (numA != numB) return numA.compareTo(numB);
    }
    return 0;
  }

  /// 从 release body 里提取所有 `- ` 开头的行（本项目自己生成的 commit 列表），去掉前缀。
  static List<String> extractChangelogLines(String body) {
    return body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- '))
        .map((line) => line.substring(2).trim())
        .toList();
  }

  static String? getIgnoredVersion() =>
      GStorage.setting.get(_kIgnoredVersionKey) as String?;

  static Future<void> setIgnoredVersion(String version) =>
      GStorage.setting.put(_kIgnoredVersionKey, version);
}
