import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/document_structure.dart';
import 'package:otter_pad/services/figure_extract_service.dart';
import 'package:path/path.dart' as p;

import '../support/local_library.dart';

/// 真实 extract.json 集成测试——验证 groupId/blockOrder 解析正确、
/// figure 提取回归不破坏。
///
/// 依赖本机数据文件（APPDATA / OTTERPAD_TEST_LIBRARY），CI 上自动 skip。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final doc1 = localLibraryDoc('c2763bc1-5aad-d64c-3ab7-a5d418c1a817');
  final doc2 = localLibraryDoc('19071c61-e86e-ec56-6337-46df5e6a84a3');

  final doc1Exists =
      doc1 != null && File(p.join(doc1, 'extract.json')).existsSync();
  final doc2Exists =
      doc2 != null && File(p.join(doc2, 'extract.json')).existsSync();

  setUpAll(() async {
    await FigureExtractService.instance.init();
  });

  // ─── Level 1: DocumentStructure 字段解析 ──────────────────

  test(
    'DocumentStructure.parse 正确读取 groupId/blockOrder',
    skip: doc1Exists ? null : '需要本机数据文件',
    () async {
      final json = await File(p.join(doc1!, 'extract.json')).readAsString();
      final structure = DocumentStructure.parse(json);

      expect(structure.pages.length, 32);

      // 第一页应有 block，且 groupId 已解析（即使都是独立值）
      final firstPage = structure.pages.first;
      expect(firstPage.blocks, isNotEmpty);

      final hasGroupId = firstPage.blocks.any((b) => b.groupId != null);
      expect(hasGroupId, isTrue, reason: 'PaddleOCR 应提供 group_id');

      // 验证 groupId 均为非负整数
      for (final b in firstPage.blocks) {
        if (b.groupId != null) {
          expect(b.groupId, greaterThanOrEqualTo(0));
        }
      }
    },
  );

  // ─── Level 2+3 回归: 中文光学教材 (c2763bc1) ─────────────

  test(
    '中文光学教材: findFigures 产出 43 个 figure (回归)',
    skip: doc1Exists ? null : '需要本机数据文件',
    () async {
      final json = await File(p.join(doc1!, 'extract.json')).readAsString();
      final structure = DocumentStructure.parse(json);

      final pages = structure.pages.map((p) => p.blocks).toList();
      final markdowns = structure.pages.map((p) => p.markdown).toList();

      final segments = FigureExtractService.instance.findFigures(
        pages,
        markdowns: markdowns,
      );

      // 45 = 原 43 + label-only caption 续接修复后新拆出的 2 个独立 figure
      expect(segments.length, 45);

      final captionNames = segments.map((s) => s.captionName).toSet();
      expect(captionNames, contains('图3-11'));
      expect(captionNames, contains('图4-1'));
      expect(captionNames.any((n) => n.startsWith('表3-1')), isTrue);
    },
  );

  // ─── Level 2+3 回归: 英文神经科学论文 (19071c61) ──────────

  test(
    '英文神经科学论文: findFigures 产出 6 个 figure (回归)',
    skip: doc2Exists ? null : '需要本机数据文件',
    () async {
      final json = await File(p.join(doc2!, 'extract.json')).readAsString();
      final structure = DocumentStructure.parse(json);

      final pages = structure.pages.map((p) => p.blocks).toList();
      final markdowns = structure.pages.map((p) => p.markdown).toList();

      final segments = FigureExtractService.instance.findFigures(
        pages,
        markdowns: markdowns,
      );

      expect(segments.length, 6);

      final captionNames = segments.map((s) => s.captionName).toSet();
      expect(captionNames, contains('Figure_1'));
      expect(captionNames, contains('Figure_5'));
      expect(captionNames, contains('Box_3'));
    },
  );
}
