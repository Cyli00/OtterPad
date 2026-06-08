import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全局键值存储单例（Hive）+ 文件系统根目录管理。
///
/// **目录布局**：
/// ```
/// <AppSupport>/OtterPad/        ← appRootPath（server root）
/// ├── db/                       ← Hive 数据库（dbDirPath）
/// │   └── *.hive *.lock
/// └── library/                  ← 文献库（libraryDirPath）
///     └── <documentId>/          ← 每篇文献自包含目录
///         ├── source.pdf
///         ├── extract.md / extract.json
///         ├── figures/
///         ├── translations.json
///         ├── summary/
///         └── .reader.html      ← WebView HTML 缓存（自包含）
/// ```
///
/// **跨平台 path 策略**：所有平台统一用 `getApplicationSupportDirectory()`：
/// - iOS：`~/Library/Application Support/...`，不暴露 Files App
/// - Android：`/data/data/<pkg>/files/`，应用沙箱私有
/// - macOS：`~/Library/Application Support/...`，不暴露 Finder
/// - Windows：`<AppData>\Roaming\...`，用户配置目录
class GStorage {
  static late Box _settingBox;
  static late Box _favoritesBox;
  static late Box _documentsBox;
  static late Box _highlightsBox;
  static late Box _historyBox;
  static late Box _zoteroSyncBox;
  static late String _dbDirPath;
  static late String _libraryDirPath;
  static late String _appRootPath;
  static bool _initialized = false;

  static Future<void> init() async {
    final appSupport = await getApplicationSupportDirectory();
    final appRoot = Directory(p.join(appSupport.path, 'OtterPad'));
    final dbDir = Directory(p.join(appRoot.path, 'db'));
    final libraryDir = Directory(p.join(appRoot.path, 'library'));
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    if (!await libraryDir.exists()) await libraryDir.create(recursive: true);

    _appRootPath = appRoot.path;
    _dbDirPath = dbDir.path;
    _libraryDirPath = libraryDir.path;

    if (!_initialized) {
      Hive.init(dbDir.path);
      _initialized = true;
    }
    await _openBoxes();
  }

  static Future<void> reopen() async {
    if (!_initialized) {
      await init();
      return;
    }
    await _openBoxes();
  }

  static Future<void> _openBoxes() async {
    final results = await Future.wait([
      Hive.isBoxOpen('settings')
          ? Future.value(Hive.box('settings'))
          : Hive.openBox('settings'),
      Hive.isBoxOpen('favorites')
          ? Future.value(Hive.box('favorites'))
          : Hive.openBox('favorites'),
      Hive.isBoxOpen('documents')
          ? Future.value(Hive.box('documents'))
          : Hive.openBox('documents'),
      Hive.isBoxOpen('highlights')
          ? Future.value(Hive.box('highlights'))
          : Hive.openBox('highlights'),
      Hive.isBoxOpen('history')
          ? Future.value(Hive.box('history'))
          : Hive.openBox('history'),
      Hive.isBoxOpen('zotero_sync')
          ? Future.value(Hive.box('zotero_sync'))
          : Hive.openBox('zotero_sync'),
    ]);
    _settingBox = results[0];
    _favoritesBox = results[1];
    _documentsBox = results[2];
    _highlightsBox = results[3];
    _historyBox = results[4];
    _zoteroSyncBox = results[5];
  }

  // ─── 生命周期 ──────────────────────────────────────────────────────────────

  static Future<void> flush() async {
    final futures = <Future<void>>[];
    if (Hive.isBoxOpen('settings')) futures.add(Hive.box('settings').flush());
    if (Hive.isBoxOpen('favorites')) futures.add(Hive.box('favorites').flush());
    if (Hive.isBoxOpen('documents')) futures.add(Hive.box('documents').flush());
    if (Hive.isBoxOpen('highlights')) {
      futures.add(Hive.box('highlights').flush());
    }
    if (Hive.isBoxOpen('history')) futures.add(Hive.box('history').flush());
    if (Hive.isBoxOpen('zotero_sync')) {
      futures.add(Hive.box('zotero_sync').flush());
    }
    await Future.wait(futures);
  }

  static Future<void> close() async {
    if (!_initialized) return;
    await Hive.close();
  }

  // ─── 公开 getter ──────────────────────────────────────────────────────────

  static Box get setting => _settingBox;
  static Box get favorites => _favoritesBox;
  static Box get documents => _documentsBox;
  static Box get highlights => _highlightsBox;
  static Box get history => _historyBox;

  /// Zotero 同步簿记：`item:<zoteroKey>` → {documentId, version}，
  /// 以及标量 `_libraryVersion`（增量拉取游标）。
  static Box get zoteroSync => _zoteroSyncBox;

  /// `<AppSupport>/OtterPad/db/`——Hive 数据库目录。
  static String get dbDirPath => _dbDirPath;

  /// `<AppSupport>/OtterPad/library/`——所有文献子目录的父目录。
  static String get libraryDirPath => _libraryDirPath;

  /// `<AppSupport>/OtterPad/`——`db/` 与 `library/` 的共同父目录。
  /// 用于 [ReaderLocalhostServer] 的 documentRoot。
  static String get appRootPath => _appRootPath;
}
