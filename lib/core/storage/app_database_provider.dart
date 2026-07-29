import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'storage.dart';

/// 当前 [AppDatabase] 实例（ADR-0001）。
///
/// 数据 provider 在 `build()` 里 `ref.watch(appDatabaseProvider)` 再
/// `select(...).watch()`——DB 是唯一真值源，provider 是派生视图。
/// 备份覆盖恢复 `GStorage.reopen()` 换库后，`ref.invalidate(appDatabaseProvider)`
/// 让所有数据 provider（含 `highlightProvider(docId)` family）重建并重订阅新库，
/// 无需枚举 docId。
final appDatabaseProvider = Provider<AppDatabase>((ref) => GStorage.db);