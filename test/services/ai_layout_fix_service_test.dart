import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/ai_layout_fix_service.dart';
import 'package:otter_pad/services/figure_extract_service.dart';
import 'package:otter_pad/services/prompts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 页尺寸 1000x1000 px。由于 _llmZoom == _apiZoom == 2.0，
  // 144 DPI 宽 = widthPx，故 144 DPI 坐标数值 == 0-1000 归一化数值，
  // 便于直接断言归一化结果。
  const pageSizes = <int, (double, double)>{0: (1000, 1000)};

  final figures = <Map<String, dynamic>>[
    {
      'img': 'fig1.png',
      'kind': 'table',
      'figure_title': 'Table 1. Parameters.',
      'page_idx': 0,
      'pair_method': 'samePage',
      'crop_bbox': <double>[100, 200, 500, 600],
      'caption_bbox': <double>[100, 610, 500, 630],
    },
  ];

  final titleInventory = <int, List<TitleInfo>>{
    0: [
      TitleInfo(
        pageIndex: 0,
        text: 'Figure 2. Orphan caption.',
        kind: 'figure',
        bbox: <double>[100, 410, 400, 430],
        blockId: 'cap2',
        source: CaptionSource.blockMatch,
      ),
    ],
  };

  final columnLayout = <int, ColumnLayout>{
    0: ColumnLayout(
      isDoubleColumn: true,
      pageLeft: 100,
      pageRight: 900,
      leftColRight: 480,
      rightColLeft: 520,
    ),
  };

  /// 从 prompt 中提取紧跟 [header] 之后的第一个 ```json 代码块并解码。
  dynamic jsonBlockAfter(String prompt, String header) {
    final h = prompt.indexOf(header);
    expect(h, greaterThanOrEqualTo(0), reason: 'header 缺失: $header');
    final start = prompt.indexOf('```json\n', h) + '```json\n'.length;
    final end = prompt.indexOf('\n```', start);
    return jsonDecode(prompt.substring(start, end));
  }

  test('manifest 条目转发 kind/caption_bbox/pair_method 且 bbox 归一化', () {
    final prompt = AiLayoutFixService.buildUserPromptForTest(
      figures: figures,
      pageSizes: pageSizes,
      titleInventoryByPage: titleInventory,
      columnLayoutByPage: columnLayout,
      yFirst: false,
    );

    final manifest = jsonBlockAfter(prompt, Prompts.layoutFixUserManifestHeader)
        as List<dynamic>;
    final entry = manifest.single as Map<String, dynamic>;

    expect(entry['kind'], 'table');
    expect(entry['pair_method'], 'samePage');
    expect(entry['bbox'], [100, 200, 500, 600]);
    expect(entry['caption_bbox'], [100, 610, 500, 630]);
  });

  test('yFirst=true 时 bbox 与 caption_bbox 按 [ymin,xmin,ymax,xmax] 排序', () {
    final prompt = AiLayoutFixService.buildUserPromptForTest(
      figures: figures,
      pageSizes: pageSizes,
      titleInventoryByPage: titleInventory,
      columnLayoutByPage: columnLayout,
      yFirst: true,
    );

    final manifest = jsonBlockAfter(prompt, Prompts.layoutFixUserManifestHeader)
        as List<dynamic>;
    final entry = manifest.single as Map<String, dynamic>;
    expect(entry['bbox'], [200, 100, 600, 500]);
    expect(entry['caption_bbox'], [610, 100, 630, 500]);
  });

  test('title inventory 段按页输出，含 kind/text/bbox（yFirst 归一化）', () {
    final prompt = AiLayoutFixService.buildUserPromptForTest(
      figures: figures,
      pageSizes: pageSizes,
      titleInventoryByPage: titleInventory,
      columnLayoutByPage: columnLayout,
      yFirst: true,
    );

    final titles = jsonBlockAfter(
      prompt,
      Prompts.layoutFixUserTitleInventoryHeader(0),
    ) as List<dynamic>;
    final t = titles.single as Map<String, dynamic>;
    expect(t['kind'], 'figure');
    expect(t['text'], 'Figure 2. Orphan caption.');
    expect(t['bbox'], [410, 100, 430, 400]); // yFirst: [t,l,b,r]
  });

  test('column layout 段按页输出，边界归一化到 0-1000', () {
    final prompt = AiLayoutFixService.buildUserPromptForTest(
      figures: figures,
      pageSizes: pageSizes,
      titleInventoryByPage: titleInventory,
      columnLayoutByPage: columnLayout,
      yFirst: false,
    );

    final col = jsonBlockAfter(
      prompt,
      Prompts.layoutFixUserColumnLayoutHeader(0),
    ) as Map<String, dynamic>;
    expect(col['double_column'], true);
    expect(col['left_col_right'], 480);
    expect(col['right_col_left'], 520);
  });

  test('无 caption_bbox 的条目省略该字段（不输出 null）', () {
    final prompt = AiLayoutFixService.buildUserPromptForTest(
      figures: [
        {
          'img': 'fig2.png',
          'kind': 'figure',
          'figure_title': 'Figure 1.',
          'page_idx': 0,
          'pair_method': 'crossPage',
          'crop_bbox': <double>[50, 50, 200, 200],
          // caption_bbox 缺失
        },
      ],
      pageSizes: pageSizes,
      titleInventoryByPage: const {},
      columnLayoutByPage: const {},
      yFirst: false,
    );

    final manifest = jsonBlockAfter(prompt, Prompts.layoutFixUserManifestHeader)
        as List<dynamic>;
    final entry = manifest.single as Map<String, dynamic>;
    expect(entry.containsKey('caption_bbox'), isFalse);
    expect(entry['kind'], 'figure');
  });
}