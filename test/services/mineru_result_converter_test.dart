import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/services/doc_extract_service.dart';
import 'package:otter_pad/services/document_structure.dart';
import 'package:otter_pad/services/figure_extract_service.dart';
import 'package:otter_pad/services/mineru_result_converter.dart';
import 'package:otter_pad/utils/doc_paths.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// 以真实 MinerU zip（test/mineru-extract-service/result_source.zip，
/// R-CNN 论文 8 页）为 fixture 的转化器测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await pdfrxInitialize();
  });
  late db_lib.AppDatabase db;
  late Directory tempLibDir;
  late Directory tempLogs;

  /// fixture 落点：library/docA/source.pdf（converter 只派生路径，不读 PDF）
  late String pdfPath;

  const figures = 9; // Figure 1-5 + Table 1-4，恢复误挂到 Table 2 的 Figure 3 题注。
  const captioned = 9;

  setUp(() async {
    db = db_lib.AppDatabase(NativeDatabase.memory());
    tempLibDir = await Directory.systemTemp.createTemp('otter_mineru_');
    tempLogs = await Directory.systemTemp.createTemp('otter_mineru_logs_');
    await GStorage.initForTest(
      db,
      dbDirPath: tempLibDir.path,
      libraryDirPath: tempLibDir.path,
      logsDirPath: tempLogs.path,
    );
    pdfPath = p.join(tempLibDir.path, 'docA', 'source.pdf');
    await File(pdfPath).create(recursive: true);
  });

  tearDown(() async {
    await db.close();
    if (await tempLibDir.exists()) {
      await tempLibDir.delete(recursive: true);
    }
    if (await tempLogs.exists()) await tempLogs.delete(recursive: true);
  });

  /// converter 会删除入参 zip → 每次复制一份 fixture。
  Future<File> stageZip() async {
    final fixture = File('test/mineru-extract-service/result_source.zip');
    expect(fixture.existsSync(), isTrue, reason: 'fixture zip 缺失');
    final staged = File(p.join(p.dirname(pdfPath), 'extract.mineru.zip'));
    await staged.writeAsBytes(await fixture.readAsBytes());
    final archive = ZipDecoder().decodeBytes(await fixture.readAsBytes());
    await File(pdfPath).writeAsBytes(
      archive.files.firstWhere((f) => f.name.endsWith('_origin.pdf')).content,
    );
    return staged;
  }

  test('Pipeline 无 v2 结果可导入，并保留额外导出包', () async {
    final staged = await stageZip();
    final original = ZipDecoder().decodeBytes(await staged.readAsBytes());
    final archive = Archive();
    for (final file in original.files) {
      if (!file.name.endsWith('_content_list_v2.json')) archive.addFile(file);
    }
    archive.addFile(ArchiveFile.string('full.html', '<html>导出内容</html>'));
    await staged.writeAsBytes(ZipEncoder().encode(archive));
    final result = await MinerUResultConverter.instance.convert(
      pdfPath: pdfPath,
      zipFile: staged,
    );
    expect(result.pageCount, 8);
    expect(await File(result.mdPath).exists(), isTrue);
    final retained = File(DocPaths.mineruExports(pdfPath));
    expect(await retained.exists(), isTrue);
    final exported = ZipDecoder().decodeBytes(await retained.readAsBytes());
    expect(exported.files.any((f) => f.name == 'full.html'), isTrue);
    expect(await staged.exists(), isFalse);
  });

  for (final rawCaptionOnly in [false, true]) {
    test('缺少几何信息时仅保留明确配对的原图（仅 Markdown 题注：$rawCaptionOnly）', () async {
      final fixture = ZipDecoder().decodeBytes(
        await File(
          'test/mineru-extract-service/result_source.zip',
        ).readAsBytes(),
      );
      final image = fixture.files
          .firstWhere((e) => e.name.endsWith('.jpg'))
          .content;
      Map<String, dynamic> block(
        String name,
        String caption,
        int x, {
        String type = 'image',
      }) => {
        'type': type,
        'bbox': [x, 0, x + 100, 100],
        'content': {
          'image_source': {'path': 'images/$name.jpg'},
          '${type}_caption': [
            {'type': 'text', 'content': caption},
          ],
        },
      };
      final raw = '''正文段落必须保留。

![](images/main.jpg)

![](images/panel.jpg)

a

Figure 1: Composite illustration.

![](images/next.jpg)

Figure 2: Independent illustration.

![](images/noise.jpg)

![](images/footer.jpg)
''';
      final archive = Archive()
        ..addFile(ArchiveFile.string('full.md', raw))
        ..addFile(
          ArchiveFile.string(
            'sample_content_list_v2.json',
            jsonEncode([
              [
                block(
                  'main',
                  rawCaptionOnly ? '' : 'Figure 1: Composite illustration.',
                  0,
                ),
                block('panel', 'a', 110),
                block('next', 'Figure 2: Independent illustration.', 220),
                block('noise', 'Working distance: 100 micrometers', 800),
                block(
                  'footer',
                  'Figure 3: Footer artifact.',
                  900,
                  type: 'vision_footer',
                ),
              ],
            ]),
          ),
        );
      for (final name in ['main', 'panel', 'next', 'noise', 'footer']) {
        archive.addFile(ArchiveFile('images/$name.jpg', image.length, image));
      }
      final zip = File(p.join(p.dirname(pdfPath), 'synthetic.zip'));
      await zip.writeAsBytes(ZipEncoder().encode(archive));
      final result = await MinerUResultConverter.instance.convert(
        pdfPath: pdfPath,
        zipFile: zip,
      );
      final entries = (await FigureExtractService.loadManifest(pdfPath))!;
      final display = FigureManifestEntry.forDisplay(entries);
      // 缺少几何信息不猜测子图归属；编号主图附近的图内标记不独立成图。
      expect(display, hasLength(rawCaptionOnly ? 1 : 2));
      expect(
        display.any(
          (e) => e.captionText == 'Working distance: 100 micrometers',
        ),
        isFalse,
      );
      expect(
        display.every((e) => !e.sourceImageNames!.contains('panel.jpg')),
        isTrue,
      );
      expect(result.processedMarkdown, contains('正文段落必须保留。'));
      expect(result.processedMarkdown, isNot(contains('panel.jpg')));
      expect(result.processedMarkdown, isNot(contains('footer.jpg')));
      expect(
        RegExp(r'^a$', multiLine: true).hasMatch(result.processedMarkdown),
        isTrue,
      );
      expect(result.processedMarkdown, isNot(contains('](images/')));
      final legacy = FigureManifestEntry.fromJson(
        display.first.toJson()..remove('source_images'),
      );
      expect(legacy.sourceImageNames, isNull);
      final (_, rebuilt) = await MinerUResultConverter.instance.reprocess(
        pdfPath: pdfPath,
      );
      expect(
        _stableMarkdown(rebuilt),
        _stableMarkdown(result.processedMarkdown),
      );
    });
  }

  test('convert: zip → 全部持久产物', () async {
    final zip = await stageZip();
    final result = await MinerUResultConverter.instance.convert(
      pdfPath: pdfPath,
      zipFile: zip,
      title: 'Rich feature hierarchies',
    );

    expect(result.pageCount, 8);
    expect(await zip.exists(), isFalse, reason: '临时 zip 转化后必须回收');

    // 图片平铺落盘
    final figuresDir = Directory(p.join(p.dirname(pdfPath), 'figures'));
    final jpgs = figuresDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .length;
    expect(jpgs, 17, reason: 'zip 内 17 张图全部落盘');

    // manifest
    final manifest = await FigureExtractService.loadManifest(pdfPath);
    expect(manifest, isNotNull);
    expect(manifest!.length, figures);
    expect(
      FigureManifestEntry.forDisplay(manifest).length,
      captioned,
      reason: 'Figure 1-5 + Table 1-4 都与真实区域关联',
    );
    expect(manifest.where((e) => e.kind == 'table').length, 4);
    final figure4 = manifest.singleWhere(
      (e) => e.captionText.startsWith('Figure 4:'),
    );
    final figure5 = manifest.singleWhere(
      (e) => e.captionText.startsWith('Figure 5:'),
    );
    expect(figure4.sourceImageNames, hasLength(6));
    expect(figure5.sourceImageNames, hasLength(4));
    final reviewDir = await Directory(
      'build/figure-review',
    ).create(recursive: true);
    await File(figure4.imagePath).copy(p.join(reviewDir.path, 'Figure_4.png'));
    await File(figure5.imagePath).copy(p.join(reviewDir.path, 'Figure_5.png'));

    // extract.json 可被防腐层消化 + 带 mineru 标记
    final jsonPath = p.join(p.dirname(pdfPath), 'extract.json');
    final jsonContent = await File(jsonPath).readAsString();
    expect(MinerUResultConverter.isMinerUExtractJson(jsonContent), isTrue);
    expect(await MinerUResultConverter.isMinerUDocument(pdfPath), isTrue);
    final structure = DocumentStructure.parse(jsonContent);
    expect(structure.pages.length, 8);
    expect(
      structure.pages.first.blocks.any((b) => b.blockLabel == 'doc_title'),
      isTrue,
      reason: '首页 level1 title → doc_title（保中文书籍题录提取）',
    );
    expect(
      structure.pages
          .expand((pg) => pg.blocks)
          .any(
            (b) =>
                b.blockLabel == 'figure_title' &&
                b.blockContent.startsWith('Figure 1:'),
          ),
      isTrue,
      reason: 'image_caption 合成 figure_title block',
    );

    // 阅读版 md
    final md = result.processedMarkdown;
    expect(md, contains('![fig:Figure 1: Object detection system overview'));
    expect(md, contains('![fig:Table 1: Detection average precision'));
    expect(md, contains('![fig:Table 3: Segmentation mean accuracy'));
    expect(
      md,
      contains('![fig:Figure 5: Sensitivity to object characteristics'),
    );
    // 表格替换后仅剩 VLM 误标的 1 段（caption 非表样 → 保留 HTML）
    expect('<table'.allMatches(md).length, 0);
    // caption 文本段已被图片标签吸收，不再以独立段落重复出现
    expect(
      RegExp(
        r'^Figure 1: Object detection system overview',
        multiLine: true,
      ).hasMatch(md),
      isFalse,
    );
    expect(
      RegExp(
        r'^Table 1: Detection average precision',
        multiLine: true,
      ).hasMatch(md),
      isFalse,
    );
    expect(md, isNot(contains('](images/')), reason: '所有 zip 相对引用已改写');
    expect(
      RegExp(r'!\[\]\(file:///').allMatches(md).length,
      0,
      reason: '无题注和子图资源不进入阅读正文',
    );
  });

  test('reprocess: raw.md + manifest 重建 md，结果与 convert 一致', () async {
    final zip = await stageZip();
    final result = await MinerUResultConverter.instance.convert(
      pdfPath: pdfPath,
      zipFile: zip,
      title: 'Rich feature hierarchies',
    );

    final (mdPath, content) = await MinerUResultConverter.instance.reprocess(
      pdfPath: pdfPath,
      title: 'Rich feature hierarchies',
    );
    expect(mdPath, result.mdPath);
    expect(_stableMarkdown(content), _stableMarkdown(result.processedMarkdown));
  });

  test('DocExtractService.reprocessMarkdown 按标记分派到 MinerU 转化器', () async {
    final zip = await stageZip();
    final result = await MinerUResultConverter.instance.convert(
      pdfPath: pdfPath,
      zipFile: zip,
      title: 'Rich feature hierarchies',
    );

    final (mdPath, content) = await DocExtractService.instance
        .reprocessMarkdown(pdfPath: pdfPath, title: 'Rich feature hierarchies');
    expect(_stableMarkdown(content), _stableMarkdown(result.processedMarkdown));
    expect(mdPath, result.mdPath);
  });
}

String _stableMarkdown(String md) =>
    md.replaceAll(RegExp(r'generation_[^/\\]+'), 'generation');
