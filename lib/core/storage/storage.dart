import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全局键值存储单例（Hive）+ 文件系统根目录管理。
///
/// **目录布局（v2，2026-05-10 起）**：
/// ```
/// <AppSupport>/OtterPad/        ← appRootPath（server root）
/// ├── db/                       ← Hive 数据库（dbDirPath / dataDirPath 别名）
/// │   └── *.hive *.lock
/// └── library/                  ← 文献库（libraryDirPath）
///     └── <hash>/                ← 每篇文献自包含目录
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
///
/// **历次迁移链**（启动时按顺序自动执行）：
/// 1. 老 `<AppDocs>/NightReader/` → `<AppSupport>/OtterPad/`（rebrand + 移位）
/// 2. 老 `<AppDocs>/OtterPad/` → `<AppSupport>/OtterPad/`（仅移位）
/// 3. 老子目录 `data/` → `db/`、`docs/` → `library/`（统一布局）
/// 4. Hive box value 内的旧绝对路径前缀替换（保证 `Document.filePath` 等仍可解析）
class GStorage {
  static late Box _settingBox;
  static late Box _favoritesBox;
  static late Box _documentsBox;
  static late Box _highlightsBox;
  static late Box _historyBox;
  static late String _dbDirPath;
  static late String _libraryDirPath;
  static late String _appRootPath;
  static bool _initialized = false;

