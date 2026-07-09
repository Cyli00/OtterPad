import 'dart:ffi';
import 'dart:io';

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
  final os = _osLabel();
  final arch = Abi.current().toString().replaceFirst('Abi.', '');
  final locale = Platform.localeName;
  return 'OtterPad ${info.version} (${info.buildNumber})\n'
      'OS: $os\n'
      'Arch: $arch\n'
      'Locale: $locale';
}

String _osLabel() {
  final v = Platform.operatingSystemVersion;
  if (Platform.isWindows) return 'Windows $v';
  if (Platform.isMacOS) return 'macOS $v';
  if (Platform.isLinux) return 'Linux $v';
  if (Platform.isAndroid) return 'Android $v';
  if (Platform.isIOS) return 'iOS $v';
  return '${Platform.operatingSystem} $v';
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
