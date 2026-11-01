// 新阅读器的独立调试入口：Rust 后端以临时目录为数据根，不读写正式数据目录。
//
//   flutter run -t lib/main_reader_lab.dart
//   flutter run -t lib/main_reader_lab.dart --dart-define=READER_LAB_DOC=<docId>
//   flutter run -t lib/main_reader_lab.dart --dart-define=READER_LAB_STRESS=3000
//   flutter run --profile -t lib/main_reader_lab.dart --dart-define=READER_LAB_AUTOSCROLL=true
//
// 首次运行把 <AppSupport>/OtterPad 下的 0.1.x db/、library/ 复制到 <Temp>/reader_lab，
// 由后端迁移器导入后打开第一篇（或 READER_LAB_DOC 指定的）可阅读文献；
// 没有可用文献或指定 READER_LAB_STRESS 时生成含大量公式的合成文档。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/app_theme.dart';
import 'core/l10n.dart';
import 'core/pdfium_library.dart';
import 'pages/reader2/reader2_page.dart';
import 'pages/reader2/reader_controller.dart';
import 'src/rust/api.dart';
import 'src/rust/api/document.dart';
import 'src/rust/document.dart';
import 'src/rust/error.dart';
import 'src/rust/frb_generated.dart';

const _stress = int.fromEnvironment('READER_LAB_STRESS');
const _documentId = String.fromEnvironment('READER_LAB_DOC');
const _autoscrollEnabled = bool.fromEnvironment('READER_LAB_AUTOSCROLL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final document = _stress == 0 ? await _openLabDocument() : null;
  final model = document ?? _synthetic(_stress == 0 ? 400 : _stress);
  debugPrint(
    '[reader2] ${model.blocks.length} blocks, '
    '${model.figureImages.length} figure images '
    'from ${document == null ? 'synthetic' : 'rust'}',
  );
  _FrameStats.start();
  runApp(_LabApp(model));
}

Future<ReaderDocument?> _openLabDocument() async {
  await RustLib.init();
  final root = p.join((await getTemporaryDirectory()).path, 'reader_lab');
  final legacy = p.join(
    (await getApplicationSupportDirectory()).path,
    'OtterPad',
  );
  if (!File(p.join(root, 'db', 'otter.db')).existsSync() &&
      File(p.join(legacy, 'db', 'otter.db')).existsSync()) {
    for (final name in ['db', 'library']) {
      await _copyTree(Directory(p.join(legacy, name)), p.join(root, name));
    }
    debugPrint('[reader2] copied 0.1.x data from $legacy');
  }
  Backend? backend;
  await for (final event in initialize(
    options: BackendOptions(
      root: root,
      pdfiumLibrary: bundledPdfiumLibrary(),
      bitmapCacheBytes: BigInt.from(64 << 20),
    ),
    taskId: 'reader-lab-init',
  )) {
    switch (event) {
      case InitializationEvent_Failed(:final error):
        debugPrint('[reader2] init failed: ${error.code.name} ${error.detail}');
        return null;
      case InitializationEvent_Migration(:final progress):
        debugPrint('[reader2] migration ${progress.done}/${progress.total}');
      case InitializationEvent_Ready(backend: final ready, :final directory):
        debugPrint('[reader2] backend ready at $directory');
        backend = ready;
    }
  }
  if (backend == null) return null;
  for (final doc in await backend.documents(limit: 200, offset: 0)) {
    if (_documentId.isNotEmpty && doc.id != _documentId) continue;
    try {
      final document = await backend.readerDocument(document: doc.id);
      // 没有 OCR 结果的文献得到空模型。
      if (document.blocks.isEmpty) continue;
      final pdf = await backend.openPdf(
        document: doc.id,
        taskId: 'reader-lab-pdf',
      );
      debugPrint('[reader2] pdfium opened ${pdf.pages.length} pages');
      await backend.closePdf(handle: pdf.handle);
      debugPrint('[reader2] opened ${doc.id} "${doc.title}"');
      return document;
    } on OtterError catch (e) {
      debugPrint('[reader2] skip ${doc.id}: ${e.code.name} ${e.detail}');
    }
  }
  return null;
}

Future<void> _copyTree(Directory source, String target) async {
  if (!source.existsSync()) return;
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = p.join(target, p.relative(entity.path, from: source.path));
    await Directory(p.dirname(path)).create(recursive: true);
    await entity.copy(path);
  }
}

class _LabApp extends StatefulWidget {
  const _LabApp(this.model);

  final ReaderDocument model;

  @override
  State<_LabApp> createState() => _LabAppState();
}

class _LabAppState extends State<_LabApp> {
  late final _controller = ReaderController(widget.model);

  @override
  void initState() {
    super.initState();
    if (_autoscrollEnabled) _autoscroll(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4A6FA5);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildAppTheme(ColorScheme.fromSeed(seedColor: seed)),
      darkTheme: buildAppTheme(
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      ),
      home: Reader2Page(controller: _controller),
    );
  }
}

