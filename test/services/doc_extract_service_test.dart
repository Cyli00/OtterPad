import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/doc_extract_service.dart';
import 'package:otter_pad/services/figure_extract_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FigureExtractService.instance.init();
  });

  test('FigureExtractService 合并换行 figure_title 与长子图说明', () {
    final service = FigureExtractService.instance;
    final segments = service.findFigures([
      [
        _layoutBlock('2', 'image', [182, 197, 634, 777]),
        _layoutBlock('3', 'image', [638, 203, 1040, 783]),
        _layoutBlock('4', 'figure_title', [
          114,
          807,
          711,
          827,
        ], 'Figure 2. Optical implant assemblies.'),
        _layoutBlock(
          '5',
          'figure_title',
          [116, 813, 1100, 862],
          'Figure 2. Optical implant assemblies.\n\n(A) Cartoon visualizations of the assemblies.',
        ),
        _layoutBlock('6', 'vision_footnote', [
          115,
          857,
          1103,
          914,
        ], '(B) Schematic illustrating axial magnification.'),
      ],
    ]);

    expect(segments, hasLength(1));
    expect(
      segments.single.captionText,
      startsWith('Figure 2. Optical implant assemblies. (A)'),
    );
    expect(segments.single.captionText, contains('(B) Schematic'));
    expect(segments.single.captionText, isNot(contains('\n')));
  });

  test('FigureExtractService markdown 兜底不吞掉 A 开头正文', () {
    final service = FigureExtractService.instance;
    final segments = service.findFigures(
      [
        [
          _layoutBlock('1', 'image', [101, 196, 732, 1196]),
        ],
      ],
      markdowns: [
        [
          '<div style="text-align: center;"><img src="imgs/img_in_image_box_101_196_732_1196.jpg" alt="Image" width="52%" /></div>',
          '',
          'Figure 1. Deep-brain fluorescence recording methods.',
          '',
          '(A) Fiber photometry enables bulk fluorescence recordings.',
          '',
          '(B) Control isosbestic and GCaMP6s signals.',
          '',
          'A crucial consideration for designing behavioral experiments remains in the body.',
        ].join('\n'),
      ],
    );

    expect(segments, hasLength(1));
    expect(segments.single.captionText, contains('(A) Fiber photometry'));
    expect(segments.single.captionText, contains('(B) Control'));
    expect(
      segments.single.captionText,
      isNot(contains('A crucial consideration')),
    );
  });

  test('replaceFigureRegions 清理多行 figure_title 与子图说明', () {
    final jsonContent = jsonEncode([
      {
        'markdown': {
          'text': [
            '<div style="text-align: center;"><img src="imgs/img_in_image_box_182_197_634_777.jpg" alt="Image" width="37%" /></div>',
            '',
            '<div style="text-align: center;"><img src="imgs/img_in_image_box_638_203_1040_783.jpg" alt="Image" width="33%" /></div>',
            '',
            '<div style="text-align: center;">Figure 2. Optical implant assemblies and GRIN lens axial magnification properties</div>',
            '',
            '<div style="text-align: center;">Figure 2. Optical implant assemblies and GRIN lens axial magnification properties  (A) Cartoon visualizations of the optical implant assemblies.</div>',
            '',
            '(B) Schematic illustrating axial magnification properties.',
            '',
            'A crucial consideration should remain as body text.',
            '',
            'GRIN lenses suffer primarily from spherical aberrations.',
          ].join('\n'),
        },
        'prunedResult': {
          'parsing_res_list': [
            _block(2, 'image', [182, 197, 634, 777], ''),
            _block(3, 'image', [638, 203, 1040, 783], ''),
            _block(
              4,
              'figure_title',
              [114, 807, 711, 827],
              'Figure 2. Optical implant assemblies and GRIN lens axial magnification properties',
            ),
            _block(
              5,
              'figure_title',
              [116, 813, 1100, 862],
              'Figure 2. Optical implant assemblies and GRIN lens axial magnification properties\n\n(A) Cartoon visualizations of the optical implant assemblies.',
            ),
            _block(
              6,
              'vision_footnote',
              [115, 857, 1103, 914],
              '(B) Schematic illustrating axial magnification properties.',
            ),
          ],
        },
      },
    ]);

    final result = DocExtractService.replaceFigureRegions(
      jsonContent: jsonContent,
      figures: const [
        FigureManifestEntry(
          imagePath: r'C:\tmp\Figure_2.png',
          captionText:
              'Figure 2. Optical implant assemblies and GRIN lens axial magnification properties\n\n(A) Cartoon visualizations of the optical implant assemblies. (B) Schematic illustrating axial magnification properties.',
          pageIndex: 0,
          blockIds: ['5', '2', '3', '6'],
        ),
      ],
      mdDir: r'C:\tmp',
    );

    final imageLines = result
        .split('\n')
        .where((line) => line.startsWith('![fig:'))
        .toList();
    expect(imageLines, hasLength(1));
    expect(imageLines.single, contains('(A) Cartoon visualizations'));
    expect(imageLines.single, contains('(B) Schematic'));
    expect(imageLines.single, isNot(contains('\n')));
    expect(
      result,
      isNot(contains('<div style="text-align: center;">Figure 2')),
    );
    expect(
      result.split('\n').where((line) => line.startsWith('(B) Schematic')),
      isEmpty,
    );
    expect(result, contains('A crucial consideration should remain'));
    expect(result, contains('GRIN lenses suffer primarily'));
  });

  test('replaceFigureRegions 匿名 entry 独立还原到 Markdown', () {
    final jsonContent = jsonEncode([
      {
        'markdown': {
          'text': [
            '<div style="text-align: center;"><img src="imgs/img_in_image_box_100_200_400_500.jpg" alt="Image" width="37%" /></div>',
            '',
            'Adjacent body text before the anonymous visual.',
            '',
            'Another body paragraph that must remain.',
          ].join('\n'),
        },
        'prunedResult': {
          'parsing_res_list': [
            _block(7, 'image', [100, 200, 400, 500], ''),
          ],
        },
      },
    ]);

    // 匿名 visual（无 caption）以独立图片写回 Markdown，不吞掉相邻正文。
    final result = DocExtractService.replaceFigureRegions(
      jsonContent: jsonContent,
      figures: const [
        FigureManifestEntry(
          imagePath: r'C:\tmp\fig0.png',
          captionText: '',
          pageIndex: 0,
          blockIds: ['7'],
          pairMethod: 'ai_fix',
          captionSource: 'none',
        ),
      ],
      mdDir: r'C:\tmp',
    );

    final imageLines = result
        .split('\n')
        .where((line) => line.startsWith('![fig:'))
        .toList();
    expect(imageLines, hasLength(1));
    expect(imageLines.single, contains('file:///'));
    expect(imageLines.single, contains('fig0.png'));
    expect(imageLines.single, isNot(contains('img_in_image_box')));
    // 原 API 图片行被替换，相邻正文原样保留。
    expect(result, isNot(contains('img_in_image_box')));
    expect(result, contains('Adjacent body text before the anonymous visual.'));
    expect(result, contains('Another body paragraph that must remain.'));
  });
}

LayoutBlock _layoutBlock(
  String id,
  String label,
  List<int> bbox, [
  String content = '',
]) {
  return LayoutBlock(
    blockId: id,
    blockLabel: label,
    blockBbox: bbox.map((v) => v.toDouble()).toList(),
    blockContent: content,
  );
}

Map<String, dynamic> _block(
  int id,
  String label,
  List<int> bbox,
  String content,
) {
  return {
    'block_id': id,
    'block_label': label,
    'block_bbox': bbox,
    'block_content': content,
  };
}
