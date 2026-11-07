import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_logger.dart';
import '../core/rust_backend.dart';
import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';
import '../src/rust/api/update.dart';
import '../src/rust/error.dart';
import '../src/rust/update.dart';

export '../src/rust/update.dart' show ApkAsset, UpdateInfo;

/// 检查与下载更新由 Rust 完成；这里提供宿主平台信息与安装 Intent。
abstract final class UpdateService {
  /// 当前版本与按优先级排列的设备 ABI（只有 Android 有）。
  static Future<(String, List<String>)> _platform() async {
    final version = (await PackageInfo.fromPlatform()).version;
    var abis = const <String>[];
    if (Platform.isAndroid) {
      try {
        abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      } catch (e) {
        log.w('[UpdateService] 无法读取设备 ABI，使用发布页更新：$e');
      }
    }
    return (version, abis);
  }

  static Future<UpdateInfo> checkForUpdate() async {
    final (version, abis) = await _platform();
    return RustBackend.instance.checkForUpdate(
      currentVersion: version,
      supportedAbis: abis,
      taskId: rustTaskId('update'),
    );
  }

  /// 启动后自动检查：受设置开关控制，忽略的版本不提示；无需提示时为 null。
  static Future<UpdateInfo?> checkAfterStartup() async {
    final (version, abis) = await _platform();
    return RustBackend.instance.checkUpdateAfterStartup(
      currentVersion: version,
      supportedAbis: abis,
      taskId: rustTaskId('update-startup'),
    );
  }

  static Future<void> setIgnoredVersion(String version) =>
      GStorage.setting.put(SettingsKeys.ignoredUpdateVersion, version);

  /// 下载 APK 到临时目录，返回路径。
  static Future<String> downloadApk({
    required ApkAsset asset,
    required String version,
    required String taskId,
    required void Function(int received, int total) onProgress,
  }) async {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'OtterPad', 'updates'),
    );
    await dir.create(recursive: true);
    final path = p.join(dir.path, 'OtterPad-$version-${asset.abi}.apk');
    await for (final event in RustBackend.instance.downloadUpdate(
      asset: asset,
      path: path,
      taskId: taskId,
    )) {
      switch (event) {
        case UpdateDownloadEvent_Progress(:final progress):
          onProgress(
            progress.transferred.toInt(),
            progress.total?.toInt() ?? 0,
          );
        case UpdateDownloadEvent_Completed(:final path):
          return path;
        case UpdateDownloadEvent_Failed(:final error):
          throw error;
      }
    }
    throw const OtterError(code: ErrorCode.cancelled, detail: 'update stream');
  }

  /// 通过 `open_filex` 的 FileProvider 生成 content:// URI 并发起安装 Intent。
  static Future<void> installApk(String filePath) async {
    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }
}
