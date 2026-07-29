import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/services/translation_service.dart';

/// TranslationService Drift 缓存（translations 表）行为测试。
///
/// 经 `@visibleForTesting` 测试缝 [TranslationService.debugGetCacheByKey] /
/// [TranslationService.debugPutCacheByKey] / [TranslationService.debugBuildCacheKey]
/// 脱离 LLM 单测缓存读写、TTL 与 key 语义。LLM 调用本身由 GUI 验证覆盖。
void main() {
  late db_lib.AppDatabase db;

  setUp(() async {
    db = db_lib.AppDatabase(NativeDatabase.memory());
    await GStorage.initForTest(db);
  });

  tearDown(() async => db.close());

  test('put 后 get 命中', () async {
    await TranslationService.debugPutCacheByKey('tr_en_1', 'hello->你好');
    expect(await TranslationService.debugGetCacheByKey('tr_en_1'), 'hello->你好');
  });

  test('未命中返回 null', () async {
    expect(await TranslationService.debugGetCacheByKey('tr_en_missing'), isNull);
  });

  test('同 key put 覆盖旧译文', () async {
    await TranslationService.debugPutCacheByKey('tr_en_7', 'old');
    await TranslationService.debugPutCacheByKey('tr_en_7', 'new');
    expect(await TranslationService.debugGetCacheByKey('tr_en_7'), 'new');
  });

  test('过期行（createdAt 超 7 天）不命中', () async {
    final staleMs =
        DateTime.now().millisecondsSinceEpoch - (8 * 24 * 60 * 60 * 1000);
    await db.into(db.translations).insertOnConflictUpdate(
          db_lib.TranslationsCompanion(
            cacheKey: const Value('tr_en_stale'),
            translation: const Value('stale'),
            createdAt: Value(staleMs),
          ),
        );
    expect(await TranslationService.debugGetCacheByKey('tr_en_stale'), isNull);
  });

  test('put 顺带清掉过期行', () async {
    final staleMs =
        DateTime.now().millisecondsSinceEpoch - (8 * 24 * 60 * 60 * 1000);
    await db.into(db.translations).insertOnConflictUpdate(
          db_lib.TranslationsCompanion(
            cacheKey: const Value('tr_en_old'),
            translation: const Value('old'),
            createdAt: Value(staleMs),
          ),
        );
    // put 一条新行触发写路径里的过期清理
    await TranslationService.debugPutCacheByKey('tr_en_fresh', 'fresh');

    final remaining = await (db.select(db.translations)
          ..where((t) => t.cacheKey.equals('tr_en_old')))
        .get();
    expect(remaining, isEmpty, reason: 'put 应顺带清掉过期行');
  });

  test('debugBuildCacheKey：同文本+同语言同 key，语言不同异 key', () {
    final k1 = TranslationService.debugBuildCacheKey('hello', 'zh');
    final k2 = TranslationService.debugBuildCacheKey('hello', 'zh');
    final k3 = TranslationService.debugBuildCacheKey('hello', 'en');
    expect(k1, k2);
    expect(k1, isNot(k3));
    expect(k1.startsWith('tr_zh_'), isTrue);
  });
}