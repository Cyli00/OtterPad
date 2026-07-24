import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_simple/sqlite3_simple.dart';

import 'app_database.dart';
import 'settings_store.dart';
import 'startup_cache.dart';

/// 全局存储单例：Drift（关系化 + FTS5）主存储 + 文件系统根目录管理。
///
/// **目录布局**：
/// ```
/// <AppSupport>/OtterPad/        ← appRootPath（server root）
/// ├── db/                       ← Drift SQLite + jieba 字典
/// │   ├── otter.db / otter.db-wal / otter.db-shm
/// │   └── cpp_jieba/            ← jieba 分词字典
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
/// **启动时序**（init）：建目录 → 全局加载 Simple 扩展（jieba tokenizer）
/// → 开 Drift（migration 建表 + ensureFts5 建 FTS5 虚表/触发器）→ jieba 字典 + 预热
/// → 预加载缓存（settings + 6 表进内存，provider 同步读）。
///
/// **跨平台 path 策略**：所有平台统一用 `getApplicationSupportDirectory()`：
/// - iOS：`~/Library/Application Support/...`，不暴露 Files App
/// - Android：`/data/data/<pkg>/files/`，应用沙箱私有
/// - macOS：`~/Library/Application Support/...`，不暴露 Finder
/// - Windows：`<AppData>\Roaming\...`，用户配置目录
class GStorage {
  // Drift 主存储
  static late AppDatabase _db;
  static late StartupCache _cache;
  static late SettingsStore _settings;
  static const _dbFileName = 'otter.db';
  static const _jiebaDictName = 'cpp_jieba';
  static bool _simpleLoaded = false;

  static late String _dbDirPath;
  static late String _libraryDirPath;
  static late String _logsDirPath;
  static late String _appRootPath;
  static bool _initialized = false;

  static Future<void> init() async {
    final appSupport = await getApplicationSupportDirectory();
    final appRoot = Directory(p.join(appSupport.path, 'OtterPad'));
    final dbDir = Directory(p.join(appRoot.path, 'db'));
    final libraryDir = Directory(p.join(appRoot.path, 'library'));
    final logsDir = Directory(p.join(appRoot.path, 'logs'));
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    if (!await libraryDir.exists()) await libraryDir.create(recursive: true);
    if (!await logsDir.exists()) await logsDir.create(recursive: true);

    _appRootPath = appRoot.path;
    _dbDirPath = dbDir.path;
    _libraryDirPath = libraryDir.path;
    _logsDirPath = logsDir.path;

    _db = AppDatabase.file(p.join(dbDir.path, _dbFileName));
    // FTS5/jieba 扩展：加载失败（目标平台缺预编译 simple 库）不致开库崩溃，
    // 搜索降级为 LIKE（见 searchDocuments）。
    try {
      if (!_simpleLoaded) {
        sqlite3.loadSimpleExtension();
        _simpleLoaded = true;
      }
      await _db.ensureFts5();
      await _setupJieba();
    } catch (e) {
      debugPrint('OtterPad: FTS5/jieba 扩展加载失败，搜索降级为 LIKE: $e');
    }

    // 预加载缓存（G2）：settings + 6 表进内存，provider 构造时同步读。
    _settings = SettingsStore(_db);
    await _settings.preload();
    _cache = await StartupCache.load(_db);

    _initialized = true;
  }

  /// jieba 字典落盘 + 告知扩展字典路径 + 预热查询。
  /// 字典文件首启写入后复用；reopen（备份恢复后）时文件已存在，重跑后两步。
  static Future<void> _setupJieba() async {
    final dictPath = p.join(_dbDirPath, _jiebaDictName);
    final dictSql = await sqlite3.saveJiebaDict(dictPath);
    await _db.customStatement(dictSql);
    await _db.customStatement("SELECT jieba_query('OtterPad 初始化（预热）')");
  }

  static Future<void> reopen() async {
    if (!_initialized) {
      await init();
      return;
    }
    // Drift 重开（备份恢复后替换了 .db 文件；Simple 扩展已全局加载，新连接自带）
    _db = AppDatabase.file(p.join(_dbDirPath, _dbFileName));
    try {
      await _db.ensureFts5();
      await _setupJieba();
    } catch (e) {
      debugPrint('OtterPad: FTS5/jieba 重载失败，搜索降级为 LIKE: $e');
    }
    _settings = SettingsStore(_db);
    await _settings.preload();
    _cache = await StartupCache.load(_db);
  }

  /// 重新从 Drift 预加载缓存（不重开连接）。备份 merge/部分 scope restore 后，
  /// 内存缓存已陈旧，调此刷新，再由 backup_orchestrator invalidate 各 provider。
  static Future<void> refreshCache() async {
    _settings = SettingsStore(_db);
    await _settings.preload();
    _cache = await StartupCache.load(_db);
  }

  /// 测试专用：注入内存 AppDatabase + 预加载缓存，不走扩展/文件系统。
  @visibleForTesting
  static Future<void> initForTest(AppDatabase database) async {
    _db = database;
    _settings = SettingsStore(database);
    await _settings.preload();
    _cache = await StartupCache.load(database);
    _initialized = false;
  }

  // ─── 生命周期 ──────────────────────────────────────────────────────────────

  /// Drift 每次写已即时落盘，无需 flush；保留空实现供备份流程调用。
  static Future<void> flush() async {}

  static Future<void> close() async {
    if (!_initialized) return;
    await _db.close();
  }

  // ─── 公开 getter ──────────────────────────────────────────────────────────

  /// Drift 主库（关系化 + FTS5）。
  static AppDatabase get db => _db;

  /// 启动预加载缓存（documents/history/favorites/highlights/zotero）。
  static StartupCache get cache => _cache;

  /// settings：Drift 后端 + 同步读缓存，对外模仿 Hive Box API。
  static SettingsStore get setting => _settings;

  /// `<AppSupport>/OtterPad/db/`——Drift SQLite + jieba 字典。
  static String get dbDirPath => _dbDirPath;

  /// `<AppSupport>/OtterPad/library/`——所有文献子目录的父目录。
  static String get libraryDirPath => _libraryDirPath;

  /// `<AppSupport>/OtterPad/logs/`——日志文件目录。
  static String get logsDirPath => _logsDirPath;

  /// `<AppSupport>/OtterPad/`——`db/` 与 `library/` 的共同父目录。
  /// 用于 [ReaderLocalhostServer] 的 documentRoot。
  static String get appRootPath => _appRootPath;
}