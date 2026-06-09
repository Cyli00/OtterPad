import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// 全局日志实例——release 模式下静默，debug 模式下输出纯文本（与 debugPrint 格式一致）。
final log = Logger(
  filter: _AppLogFilter(),
  printer: _PlainPrinter(),
  output: _DebugPrintOutput(),
);

class _AppLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => kDebugMode;
}

/// 纯文本输出，不加 emoji / 边框 / 时间戳——保持与原 debugPrint 一致的控制台体验。
class _PlainPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final msg = event.message?.toString() ?? '';
    final buf = StringBuffer(msg);
    if (event.error != null) buf.write('\n${event.error}');
    if (event.stackTrace != null) buf.write('\n${event.stackTrace}');
    return [buf.toString()];
  }
}

/// 走 debugPrint 通道输出——复用 Flutter 的节流机制，避免大量日志淹没平台 logger。
class _DebugPrintOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      debugPrint(line);
    }
  }
}
