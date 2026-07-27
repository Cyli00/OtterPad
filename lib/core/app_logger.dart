import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

import 'storage/settings_keys.dart';
import 'storage/storage.dart';

final _fileLogOutput = _FileLogOutput();

/// 全局日志实例——debug 模式输出纯文本到控制台，
/// 用户开启日志记录时按级别持久化到磁盘（debug / release 均写文件）。
final log = Logger(
  filter: _AppLogFilter(),
  printer: _PlainPrinter(),
  output: MultiOutput([
    _DebugPrintOutput(),
    _fileLogOutput,
  ]),
);

const _kLogEnabled = SettingsKeys.logEnabled;
const _kLogLevel = SettingsKeys.logLevel;

Level _levelFromString(String s) => switch (s) {
      'info' => Level.info,
      'warning' => Level.warning,
      _ => Level.error,
    };

/// 读取用户配置的最低日志级别；GStorage 未初始化时回退 error。
Level _configuredMinLevel() {
  try {
    final enabled = GStorage.setting.get(_kLogEnabled) as bool? ?? true;
    if (!enabled) return Level.off;
    final str = GStorage.setting.get(_kLogLevel) as String? ?? 'error';
    return _levelFromString(str);
  } catch (_) {
    return Level.error;
  }
}

/// 刷新文件日志缓冲，确保导出前内容落盘。
Future<void> flushAppLogs() => _fileLogOutput.flush();

/// 今日日志文件（存在且非空时返回）。
File? todayAppLogFile() {
  try {
    final dateStr = _logDateFmt.format(DateTime.now());
    final file = File(p.join(GStorage.logsDirPath, 'app_$dateStr.log'));
    if (file.existsSync() && file.lengthSync() > 0) return file;
  } catch (_) {}
  return null;
}

/// debug 全放行到输出端；各 Output 自行决定控制台/文件策略。
class _AppLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kDebugMode) return true;
    return event.level.value >= _configuredMinLevel().value;
  }
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
    if (!kDebugMode) return;
    for (final line in event.lines) {
      debugPrint(line);
    }
  }
}

final _logDateFmt = DateFormat('yyyy-MM-dd');
final _logTimeFmt = DateFormat('HH:mm:ss.SSS');

const _levelLabel = {
  Level.info: 'INFO',
  Level.warning: 'WARN',
  Level.error: 'ERROR',
  Level.fatal: 'FATAL',
};

const _maxLogAgeDays = 7;

/// 将日志写入磁盘——按日滚动，保留 7 天。
/// 用户开启日志时 debug/release 均落盘；级别按设置过滤。
class _FileLogOutput extends LogOutput {
  IOSink? _sink;
  String? _currentDate;

  @override
  void output(OutputEvent event) {
    final min = _configuredMinLevel();
    if (min == Level.off) return;
    if (event.level.value < min.value) return;

    final now = DateTime.now();
    final dateStr = _logDateFmt.format(now);

    if (_currentDate != dateStr) {
      _rotateSink(dateStr);
      _pruneOldLogs(now);
    }

    final sink = _sink;
    if (sink == null) return;

    final time = _logTimeFmt.format(now);
    final label = _levelLabel[event.level] ?? event.level.name.toUpperCase();
    for (final line in event.lines) {
      sink.writeln('$time [$label] $line');
    }
  }

  Future<void> flush() async {
    await _sink?.flush();
  }

  void _rotateSink(String dateStr) {
    _sink?.flush();
    _sink?.close();

    try {
      final file = File(p.join(GStorage.logsDirPath, 'app_$dateStr.log'));
      _sink = file.openWrite(mode: FileMode.append);
      _currentDate = dateStr;
    } catch (_) {
      _sink = null;
      _currentDate = null;
    }
  }

  void _pruneOldLogs(DateTime now) {
    try {
      final dir = Directory(GStorage.logsDirPath);
      if (!dir.existsSync()) return;
      final cutoff = now.subtract(const Duration(days: _maxLogAgeDays));
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = p.basenameWithoutExtension(entity.path);
        if (!name.startsWith('app_')) continue;
        final dateStr = name.substring(4);
        final date = DateTime.tryParse(dateStr);
        if (date != null && date.isBefore(cutoff)) {
          entity.deleteSync();
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> destroy() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
