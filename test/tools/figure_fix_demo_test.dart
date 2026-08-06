// 一次性 demo 工具：用真实 extract.json 跑 figure-fix 管线。
//
// 用法（分两步，中间用 subagent 当 LLM）：
//   1. flutter test test/tools/figure_fix_demo_test.dart --plain-name demoAnalyze
//      → 产出 {dir}/figure_inventory.txt（user prompt）+ figure_system_prompt.txt
//   2. 把 figure_system_prompt.txt + figure_inventory.txt 喂给 subagent，
//      把 subagent 返回的 JSON 存为 {dir}/figure_llm.json
//   3. flutter test test/tools/figure_fix_demo_test.dart --plain-name demoApply
//      → 读 figure_llm.json → parseAndValidate → mergeFigures → 裁图到 {dir}/figures_llm/
//      + 写 figures_llm/figures.json
//
// 路径硬编码为用户指定的文献目录。文件不存在则 skip。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:otter_pad/services/figure_extract_service.dart';
import 'package:otter_pad/services/figure_fix_service.dart';
import 'package:otter_pad/services/prompts.dart';

const _dir =
    r'C:\Users\leahd\AppData\Roaming\io.github.cyli00\OtterPad\OtterPad\library\c2763bc1-5aad-d64c-3ab7-a5d418c1a817';
const _pdfPath = r'C:\Users\leahd\AppData\Roaming\io.github.cyli00\OtterPad\OtterPad\library\c2763bc1-5aad-d64c-3ab7-a5d418c1a817\source.pdf';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FigureExtractService.instance.init();
  });

  test('demoAnalyze: 生成 inventory prompt', () async {
    final pdf = File(_pdfPath);
    if (!pdf.existsSync()) {
      print('SKIP: source.pdf 不存在 @ $_pdfPath');
      return;
    }
    final analysis = await FigureFixService.instance.analyze(pdfPath: _pdfPath);
    final userPrompt = FigureFixService.assembleUserPrompt(analysis.inventory);

    await File(p.join(_dir, 'figure_system_prompt.txt'))
        .writeAsString(Prompts.figureFixSystem);
    await File(p.join(_dir, 'figure_inventory.txt')).writeAsString(userPrompt);

    print('analyze 完成: pages=${analysis.pages.length}, '
        'captions=${analysis.captionRegistry.length}, '
        'visuals=${analysis.visualRegistry.length}, '
        'heuristic=${analysis.heuristic.length}, '
        'estTokens=${analysis.estimatedTokens}');
    print('inventory → ${p.join(_dir, 'figure_inventory.txt')}');
  });

  test('demoApply: 读 figure_llm.json 裁图到 figures_llm/', () async {
    final pdf = File(_pdfPath);
    final llmFile = File(p.join(_dir, 'figure_llm.json'));
    if (!pdf.existsSync()) {
      print('SKIP: source.pdf 不存在');
      return;
    }
    if (!llmFile.existsSync()) {
      print('SKIP: figure_llm.json 不存在，请先跑 demoAnalyze + subagent');
      return;
    }

    final analysis = await FigureFixService.instance.analyze(pdfPath: _pdfPath);
    final llmText = await llmFile.readAsString();

    final result = FigureFixService.parseAndValidate(
      llmText,
      analysis.captionRegistry,
      analysis.visualRegistry,
    );
    print('LLM 解析: figures=${result.figures.length}, '
        'orphans=${result.orphanCaptionIds.length}, '
        'uncaptioned=${result.uncaptionedVisualIds.length}');

    final plan = FigureFixService.mergeFigures(
      result: result,
      heuristic: analysis.heuristic,
      captionRegistry: analysis.captionRegistry,
      visualRegistry: analysis.visualRegistry,
    );
    print('合并: cropRequests=${plan.cropRequests.length}, '
        'keptHeuristic=${plan.keptHeuristic.length}');

    final outDir = p.join(_dir, 'figures_llm');
    final pageBlocks = [for (final pg in analysis.pages) pg.blocks];

    final manifest = await FigureExtractService.instance.cropFiguresFromSegments(
      pdfPath: _pdfPath,
      segments: plan.cropRequests,
      pageBlocks: pageBlocks,
      outputDir: outDir,
      onProgress: (done, total) => print('  crop $done/$total'),
    );
    print('裁剪完成: ${manifest.length} 张图 → $outDir');

    // figures_llm/figures.json：AI 重裁 + 未触碰启发式条目。
    final combined = [...manifest, ...plan.keptHeuristic];
    combined.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    await File(p.join(outDir, 'figures.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'figures': [for (final e in combined) e.toJson()],
        'diagnostics': {
          'source': 'ai_fix_demo',
          'ai_figures': manifest.length,
          'kept_heuristic': plan.keptHeuristic.length,
        },
      }),
    );
    print('manifest → ${p.join(outDir, 'figures.json')}');
  });
}