import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/settings_keys.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/services/doc_extract_usage_service.dart';

/// 提取用量本地记账：日期滚动归零 + 按提供商分桶。
void main() {
  late db_lib.AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = db_lib.AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('otter_usage_');
    await GStorage.initForTest(
      db,
      dbDirPath: tempDir.path,
      libraryDirPath: tempDir.path,
      logsDirPath: tempDir.path,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('初始为 0；按提供商分别累计', () async {
    expect(DocExtractUsageService.today(), (paddle: 0, mineru: 0));

    await DocExtractUsageService.record(DocExtractProvider.paddle, 12);
    await DocExtractUsageService.record(DocExtractProvider.mineru, 5);
    await DocExtractUsageService.record(DocExtractProvider.paddle, 3);
    expect(DocExtractUsageService.today(), (paddle: 15, mineru: 5));
  });

  test('并发记录不会覆盖同一提供商或另一提供商的页数', () async {
    await Future.wait([
      for (var i = 0; i < 10; i++) ...[
        DocExtractUsageService.record(DocExtractProvider.paddle, 2),
        DocExtractUsageService.record(DocExtractProvider.mineru, 3),
      ],
    ]);
    expect(DocExtractUsageService.today(), (paddle: 20, mineru: 30));
  });

  test('日期滚动时归零重记', () async {
    // 伪造昨日数据
    await GStorage.setting.put(SettingsKeys.docExtractUsage, {
      'date': '2000-01-01',
      'paddle': 999,
      'mineru': 999,
    });
    expect(DocExtractUsageService.today(), (paddle: 0, mineru: 0));

    await DocExtractUsageService.record(DocExtractProvider.mineru, 7);
    final usage = DocExtractUsageService.today();
    expect(usage, (paddle: 0, mineru: 7));
  });

  test('0 / 负页数不记账', () async {
    await DocExtractUsageService.record(DocExtractProvider.paddle, 0);
    expect(
      GStorage.setting.get(SettingsKeys.docExtractUsage),
      isNull,
      reason: '无实际页数时不写存储',
    );
  });
}
