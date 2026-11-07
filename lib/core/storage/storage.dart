import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api.dart';
import 'settings_store.dart';

/// 设置的同步读缓存与数据目录。数据本身由 Rust 保存在 `<AppSupport>/OtterPad/v2/`。
class GStorage {
  static late SettingsStore _settings;
  static late String _dataDirPath;

  static Future<void> init(Backend backend) async {
    final appSupport = await getApplicationSupportDirectory();
    _dataDirPath = p.join(appSupport.path, 'OtterPad', 'v2');
    _settings = SettingsStore(backend);
    await _settings.preload();
  }

  /// 恢复备份后从 Rust 重新载入设置。
  static Future<void> reloadSettings() => _settings.preload();

  static SettingsStore get setting => _settings;

  /// `<AppSupport>/OtterPad/v2/`：Rust 数据根。
  static String get dataDirPath => _dataDirPath;

  /// `<AppSupport>/OtterPad/v2/library/`：每篇文献一个目录，PDF 为 `source.pdf`。
  static String get libraryDirPath => p.join(_dataDirPath, 'library');

  /// `<AppSupport>/OtterPad/v2/logs/`：Rust 写入的日志。
  static String get logsDirPath => p.join(_dataDirPath, 'logs');
}