  static Future<void> init() async {
    final appSupport = await getApplicationSupportDirectory();
    final appDocs = await getApplicationDocumentsDirectory();
    final appRoot = Directory(p.join(appSupport.path, 'OtterPad'));

    // Phase 1: 物理目录迁移（必须在 Hive.init 前完成——hive 文件随 db/ 目录搬）
    await _migrateLegacyDirectories(
      targetRoot: appRoot,
      appDocsPath: appDocs.path,
    );

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

    // Phase 2: 修正 box 内残留的旧绝对路径引用（Document.filePath 等）
    await _migrateHivePathReferences(appDocsPath: appDocs.path);
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
    ]);
    _settingBox = results[0];
    _favoritesBox = results[1];
    _documentsBox = results[2];
    _highlightsBox = results[3];
    _historyBox = results[4];
  }

  // ─── 物理目录迁移 ──────────────────────────────────────────────────────────

  /// 把旧位置（含 `<AppDocs>/NightReader/` 和 `<AppDocs>/OtterPad/`）的整目录
  /// 搬到新 `<AppSupport>/OtterPad/`，并把内部 `data/` → `db/`、`docs/` →
  /// `library/`。每步都幂等：已迁过则跳过。
  ///
  /// `rename` 跨卷会抛 `FileSystemException`（移动设备/不同分区）—— fallback
  /// 到递归复制 + 删除。iOS/Android 上 AppDocs 与 AppSupport 同卷，rename
  /// 应该总是成功；只在桌面跨卷场景才走 fallback。
  static Future<void> _migrateLegacyDirectories({
    required Directory targetRoot,
    required String appDocsPath,
  }) async {
    // 候选旧根：从老到新（NightReader 先尝试，避免和 OtterPad 重复迁移）
    final legacyRoots = [
      Directory(p.join(appDocsPath, 'NightReader')),
      Directory(p.join(appDocsPath, 'OtterPad')),
    ];

    for (final legacy in legacyRoots) {
      if (p.equals(legacy.path, targetRoot.path)) continue;
      if (!await legacy.exists()) continue;
      if (await targetRoot.exists()) {
        // 目标已存在 → 假定迁移已完成，旧目录残留视为脏数据，忽略
        debugPrint(
          '[GStorage] 目标 ${targetRoot.path} 已存在，跳过来自 '
          '${legacy.path} 的迁移（可能是上次迁移完成后旧残留）',
        );
        continue;
      }

      debugPrint('[GStorage] 迁移目录 ${legacy.path} → ${targetRoot.path}');
      await targetRoot.parent.create(recursive: true);
      try {
        await legacy.rename(targetRoot.path);
      } on FileSystemException catch (e) {
        debugPrint('[GStorage] rename 失败，回退递归复制：$e');
        await _copyDirectory(legacy, targetRoot);
        try {
          await legacy.delete(recursive: true);
        } catch (delErr) {
          debugPrint('[GStorage] 旧目录删除失败（不影响功能）：$delErr');
        }
      }
      break;
    }

    // 子目录改名：data → db
    final oldData = Directory(p.join(targetRoot.path, 'data'));
    final newDb = Directory(p.join(targetRoot.path, 'db'));
    if (await oldData.exists() && !await newDb.exists()) {
      debugPrint('[GStorage] 子目录改名 ${oldData.path} → ${newDb.path}');
      await oldData.rename(newDb.path);
    }

    // 子目录改名：docs → library
    final oldDocs = Directory(p.join(targetRoot.path, 'docs'));
    final newLibrary = Directory(p.join(targetRoot.path, 'library'));
    if (await oldDocs.exists() && !await newLibrary.exists()) {
      debugPrint('[GStorage] 子目录改名 ${oldDocs.path} → ${newLibrary.path}');
      await oldDocs.rename(newLibrary.path);
    }

    // 旧 HTML 缓存目录 ._readers/（v1 设计），新方案 HTML 自包含到
    // library/<hash>/.reader.html 后无用，启动时一次性清理。
    for (final stale in const ['._readers', '_readers']) {
      final dir = Directory(p.join(targetRoot.path, 'db', stale));
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
          debugPrint('[GStorage] 已清理旧 HTML 缓存目录 ${dir.path}');
        } catch (e) {
          debugPrint('[GStorage] 清理 ${dir.path} 失败（不影响功能）：$e');
        }
      }
    }
  }

  static Future<void> _copyDirectory(Directory src, Directory dst) async {
    if (!await dst.exists()) await dst.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final newPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  // ─── Hive 内绝对路径修正 ──────────────────────────────────────────────────

  /// 把 box value 内残留的旧绝对路径前缀（NightReader、AppDocs/OtterPad/docs
  /// 等）替换成新位置。**顺序**：先替换更具体的（含 `/docs` `/data` 等子目录
  /// 名的完整路径），再替换通用 OtterPad 父目录前缀——否则父前缀替换会破坏
  /// 子目录名替换的结果。
  static Future<void> _migrateHivePathReferences({
    required String appDocsPath,
  }) async {
    final mappings = <(String, String)>[
      // 旧 NightReader 完整路径
      (p.join(appDocsPath, 'NightReader', 'docs'),
          p.join(_appRootPath, 'library')),
      (p.join(appDocsPath, 'NightReader', 'data'),
          p.join(_appRootPath, 'db')),
      (p.join(appDocsPath, 'NightReader'), _appRootPath),
      // 旧 OtterPad-in-Documents 完整路径
      (p.join(appDocsPath, 'OtterPad', 'docs'),
          p.join(_appRootPath, 'library')),
      (p.join(appDocsPath, 'OtterPad', 'data'),
          p.join(_appRootPath, 'db')),
      (p.join(appDocsPath, 'OtterPad'), _appRootPath),
      // 同根但旧子目录名（极端情况：上次启动到一半中断）
      (p.join(_appRootPath, 'docs'), p.join(_appRootPath, 'library')),
      (p.join(_appRootPath, 'data'), p.join(_appRootPath, 'db')),
    ];

    final boxes = [
      _settingBox,
      _favoritesBox,
      _documentsBox,
      _highlightsBox,
      _historyBox,
    ];
    for (final box in boxes) {
      for (final key in box.keys.toList()) {
        var value = box.get(key);
        var changed = false;
        for (final (oldP, newP) in mappings) {
          if (p.equals(oldP, newP)) continue;
          final next = _replaceLegacyPath(value, oldP, newP);
          if (!identical(next, value)) {
            value = next;
            changed = true;
          }
        }
        if (changed) await box.put(key, value);
      }
    }
  }

  static dynamic _replaceLegacyPath(
    dynamic value,
    String legacyPath,
    String currentPath,
  ) {
    if (value is String) {
      final migrated = value
          .replaceAll(legacyPath, currentPath)
          .replaceAll(_jsonPath(legacyPath), _jsonPath(currentPath));
      return migrated == value ? value : migrated;
    }

    if (value is List) {
      var changed = false;
      final migrated = value.map((item) {
        final next = _replaceLegacyPath(item, legacyPath, currentPath);
        changed = changed || !identical(next, item);
        return next;
      }).toList();
      return changed ? migrated : value;
    }

    if (value is Map) {
      var changed = false;
      final migrated = <dynamic, dynamic>{};
      value.forEach((key, item) {
        final nextKey = _replaceLegacyPath(key, legacyPath, currentPath);
        final nextValue = _replaceLegacyPath(
          item,
          legacyPath,
          currentPath,
        );
        changed =
            changed || !identical(nextKey, key) || !identical(nextValue, item);
        migrated[nextKey] = nextValue;
      });
      return changed ? migrated : value;
    }

    return value;
  }

  static String _jsonPath(String path) => path.replaceAll(r'\', r'\\');

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

  /// `<AppSupport>/OtterPad/db/`——Hive 数据库目录。
  static String get dbDirPath => _dbDirPath;

  /// 历史别名，等同 [dbDirPath]。新代码请用 [dbDirPath]。
  /// 保留是为外部调用方过渡期免破坏（已经全部就地替换的话可删）。
  @Deprecated('Use dbDirPath instead')
  static String get dataDirPath => _dbDirPath;

  /// `<AppSupport>/OtterPad/library/`——所有文献子目录的父目录。
  /// 替代旧 `documents_provider.getDocsDir()` 的硬编码路径。
  static String get libraryDirPath => _libraryDirPath;

  /// `<AppSupport>/OtterPad/`——`db/` 与 `library/` 的共同父目录。
  ///
  /// **用于 [ReaderLocalhostServer] 的 root**：HTML（在 `library/<hash>/.reader.html`）
  /// 与 figures（在 `library/<hash>/figures/`）现在同处一个文献目录，server
  /// root 仍设在此处统一服务（保留向后兼容，HTML 路径写死时也能找到）。
  static String get appRootPath => _appRootPath;
}
