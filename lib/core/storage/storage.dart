import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_simple/sqlite3_simple.dart';

import '../../data/models/collection/favorite.dart' as fav;
import 'app_database.dart';
import 'db_convert.dart' show favoriteCompanion;
import 'settings_store.dart';
import 'zotero_snapshot.dart';

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
/// **启动时序**（init，ADR-0005）：建目录 → 全局加载 Simple 扩展（必须在开
/// Drift 连接前注册 auto-extension）→ 开 Drift（migration 建 8 表）→ jieba
/// 字典路径注册（jieba_dict SQL，配置 jieba 字典让 simple tokenizer 与 jieba_query 可用）+ 预热 → ensureFts5
/// 建 FTS5 虚表/触发器 → 预加载 settings（SettingsStore，ADR-0002）。
///
/// 数据 provider 不再读启动缓存——它们 `ref.watch(appDatabaseProvider)` 后
/// `select(...).watch()`，DB 是唯一真值源（ADR-0001，弃用 StartupCache）。
///
/// **跨平台 path 策略**：所有平台统一用 `getApplicationSupportDirectory()`：
/// - iOS：`~/Library/Application Support/...`，不暴露 Files App
/// - Android：`/data/data/<pkg>/files/`，应用沙箱私有
/// - macOS：`~/Library/Application Support/...`，不暴露 Finder
/// - Windows：`<AppData>\Roaming/...`，用户配置目录
class GStorage {
  // Drift 主存储
  static late AppDatabase _db;
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

    // ADR-0005：全局 Simple 扩展必须在开 Drift 连接前注册（auto-extension
    // 对之后打开的连接生效）。加载失败（目标平台缺预编译 simple 库）不致开库
    // 崩溃，搜索降级为 LIKE（见 searchDocuments）。
    try {
      if (!_simpleLoaded) {
        sqlite3.loadSimpleExtension();
        _simpleLoaded = true;
      }
    } catch (e) {
      debugPrint('OtterPad: sqlite3_simple 原生扩展加载失败，搜索降级为 LIKE: $e');
    }

    _db = AppDatabase.file(p.join(dbDir.path, _dbFileName));

    // 先配置 jieba 字典路径（jieba_dict SQL），让 simple tokenizer（jieba 分词
    // + 拼音）与 jieba_query 查询函数可用，再建 FTS5 虚表。simple 扩展只注册
    // simple tokenizer，jieba 是 query 函数前缀而非 tokenizer 名（真机实测，
    // ADR-0005 #5）。
    try {
      await _setupJieba();
    } catch (e) {
      debugPrint('OtterPad: jieba 字典配置失败，拼音/中文分词可能不可用: $e');
    }

    try {
      await _db.ensureFts5();
      await _syncFtsIfStale();
    } catch (e) {
      debugPrint('OtterPad: FTS5 建表失败（documents_fts），搜索降级为 LIKE: $e');
    }

    // ADR-0002：SettingsStore 私有写穿透缓存（非 StartupCache），启动加载。
    _settings = SettingsStore(_db);
    await _settings.preload();
    // ADR-0002：ZoteroSyncStore 同步快照订阅 zotero_items + meta 流。
    await ZoteroSnapshot.attach(_db);
    await _ensureDefaultFavorite();

    if (kDebugMode) await _debugFtsSelfCheck();

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

  /// 修复历史 FTS 数据不一致：旧版本（tokenize='jieba' 建表失败）导入的文献
  /// 没进 documents_fts，删除时 documents_ad 触发器的 FTS5 'delete' 命令找不到
  /// 匹配行报 SQL logic error。启动/重开时若 documents 行数 ≠ documents_fts
  /// 行数，清空并从 documents 全量重建 FTS 索引（一次性，之后触发器保持一致）。
  static Future<void> _syncFtsIfStale() async {
    final docCount = (await _db.select(_db.documents).get()).length;
    if (docCount == 0) return;
    final ftsCount =
        (await _db.customSelect('SELECT count(*) AS c FROM documents_fts')
                .getSingle())
            .read<int>('c');
    // 旧触发器用 id 自动分配 FTS rowid（≠ documents rowid），导致 'delete' 命令
    // 找不到行。行数不等或 rowid 关联不一致时重建。
    final rowidMismatch = ftsCount == docCount
        ? (await _db.customSelect(
                "SELECT count(*) AS c FROM documents_fts f "
                "JOIN documents d ON d.id = f.id WHERE f.rowid != d.rowid")
              .getSingle())
            .read<int>('c')
        : 1;
    if (ftsCount == docCount && rowidMismatch == 0) return;
    debugPrint('OtterPad: FTS 索引不一致（$ftsCount/$docCount，rowid 偏差 $rowidMismatch），重建 documents_fts');
    await _db.customStatement('DELETE FROM documents_fts');
    await _db.customStatement(
      'INSERT INTO documents_fts(rowid, id, title, authors, journal, keywords) '
      'SELECT rowid, id, title, authors, journal, keywords FROM documents',
    );
  }

