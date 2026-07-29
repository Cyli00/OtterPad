import 'dart:math';

/// 生成密码学随机的 UUID v4 风格字符串（16 字节，分 4-2-2-2-6 组）。
///
/// 用 `Random.secure()`（CSPRNG）避免可预测；分组沿用项目既有格式
/// （见原 `DocumentsNotifier._newDocumentId`）。文档/标注等实体的唯一 id
/// 统一走本函数，避免不同模块各写一套 id 生成策略导致风格不一致或撞 id。
String generateUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}