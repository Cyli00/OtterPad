import 'dart:io';

import 'package:path/path.dart' as p;

/// 本机 OtterPad library 根目录。
///
/// 优先 [OTTERPAD_TEST_LIBRARY]；否则用 `APPDATA` 拼默认安装路径。
/// 不硬编码用户名，避免本机路径进仓库。
String? localLibraryRoot() {
  final override = Platform.environment['OTTERPAD_TEST_LIBRARY'];
  if (override != null && override.isNotEmpty) return override;
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) return null;
  return p.join(appData, 'io.github.cyli00', 'OtterPad', 'OtterPad', 'library');
}

String? localLibraryDoc(String documentId) {
  final root = localLibraryRoot();
  if (root == null) return null;
  return p.join(root, documentId);
}