/// 帧耗时统计：[mark] 开始一段，[report] 输出该段 build/raster 的分位数。
abstract final class _FrameStats {
  static final _build = <int>[];
  static final _raster = <int>[];

  static void start() => SchedulerBinding.instance.addTimingsCallback((t) {
    for (final f in t) {
      _build.add(f.buildDuration.inMicroseconds);
      _raster.add(f.rasterDuration.inMicroseconds);
    }
  });

  static void mark() {
    _build.clear();
    _raster.clear();
  }

  static void report(String label) {
    String q(List<int> v) {
      if (v.isEmpty) return '-';
      v.sort();
      String at(double f) =>
          (v[((v.length - 1) * f).round()] / 1000).toStringAsFixed(1);
      return 'p50=${at(.5)} p90=${at(.9)} p99=${at(.99)} max=${at(1)}ms';
    }

    final janky = _build.indexed
        .where((e) => e.$2 + _raster[e.$1] > 16667)
        .length;
    debugPrint(
      '[reader2] $label frames=${_build.length} over16ms=$janky '
      'build ${q(_build)} | raster ${q(_raster)}',
    );
  }
}

/// READER_LAB_AUTOSCROLL：以约 2000px/s 匀速滚动 15 秒，再连续翻 40 页，分别统计帧耗时。
Future<void> _autoscroll(ReaderController controller) async {
  await Future<void>.delayed(const Duration(seconds: 2));
  ScrollPosition? find() {
    ScrollPosition? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final position = (e.state as ScrollableState).position;
        if (position.maxScrollExtent > 1000) found = position;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  final scroll = find()!;
  _FrameStats.mark();
  await scroll.animateTo(
    scroll.pixels + 30000,
    duration: const Duration(seconds: 15),
    curve: Curves.linear,
  );
  _FrameStats.report('scroll 2000px/s');

  controller.mode = ReaderMode.paged;
  await Future<void>.delayed(const Duration(seconds: 1));
  final pages = find()!;
  _FrameStats.mark();
  for (var i = 0; i < 40; i++) {
    await pages.animateTo(
      pages.pixels + pages.viewportDimension,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
  _FrameStats.report('page turn x40');
}

/// 合成文档：公式各不相同（避开尺寸缓存）；每段 4 个行内公式，每 8 段一个独立公式，每 30 段一个标题。
ReaderDocument _synthetic(int paragraphs) {
  const inline = [
    r'\frac{\partial E}{\partial w_{ij}}',
    r'\sum_{k=1}^{n} x_k^2',
    r'\mathbf{h}_t = \tanh(W\mathbf{x}_t + U\mathbf{h}_{t-1})',
    r'\alpha \in [0, 1]',
    r'\sqrt{\sigma^2 + \epsilon}',
    r'p(y \mid x; \theta)',
  ];
  const display = [
    r'\mathcal{L}(\theta) = -\frac{1}{N}\sum_{i=1}^{N} \log p_\theta(y_i \mid x_i)',
    r'\nabla_\theta J = \mathbb{E}_{\pi}\left[\sum_{t} \nabla_\theta \log \pi(a_t \mid s_t) G_t\right]',
    r'A = \begin{pmatrix} a_{11} & a_{12} \\ a_{21} & a_{22} \end{pmatrix}',
  ];
  const words =
      'Deep networks compose simple nonlinear modules into representations '
      'that grow more abstract with depth, and the gradient of the objective '
      'is propagated backwards through every layer to update the weights ';
  final blocks = <Block>[];
  Block block(BlockKind kind, List<InlineRun> runs, {int? level}) {
    final text = runs.map((r) => r.text).join();
    return Block(
      id: 'b${blocks.length}',
      kind: kind,
      headingLevel: level,
      sourceRegions: const [],
      text: text,
      markdown: text,
      revision: '${text.hashCode}',
      runs: runs,
    );
  }

  for (var i = 0; i < paragraphs; i++) {
    if (i % 30 == 0) {
      blocks.add(
        block(BlockKind.heading, [_run('Section ${i ~/ 30 + 1}')], level: 1),
      );
    }
    final runs = <InlineRun>[];
    for (var k = 0; k < 4; k++) {
      final tex = '${inline[(i + k) % inline.length]} + c_{$i}';
      runs
        ..add(_run(words.substring(0, 60 + (i * 7 + k * 13) % 110)))
        ..add(_run('\$$tex\$', math: tex));
    }
    runs.add(_run(' which closes the paragraph.'));
    blocks.add(block(BlockKind.paragraph, runs));
    if (i % 8 == 7) {
      final tex = '${display[i % display.length]} + r_{$i}';
      blocks.add(block(BlockKind.equation, [_run('\$\$$tex\$\$', math: tex)]));
    }
  }
  return ReaderDocument(
    version: 1,
    blocks: blocks,
    figures: const [],
    figureAssets: const [],
    figureImages: const [],
    assetDirectory: '',
  );
}

InlineRun _run(String text, {String? math}) => InlineRun(
  text: text,
  bold: false,
  italic: false,
  code: false,
  strike: false,
  math: math,
);
