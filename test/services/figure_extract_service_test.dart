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

  test('无 caption 的 image cluster 被丢弃(防误识别图标/装饰图)', () {
    // 与下一条"纯 table 孤儿"语义对齐: caption 召回失败时,视觉簇宁可漏也不要错.
    // 后续 PR-4 (Stage D + inline reference) 会用正文引用做弱兜底,
    // 替代旧的"无 caption 也产出匿名 segment"路线.
    final service = FigureExtractService.instance;
    final pages = [
      [_block('1', 'image', [101, 196, 732, 1196])],
    ];

    final segments = service.findFigures(pages, markdowns: ['']);
    expect(segments, isEmpty);
  });

  test('纯 table 孤儿同样被丢弃(防 sidebar 误识别)', () {
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

  test('caption 在 figure 上方(direction=below) → 向下扩展裁剪框', () {
    // 罕见现场:caption "Figure X." 出现在 figure 之上,figure 视觉块在 caption
    // 下方 + 漏检了下半部分.direction inference 看到 caption 下方 visual height
    // 远大于上方 → below,沿下方扩展.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('cap', 'figure_title', [115, 200, 783, 220],
          'Figure 5. Caption on top.'),
      // 已检出的视觉块在 caption 下方紧邻 (panel A 被检出)
      _block('v1', 'chart', [193, 250, 524, 410]),
      _block('v2', 'chart', [520, 255, 680, 408]),
      // 漏检的 panel B/C/D 在 y=410..1300 范围 (无 block) - 这是测试要扩展的空白
      // 下方 blocker: 段落
      _block('p1', 'text', [114, 1350, 1100, 1450], 'subsequent paragraph'),
    ];
    final segment = pageBlocks
        .where((b) => {'cap', 'v1', 'v2'}.contains(b.blockId))
        .toList();

    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);

    // visualUnion = [193, 250, 680, 410]; height=160
    // direction=below (caption.bottom=220 < visual.top=250, 视觉块都在 caption 下方)
    // 下方最近 blocker = text.top=1350, gap=1350-410=940, gap/height=940/160=5.875
    // newBottom = 1350 - 8 = 1342
    expect(bbox[0], 193.0);
    expect(bbox[1], 250.0);
    expect(bbox[2], 680.0);
    expect(bbox[3], 1342.0);
  });

  test('column detection: caption 横跨双栏 → 整页 column', () {
    // 双栏论文中 caption 横跨整页,figure 也横跨两栏.
    // 上方 blocker 应包括左右两栏的 paragraph/header.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      // 左右两栏各 3 段(足够 detection 判双栏)
      _block('L1', 'text', [100, 200, 590, 300], 'L1'),
      _block('L2', 'text', [100, 310, 590, 410], 'L2'),
      _block('L3', 'text', [100, 420, 590, 520], 'L3'),
      _block('R1', 'text', [610, 200, 1100, 300], 'R1'),
      _block('R2', 'text', [610, 310, 1100, 410], 'R2'),
      _block('R3', 'text', [610, 420, 1100, 520], 'R3'),
      // 跨栏 figure: caption [100, 1098, 1100, 1118] 跨整页
      _block('v1', 'chart', [100, 700, 1100, 1080]),
      _block('cap', 'figure_title', [100, 1098, 1100, 1118],
          'Figure 1. Full-width figure.'),
    ];
    final segment = pageBlocks
        .where((b) => {'v1', 'cap'}.contains(b.blockId))
        .toList();

    // visualUnion top=700, blocker = max(L3.bottom=520, R3.bottom=520) = 520
    // gap = 700-520 = 180, height = 1080-700 = 380, ratio=0.47 ≥ 0.3 → 扩展
    // newTop = 520 + 8 = 528
    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);
    expect(bbox[1], 528.0);
  });

  test('column detection: 单栏 figure 上方有 header → 扩展到 header 底', () {
    // 单栏论文(text block 不足 4 个),整页一栏.figure 上方只有 header.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('h1', 'header', [100, 50, 1100, 110], 'Journal Name'),
      _block('v1', 'chart', [200, 400, 1000, 800]),
      _block('cap', 'figure_title', [200, 820, 1000, 840],
          'Figure 1. Single column.'),
      _block('p1', 'text', [100, 900, 1100, 1000], 'body text'),
    ];
    final segment = pageBlocks
        .where((b) => {'v1', 'cap'}.contains(b.blockId))
        .toList();

    // gap = 400-110 = 290, height = 400, ratio=0.725 ≥ 0.3 → 扩展
    // newTop = 110 + 8 = 118
    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);
    expect(bbox[1], 118.0);
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

  // ─── PR-2: caption 候选放宽 (label 白名单解除 + 多行合并) ───────

  test('PR-2: 白名单外 label 的 caption 内容也被召回 (image_caption / unknown)', () {
    // PaddleOCR-VL 可能把 caption 错标为 image_caption 或某新版 label.
    // PR-1 之前 _captionCandidateLabels 白名单 (figure_title/text/footer/...)
    // 会过滤掉它们; PR-2 解除白名单后只看内容匹配 _mainCaptionRe.
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('1', 'image', [100, 100, 700, 600]),
        _block('2', 'image_caption', [100, 620, 700, 660],
            'Figure 3. Caption with custom label.'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 1);
    expect(segments.single.captionName, 'Figure_3');
    expect(segments.single.captionText, contains('Caption with custom label'));
  });

  test('PR-2: 多行 caption 合并 - 延续行被吸收为同一候选', () {
    // PaddleOCR 把一段长 caption 拆成 3 个连续的 figure_title block.
    // 第 1 行匹配 _mainCaptionRe; 第 2/3 行不匹配但纵向紧邻、横向同 column.
    // 期望: 合并为单个 caption candidate, 全部 3 个 block 都进 segment.blocks
    // (用于下游 markdown 替换抹掉残骸).
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('img', 'image', [100, 100, 700, 600]),
        _block('cap1', 'figure_title', [100, 620, 700, 640],
            'Figure 1. First line of a long caption that continues'),
        _block('cap2', 'figure_title', [100, 645, 700, 665],
            'across multiple lines and includes detailed methodology'),
        _block('cap3', 'figure_title', [100, 670, 700, 690],
            'about the experimental setup.'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 1);

    // 合并后的 captionText 包含三行全部内容
    final text = segments.single.captionText;
    expect(text, contains('First line'));
    expect(text, contains('across multiple lines'));
    expect(text, contains('experimental setup'));

    // 3 个 caption-related block id 都在 segment.blocks 里
    final ids = segments.single.blocks.map((b) => b.blockId).toSet();
    expect(ids, containsAll(['cap1', 'cap2', 'cap3']));
  });

  test('PR-2: 多行合并不跨越下一个 caption (Figure 1 不吸 Figure 2)', () {
    // 两个 caption 紧邻: Figure 1 + Figure 2, 中间几何上"看着像延续".
    // 硬终止条件 (_mainCaptionRe 匹配) 阻止 Figure 1 把 Figure 2 吃掉.
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('img1', 'image', [100, 100, 700, 400]),
        _block('cap1', 'figure_title', [100, 420, 700, 440],
            'Figure 1. First.'),
        _block('img2', 'image', [100, 500, 700, 800]),
        _block('cap2', 'figure_title', [100, 820, 700, 840],
            'Figure 2. Second.'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 2);
    expect(
      segments.map((s) => s.captionName).toSet(),
      equals({'Figure_1', 'Figure_2'}),
    );
    // 各自 caption 文本独立, 没串吃
    final figure1 = segments.firstWhere((s) => s.captionName == 'Figure_1');
    expect(figure1.captionText, isNot(contains('Second')));
  });

  test('PR-2: 纵向 gap 过大时不视为延续行', () {
    // gap = 250 - 40 = 210; anchor 高度 20 → maxGap = max(20*0.8, 15) = 16.
    // 210 >> 16, 不应作为 caption 延续吃掉远处文字.
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('img', 'image', [100, 100, 700, 30]),
        _block('cap', 'figure_title', [100, 20, 700, 40],
            'Figure 1. Short caption.'),
        _block('far', 'text', [100, 250, 700, 270],
            'unrelated paragraph far below'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 1);
    // 不应该把远处文字吃进 caption
    expect(segments.single.captionText,
        equals('Figure 1. Short caption.'));
  });

  // ─── PR-5b: vision_footnote 双角色 (子图标签 vs caption 说明) ────

  test('PR-5b: vision_footnote (a) 是 figure 左上角的唯一锚点 (移除该位置其他 visual)', () {
    // 终于的设计: figure 真实占据 [100,200,1000,900], 但 PaddleOCR 只识别右半部分.
    // (a) 子图标签 vf 位于 [110,210,140,230] 是左上角唯一信号.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('p', 'text', [50, 50, 1100, 150], 'preceding paragraph'),
      // (a) 子图位置: 仅 vf 标签存在, image 漏检
      _block('vfa', 'vision_footnote', [110, 210, 140, 230], '(a)'),
      // 右上 (b), 右下 (c), 左下 (d) — image 都被识别. 子图坐标设计成
      // 让左上角 [100~500, 200~400] 完全没 image, vfa 是唯一锚.
      _block('vb', 'image', [600, 200, 1000, 400]),
      _block('vc', 'image', [600, 500, 1000, 900]),
      _block('vd', 'image', [600, 600, 1000, 900]),
      _block('cap', 'figure_title', [100, 950, 900, 970],
          'Figure 1. Four-panel composite.'),
    ];
    final segment = pageBlocks
        .where((b) => {'vfa', 'vb', 'vc', 'vd', 'cap'}.contains(b.blockId))
        .toList();

    // 不并入 vfa: visuals=[vb,vc,vd], union=[600,200,1000,900]
    // 并入 vfa: union=[110,200,1000,900] — left 从 600 拉到 110 ✓
    //
    // direction inference: visuals 都在 caption 上方 (caption.top=950)
    //   aboveArea (vb+vc+vd): (400*200) + (400*400) + (400*300) = 360000
    //   leftArea / rightArea: caption 横向 [100..900], 与 visuals 同 row 检查...
    //     vb top=200 < captionBottom=970, bottom=400 > captionTop=950? 400<950 ✗ 不 inRow
    //   → above 胜出
    // vfa 同 direction (above): vfa.bottom=230 ≤ caption.top=950 ✓ → 并入
    //
    // 期望: bbox.left = 110 (vfa 锚定), 而不是 600 (visuals 单独).
    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);

    expect(bbox[0], 110.0,
        reason: 'vision_footnote (a) 应作为左上角锚点, 把 left 从 600 拉到 110');
    expect(bbox[1], 200.0); // top 不变 (vb.top=200 = vfa.top+10 中较小者)
    expect(bbox[2], 1000.0);
    expect(bbox[3], 900.0);
  });

  test('PR-5b 回归保护: vision_footnote 在 caption 反侧 (下方说明文字) 不并入', () {
    // 这是已有测试 1 的关键场景, 用更显式的断言:
    // direction=above (figure 在 caption 上), 但 vf 在 caption 下方 → 反侧, 排除.
    // 验证 PR-5b 改动没破坏 vf 角色 (1) 的处理.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('p', 'text', [50, 50, 1100, 150], 'preceding paragraph'),
      _block('v', 'image', [200, 200, 800, 900]),
      _block('cap', 'figure_title', [100, 950, 900, 970],
          'Figure 1. Composite.'),
      // 这条 vision_footnote 在 caption 下方 (top=985 > caption.bottom=970)
      // → 反侧 → 不并入. 即使它的 left=50 比 visual.left=200 小, bbox.left 也应仍是 200.
      _block('vfBelow', 'vision_footnote', [50, 985, 1100, 1010],
          '(A) Description below caption.'),
    ];
    final segment = pageBlocks
        .where((b) => {'v', 'cap', 'vfBelow'}.contains(b.blockId))
        .toList();

    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);

    // bbox.left 必须是 200 (visual), 而不是 50 (vfBelow)
    expect(bbox[0], 200.0,
        reason: 'caption 下方的 vision_footnote 是说明文字, 不该污染 bbox.left');
    expect(bbox[2], 800.0,
        reason: '同上, 不该影响 bbox.right');
  });

  // ─── PR-5a: left/right 方向扩展 ───────────────────────────

  test('PR-5a: caption 在 figure 右侧 → direction=left → 向左扩展', () {
    // figure 占大版面在左, caption 作为 sidebar 在右. 上方有一段 header text.
    // visual 块漏检导致左侧有空白, 期望沿 caption 反方向(向左)扩展到 stable
    // blocker (页边界 = 0) + margin.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('h', 'text', [50, 100, 1100, 250], 'header line'),
      _block('v', 'chart', [400, 250, 800, 900]),
      _block('cap', 'figure_title', [820, 400, 1100, 440],
          'Figure 1. Right sidebar caption.'),
    ];
    final segment = pageBlocks
        .where((b) => {'v', 'cap'}.contains(b.blockId))
        .toList();

    // direction inference (面积比较):
    //   aboveArea (text inColumn): 1050 * 150 = 157500
    //   leftArea  (chart inRow):    400 *  650 = 260000
    //   → direction = left
    // _extendLeftward: visualLeft=400, visualWidth=400, blockerRight=0 (text 横跨)
    //   gap=400, gap/width=1.0 ≥ 0.30 → newLeft = 0 + 8 = 8
    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);
    expect(bbox, [8.0, 250.0, 800.0, 900.0]);
  });

  test('PR-5a: caption 在 figure 左侧 → direction=right → 向右扩展', () {
    // 与上一条对称: caption 在左 sidebar, figure 在右占大版面.
    final service = FigureExtractService.instance;
    final pageBlocks = [
      _block('h', 'text', [50, 100, 1100, 250], 'header line'),
      _block('cap', 'figure_title', [50, 400, 280, 440],
          'Figure 1. Left sidebar caption.'),
      _block('v', 'chart', [300, 250, 700, 900]),
    ];
    final segment = pageBlocks
        .where((b) => {'v', 'cap'}.contains(b.blockId))
        .toList();

    // direction inference:
    //   aboveArea (text inColumn): 157500
    //   rightArea (chart inRow):   260000
    //   → direction = right
    // _extendRightward: visualRight=700, visualWidth=400, pageRight=1100,
    //   blockerLeft=1100 (text bLeft=50 ≤ 700 不算 blocker), gap=400, ratio=1.0
    //   → newRight = 1100 - 8 = 1092
    final bbox = service.computeMergedBbox(segment, pageBlocks: pageBlocks);
    expect(bbox, [300.0, 250.0, 1092.0, 900.0]);
  });

  test('PR-5a: trim 在 caption 重叠 region 左侧时从 left 收缩', () {
    // 直接测 trim 算法的 left 收缩分支.
    // region [100,100,1000,1000], caption [120,400,200,440] 在 region 左半中间.
    // 损失面积 (w=900, h=900):
    //   trim top    = 900 * (440-100) = 306000
    //   trim bottom = 900 * (1000-400) = 540000
    //   trim left   = 900 * (200-100) = 90000  ← min
    //   trim right  = 900 * (1000-120) = 792000
    // → trim left → newLeft = 200 + 8 = 208
    final service = FigureExtractService.instance;
    final segment = [
      _block('cap', 'figure_title', [120, 400, 200, 440],
          'Figure 1. Left edge caption inside region.'),
      _block('v', 'image', [100, 100, 1000, 1000]),
    ];
    final trimmed =
        service.trimCaptionFromRegion([100, 100, 1000, 1000], segment);
    expect(trimmed, [208.0, 100.0, 1000.0, 1000.0]);
  });

  test('PR-5a: trim 在 caption 重叠 region 右侧时从 right 收缩', () {
    // 对称: caption [900,400,980,440] 在 region 右半中间.
    // 损失面积:
    //   trim top    = 900 * 340 = 306000
    //   trim bottom = 900 * 600 = 540000
    //   trim left   = 900 * 880 = 792000
    //   trim right  = 900 * 100 = 90000  ← min
    // → trim right → newRight = 900 - 8 = 892
    final service = FigureExtractService.instance;
    final segment = [
      _block('cap', 'figure_title', [900, 400, 980, 440],
          'Figure 1. Right edge caption inside region.'),
      _block('v', 'image', [100, 100, 1000, 1000]),
    ];
    final trimmed =
        service.trimCaptionFromRegion([100, 100, 1000, 1000], segment);
    expect(trimmed, [100.0, 100.0, 892.0, 1000.0]);
  });

  // ─── 硬契约: trimCaptionFromRegion ────────────────────────
  //
  // 这组测试单独验证 "裁剪 region 不含 main caption" 的契约.
  // 当前实现下 visual-union 起点 + 扩展方向天然避开 caption, trim 是 no-op;
  // 但通过显式测试这个函数, 任何未来对 _isVisualBlock / region 扩展的改动
  // 若意外把 caption 包进 bbox, 都会被这组测试拦下.

  test('硬契约: caption 在 region 上半 + 横向重叠 → top 收缩', () {
    final service = FigureExtractService.instance;
    final segment = [
      _block('cap', 'figure_title', [200, 200, 800, 250],
          'Figure 1. Top caption inside region.'),
      _block('v', 'image', [100, 100, 1000, 1000]),
    ];
    // distFromTop = 250-100 = 150, distFromBottom = 1000-200 = 800
    // → top 收缩: newTop = 250 + 8 = 258
    final trimmed =
        service.trimCaptionFromRegion([100, 100, 1000, 1000], segment);
    expect(trimmed, [100.0, 258.0, 1000.0, 1000.0]);
  });

  test('硬契约: caption 在 region 下半 + 横向重叠 → bottom 收缩', () {
    final service = FigureExtractService.instance;
    final segment = [
      _block('cap', 'figure_title', [200, 900, 800, 950],
          'Figure 1. Bottom caption inside region.'),
      _block('v', 'image', [100, 100, 1000, 1000]),
    ];
    // distFromTop = 950-100 = 850, distFromBottom = 1000-900 = 100
    // → bottom 收缩: newBottom = 900 - 8 = 892
    final trimmed =
        service.trimCaptionFromRegion([100, 100, 1000, 1000], segment);
    expect(trimmed, [100.0, 100.0, 1000.0, 892.0]);
  });

  test('硬契约: 子标签 "(a)" / "(b)" 不被视为 main caption → trim no-op', () {
    // 子标签 figure_title 内容不匹配 _mainCaptionRe, 应保留在 region 内
    // (它们是 figure 内部结构, 不是"图注").
    final service = FigureExtractService.instance;
    final segment = [
      _block('subA', 'figure_title', [200, 200, 220, 220], '(a)'),
      _block('subB', 'figure_title', [600, 200, 620, 220], '(b)'),
      _block('v', 'image', [100, 100, 1000, 1000]),
    ];
    final trimmed =
        service.trimCaptionFromRegion([100, 100, 1000, 1000], segment);
    expect(trimmed, [100.0, 100.0, 1000.0, 1000.0]);
  });

  test('硬契约: caption 与 region 无重叠 → trim no-op (visual-union 常态)', () {
    // 当前 visual-union baseBbox 路径下的常态: caption 在 region 之外.
    // 这条用例确保不相交时 trim 一次都不动 region.
    final service = FigureExtractService.instance;
    final segment = [
      _block('cap', 'figure_title', [200, 1100, 800, 1150],
          'Figure 1. Below region.'),
      _block('v', 'image', [100, 100, 1000, 1000]),
    ];
    final trimmed =
        service.trimCaptionFromRegion([100, 100, 1000, 1000], segment);
    expect(trimmed, [100.0, 100.0, 1000.0, 1000.0]);
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
  // ─── caption 延续行 body-text 过度合并 ──────────────────

  test('text-label 正文段落不应被合并为 caption 延续行 (caption 已完整)', () {
    // Bug 现场: anchor block 已包含完整 caption 文本 (以句号结尾),
    // 后续 text 块是正文段落, 不应被当作 caption 延续行合并.
    // anchor 高度大 (height=163), 导致 gap 阈值过大 (130px),
    // 使得仅 gap=28 的正文段落通过了 gap 检查.
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('img', 'image', [101, 118, 582, 597]),
        _block('sub', 'figure_title', [125, 580, 519, 621],
            'Accessing large brain regions'),
        _block('cap', 'figure_title', [97, 635, 588, 798],
            'Figure 2. Current challenges in all-optical brain interrogation.'),
        _block('body', 'text', [96, 826, 588, 1202],
            'microscopy techniques must be developed to record and manipulate the activity of multiple brain areas.'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 1);
    // caption 不应包含正文内容
    expect(segments.single.captionText, isNot(contains('microscopy')));
    // body block 不应在 segment.blocks 中 (作为 caption continuation)
    final ids = segments.single.blocks.map((b) => b.blockId).toSet();
    expect(ids, isNot(contains('body')));
  });

  test('text-label 块仍可作为延续行——当 anchor 文本不完整 (仅有编号无描述)', () {
    // 原始修复场景: OCR 把 caption 拆成 figure_title + text,
    // anchor 仅有 "Figure 1." 没有描述, text 块包含实际 caption 描述.
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('img', 'image', [100, 100, 700, 600]),
        _block('cap', 'figure_title', [100, 620, 700, 640],
            'Figure 1.'),
        _block('desc', 'text', [100, 645, 700, 680],
            'Detailed description of the experimental setup.'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 1);
    // caption 应包含延续行的描述
    expect(segments.single.captionText, contains('Detailed description'));
  });

  test('text-label 块仍可作为延续行——当 anchor 描述未结束 (无句号结尾)', () {
    // anchor 有描述但句子未完成 (被 OCR 在中间截断)
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('img', 'image', [100, 100, 700, 600]),
        _block('cap', 'figure_title', [100, 620, 700, 640],
            'Figure 1. Detailed description of the experimental'),
        _block('cont', 'text', [100, 645, 700, 680],
            'setup and methodology.'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 1);
    // caption 应包含延续行
    expect(segments.single.captionText, contains('setup and methodology'));
  });

  // ─── 中文连字符编号 caption (图X-Y / 表X-Y) ──────────────

  test('中文连字符编号 caption (图3-9) 被正确识别并配对', () {
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('1', 'image', [100, 100, 700, 600]),
        _block('2', 'figure_title', [100, 620, 700, 660],
            '图3-9 折射球面光路图'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 1);
    expect(segments.single.captionText, startsWith('图3-9'));
    expect(segments.single.blocks.any((b) => b.blockId == '1'), isTrue);
  });

  test('中文 table 连字符编号 (表3-1) + 同页 figure 共存', () {
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('img', 'image', [100, 100, 500, 400]),
        _block('cap1', 'figure_title', [100, 420, 500, 450],
            '图4-1 光路示意图'),
        _block('tbl', 'table', [100, 500, 900, 800]),
        _block('cap2', 'figure_title', [100, 820, 900, 850],
            '表3-1 常用玻璃的折射率'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 2);
    final names = segments.map((s) => s.captionText).toSet();
    expect(names, contains(startsWith('图4-1')));
    expect(names, contains(startsWith('表3-1')));
  });

  test('回归: 点分编号 (Figure 1.2) 仍然正常工作', () {
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('1', 'image', [100, 100, 700, 600]),
        _block('2', 'figure_title', [100, 620, 700, 660],
            'Figure 1.2 Optical layout.'),
      ],
    ];
    final segments = service.findFigures(pages);
    expect(segments.length, 1);
    expect(segments.single.captionText, startsWith('Figure 1.2'));
    expect(segments.single.blocks.any((b) => b.blockId == '1'), isTrue);
  });

  // ─── Pass 4: ordinal matching ──────────────────────────

  group('Pass 4 ordinal matching (预印本 Figure Legends 布局)', () {
    test('标准分离布局——3 caption 集中 + 3 image 分散', () {
      final service = FigureExtractService.instance;
      // Page 0: 正文
      // Page 1: Figure Legends (3 个 caption, 无 image)
      // Page 2-4: 每页一张 figure image
      final segments = service.findFigures([
        // page 0: 正文
        [_block('t1', 'text', [100, 100, 700, 200], 'Introduction...')],
        // page 1: Figure Legends
        [
          _block('c1', 'figure_title', [100, 100, 700, 130],
              'Figure 1. Experimental setup.'),
          _block('c2', 'figure_title', [100, 300, 700, 330],
              'Figure 2. Results overview.'),
          _block('c3', 'figure_title', [100, 500, 700, 530],
              'Figure 3. Statistical analysis.'),
        ],
        // page 2: figure image 1
        [_block('i1', 'image', [100, 100, 700, 900])],
        // page 3: figure image 2
        [_block('i2', 'image', [100, 100, 700, 900])],
        // page 4: figure image 3
        [_block('i3', 'image', [100, 100, 700, 900])],
      ]);

      expect(segments.length, 3);
      expect(segments[0].captionName, 'Figure_1');
      expect(segments[0].pairMethod, PairMethod.ordinalMatch);
      expect(segments[0].blocks.any((b) => b.blockId == 'i1'), isTrue);
      expect(segments[1].captionName, 'Figure_2');
      expect(segments[1].pairMethod, PairMethod.ordinalMatch);
      expect(segments[1].blocks.any((b) => b.blockId == 'i2'), isTrue);
      expect(segments[2].captionName, 'Figure_3');
      expect(segments[2].pairMethod, PairMethod.ordinalMatch);
      expect(segments[2].blocks.any((b) => b.blockId == 'i3'), isTrue);
    });

    test('数量差 1 容忍——3 caption + 2 cluster = 配对 2 个', () {
      final service = FigureExtractService.instance;
      final segments = service.findFigures([
        // page 0: Figure Legends
        [
          _block('c1', 'figure_title', [100, 100, 700, 130],
              'Figure 1. Setup.'),
          _block('c2', 'figure_title', [100, 300, 700, 330],
              'Figure 2. Data.'),
          _block('c3', 'figure_title', [100, 500, 700, 530],
              'Figure 3. Stats.'),
        ],
        // page 1-2: 只有 2 个 figure image
        [_block('i1', 'image', [100, 100, 700, 900])],
        [_block('i2', 'image', [100, 100, 700, 900])],
      ]);

      expect(segments.length, 2);
      expect(segments[0].captionName, 'Figure_1');
      expect(segments[0].pairMethod, PairMethod.ordinalMatch);
      expect(segments[1].captionName, 'Figure_2');
      expect(segments[1].pairMethod, PairMethod.ordinalMatch);
    });

    test('数量差 >1 的安全守卫——4 caption + 2 cluster = 不触发', () {
      final service = FigureExtractService.instance;
      final segments = service.findFigures([
        // page 0: Figure Legends (4 个 caption)
        [
          _block('c1', 'figure_title', [100, 100, 700, 130],
              'Figure 1. A.'),
          _block('c2', 'figure_title', [100, 200, 700, 230],
              'Figure 2. B.'),
          _block('c3', 'figure_title', [100, 300, 700, 330],
              'Figure 3. C.'),
          _block('c4', 'figure_title', [100, 400, 700, 430],
              'Figure 4. D.'),
        ],
        // page 1-2: 只有 2 个 figure image
        [_block('i1', 'image', [100, 100, 700, 900])],
        [_block('i2', 'image', [100, 100, 700, 900])],
      ]);

      // 数量差 2 > 1 → 不触发 ordinal match, cluster 被 drop
      expect(segments.length, 0);
    });

    test('Table caption 被正确排除', () {
      final service = FigureExtractService.instance;
      final segments = service.findFigures([
        // page 0: Figure Legends 含 table caption 夹在中间
        [
          _block('c1', 'figure_title', [100, 100, 700, 130],
              'Figure 1. Setup.'),
          _block('ct', 'figure_title', [100, 250, 700, 280],
              'Table 1. Summary of results.'),
          _block('c2', 'figure_title', [100, 400, 700, 430],
              'Figure 2. Data.'),
        ],
        // page 1-2: 2 个 figure image
        [_block('i1', 'image', [100, 100, 700, 900])],
        [_block('i2', 'image', [100, 100, 700, 900])],
      ]);

      expect(segments.length, 2);
      expect(segments[0].captionName, 'Figure_1');
      expect(segments[0].pairMethod, PairMethod.ordinalMatch);
      expect(segments[1].captionName, 'Figure_2');
      expect(segments[1].pairMethod, PairMethod.ordinalMatch);
    });

    test('非分离布局不触发——caption 与 cluster 同页有交集', () {
      final service = FigureExtractService.instance;
      final segments = service.findFigures([
        // page 0: caption + image 在同一页 (Pass 1 能处理)
        [
          _block('c1', 'figure_title', [100, 800, 700, 830],
              'Figure 1. Setup.'),
          _block('i1', 'image', [100, 100, 700, 780]),
        ],
        // page 1: 独立 caption (无 cluster 在此页)
        [
          _block('c2', 'figure_title', [100, 100, 700, 130],
              'Figure 2. Data.'),
        ],
        // page 2: 独立 cluster (无 caption 在此页)
        [_block('i2', 'image', [100, 100, 700, 900])],
      ]);

      // Figure 1 由 Pass 1 同页配对, Figure 2 + i2 只有各 1 个 → < 2 不触发
      expect(
        segments.where((s) => s.pairMethod == PairMethod.ordinalMatch).length,
        0,
      );
      // Figure 1 应该被 Pass 1 配上
      expect(segments.any((s) => s.captionName == 'Figure_1'), isTrue);
    });

    test('Supplementary figure 混合排序', () {
      final service = FigureExtractService.instance;
      final segments = service.findFigures([
        // page 0: Figure Legends 含 supplementary
        [
          _block('c1', 'figure_title', [100, 100, 700, 130],
              'Figure 1. Main result.'),
          _block('c2', 'figure_title', [100, 250, 700, 280],
              'Figure 2. Secondary.'),
          _block('cs', 'figure_title', [100, 400, 700, 430],
              'Supplementary Figure S1. Extra data.'),
        ],
        // page 1-3: 按顺序排列
        [_block('i1', 'image', [100, 100, 700, 900])],
        [_block('i2', 'image', [100, 100, 700, 900])],
        [_block('is', 'image', [100, 100, 700, 900])],
      ]);

      expect(segments.length, 3);
      expect(segments[0].captionName, 'Figure_1');
      expect(segments[1].captionName, 'Figure_2');
      // Supplementary 排在最后
      expect(segments[2].captionText, startsWith('Supplementary Figure S1'));
      expect(
        segments.every((s) => s.pairMethod == PairMethod.ordinalMatch),
        isTrue,
      );
    });
  });

  // ─── groupId 子图聚类 ──────────────────────────────────

  group('groupId 预分组聚类', () {
    test('同 groupId 的远距离子图聚为一簇', () {
      // 四个子图分散在页面四角，空间距离远超 maxGap，
      // 但 PaddleOCR 给了相同 group_id=1 → 应归为同一 cluster。
      final service = FigureExtractService.instance;
      final pages = [
        [
          _blockEx('a', 'image', [50, 50, 200, 200], groupId: 1),
          _blockEx('b', 'image', [800, 50, 950, 200], groupId: 1),
          _blockEx('c', 'image', [50, 800, 200, 950], groupId: 1),
          _blockEx('d', 'image', [800, 800, 950, 950], groupId: 1),
          _block('cap', 'figure_title', [300, 980, 700, 1010],
              'Figure 1. Four-panel composite.'),
        ],
      ];
      final segments = service.findFigures(pages);
      expect(segments.length, 1);
      expect(segments.single.captionName, 'Figure_1');
      final ids = segments.single.blocks.map((b) => b.blockId).toSet();
      expect(ids, containsAll(['a', 'b', 'c', 'd']));
    });

    test('不同 groupId → 分属不同 cluster', () {
      final service = FigureExtractService.instance;
      final pages = [
        [
          _blockEx('a', 'image', [100, 100, 400, 400], groupId: 1),
          _blockEx('b', 'image', [100, 420, 400, 500], groupId: 1),
          _block('cap1', 'figure_title', [100, 510, 400, 530],
              'Figure 1. First.'),
          _blockEx('c', 'image', [600, 100, 900, 400], groupId: 2),
          _block('cap2', 'figure_title', [600, 410, 900, 430],
              'Figure 2. Second.'),
        ],
      ];
      final segments = service.findFigures(pages);
      expect(segments.length, 2);
      final fig1 = segments.firstWhere((s) => s.captionName == 'Figure_1');
      final fig2 = segments.firstWhere((s) => s.captionName == 'Figure_2');
      expect(fig1.blocks.map((b) => b.blockId), containsAll(['a', 'b']));
      expect(fig2.blocks.map((b) => b.blockId), contains('c'));
    });

    test('null groupId → 退化为空间聚类（回归）', () {
      // 没有 groupId 的 block 走原有空间聚类逻辑
      final service = FigureExtractService.instance;
      final pages = [
        [
          _block('a', 'image', [100, 100, 400, 400]),
          _block('b', 'image', [100, 410, 400, 500]),
          _block('cap', 'figure_title', [100, 510, 400, 530],
              'Figure 1. Grouped by spatial proximity.'),
        ],
      ];
      final segments = service.findFigures(pages);
      expect(segments.length, 1);
      final ids = segments.single.blocks.map((b) => b.blockId).toSet();
      expect(ids, containsAll(['a', 'b']));
    });
  });

  // ─── 双栏配对约束 ──────────────────────────────────────

  group('双栏栏位约束配对', () {
    test('双栏页面：左栏 caption 配左栏 image，不跨栏', () {
      // 双栏排版需要至少 4 个 text block (每侧 ≥3) 触发双栏检测。
      // 左栏 image + caption，右栏 image + caption，caption 空间上
      // 可能离对栏 image 也不远，但栏位约束阻止跨栏配对。
      final service = FigureExtractService.instance;
      final pages = [
        [
          // 左栏 text blocks (触发双栏检测)
          _block('t1', 'text', [50, 50, 500, 80], 'Left column text 1'),
          _block('t2', 'text', [50, 90, 500, 120], 'Left column text 2'),
          _block('t3', 'text', [50, 130, 500, 160], 'Left column text 3'),
          // 右栏 text blocks
          _block('t4', 'text', [550, 50, 1050, 80], 'Right column text 1'),
          _block('t5', 'text', [550, 90, 1050, 120], 'Right column text 2'),
          _block('t6', 'text', [550, 130, 1050, 160], 'Right column text 3'),
          // 左栏 figure
          _block('L_img', 'image', [50, 200, 500, 700]),
          _block('L_cap', 'figure_title', [50, 710, 500, 740],
              'Figure 1. Left column figure.'),
          // 右栏 figure
          _block('R_img', 'image', [550, 200, 1050, 700]),
          _block('R_cap', 'figure_title', [550, 710, 1050, 740],
              'Figure 2. Right column figure.'),
        ],
      ];
      final segments = service.findFigures(pages);
      expect(segments.length, 2);
      final fig1 = segments.firstWhere((s) => s.captionName == 'Figure_1');
      final fig2 = segments.firstWhere((s) => s.captionName == 'Figure_2');
      expect(fig1.blocks.any((b) => b.blockId == 'L_img'), isTrue);
      expect(fig2.blocks.any((b) => b.blockId == 'R_img'), isTrue);
    });

    test('单栏页面不受栏位约束影响（回归）', () {
      final service = FigureExtractService.instance;
      final pages = [
        [
          _block('img', 'image', [100, 100, 900, 600]),
          _block('cap', 'figure_title', [100, 620, 900, 660],
              'Figure 1. Single column.'),
        ],
      ];
      final segments = service.findFigures(pages);
      expect(segments.length, 1);
      expect(segments.single.captionName, 'Figure_1');
    });
  });

  // ─── group_id 段落续接 caption 合并 ─────────────────────

  group('group_id 段落续接', () {
    test('同 group_id 的 text 块跳过空间检查直接合并为 caption 续接', () {
      // OCR 把 caption 标为 text 并拆成两个 block，共享 group_id=5。
      // 即使纵向 gap 超出通常阈值，同 group 也应合并。
      final service = FigureExtractService.instance;
      final pages = [
        [
          _block('img', 'image', [100, 100, 700, 400]),
          _blockEx('cap', 'text', [100, 420, 700, 440],
              content: 'Figure 1. First part of a caption that', groupId: 5),
          _blockEx('cont', 'text', [100, 550, 700, 570],
              content: 'continues across a large gap.', groupId: 5),
        ],
      ];
      final segments = service.findFigures(pages);
      expect(segments.length, 1);
      expect(segments.single.captionText, contains('continues across'));
    });

    test('不同 group_id 的 text 块不合并（停止信号）', () {
      // 候选 block 与后续 block 共享 group_id=6（属于另一段落），
      // 应作为停止信号，不合并到 caption。
      final service = FigureExtractService.instance;
      final pages = [
        [
          _block('img', 'image', [100, 100, 700, 400]),
          _blockEx('cap', 'text', [100, 420, 700, 440],
              content: 'Figure 1. Complete caption.', groupId: 5),
          _blockEx('para1', 'text', [100, 450, 700, 470],
              content: 'This is body text paragraph', groupId: 6),
          _blockEx('para2', 'text', [100, 475, 700, 495],
              content: 'that should not be merged.', groupId: 6),
        ],
      ];
      final segments = service.findFigures(pages);
      expect(segments.length, 1);
      expect(segments.single.captionText, isNot(contains('body text')));
    });
  });

  // ─── label-only caption 续接边界 ─────────────────────────

  test('label-only caption 不吸收远左的全宽正文段落', () {
    // 复现真实 bug：中文教材"图3-9/10/11"三图并排，
    // "图3-11"（66px 宽 label）后面紧跟全宽正文（837px 宽）。
    // 正文左边缘 (95) 远在 anchor 左边缘 (697) 左侧 → 不应被吸收。
    // 如果吸收，caption bbox 膨胀到全宽，导致 3 张图全部误配到 "图3-11"。
    final service = FigureExtractService.instance;
    final pages = [
      [
        _block('11', 'image', [190, 853, 354, 1010]),
        _block('12', 'figure_title', [244, 1030, 300, 1049], '图3-9'),
        _block('13', 'image', [417, 852, 558, 1012]),
        _block('14', 'figure_title', [455, 1030, 521, 1049], '图3-10'),
        _block('15', 'image', [620, 908, 839, 1012]),
        _block('16', 'figure_title', [697, 1029, 763, 1049], '图3-11'),
        _block('17', 'text', [95, 1062, 931, 1149],
            '若需经一次反射使光轴转过若干角度，根据反射定律和几何关系...'),
      ],
    ];
    final segments = service.findFigures(pages);
    // 应该是 3 个独立的 figure，而不是全部合并到 "图3-11"
    expect(segments.length, 3);
    final names = segments.map((s) => s.captionName).toSet();
    expect(names, containsAll(['图3-9', '图3-10', '图3-11']));
    // 正文不应出现在任何 segment 中
    for (final seg in segments) {
      expect(seg.blocks.any((b) => b.blockId == '17'), isFalse);
    }
  });

  // ─── previous anchor vision_footnote 消歧 ──────────────

  group('previous anchor vision_footnote 消歧', () {
    test('table 后的 vision_footnote → table cluster 亲和', () {
      // 页面上方是 image + 其 caption，下方是 table + vision_footnote。
      // vision_footnote 的 previous anchor 是 table，应与 table caption 配对。
      final service = FigureExtractService.instance;
      final pages = [
        [
          _block('img', 'image', [100, 100, 900, 400]),
          _block('cap1', 'figure_title', [100, 410, 900, 440],
              'Figure 1. Image result.'),
          _block('tbl', 'table', [100, 500, 900, 800]),
          _block('cap2', 'figure_title', [100, 810, 900, 840],
              'Table 1. Data summary.'),
          _block('vf', 'vision_footnote', [100, 845, 900, 870],
              'Note: values are means ± SD.'),
        ],
      ];
      final segments = service.findFigures(pages);
      expect(segments.length, 2);
      final tblSeg = segments.firstWhere(
        (s) => s.captionName.startsWith('Table'),
      );
      // vision_footnote 应归入 table segment
      expect(tblSeg.blocks.any((b) => b.blockId == 'vf'), isTrue);
    });
  });

  group('caption_patterns 等价性', () {
    final service = FigureExtractService.instance;

    test('isMainCaption 覆盖各语言正文前缀', () {
      const cases = [
        'Figure 1.',
        'Fig. 2',
        'FIGURE 3:',
        'Table 1.',
        'TABLE 2',
        'Scheme 1.',
        'Chart 2:',
        '图1',
        '表 2',
        '附图 3',
        'Abbildung 1',
        'Abb. 2',
        'Tabelle 3',
        'Figura 1',
        'Tabla 2',
        'Cuadro 3',
        '図1',
        '表 2',
        'Рис. 1',
        'Рисунок 2',
        'Таблица 3',
        '그림 1',
        '표 2',
        'Hình 1',
        'Bảng 2',
        'Supplementary Figure S1.',
      ];
      for (final caption in cases) {
        expect(service.isMainCaption(caption), isTrue, reason: caption);
      }
    });

    test('无前缀编号的主 caption 应拒绝', () {
      const rejected = ['Figure', 'Fig', 'Table', '图', '表'];
      for (final caption in rejected) {
        expect(service.isMainCaption(caption), isFalse, reason: caption);
      }
    });

    test('isSupplementaryCaption 覆盖补充图前缀', () {
      const cases = [
        'Supplementary Figure S1.',
        'Extended Data Fig. 2',
        'Supporting Information Figure 3',
        'SI Fig. 4',
        'Appendix Figure 5',
        '补充图1',
        '附录 图 2',
        '補足図1',
        'Ergänzende Abbildung 3',
        'Figura suplementaria 4',
        'Доп. рис. 5',
        '보조 그림 6',
        'Hình bổ sung 7',
        'Figure supplémentaire 8',
      ];
      for (final caption in cases) {
        expect(service.isSupplementaryCaption(caption), isTrue,
            reason: caption);
      }
    });
  });

  group('isSupplementaryCaption', () {
    final service = FigureExtractService.instance;

    test('识别多语言补充图 caption', () {
      const supplementary = [
        'Supplementary Figure S1. Extra data.',
        'Extended Data Fig. 2',
        '补充图1 实验流程',
        '補充圖2 實驗流程',
        '補足図1 実験手順',
        'Ergänzende Abbildung 3',
        'Figura suplementaria 4',
        'Доп. рис. 5',
        '보조 그림 6',
        'Hình bổ sung 7',
      ];
      for (final caption in supplementary) {
        expect(service.isSupplementaryCaption(caption), isTrue,
            reason: caption);
      }
    });

    test('正文 figure caption 不算补充图', () {
      const primary = [
        'Figure 1. Main result.',
        '图 2 主要结果',
        'Abbildung 3',
        '図 4',
      ];
      for (final caption in primary) {
        expect(service.isSupplementaryCaption(caption), isFalse,
            reason: caption);
      }
    });
  });

  group('classifyKind', () {
    test('figure / table / chart / supplementary 分类', () {
      final service = FigureExtractService.instance;
      expect(service.classifyKind('Figure 1. Optical paths.'), 'figure');
      expect(service.classifyKind('Fig. 2 Result.'), 'figure');
      expect(service.classifyKind('Table 1. Parameters.'), 'table');
      expect(service.classifyKind('表 3-1 基本参数'), 'table');
      expect(service.classifyKind('Chart 1. Data.'), 'chart');
      expect(service.classifyKind('Scheme 1. Synthesis.'), 'chart');
      expect(service.classifyKind('Box 3. Definition.'), 'chart');
      // supplementary 归 figure。
      expect(service.classifyKind('Supplementary Figure 1.'), 'figure');
      expect(service.classifyKind('Extended Data Figure 2.'), 'figure');
    });
  });

  group('collectTitleInventory', () {
    test('含 orphan 标题：未配对的 caption 也进入 inventory', () {
      final service = FigureExtractService.instance;
      // 页面上有 Figure 1 caption + 一个无 caption 的 image，外加一个
      // orphan Figure 2 caption（无视觉块对应）。
      final blocks = [
        _block('img1', 'image', [100, 100, 400, 400]),
        _block('cap1', 'figure_title', [100, 410, 400, 430],
            'Figure 1. Main result.'),
        _block('cap2', 'figure_title', [600, 100, 900, 120],
            'Figure 2. Orphan caption.'),
      ];
      final titles = service.collectTitleInventory(blocks, '', 0);
      final texts = titles.map((t) => t.text).toList();
      expect(texts, containsAll(['Figure 1. Main result.', 'Figure 2. Orphan caption.']));
      final fig2 = titles.firstWhere((t) => t.text.startsWith('Figure 2'));
      expect(fig2.kind, 'figure');
      expect(fig2.bbox.length, 4);
    });

    test('多行 caption 合并后作为单条标题', () {
      final service = FigureExtractService.instance;
      final blocks = [
        _block('c0', 'figure_title', [100, 410, 400, 430],
            'Figure 3. Multi-line caption.'),
        _block('c1', 'figure_title', [100, 432, 400, 450],
            'Second line of the caption.'),
      ];
      final titles = service.collectTitleInventory(blocks, '', 0);
      expect(titles.length, 1);
      expect(titles.single.text, contains('Multi-line caption.'));
      expect(titles.single.text, contains('Second line'));
    });

    test('table caption 分类为 table', () {
      final service = FigureExtractService.instance;
      final blocks = [
        _block('t0', 'figure_title', [100, 410, 400, 430],
            'Table 1. Parameters.'),
      ];
      final titles = service.collectTitleInventory(blocks, '', 0);
      expect(titles.single.kind, 'table');
    });
  });

  group('detectColumns', () {
    test('单栏页面返回 isDoubleColumn=false', () {
      final blocks = [
        _block('t1', 'text', [100, 100, 900, 130]),
        _block('t2', 'text', [100, 140, 900, 170]),
      ];
      final col = FigureExtractService.detectColumns(blocks);
      expect(col.isDoubleColumn, isFalse);
    });

    test('双栏页面返回 isDoubleColumn=true 且有栏边界', () {
      // 左栏文字 100..480，右栏文字 520..900，中点 500。
      final blocks = [
        _block('l1', 'text', [100, 100, 480, 130]),
        _block('l2', 'text', [100, 140, 480, 170]),
        _block('l3', 'text', [100, 180, 480, 210]),
        _block('r1', 'text', [520, 100, 900, 130]),
        _block('r2', 'text', [520, 140, 900, 170]),
        _block('r3', 'text', [520, 180, 900, 210]),
      ];
      final col = FigureExtractService.detectColumns(blocks);
      expect(col.isDoubleColumn, isTrue);
      expect(col.leftColRight, isNotNull);
      expect(col.rightColLeft, isNotNull);
      expect(col.leftColRight! < col.rightColLeft!, isTrue);
    });
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

LayoutBlock _blockEx(
  String id,
  String label,
  List<double> bbox, {
  String content = '',
  int? groupId,
  int? blockOrder,
}) {
  return LayoutBlock(
    blockId: id,
    blockLabel: label,
    blockBbox: bbox,
    blockContent: content,
    groupId: groupId,
    blockOrder: blockOrder,
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
