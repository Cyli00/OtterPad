import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/figure_extract_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FigureExtractService.instance.init();
  });

  test('裁剪框只取 image/chart/table，忽略 vision_footnote 子图注', () {
    final service = FigureExtractService.instance;
    // 模拟 Figure_4 排版:image+chart 在上半页,主图注与 vision_footnote 子图注
    // 在下半页. 旧实现会把子图注高度也算进裁剪框.
    final segment = [
      _block('a', 'figure_title', [114, 1019, 751, 1040],
          'Figure 4. Optical paths.'),
      _block('b', 'image', [223, 214, 644, 662]),
      _block('c', 'chart', [186, 691, 624, 981]),
      _block('d', 'vision_footnote', [114, 1055, 665, 1072],
          '(B) 2-photon optical path.'),
      _block('e', 'vision_footnote', [115, 1069, 1100, 1093],
          '(C and D) ...'),
    ];

    final bbox = service.computeMergedBbox(segment);

    // 期望:crop 紧贴视觉块(y 186..981),不含 caption (y=1019+) 也不含
    // vision_footnote (y=1055+).
    expect(bbox, [186.0, 214.0, 644.0, 981.0]);
  });

  test('同名多个 caption mention 自动选最长内容', () {
    final service = FigureExtractService.instance;
    // PaddleOCR 把同一行 caption 拆成两个重叠的 figure_title block(短标签 + 完整)
    // inventory 阶段同 captionName 选内容最长者.
    final blocks = [
      _block('2', 'image', [182, 197, 634, 777]),
      _block('3', 'image', [638, 203, 1040, 783]),
      _block('4', 'figure_title', [114, 807, 711, 827],
          'Figure 2. Optical implant assemblies.'),
      _block('5', 'figure_title', [116, 813, 1100, 862],
          'Figure 2. Optical implant assemblies. (A) Cartoon visualizations of the assemblies.'),
      _block('6', 'vision_footnote', [115, 857, 1103, 914], '(B) Schematic ...'),
    ];

    final segments = service.findFigures([blocks]);

    expect(segments.length, 1);
    // 用更长的 caption 文本(来自 block 5)
    expect(segments.single.captionText,
        startsWith('Figure 2. Optical implant assemblies. (A)'));
    expect(segments.single.captionName, 'Figure_2');
    // 视觉块 + vision_footnote 都进 blocks(用于 markdown 替换清理)
    final ids = segments.single.blocks.map((b) => b.blockId).toSet();
    expect(ids, containsAll(['2', '3', '6']));
  });

  test('markdown 行作为 caption 来源——parsing_res_list 漏掉时兜底', () {
    final service = FigureExtractService.instance;
    // Page 1 现场:image 块存在但 caption 在 parsing_res_list 里 content 为空,
    // 而 markdown.text 第 17 行有 "Figure 1." 完整文字.
    final pages = [
      [
        _block('1', 'image', [101, 196, 732, 1196]),
        // 空内容 block——以前需要 _fillEmptyAnchorsFromMarkdown 救场
        _block('2', 'text', [763, 199, 1088, 235], ''),
      ],
    ];
    final markdowns = [
      'body text\n\nFigure 1. Deep-brain fluorescence recording methods.\n\n(A) Fiber photometry.',
    ];

    final segments = service.findFigures(pages, markdowns: markdowns);

    expect(segments.length, 1);
    expect(segments.single.captionName, 'Figure_1');
    expect(segments.single.captionText,
        startsWith('Figure 1. Deep-brain fluorescence'));
    // image 块进 blocks 列表
    expect(segments.single.blocks.any((b) => b.blockId == '1'), true);
  });

  test('text-label block 内容像 caption 也算锚点(原 _recoverMissingAnchors 场景)', () {
    final service = FigureExtractService.instance;
    // caption 被 OCR 错标为 text 而非 figure_title——只要内容匹配正则就该被采纳
    final pages = [
      [
        _block('1', 'image', [100, 100, 700, 600]),
        _block('2', 'text', [100, 620, 700, 660],
            'Figure 3. A correctly identified caption.'),
      ],
    ];

    final segments = service.findFigures(pages);
    expect(segments.length, 1);
    expect(segments.single.captionName, 'Figure_3');
    expect(segments.single.blocks.first.blockId, '2');
  });

  test('匿名兜底:无 caption 的 image cluster 仍被裁剪', () {
    final service = FigureExtractService.instance;
    final pages = [
      [_block('1', 'image', [101, 196, 732, 1196])],
    ];

    final segments = service.findFigures(pages, markdowns: ['']);
    expect(segments.length, 1);
    expect(segments.single.captionName, isEmpty);
    expect(segments.single.captionText, isEmpty);
    expect(segments.single.blocks.single.blockId, '1');
  });

  test('匿名兜底拒绝纯 table 孤儿(防 sidebar 误识别)', () {
    final service = FigureExtractService.instance;
    final pages = [
      [_block('1', 'table', [100, 100, 700, 700])],
    ];

    final segments = service.findFigures(pages, markdowns: ['']);
    expect(segments, isEmpty);
  });

  test('caption 上方大段空白(漏检子图) → 向上扩展裁剪框', () {
    // 模拟 Figure 5 现场(完整 5 chart): page 顶部 header,中间 y=163..605 是
    // PaddleOCR 漏检的 panel A 区,然后是 chart 块 (panels B/C/D),最下方是
    // caption. visualUnion 横向 [188, 1029] 同时覆盖左 header_image(right=286)
    // 与右 header(left=978) → max blocker bottom=163 → newTop=163+8=171.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('h1', 'header_image', [117, 100, 286, 135]),
      _block('h2', 'header', [978, 98, 1104, 163], 'Neuron Primer'),
      _block('2', 'chart', [193, 622, 524, 782]),
      _block('3', 'chart', [520, 627, 680, 780]),
      _block('4', 'chart', [671, 605, 1029, 779]),
      _block('5', 'chart', [188, 785, 659, 1070]),
      _block('6', 'chart', [666, 798, 993, 1065]),
      _block('7', 'figure_title', [115, 1099, 783, 1118],
          'Figure 5. Calcium imaging pipeline.'),
      _block('12', 'text', [114, 1318, 601, 1382], 'mean...'),
    ];
    final segment = pageBlocks
        .where((b) => {'2', '3', '4', '5', '6', '7'}.contains(b.blockId))
        .toList();

    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);

    expect(bbox[0], 188.0);
    expect(bbox[1], 171.0);
    expect(bbox[2], 1029.0);
    expect(bbox[3], 1070.0);
  });

  test('caption 紧贴上方段落 → 不扩展(gap 太小)', () {
    // gap = 605 - 580 = 25 < 80px 阈值,不应扩展.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('1', 'text', [100, 200, 1000, 580], 'preceding paragraph'),
      _block('2', 'chart', [193, 605, 1029, 1070]),
      _block('3', 'figure_title', [115, 1099, 783, 1118],
          'Figure 5. Calcium imaging pipeline.'),
    ];
    final segment = pageBlocks
        .where((b) => {'2', '3'}.contains(b.blockId))
        .toList();

    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);
    expect(bbox[1], 605.0);
  });

  test('双栏 layout: 邻栏文字不应限制扩展', () {
    // left 栏 figure 上方完全空白; right 栏全是 paragraph 文字.
    // 邻栏块横向无 overlap,blocker 集合应为空,扩展到 0+margin=8.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      // 右栏满铺段落 (不该作为 left 栏 figure 的 blocker)
      _block('r1', 'text', [610, 200, 1100, 800], 'right column text'),
      // 左栏 figure (left=100, right=580)
      _block('1', 'chart', [100, 700, 580, 1000]),
      _block('2', 'figure_title', [100, 1020, 580, 1040],
          'Figure 1. Left column.'),
    ];
    final segment = pageBlocks
        .where((b) => {'1', '2'}.contains(b.blockId))
        .toList();

    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);
    expect(bbox[0], 100.0);
    expect(bbox[1], 8.0); // 上方无 blocker → 0 + margin
    expect(bbox[2], 580.0);
    expect(bbox[3], 1000.0);
  });

  test('gap 占比过小 → 不扩展(防止误伤段落)', () {
    // gap=200, visualHeight=1000, ratio=0.2 < 0.30 → 不扩展.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('1', 'text', [100, 100, 1000, 200], 'header line'),
      _block('2', 'chart', [100, 400, 1000, 1400]),
      _block('3', 'figure_title', [100, 1420, 800, 1440],
          'Figure 1. Tall figure.'),
    ];
    final segment = pageBlocks
        .where((b) => {'2', '3'}.contains(b.blockId))
        .toList();

    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);
    expect(bbox[1], 400.0); // 不扩展
  });

  test('连续底部图注不会把后一张图吸到前一张', () {
    final service = FigureExtractService.instance;
    final blocks = [
      _block('1', 'figure_title', [320, 91, 345, 110], '(a)'),
      _block('2', 'chart', [307, 100, 665, 439]),
      _block('3', 'figure_title', [688, 89, 712, 109], '(b)'),
      _block('4', 'chart', [674, 108, 1036, 436]),
      _block('5', 'figure_title', [
        305,
        459,
        1106,
        625,
      ], 'Figure 6. Size correlations.'),
      _block('6', 'figure_title', [309, 656, 335, 678], '(a)'),
      _block('7', 'figure_title', [670, 656, 697, 679], '(b)'),
      _block('8', 'image', [309, 674, 664, 1008]),
      _block('9', 'chart', [665, 661, 1031, 788]),
      _block('10', 'chart', [673, 806, 1033, 1031]),
      _block('11', 'figure_title', [
        305,
        1052,
        1082,
        1095,
      ], 'Figure 7. Average fluorescence recording.'),
      _block('12', 'table', [310, 1130, 1099, 1338]),
      _block('13', 'figure_title', [
        307,
        1353,
        699,
        1376,
      ], 'Table 1. Information about the analyzed recordings.'),
    ];

    final segments = service.findFigureSegments(blocks);

    expect(_idsForCaption(segments, 'Figure 6'), containsAllInOrder(['5']));
    expect(_idsForCaption(segments, 'Figure 6'),
        containsAll(['1', '2', '3', '4']));
    expect(_idsForCaption(segments, 'Figure 7'), containsAllInOrder(['11']));
    expect(_idsForCaption(segments, 'Figure 7'),
        containsAll(['6', '7', '8', '9', '10']));
    expect(_idsForCaption(segments, 'Table 1'), ['13', '12']);
  });
}

LayoutBlock _block(
  String id,
  String label,
  List<double> bbox, [
  String content = '',
]) {
  return LayoutBlock(
    blockId: id,
    blockLabel: label,
    blockBbox: bbox,
    blockContent: content,
  );
}

List<String> _idsForCaption(
  List<List<LayoutBlock>> segments,
  String captionPrefix,
) {
  final segment = segments.singleWhere(
    (segment) =>
        segment.any((block) => block.blockContent.startsWith(captionPrefix)),
  );
  return segment.map((block) => block.blockId).toList();
}
