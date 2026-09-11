import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/settings_store.dart';

void main() {
  late AppDatabase database;
  late SettingsStore settings;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    settings = SettingsStore(database);
    await settings.put('fixture', '旧值');
  });
  tearDown(() => database.close());

  test('写入失败时内存设置仍与数据库一致', () async {
    await database.customStatement(
      "CREATE TRIGGER fail_setting BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT, '测试失败'); END",
    );
    await expectLater(settings.put('fixture', '新值'), throwsA(anything));
    expect(settings.get('fixture'), '旧值');
    expect(
      (await database.select(database.settings).get()).single.value,
      '"旧值"',
    );
  });

  for (final clearAll in [false, true]) {
    test('删除失败时仍保留内存设置：全部=$clearAll', () async {
      await database.customStatement(
        "CREATE TRIGGER fail_setting BEFORE DELETE ON settings BEGIN SELECT RAISE(ABORT, '测试失败'); END",
      );
      await expectLater(
        clearAll ? settings.clear() : settings.delete('fixture'),
        throwsA(anything),
      );
      expect(settings.get('fixture'), '旧值');
    });
  }
}
