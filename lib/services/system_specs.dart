import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_logger.dart';
import 'haptics.dart';
import 'snackbar_service.dart';

/// OtterPad GitHub 仓库与 issue 模板标识。
const kGitHubRepo = 'Cyli00/OtterPad';
const kGitHubUrl = 'https://github.com/$kGitHubRepo';
const kBugReportTemplate = 'bug_report.yml';

/// 精简 system specs，供 issue 粘贴与剪贴板复制。
Future<String> buildSystemSpecs() async {
  final info = await PackageInfo.fromPlatform();
  final os = await resolveOsLabel();
  final arch = Abi.current().toString().replaceFirst('Abi.', '');
  final locale = Platform.localeName;
  return 'OtterPad ${info.version} (${info.buildNumber})\n'
      'OS: $os\n'
      'Arch: $arch\n'
      'Locale: $locale';
}

/// About 页短标签：Android 用真实 RELEASE（如 15），避免误读 Build.DISPLAY。
///
/// [Platform.operatingSystemVersion] 在 Android 上常是 `AP3A.240905.015`
/// 这类 build 串，取首个数字会得到错误的「Android 3」。
Future<String> resolveOsShortLabel() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      final release = info.version.release.trim();
      return release.isEmpty ? 'Android' : 'Android $release';
    }
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      final v = info.systemVersion.trim();
      return v.isEmpty ? 'iOS' : 'iOS $v';
    }
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
  } catch (_) {
    // 回退到平台名
  }
  return Platform.operatingSystem;
}

/// Issue / 剪贴板用的稍完整 OS 描述。
Future<String> resolveOsLabel() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      final release = info.version.release.trim();
      final sdk = info.version.sdkInt;
      if (release.isEmpty) return 'Android (SDK $sdk)';
      return 'Android $release (SDK $sdk)';
    }
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      final v = info.systemVersion.trim();
      return v.isEmpty ? 'iOS' : 'iOS $v';
    }
    if (Platform.isWindows) {
      final info = await plugin.windowsInfo;
      final build = info.buildNumber;
      return 'Windows ${info.majorVersion}.${info.minorVersion} (Build $build)';
    }
    if (Platform.isMacOS) {
      final info = await plugin.macOsInfo;
      return 'macOS ${info.majorVersion}.${info.minorVersion}.${info.patchVersion}';
    }
    if (Platform.isLinux) {
      final info = await plugin.linuxInfo;
      return info.prettyName.isNotEmpty ? info.prettyName : 'Linux';
    }
  } catch (_) {
    // 回退
  }
  return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
}

/// 复制 system specs 到剪贴板。
Future<void> copySystemSpecs({
  required SnackBarService snackBar,
  required String copiedMessage,
}) async {
  final specs = await buildSystemSpecs();
  await Clipboard.setData(ClipboardData(text: specs));
  Haptics.soft();
  snackBar.showResult(message: copiedMessage);
}

/// 复制 system specs 并打开 GitHub Bug Report 表单。
Future<void> openBugReportForm({
  required SnackBarService snackBar,
  required String copiedMessage,
  required String openFailedMessage,
}) async {
  await copySystemSpecs(snackBar: snackBar, copiedMessage: copiedMessage);
  final uri = Uri.parse(
    '$kGitHubUrl/issues/new?template=$kBugReportTemplate',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    snackBar.showResult(message: openFailedMessage);
  }
}

/// 导出今日日志文件路径（已 flush）；无文件返回 null。
Future<File?> prepareTodayLogForExport() async {
  await flushAppLogs();
  return todayAppLogFile();
}
