/// 将 Dart 字符串转义为 JS 单引号字符串字面量的内容（不含外层引号）。
String escapeJsLiteral(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll("'", "\\'")
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '');
