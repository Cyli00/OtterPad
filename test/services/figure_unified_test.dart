import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/doc_extract_service.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/utils/doc_paths.dart';
import 'package:otter_pad/services/document_structure.dart';
import 'package:otter_pad/services/extraction_artifacts.dart';
import 'package:otter_pad/services/figure_extract_service.dart';
import 'package:otter_pad/services/mineru_result_converter.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await FigureExtractService.instance.init();
    await pdfrxInitialize();
  });

  test('旧版单份产物迁移，双来源互不覆盖并可明确切换', () async {
    final dir = await Directory.systemTemp.createTemp('otter_sources_');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = p.join(dir.path, 'source.pdf');
    await Directory(DocPaths.figuresDir(pdf)).create();
    await File(DocPaths.json(pdf)).writeAsString('[]');
    await File(DocPaths.rawMd(pdf)).writeAsString('paddle raw');
    await File(DocPaths.figuresManifest(pdf)).writeAsString('{"figures":[]}');
    expect(await ExtractionArtifacts.availableSources(pdf), [
      DocExtractProvider.paddle,
    ]);
    await ExtractionArtifacts.publish(pdf, DocExtractProvider.mineru, {
      DocPaths.json(pdf): '{"_source":"mineru"}',
      DocPaths.rawMd(pdf): 'mineru raw',
      DocPaths.figuresManifest(pdf): '{"figures":[],"revision":1}',
    });
    expect(
      await ExtractionArtifacts.availableSources(pdf),
      DocExtractProvider.values,
    );
    expect(
      await File(DocPaths.json(pdf, source: 'paddleocr')).readAsString(),
      '[]',
    );
    expect(
      await File(DocPaths.rawMd(pdf, source: 'paddleocr')).readAsString(),
      'paddle raw',
    );
    final savedMinerU = await File(
      DocPaths.figuresManifest(pdf, source: 'mineru'),
    ).readAsString();
    await ExtractionArtifacts.publish(pdf, DocExtractProvider.paddle, {
      DocPaths.json(pdf): '[]',
      DocPaths.rawMd(pdf): 'paddle raw',
      DocPaths.figuresManifest(pdf): '{"figures":[],"revision":2}',
    });
    expect(
      await ExtractionArtifacts.activeSource(pdf),
      DocExtractProvider.paddle,
    );
    expect(
      await File(
        DocPaths.figuresManifest(pdf, source: 'mineru'),
      ).readAsString(),
      savedMinerU,
    );
    expect(
      (await ExtractionArtifacts.inputs(pdf, DocExtractProvider.mineru)).$1,
      DocPaths.json(pdf, source: 'mineru'),
    );
    await expectLater(
      DocExtractService.instance.reprocessMarkdown(pdfPath: pdf),
      throwsStateError,
    );
  });

  for (final reversed in [false, true]) {
    test('相邻页无全局组号仍匹配完整视觉簇，反向=$reversed', () {
      final images = [
        block('0', 'image', [100, 1000, 480, 1450]),
        block('1', 'chart', [500, 1000, 900, 1450]),
      ];
      final caption = [
        block('0', 'figure_title', [
          100,
          50,
          900,
          100,
        ], 'Figure 1. Complete panels.'),
      ];
      final pages = reversed
          ? [
              [
                block('0', 'figure_title', [
                  100,
                  1400,
                  900,
                  1450,
                ], 'Figure 1. Complete panels.'),
              ],
              [
                block('0', 'image', [100, 50, 480, 500]),
                block('1', 'chart', [500, 50, 900, 500]),
              ],
            ]
          : [images, caption];
      final figures = FigureExtractService.instance.findFigures(pages);
      expect(figures, hasLength(1));
      expect(figures.single.pairMethod, PairMethod.crossPage);
      expect(
        figures.single.blocks.where(
          (b) => b.blockLabel == 'image' || b.blockLabel == 'chart',
        ),
        hasLength(2),
      );
    });
  }

  test('跨页同组子图只产生一个图，两个页面可以重复 blockId', () {
    final figures = FigureExtractService.instance.findFigures([
      [
        block('0', 'image', [100, 1000, 480, 1450], '', 7),
        block('1', 'image', [500, 1000, 900, 1450], '', 7),
      ],
      [
        block(
          '0',
          'figure_title',
          [100, 50, 900, 100],
          'Figure 1. Complete panels.',
          7,
        ),
      ],
    ]);
    expect(figures, hasLength(1));
    expect(
      figures.single.blocks.where((b) => b.blockLabel == 'image'),
      hasLength(2),
    );
  });

  test('独立正文阻断跨页猜配', () {
    final figures = FigureExtractService.instance.findFigures([
      [
        block('i', 'image', [100, 900, 900, 1200]),
        block('t', 'text', [100, 1250, 900, 1400], 'Independent paragraph.'),
      ],
      [
        block('c', 'figure_title', [100, 50, 900, 100], 'Figure 1. Caption.'),
      ],
    ]);
    expect(figures, isEmpty);
  });

  test('所有 profile 均丢弃无题注图片', () {
    for (final profile in FigureExtractProfile.values) {
      expect(
        FigureExtractService.instance.findFigures([
          [
            block('i', 'image', [100, 100, 900, 1200]),
          ],
        ], profile: profile),
        isEmpty,
      );
    }
  });

  test('跨页正文替换清理真实题注来源，不误删同号正文', () {
    const caption = 'Figure 1. Complete panels.';
    const reference = 'Figure 1. This paragraph discusses the result.';
    final json = jsonEncode([
      {
        'markdown': {'text': '![](img_100_1000_900_1450.jpg)'},
        'prunedResult': {
          'parsing_res_list': [
            block('0', 'image', [100, 1000, 900, 1450]).toJson(),
          ],
        },
      },
      {
        'markdown': {'text': '$caption\n\n$reference'},
        'prunedResult': {
          'parsing_res_list': [
            block('0', 'figure_title', [100, 50, 900, 100], caption).toJson(),
            block('1', 'text', [100, 200, 900, 300], reference).toJson(),
          ],
        },
      },
    ]);
    final figure = FigureManifestEntry.fromJson({
      'id': 'cross',
      'img': 'C:/test/figure.png',
      'figure_title': caption,
      'page_idx': 0,
      'block_ids': ['0'],
      'pair_method': 'crossPage',
      'caption_refs': [
        {'page_idx': 1, 'block_id': '0', 'text': caption},
      ],
    });
    final md = DocExtractService.replaceFigureRegions(
      jsonContent: json,
      figures: [figure],
      mdDir: 'C:/test',
    );
    expect(md.split(caption), hasLength(2));
    expect(md, contains(reference));
    expect(md, contains(figure.markdownAnchor));
  });

  test(
    'layout and Paddle preserve equivalent ownership and 144 DPI geometry',
    () {
      final mineru = DocumentStructure.fromMinerULayout(_layout());
      final paddle = DocumentStructure.parse(jsonEncode(mineru.toJson()));
      expect(mineru.pages.single.pageSize, [1200.0, 1600.0]);
      expect(paddle.pages.single.blocks.first.blockBbox, [
        100.0,
        400.0,
        500.0,
        600.0,
      ]);
      List<FigureSegment> find(DocumentStructure s) => FigureExtractService
          .instance
          .findFigures(s.pages.map((p) => p.blocks).toList());
      final a = find(mineru).single;
      final b = find(paddle).single;
      expect(a.captionText, 'Composite results');
      expect(a.blocks.map((b) => b.blockId), b.blocks.map((b) => b.blockId));
      expect(a.blocks.where((b) => b.blockLabel == 'image'), hasLength(2));
      expect(a.blocks.any((b) => b.blockContent == '(a)'), isTrue);
    },
  );

  test('v2 scales x and y separately, and never invents a caption bbox', () {
    final data = [
      [
        {
          'type': 'image',
          'bbox': [100, 200, 500, 600],
          'content': {
            'image_source': {'path': 'images/a.jpg'},
            'image_caption': [
              {'content': 'Results'},
            ],
          },
        },
      ],
    ];
    final s = DocumentStructure.fromMinerUV2(
      data,
      pageSizes: [
        [600, 800],
      ],
    );
    expect(s.pages.single.blocks.first.blockBbox, [120, 320, 600, 960]);
    expect(s.pages.single.blocks.last.blockBbox, isEmpty);
    expect(
      DocumentStructure.fromMinerUV2(data).pages.single.blocks.first.blockBbox,
      isEmpty,
    );
  });

  test(
    'equally plausible captions abstain; an intervening paragraph blocks association',
    () {
      final s = FigureExtractService.instance;
      final image = _b('image', 'image', [100, 200, 300, 400]);
      final ambiguous = s.findFigures([
        [
          _b('a', 'figure_title', [100, 160, 300, 180], 'Figure 1. Before'),
          image,
          _b('b', 'figure_title', [100, 420, 300, 440], 'Figure 2. After'),
        ],
      ], profile: FigureExtractProfile.paper);
      expect(ambiguous, isEmpty);
      final blocked = s.findFigures([
        [
          image,
          _b('body', 'text', [100, 410, 300, 450], 'Independent paragraph.'),
          _b('cap', 'figure_title', [100, 460, 300, 490], 'Figure 1. Caption'),
        ],
      ], profile: FigureExtractProfile.paper);
      expect(blocked, isEmpty);
    },
  );

  test(
    'same caption numbers at different locations retain independent identities',
    () {
      final blocks = [
        _b('i1', 'image', [0, 0, 150, 150]),
        _b('c1', 'figure_title', [0, 160, 150, 190], 'Figure 1. First'),
        _b('i2', 'image', [400, 0, 550, 150]),
        _b('c2', 'figure_title', [400, 160, 550, 190], 'Figure 1. Second'),
      ];
      final figures = FigureExtractService.instance.findFigures([blocks]);
      expect(figures, hasLength(2));
      expect(
        figures
            .map(
              (s) => FigureManifestEntry.identity(
                s.pageIndex,
                s.blocks.map((b) => b.blockId),
              ),
            )
            .toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'missing first table image does not shift the second table, in either provider',
    () {
      const raw =
          '<table><tr><td>FIRST</td></tr></table>\n\n'
          '<table><tr><td>SECOND</td></tr></table>\n\nTable 2. Results';
      const entry = FigureManifestEntry(
        id: 'second',
        imagePath: 'C:/test/second.png',
        captionText: 'Table 2. Results',
        pageIndex: 0,
        blockIds: ['t2', 'c2'],
        kind: 'table',
        sourceImageNames: ['second.jpg'],
      );
      final mineru = MinerUResultConverter.buildReaderMarkdown(
        raw,
        [entry],
        assets: {},
        tableSources: [null, 'second.jpg'],
      );
      final paddle = DocExtractService.replaceFigureRegions(
        jsonContent: jsonEncode([
          {
            'markdown': {'text': raw},
            'prunedResult': {
              'parsing_res_list': [
                _b('t1', 'table', [
                  0,
                  0,
                  200,
                  100,
                ], '<table>FIRST</table>').toJson(),
                _b('t2', 'table', [
                  0,
                  200,
                  200,
                  300,
                ], '<table>SECOND</table>').toJson(),
                _b('c2', 'figure_title', [
                  0,
                  310,
                  200,
                  330,
                ], 'Table 2. Results').toJson(),
              ],
            },
          },
        ]),
        figures: [entry],
        mdDir: 'C:/test',
      );
      for (final md in [mineru, paddle]) {
        expect(md, contains('<td>FIRST</td>'));
        expect(md, isNot(contains('<td>SECOND</td>')));
        expect(md, contains(entry.markdownAnchor));
      }
    },
  );

  test(
    'body references starting with the same figure number are not deleted',
    () {
      const reference = 'Figure 1. This is a separate discussion in the body.';
      final blocks = [
        _b('i', 'image', [0, 0, 100, 100]),
        _b('c', 'figure_title', [
          0,
          110,
          100,
          130,
        ], 'Figure 1. Actual caption.'),
      ];
      final md = DocExtractService.replaceFigureRegions(
        jsonContent: jsonEncode([
          {
            'markdown': {
              'text':
                  '![](img_0_0_100_100.jpg)\n\nFigure 1. Actual caption.\n\n'
                  'Intervening paragraph.\n\n$reference',
            },
            'prunedResult': {
              'parsing_res_list': blocks.map((b) => b.toJson()).toList(),
            },
          },
        ]),
        figures: [
          const FigureManifestEntry(
            imagePath: 'C:/test/figure.png',
            captionText: 'Figure 1. Actual caption.',
            pageIndex: 0,
            blockIds: ['i', 'c'],
          ),
        ],
        mdDir: 'C:/test',
      );
      expect(md, contains(reference));
    },
  );

  test(
    'native PDF crop restores both panels and the external panel label even with corrupt source images',
    () async {
      final dir = await Directory.systemTemp.createTemp('otter_unified_pdf_');
      try {
        final pdf = File(p.join(dir.path, 'source.pdf'));
        await pdf.writeAsBytes(_pdf());
        final archive = Archive()
          ..addFile(
            ArchiveFile.string(
              'full.md',
              '![](images/a.jpg)\n\n(a)\n\n'
                  '![](images/b.jpg)\n\nComposite results\n',
            ),
          )
          ..addFile(ArchiveFile.string('layout.json', jsonEncode(_layout())))
          ..addFile(ArchiveFile.string('test_content_list_v2.json', '[[]]'))
          ..addFile(ArchiveFile.string('images/a.jpg', 'broken image'))
          ..addFile(ArchiveFile.string('images/b.jpg', 'broken image'));
        final zip = File(p.join(dir.path, 'result.zip'));
        await zip.writeAsBytes(ZipEncoder().encode(archive));
        final result = await MinerUResultConverter.instance.convert(
          pdfPath: pdf.path,
          zipFile: zip,
        );
        final figures = (await FigureExtractService.loadManifest(pdf.path))!;
        final figure = FigureManifestEntry.forDisplay(figures).single;
        expect(figure.sourceImageNames, containsAll(['a.jpg', 'b.jpg']));
        expect(figure.cropBbox![1], lessThanOrEqualTo(380));
        expect(figure.cropBbox![2], greaterThanOrEqualTo(1000));
        expect(figure.cropBbox![3], lessThan(640)); // no main caption in image
        expect(
          RegExp(
            r'^\(a\)$',
            multiLine: true,
          ).hasMatch(result.processedMarkdown),
          isFalse,
        );
        expect(result.processedMarkdown, contains(figure.markdownAnchor));
        final codec = await ui.instantiateImageCodec(
          await File(figure.imagePath).readAsBytes(),
        );
        final frame = await codec.getNextFrame();
        final pixels = (await frame.image.toByteData())!.buffer.asUint8List();
        var red = 0, blue = 0, black = 0;
        for (var i = 0; i < pixels.length; i += 4) {
          if (pixels[i] > 200 && pixels[i + 1] < 30 && pixels[i + 2] < 30) {
            red++;
          }
          if (pixels[i] < 30 && pixels[i + 1] < 30 && pixels[i + 2] > 200) {
            blue++;
          }
          if (pixels[i] < 30 && pixels[i + 1] < 30 && pixels[i + 2] < 30) {
            black++;
          }
        }
        expect(red, greaterThan(1000));
        expect(blue, greaterThan(1000));
        expect(black, greaterThan(10)); // label outside both source image boxes
        frame.image.dispose();
        codec.dispose();
        final before = await File(
          p.join(dir.path, 'extract.md'),
        ).readAsString();
        final invalid = File(p.join(dir.path, 'invalid.zip'));
        await invalid.writeAsBytes(
          ZipEncoder().encode(
            Archive()..addFile(ArchiveFile.string('full.md', 'invalid')),
          ),
        );
        await expectLater(
          MinerUResultConverter.instance.convert(
            pdfPath: pdf.path,
            zipFile: invalid,
          ),
          throwsFormatException,
        );
        expect(
          await File(p.join(dir.path, 'extract.md')).readAsString(),
          before,
        );
        expect(await File(figure.imagePath).exists(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'metadata publication restores previous files after a rename failure',
    () async {
      final dir = await Directory.systemTemp.createTemp('otter_publish_');
      try {
        final first = File(p.join(dir.path, 'first.md'));
        await first.writeAsString('previous');
        await expectLater(
          publishExtractionArtifacts({
            first.path: 'new',
            p.join(dir.path, 'absent', 'second.md'): 'new',
          }),
          throwsA(isA<FileSystemException>()),
        );
        expect(await first.readAsString(), 'previous');
        expect(dir.listSync().whereType<Directory>(), isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}

LayoutBlock _b(String id, String label, List<num> box, [String text = '']) =>
    LayoutBlock(
      blockId: id,
      blockLabel: label,
      blockBbox: box.map((v) => v.toDouble()).toList(),
      rawBbox: box,
      blockContent: text,
    );

Map<String, dynamic> _layout() => {
  'pdf_info': [
    {
      'page_idx': 0,
      'page_size': [600, 800],
      'para_blocks': [
        {
          'type': 'image',
          'blocks': [
            for (final body in [('a.jpg', 50, 250), ('b.jpg', 300, 500)])
              {
                'type': 'image_body',
                'bbox': [body.$2, 200, body.$3, 300],
                'lines': [
                  {
                    'spans': [
                      {'type': 'image', 'image_path': body.$1},
                    ],
                  },
                ],
              },
            {
              'type': 'text',
              'bbox': [55, 190, 75, 200],
              'lines': [
                {
                  'spans': [
                    {'content': '(a)'},
                  ],
                },
              ],
            },
            {
              'type': 'image_caption',
              'bbox': [50, 320, 500, 350],
              'lines': [
                {
                  'spans': [
                    {'content': 'Composite results'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};

List<int> _pdf() {
  const commands =
      '1 0 0 rg 50 500 200 100 re f\n0 0 1 rg 300 500 200 100 re f\n'
      '0 0 0 rg BT /F1 12 Tf 55 602 Td (\\(a\\)) Tj ET\n'
      'BT /F1 12 Tf 50 465 Td (Composite results) Tj ET\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${commands.length} >>\nstream\n${commands}endstream',
  ];
  var pdf = '%PDF-1.4\n';
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final xref = pdf.length;
  pdf += 'xref\n0 6\n0000000000 65535 f \n';
  for (final offset in offsets) {
    pdf += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  pdf += 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
  return ascii.encode(pdf);
}

LayoutBlock block(
  String id,
  String label,
  List<num> box, [
  String text = '',
  int? global,
]) => LayoutBlock(
  blockId: id,
  blockLabel: label,
  blockBbox: box.map((v) => v.toDouble()).toList(),
  rawBbox: box,
  blockContent: text,
  globalGroupId: global,
);
