@Tags(['tools'])
library;

// 一次性工具：用真实 LLM（auth.json 里的 key/model）跑 figure-fix 全管线。
// CI 通过 `--exclude-tags tools` 跳过；本地手动跑：
//   flutter test test/tools/figure_fix_llm_test.dart --plain-name demoLlmFix
//
// 用法：
//   flutter test test/tools/figure_fix_llm_test.dart --plain-name demoLlmFix
//
// 流程：analyze → 调 LLM（OpenAI Responses 协议）→ parseAndValidate →
// mergeFigures → 裁图到 {dir}/figure_llm/ + 写 figure_llm/figures.json。
// LLM 原始输出存 {dir}/figure_llm.json 便于复查。
//
// auth.json 格式：{"key","base_url","model"}。base_url 形如
// https://api.deepseek.com/responses，传给 AgentChatService 前剥掉尾部
// /responses，让 chatUrl 拼出 /v1/responses。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:drift/native.dart';

import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/services/agent_chat_service.dart';
import 'package:otter_pad/services/figure_extract_service.dart';
import 'package:otter_pad/services/figure_fix_service.dart';
import 'package:otter_pad/services/prompts.dart';

import '../support/local_library.dart';

const _docId = 'c2763bc1-5aad-d64c-3ab7-a5d418c1a817';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dir = localLibraryDoc(_docId);
  final pdfPath = dir == null ? null : p.join(dir, 'source.pdf');

  setUpAll(() async {
    await GStorage.initForTest(AppDatabase(NativeDatabase.memory()));
    await FigureExtractService.instance.init();
  });

  test(
    'demoLlmFix: 真实 LLM 全管线 → figure_llm/',
    () async {
    if (dir == null || pdfPath == null || !File(pdfPath).existsSync()) {
      print('SKIP: source.pdf 不存在');
      return;
    }
    final authFile = File(p.join(dir, 'auth.json'));
    if (!authFile.existsSync()) {
      print('SKIP: auth.json 不存在');
      return;
    }
    final auth = jsonDecode(await authFile.readAsString()) as Map<String, dynamic>;
    final apiKey = auth['key'] as String;
    final modelId = auth['model'] as String;
    var baseUrl = auth['base_url'] as String;
    // 剥掉尾部 /responses，让 chatUrl 拼出 /v1/responses。
    if (baseUrl.endsWith('/responses')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - '/responses'.length);
    }

    // ── analyze ──
    final analysis = await FigureFixService.instance.analyze(pdfPath: pdfPath);
    print('analyze: pages=${analysis.pages.length}, '
        'captions=${analysis.captionRegistry.length}, '
        'visuals=${analysis.visualRegistry.length}, '
        'heuristic=${analysis.heuristic.length}, '
        'estTokens=${analysis.estimatedTokens}');

    // ── 调 LLM ──
    final agentState = AgentApiState(
      provider: AgentApiProvider.openai,
      baseUrl: baseUrl,
      apiKey: apiKey,
      defaultModelId: modelId,
    );
    print('LLM 调用: model=$modelId baseUrl=$baseUrl');
    // TestWidgetsFlutterBinding 会拦截所有 HTTP 返回 400，这里恢复真实网络。
    HttpOverrides.global = null;
    final userPrompt = FigureFixService.assembleUserPrompt(analysis.inventory);
    final llmText = await AgentChatService.send(
      provider: agentState.provider,
      baseUrl: agentState.effectiveBaseUrl,
      apiKey: agentState.apiKey,
      modelId: modelId,
      systemPrompt: Prompts.figureFixSystem,
      userPrompt: userPrompt,
      schema: FigureFixService.buildOutputSchema(),
      schemaName: 'figure_fix',
      anthropicMaxTokens: 16384,
    );
    await File(p.join(dir, 'figure_llm.json')).writeAsString(llmText);
    print('LLM 原始输出 → figure_llm.json');

    // ── parse + merge ──
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

    // ── 裁图到 figure_llm/ ──
    final outDir = p.join(dir, 'figure_llm');
    final pageBlocks = [for (final pg in analysis.pages) pg.blocks];
    final manifest = await FigureExtractService.instance.cropFiguresFromSegments(
      pdfPath: pdfPath,
      segments: plan.cropRequests,
      pageBlocks: pageBlocks,
      outputDir: outDir,
      onProgress: (done, total) => print('  crop $done/$total'),
    );
    print('裁剪完成: ${manifest.length} 张图 → $outDir');

    final combined = [...manifest, ...plan.keptHeuristic];
    combined.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    await File(p.join(outDir, 'figures.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'figures': [for (final e in combined) e.toJson()],
        'diagnostics': {
          'source': 'ai_fix_llm',
          'ai_figures': manifest.length,
          'kept_heuristic': plan.keptHeuristic.length,
        },
      }),
    );
    print('manifest → ${p.join(outDir, 'figures.json')}');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
