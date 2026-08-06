import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/figure_extract_service.dart';
import 'package:otter_pad/services/figure_fix_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FigureExtractService.instance.init();
  });

  group('parseAndValidate', () {
    test('合法 JSON + 白名单 id 通过', () {
      final caps = <String, CaptionRef>{};
      final vis = <String, VisualRef>{
        'p0:b1': VisualRef(0, _block('1', 'image', [0, 0, 100, 100])),
      };
      caps['p0:c0'] = CaptionRef(0, 0, _capInfo('Figure 1.', 'Figure_1', '0'));
      final text = '''
{"figures":[{"caption_id":"p0:c0","visual_ids":["p0:b1"],"kind":"figure"}],
 "orphan_captions":[],"uncaptioned_visuals":[]}''';
      final r = FigureFixService.parseAndValidate(text, caps, vis);
      expect(r.figures.length, 1);
      expect(r.figures.single.captionId, 'p0:c0');
      expect(r.figures.single.visualIds, ['p0:b1']);
      expect(r.figures.single.kind, 'figure');
    });

    test('剥离 code fence', () {
      final caps = <String, CaptionRef>{};
      final vis = <String, VisualRef>{
        'p0:b1': VisualRef(0, _block('1', 'image', [0, 0, 10, 10])),
      };
      final r = FigureFixService.parseAndValidate(
        '```json\n{"figures":[{"caption_id":null,"visual_ids":["p0:b1"],"kind":"figure"}],"orphan_captions":[],"uncaptioned_visuals":[]}\n```',
        caps,
        vis,
      );
      expect(r.figures.single.captionId, isNull);
    });

    test('未知 visual_id 被剔除，figure 保留其余已知 id', () {
      final vis = <String, VisualRef>{
        'p0:b1': VisualRef(0, _block('1', 'image', [0, 0, 10, 10])),
      };
      final r = FigureFixService.parseAndValidate(
        '{"figures":[{"caption_id":null,"visual_ids":["p0:b1","p0:bGHOST"],"kind":"figure"}],"orphan_captions":[],"uncaptioned_visuals":[]}',
        const {},
        vis,
      );
      expect(r.figures.single.visualIds, ['p0:b1']);
    });

    test('重复认领 visual：document 序先到先得', () {
      final vis = <String, VisualRef>{
        'p0:b1': VisualRef(0, _block('1', 'image', [0, 0, 10, 10])),
      };
      // figure A (caption p0:c0, page 0) 与 figure B (caption p1:c0, page 1)
      // 都认领 p0:b1 → A 在 page 0，先到先得。
      final caps = {
        'p0:c0': CaptionRef(0, 0, _capInfo('Figure 1.', 'Figure_1', '0')),
        'p1:c0': CaptionRef(1, 0, _capInfo('Figure 2.', 'Figure_2', '5')),
      };
      final text =
          '{"figures":['
          '{"caption_id":"p1:c0","visual_ids":["p0:b1"],"kind":"figure"},'
          '{"caption_id":"p0:c0","visual_ids":["p0:b1"],"kind":"figure"}],'
          '"orphan_captions":[],"uncaptioned_visuals":[]}';
      final r = FigureFixService.parseAndValidate(text, caps, vis);
      // 排序后 page 0 的 figure 先 → 认领 p0:b1；page 1 的 figure 失去 visual → 弃。
      expect(r.figures.length, 1);
      expect(r.figures.single.captionId, 'p0:c0');
    });

    test('空 visual_ids + 有 caption 降级为 orphan', () {
      final caps = {
        'p0:c0': CaptionRef(0, 0, _capInfo('Figure 1.', 'Figure_1', '0')),
      };
      final r = FigureFixService.parseAndValidate(
        '{"figures":[{"caption_id":"p0:c0","visual_ids":[],"kind":"figure"}],'
        '"orphan_captions":[],"uncaptioned_visuals":[]}',
        caps,
        const {},
      );
      expect(r.figures, isEmpty);
      expect(r.orphanCaptionIds, contains('p0:c0'));
    });

    test('kind 非 figure/table/chart → 按 caption 文本回退', () {
      final caps = {
        'p0:c0': CaptionRef(0, 0, _capInfo('Table 1.', 'Table_1', '0')),
      };
      final vis = {
        'p0:b1': VisualRef(0, _block('1', 'table', [0, 0, 10, 10])),
      };
      final r = FigureFixService.parseAndValidate(
        '{"figures":[{"caption_id":"p0:c0","visual_ids":["p0:b1"],"kind":"bogus"}],'
        '"orphan_captions":[],"uncaptioned_visuals":[]}',
        caps,
        vis,
      );
      expect(r.figures.single.kind, 'table');
    });
  });

  group('mergeFigures', () {
    test('caption 被 AI 接管 → 丢弃启发式条目；未认领 visual 保留为匿名 cropRequest', () {
      final caps = {
        'p0:c0': CaptionRef(
          0,
          0,
          _capInfo(
            'Figure 1.',
            'Figure_1',
            '0',
            bbox: [0, 800, 100, 820],
            continuation: ['1'],
          ),
        ),
      };
      // 启发式条目：caption blockId=0, continuation=1, visuals=2,3
      final heuristic = [
        FigureManifestEntry(
          imagePath: '/old/Figure_1.png',
          captionText: 'Figure 1. ...',
          pageIndex: 0,
          blockIds: ['0', '1', '2', '3'],
        ),
      ];
      final vis = {
        'p0:b2': VisualRef(0, _block('2', 'image', [0, 0, 50, 50])),
        'p0:b3': VisualRef(0, _block('3', 'image', [0, 0, 50, 50])),
      };
      // AI 接管 c0，只认领 b2，未认领 b3 → b3 应作为匿名 cropRequest 保留。
      final result = FigureFixResult(
        figures: [
          AiFigure(captionId: 'p0:c0', visualIds: ['p0:b2'], kind: 'figure'),
        ],
        orphanCaptionIds: const {},
        uncaptionedVisualIds: const {},
      );
      final plan = FigureFixService.mergeFigures(
        result: result,
        heuristic: heuristic,
        captionRegistry: caps,
        visualRegistry: vis,
      );
      // 一条 AI figure cropRequest（含 b2）+ 一条匿名 cropRequest（b3）。
      expect(plan.cropRequests.length, 2);
      expect(plan.keptHeuristic, isEmpty);
      final anon = plan.cropRequests
          .where((r) => r.captionText.isEmpty)
          .toList();
      expect(anon.length, 1);
      expect(anon.single.visualBlocks.single.blockId, '3');
    });

    test('未触碰的启发式条目原样保留', () {
      final caps = {
        'p0:c0': CaptionRef(0, 0, _capInfo('Figure 1.', 'Figure_1', '0')),
      };
      final heuristic = [
        FigureManifestEntry(
          imagePath: '/old/Figure_1.png',
          captionText: 'Figure 1. ...',
          pageIndex: 0,
          blockIds: ['0', '2'],
        ),
      ];
      final vis = {
        'p0:b2': VisualRef(0, _block('2', 'image', [0, 0, 50, 50])),
      };
      // AI 既不接管 c0 也不认领 b2 → 启发式条目保留。
      final plan = FigureFixService.mergeFigures(
        result: const FigureFixResult(
          figures: [],
          orphanCaptionIds: {},
          uncaptionedVisualIds: {},
        ),
        heuristic: heuristic,
        captionRegistry: caps,
        visualRegistry: vis,
      );
      expect(plan.cropRequests, isEmpty);
      expect(plan.keptHeuristic.length, 1);
    });

    test('caption 未被接管但 visual 被部分认领 → 用剩余 visual 重建', () {
      final caps = {
        'p0:c0': CaptionRef(
          0,
          0,
          _capInfo('Figure 1.', 'Figure_1', '0', bbox: [0, 800, 100, 820]),
        ),
      };
      final heuristic = [
        FigureManifestEntry(
          imagePath: '/old/Figure_1.png',
          captionText: 'Figure 1. ...',
          pageIndex: 0,
          blockIds: ['0', '2', '3'],
        ),
      ];
      final vis = {
        'p0:b2': VisualRef(0, _block('2', 'image', [0, 0, 50, 50])),
        'p0:b3': VisualRef(0, _block('3', 'image', [0, 0, 50, 50])),
        'p0:b9': VisualRef(0, _block('9', 'image', [0, 0, 50, 50])),
      };
      // 另一个 AI figure（匿名，无 caption）认领 b2 → c0 的 figure 重建为只剩 b3。
      final result = FigureFixResult(
        figures: [
          AiFigure(captionId: null, visualIds: ['p0:b2'], kind: 'figure'),
        ],
        orphanCaptionIds: const {},
        uncaptionedVisualIds: const {},
      );
      final plan = FigureFixService.mergeFigures(
        result: result,
        heuristic: heuristic,
        captionRegistry: caps,
        visualRegistry: vis,
      );
      // 一条匿名（b2）+ 一条重建（c0 + b3）。
      expect(plan.cropRequests.length, 2);
      final rebuilt = plan.cropRequests
          .where((r) => r.captionText.isNotEmpty)
          .toList();
      expect(rebuilt.length, 1);
      expect(rebuilt.single.captionBlockId, '0');
      expect(rebuilt.single.visualBlocks.single.blockId, '3');
      expect(rebuilt.single.pairMethod, 'ai_fix_reduced');
    });

    test('orphan_captions 删除对应启发式条目，visual 保留为匿名', () {
      final caps = {
        'p0:c0': CaptionRef(0, 0, _capInfo('Figure 1.', 'Figure_1', '0')),
      };
      final heuristic = [
        FigureManifestEntry(
          imagePath: '/old/Figure_1.png',
          captionText: 'Figure 1. ...',
          pageIndex: 0,
          blockIds: ['0', '2'],
        ),
      ];
      final vis = {
        'p0:b2': VisualRef(0, _block('2', 'image', [0, 0, 50, 50])),
      };
      final plan = FigureFixService.mergeFigures(
        result: FigureFixResult(
          figures: const [],
          orphanCaptionIds: {'p0:c0'},
          uncaptionedVisualIds: const {},
        ),
        heuristic: heuristic,
        captionRegistry: caps,
        visualRegistry: vis,
      );
      expect(plan.keptHeuristic, isEmpty);
      expect(plan.cropRequests.length, 1);
      expect(plan.cropRequests.single.captionText, isEmpty);
    });

    test('同页多块合并成一张图（一个 caption → 一个 cropRequest）', () {
      final caps = {
        'p0:c0': CaptionRef(
          0,
          0,
          _capInfo('Figure 1.', 'Figure_1', '0', bbox: [0, 800, 100, 820]),
        ),
      };
      final vis = {
        'p0:b1': VisualRef(0, _block('1', 'image', [0, 0, 50, 50])),
        'p0:b2': VisualRef(0, _block('2', 'chart', [200, 0, 400, 200])),
      };
      final plan = FigureFixService.mergeFigures(
        result: FigureFixResult(
          figures: [
            AiFigure(
              captionId: 'p0:c0',
              visualIds: ['p0:b1', 'p0:b2'],
              kind: 'figure',
            ),
          ],
          orphanCaptionIds: const {},
          uncaptionedVisualIds: const {},
        ),
        heuristic: const [],
        captionRegistry: caps,
        visualRegistry: vis,
      );
      // 一个 caption + 同页两块 → 一条 cropRequest（两块全在 visualBlocks 里）。
      expect(plan.cropRequests.length, 1);
      expect(plan.cropRequests.single.visualBlocks.map((b) => b.blockId), [
        '1',
        '2',
      ]);
      expect(plan.cropRequests.single.captionBlockId, '0');
    });

    test('AI 认领 text 子图序号时保留其 block bbox', () {
      final caps = {
        'p0:c0': CaptionRef(0, 0, _capInfo('Figure 1.', 'Figure_1', '0')),
      };
      final vis = {
        'p0:bsub': VisualRef(
          0,
          _block('sub', 'text', [110, 210, 140, 230], content: '(a)'),
        ),
      };
      final plan = FigureFixService.mergeFigures(
        result: FigureFixResult(
          figures: [
            AiFigure(
              captionId: 'p0:c0',
              visualIds: ['p0:bsub'],
              kind: 'figure',
            ),
          ],
          orphanCaptionIds: const {},
          uncaptionedVisualIds: const {},
        ),
        heuristic: const [],
        captionRegistry: caps,
        visualRegistry: vis,
      );

      expect(plan.cropRequests.single.visualBlocks.single.blockId, 'sub');
      expect(plan.cropRequests.single.visualBlocks.single.blockBbox, [
        110.0,
        210.0,
        140.0,
        230.0,
      ]);
    });

    test('跨页同 caption：主页带 caption，其余页 visual 回退匿名', () {
      final caps = {
        'p0:c0': CaptionRef(
          0,
          0,
          _capInfo('Figure 1.', 'Figure_1', '0', bbox: [0, 800, 100, 820]),
        ),
      };
      final vis = {
        'p0:b1': VisualRef(0, _block('1', 'image', [0, 0, 50, 50])),
        'p1:b5': VisualRef(1, _block('5', 'image', [0, 0, 50, 50])),
      };
      final plan = FigureFixService.mergeFigures(
        result: FigureFixResult(
          figures: [
            AiFigure(
              captionId: 'p0:c0',
              visualIds: ['p0:b1', 'p1:b5'],
              kind: 'figure',
            ),
          ],
          orphanCaptionIds: const {},
          uncaptionedVisualIds: const {},
        ),
        heuristic: const [],
        captionRegistry: caps,
        visualRegistry: vis,
      );
      // 主图（page 0，带 caption）+ 匿名 spillover（page 1）。
      expect(plan.cropRequests.length, 2);
      final primary = plan.cropRequests.firstWhere(
        (r) => r.captionText.isNotEmpty,
      );
      expect(primary.pageIndex, 0);
      expect(primary.visualBlocks.single.blockId, '1');
      final spillover = plan.cropRequests.firstWhere(
        (r) => r.captionText.isEmpty,
      );
      expect(spillover.pageIndex, 1);
      expect(spillover.pairMethod, 'ai_cross_page');
      expect(spillover.visualBlocks.single.blockId, '5');
    });

    test('全部 visual 被匿名 AiFigure 认领 → 旧 heuristic 移除，产一条独立匿名 cropRequest', () {
      final caps = {
        'p0:c0': CaptionRef(
          0,
          0,
          _capInfo('Figure 1.', 'Figure_1', '0', bbox: [0, 800, 100, 820]),
        ),
      };
      // 启发式条目：caption blockId=0, visuals=2,3
      final heuristic = [
        FigureManifestEntry(
          imagePath: '/old/Figure_1.png',
          captionText: 'Figure 1. ...',
          pageIndex: 0,
          blockIds: ['0', '2', '3'],
        ),
      ];
      final vis = {
        'p0:b2': VisualRef(0, _block('2', 'image', [0, 0, 50, 50])),
        'p0:b3': VisualRef(0, _block('3', 'image', [0, 0, 50, 50])),
      };
      // 匿名 AiFigure（无 caption）认领全部 visual → 旧 caption 被丢弃，
      // visual 由后续匿名 AI cropRequest 独立保留。
      final result = FigureFixResult(
        figures: [
          AiFigure(
            captionId: null,
            visualIds: ['p0:b2', 'p0:b3'],
            kind: 'figure',
          ),
        ],
        orphanCaptionIds: const {},
        uncaptionedVisualIds: const {},
      );
      final plan = FigureFixService.mergeFigures(
        result: result,
        heuristic: heuristic,
        captionRegistry: caps,
        visualRegistry: vis,
      );
      expect(plan.keptHeuristic, isEmpty);
      // 一条匿名 AI cropRequest（b2+b3 合并），无 caption 关联。
      expect(plan.cropRequests.length, 1);
      final r = plan.cropRequests.single;
      expect(r.captionBlockId, isNull);
      expect(r.captionPageIndex, isNull);
      expect(r.captionText, isEmpty);
      expect(r.captionSource, 'none');
      expect(r.pairMethod, 'ai_fix');
      expect(r.visualBlocks.map((b) => b.blockId), ['2', '3']); // 无重复/无丢失
    });

    test(
      '全部 visual 被 uncaptionedVisualIds 认领 → 旧 heuristic 移除，产 ai_visual_only cropRequest',
      () {
        final caps = {
          'p0:c0': CaptionRef(
            0,
            0,
            _capInfo('Figure 1.', 'Figure_1', '0', bbox: [0, 800, 100, 820]),
          ),
        };
        final heuristic = [
          FigureManifestEntry(
            imagePath: '/old/Figure_1.png',
            captionText: 'Figure 1. ...',
            pageIndex: 0,
            blockIds: ['0', '2', '3'],
          ),
        ];
        final vis = {
          'p0:b2': VisualRef(0, _block('2', 'image', [0, 0, 50, 50])),
          'p0:b3': VisualRef(0, _block('3', 'image', [0, 0, 50, 50])),
        };
        final result = FigureFixResult(
          figures: const [],
          orphanCaptionIds: const {},
          uncaptionedVisualIds: {'p0:b2', 'p0:b3'},
        );
        final plan = FigureFixService.mergeFigures(
          result: result,
          heuristic: heuristic,
          captionRegistry: caps,
          visualRegistry: vis,
        );
        expect(plan.keptHeuristic, isEmpty);
        // 每个 visual 一条 ai_visual_only 匿名 cropRequest，均无 caption 关联。
        expect(plan.cropRequests.length, 2);
        for (final r in plan.cropRequests) {
          expect(r.captionBlockId, isNull);
          expect(r.captionText, isEmpty);
          expect(r.captionSource, 'none');
          expect(r.pairMethod, 'ai_visual_only');
        }
        expect(
          plan.cropRequests
              .expand((r) => r.visualBlocks.map((b) => b.blockId))
              .toSet(),
          {'2', '3'},
        );
      },
    );
  });

  group('buildInventory / assembleUserPrompt', () {
    test('复合 id 格式与 page inventory 结构', () {
      final pages = [
        PageData(
          0,
          [
            _block('0', 'figure_title', [
              0,
              800,
              100,
              820,
            ], content: 'Figure 1. ...'),
            _block('1', 'image', [0, 0, 100, 100]),
          ],
          '',
          const ColumnLayout(
            isDoubleColumn: false,
            pageLeft: 0,
            pageRight: 1000,
            leftColRight: null,
            rightColLeft: null,
          ),
        ),
      ];
      final caps = <String, CaptionRef>{
        'p0:c0': CaptionRef(
          0,
          0,
          _capInfo('Figure 1.', 'Figure_1', '0', bbox: [0, 800, 100, 820]),
        ),
      };
      final vis = <String, VisualRef>{
        'p0:b1': VisualRef(0, _block('1', 'image', [0, 0, 100, 100])),
      };
      final inv = FigureFixService.buildInventory(
        [0],
        pages,
        caps,
        vis,
        const [],
      );
      expect((inv['pages'] as List).length, 1);
      final page = (inv['pages'] as List).single as Map<String, dynamic>;
      expect(page['captions'].length, 1);
      expect((page['captions'] as List).single['caption_id'], 'p0:c0');
      expect((page['visuals'] as List).single['visual_id'], 'p0:b1');
      expect((inv['candidate_hints'] as List).single['candidates'], isNotEmpty);

      final prompt = FigureFixService.assembleUserPrompt(inv);
      expect(prompt, contains('p0:c0'));
      expect(prompt, contains('p0:b1'));
      expect(prompt, contains('Page inventory'));
    });

    test('text 子图序号进入 inventory 并携带 bbox 与 role', () {
      final label = _block('sub', 'text', [110, 210, 140, 230], content: '(a)');
      final pages = [
        PageData(
          0,
          [label],
          '',
          const ColumnLayout(
            isDoubleColumn: false,
            pageLeft: 0,
            pageRight: 1000,
            leftColRight: null,
            rightColLeft: null,
          ),
        ),
      ];
      final visualRegistry = <String, VisualRef>{
        'p0:bsub': VisualRef(0, label),
      };

      final inventory = FigureFixService.buildInventory(
        [0],
        pages,
        const <String, CaptionRef>{},
        visualRegistry,
        const [],
      );
      final page = (inventory['pages'] as List).single as Map<String, dynamic>;
      final visual = (page['visuals'] as List).single as Map<String, dynamic>;

      expect(visual['visual_id'], 'p0:bsub');
      expect(visual['bbox'], [110.0, 210.0, 140.0, 230.0]);
      expect(visual['role'], 'subfigure_label');
    });
  });

  group('buildOutputSchema / estimateTokens', () {
    test('schema 根 object 含三必需字段', () {
      final s = FigureFixService.buildOutputSchema();
      expect(s['type'], 'object');
      expect(
        (s['required'] as List),
        containsAll(['figures', 'orphan_captions', 'uncaptioned_visuals']),
      );
      expect(s['additionalProperties'], false);
    });

    test('estimateTokens 为正', () {
      final t = FigureFixService.estimateTokens({'x': 'a' * 1000});
      expect(t, greaterThan(0));
    });
  });
}

// ─── 桩构造 ──────────────────────────────────────────────

LayoutBlock _block(
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

CaptionCandidateInfo _capInfo(
  String text,
  String captionName,
  String blockId, {
  List<double>? bbox,
  List<String> continuation = const [],
}) {
  return CaptionCandidateInfo(
    pageIndex: 0,
    text: text,
    captionName: captionName,
    source: CaptionSource.blockMatch,
    bbox: bbox,
    blockId: blockId,
    continuationBlocks: [
      for (final bid in continuation)
        LayoutBlock(
          blockId: bid,
          blockLabel: 'text',
          blockBbox: const [0, 0, 0, 0],
          blockContent: '',
        ),
    ],
    groupId: null,
    blockOrder: null,
  );
}
