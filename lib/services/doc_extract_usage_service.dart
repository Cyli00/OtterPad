import 'package:flutter_riverpod/legacy.dart';

import '../core/app_logger.dart';

import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';
import '../providers/api_provider.dart';

/// 文档提取用量的本地记账（按服务商各自 API 均无额度查询接口，只能本地估算）。
///
/// 存储形状（[SettingsKeys.docExtractUsage]，GStorage.setting）：
/// `{'date': 'yyyy-MM-dd', 'paddle': n, 'mineru': m}`，日期滚动归零。
/// 仅统计提取**成功**的页数；UI 需标注「本地估算，以服务商为准」。
class DocExtractUsageService {
  DocExtractUsageService._();

  static Future<void> _pending = Future.value();

  static String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static Map<String, dynamic> _readRaw() {
    final raw = GStorage.setting.get(SettingsKeys.docExtractUsage);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  /// 今日各提供商已用页数（日期不符视为 0）。
  static ({int paddle, int mineru}) today() {
    final raw = _readRaw();
    if (raw['date'] != _today()) return (paddle: 0, mineru: 0);
    return (
      paddle: (raw['paddle'] as num?)?.toInt() ?? 0,
      mineru: (raw['mineru'] as num?)?.toInt() ?? 0,
    );
  }

  /// 记录一次成功提取的页数；日期滚动时归零重记。
  static Future<void> record(DocExtractProvider provider, int pages) {
    if (pages <= 0) return Future.value();
    // 读改写必须一起串行，否则同时完成的提取会读取同一份旧计数。
    final task = _pending.then((_) => _record(provider, pages));
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  static Future<void> _record(DocExtractProvider provider, int pages) async {
    final current = today();
    final updated = switch (provider) {
      DocExtractProvider.paddle => (
        paddle: current.paddle + pages,
        mineru: current.mineru,
      ),
      DocExtractProvider.mineru => (
        paddle: current.paddle,
        mineru: current.mineru + pages,
      ),
    };
    await GStorage.setting.put(SettingsKeys.docExtractUsage, {
      'date': _today(),
      'paddle': updated.paddle,
      'mineru': updated.mineru,
    });
  }
}

class DocExtractUsageNotifier
    extends StateNotifier<({int paddle, int mineru})> {
  DocExtractUsageNotifier() : super(DocExtractUsageService.today());

  /// 记账并刷新状态。
  Future<void> record(DocExtractProvider provider, int pages) async {
    try {
      await DocExtractUsageService.record(provider, pages);
      if (mounted) state = DocExtractUsageService.today();
    } catch (error) {
      log.d('提取用量记账失败: $error');
    }
  }

  void reload() {
    state = DocExtractUsageService.today();
  }
}

final docExtractUsageProvider =
    StateNotifierProvider<DocExtractUsageNotifier, ({int paddle, int mineru})>(
      (ref) => DocExtractUsageNotifier(),
    );