  /// Debug 自检：确认 documents_fts 存在 + jieba_query 可调（ADR-0005 #5）。
  /// 仅 debug、仅 init（不在 initForTest）。失败只 debugPrint，不致崩溃。
  /// 真机中文/拼音命中与触发器同步的完整 smoke 由发布前在 Android 上手动跑。
  static Future<void> _debugFtsSelfCheck() async {
    try {
      final ftsRow = await _db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='documents_fts'",
          )
          .getSingleOrNull();
      if (ftsRow == null) {
        debugPrint('OtterPad FTS 自检：documents_fts 不存在（simple 扩展未加载），搜索走 LIKE');
        return;
      }
      await _db.customStatement("SELECT jieba_query('文献测试')");
      debugPrint('OtterPad FTS 自检：documents_fts 存在 + jieba_query 可调，FTS5 主路径可用');
    } catch (e) {
      debugPrint('OtterPad FTS 自检异常: $e');
    }
  }

  /// 启动/恢复后幂等补建默认「我的收藏」收藏夹（首次启动或恢复的备份缺默认夹时）。
  /// 从 FavoritesNotifier.build() 移入——build() 应纯读，副作用归 init 钩子。
  static Future<void> _ensureDefaultFavorite() async {
    final exists = await (_db.select(_db.favorites)
          ..where((t) => t.id.equals(fav.Favorite.defaultId)))
        .getSingleOrNull();
    if (exists == null) {
      await _db.into(_db.favorites).insertOnConflictUpdate(
            favoriteCompanion(
              fav.Favorite.defaultFor(
                PlatformDispatcher.instance.locale.languageCode,
              ),
            ),
          );
    }
  }

  static Future<void> reopen() async {
    if (!_initialized) {
      await init();
      return;
    }
    // ADR-0005：Simple 扩展已全局加载（_simpleLoaded），新连接自带；按契约仍在开库前确保。
    try {
      if (!_simpleLoaded) {
        sqlite3.loadSimpleExtension();
        _simpleLoaded = true;
      }
    } catch (e) {
      debugPrint('OtterPad: sqlite3_simple 原生扩展重载失败，搜索降级为 LIKE: $e');
    }
    // Drift 重开（备份恢复后替换了 .db 文件；Simple 扩展已全局加载，新连接自带）
    _db = AppDatabase.file(p.join(_dbDirPath, _dbFileName));
    // 先配置 jieba 字典（让 simple tokenizer + jieba_query 可用），再建 FTS5（同 init）
    try {
      await _setupJieba();
    } catch (e) {
      debugPrint('OtterPad: jieba 字典配置失败，拼音/中文分词可能不可用: $e');
    }
    try {
      await _db.ensureFts5();
      await _syncFtsIfStale();
    } catch (e) {
      debugPrint('OtterPad: FTS5 建表失败（documents_fts），搜索降级为 LIKE: $e');
    }
    _settings = SettingsStore(_db);
    await _settings.preload();
    await ZoteroSnapshot.attach(_db);
    await _ensureDefaultFavorite();
  }

  /// 重新加载 settings 缓存（不重开库）。settingsOnly 覆盖恢复直接写 settings
  /// 表后，SettingsStore 的私有缓存过期，调此重建（ADR-0001 取代 refreshCache）。
  static Future<void> reloadSettings() async {
    _settings = SettingsStore(_db);
    await _settings.preload();
  }

  /// 测试专用：注入内存 AppDatabase + 预加载 settings，不走扩展/文件系统。
  /// 数据 provider 经 [appDatabaseProvider] 读 GStorage.db（= 注入的库）。
  @visibleForTesting
  static Future<void> initForTest(
    AppDatabase database, {
    String? dbDirPath,
    String? libraryDirPath,
    String? logsDirPath,
  }) async {
    _db = database;
    if (dbDirPath != null) _dbDirPath = dbDirPath;
    if (libraryDirPath != null) _libraryDirPath = libraryDirPath;
    if (logsDirPath != null) _logsDirPath = logsDirPath;
    _settings = SettingsStore(database);
    await _settings.preload();
    await ZoteroSnapshot.attach(database);
    _initialized = false;
  }

  // ─── 生命周期 ──────────────────────────────────────────────────────────────

  /// Drift 每次写已即时落盘，无需 flush；保留空实现供备份流程调用。
  static Future<void> flush() async {}

  static Future<void> close() async {
    if (!_initialized) return;
    await ZoteroSnapshot.detach();
    await _db.close();
  }

  // ─── 公开 getter ──────────────────────────────────────────────────────────

  /// Drift 主库（关系化 + FTS5）。
  static AppDatabase get db => _db;

  /// settings：Drift 后端 + 同步读缓存，对外模仿 Hive Box API（ADR-0002）。
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