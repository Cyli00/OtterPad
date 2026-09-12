import 'dart:io';

import 'package:dio/dio.dart';
import 'proxy_adapter.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

/// 下载 APK 并触发系统安装界面。
///
/// 存放路径 `<tempDir>/OtterPad/updates/` 落在 `StorageUsageService`
/// 现有"临时文件"缓存条目（`<tempDir>/OtterPad`）下，随现有清理逻辑一并回收，
/// 不需要新增追踪项。
class UpdateDownloadService {
  UpdateDownloadService._();
  static final UpdateDownloadService instance = UpdateDownloadService._();

  // 下载大文件，只设 connectTimeout；不设 receiveTimeout，否则大 APK 会超时。
  late final Dio _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 15)),
  );

  /// 更新代理配置，与其它联网服务共用 `ProxyProvider` 总线。
  /// [mode] 收 `Enum` 便于跨包传 `ProxyMode`（按 name 匹配）。
  void applyProxy(Enum mode, String host, int port) {
    _dio.httpClientAdapter = buildProxyAdapter(
      mode.name,
      host,
      port,
    );
  }

  Future<String> downloadApk({
    required ApkAsset asset,
    required String version,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, 'OtterPad', 'updates'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final savePath = p.join(dir.path, 'OtterPad-$version-arm64-v8a.apk');

    await _dio.download(
      asset.downloadUrl,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );

    return savePath;
  }

  /// 通过 `open_filex` 内置的 FileProvider 生成 content:// URI 并发起安装 Intent。
  Future<void> installApk(String filePath) async {
    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }
}
