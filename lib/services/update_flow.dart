import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_logger.dart';
import '../core/l10n.dart';
import '../providers/task_activity_provider.dart';
import '../router/app_router.dart';
import '../widgets/app_dialog.dart';
import '../widgets/update_dialog.dart';
import 'snackbar_service.dart';
import 'update_download_service.dart';
import 'update_service.dart';

/// 展示更新弹窗并串联"立即更新/忽略此版本/稍后/查看发布页"四个动作。
/// About 页手动检查与 [UpdateCheckScheduler] 自动检查共用这一条编排逻辑。
///
/// 只收 [BuildContext]：`Ref`（Provider）与 `WidgetRef`（Widget）在 Riverpod
/// 里是两个无公共父类型的类，无法用一个参数同时接收；改从 context 拿
/// [ProviderContainer] 读 provider，两个调用方都持有 context。
Future<void> presentUpdateDialog({
  required BuildContext context,
  required UpdateInfo info,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showAppDialog(
    context: context,
    builder: (ctx) => UpdateDialog(
      info: info,
      onUpdateNow: () => _handleUpdateNow(ctx, container, info),
      onIgnore: () => _handleIgnore(ctx, info),
      onLater: () => Navigator.of(ctx).pop(),
      onOpenReleasePage: () => _openReleasePage(info),
    ),
  );
}

Future<void> _handleUpdateNow(
  BuildContext ctx,
  ProviderContainer container,
  UpdateInfo info,
) async {
  Navigator.of(ctx).pop();
  final asset = info.arm64Asset;
  // 非 Android 或无匹配 APK：回退到浏览器打开发布页
  if (!Platform.isAndroid || asset == null) {
    await _openReleasePage(info);
    return;
  }
  await _downloadAndInstall(container, info, asset);
}

void _handleIgnore(BuildContext ctx, UpdateInfo info) {
  // 忽略标记的持久化无需阻塞 UI：Hive 内存写立即生效，下次启动可读到
  unawaited(UpdateService.setIgnoredVersion(info.remoteVersion));
  Navigator.of(ctx).pop();
}

Future<void> _openReleasePage(UpdateInfo info) async {
  final uri = Uri.parse(info.releaseUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> _downloadAndInstall(
  ProviderContainer container,
  UpdateInfo info,
  ApkAsset asset,
) async {
  // 文案在任何 await 之前一次性解析好，避免异步后再碰 BuildContext
  final startCtx = rootNavigatorKey.currentContext;
  final l10n = startCtx != null ? AppLocalizations.of(startCtx) : null;
  final title = l10n?.updateDownloading ?? '下载更新中';
  final failMessage = l10n?.updateDownloadFailed ?? '下载更新失败';

  final activity = container.read(taskActivityProvider.notifier);
  final progress = ValueNotifier(
    ListenableProgress(current: 0, total: 0, status: title),
  );
  final cancelToken = CancelToken();
  final taskId = activity.report(
    progress: progress,
    title: title,
    onCancel: () => cancelToken.cancel(),
  );

  final downloader = UpdateDownloadService.instance;
  try {
    final path = await downloader.downloadApk(
      asset: asset,
      version: info.remoteVersion,
      cancelToken: cancelToken,
      onProgress: (received, total) {
        // 进度条按百分比呈现（字节数直接显示不可读）；total 未知时退化为纯 spinner
        final percent = total > 0 ? (received * 100 ~/ total) : 0;
        progress.value = ListenableProgress(
          current: percent,
          total: total > 0 ? 100 : 0,
          status: title,
        );
      },
    );
    await downloader.installApk(path);
  } catch (e) {
    // 用户主动取消不算失败，不提示
    if (!cancelToken.isCancelled) {
      log.w('[UpdateFlow] 下载/安装失败：$e');
      container.read(snackBarServiceProvider).showResult(message: failMessage);
    }
  } finally {
    activity.finish(taskId);
    progress.dispose();
  }
}
