import '../src/rust/api.dart';
import '../src/rust/frb_generated.dart';
import 'pdfium_library.dart';

/// 进程内唯一的 Rust 后端，启动时在其他存储之前打开。
abstract final class RustBackend {
  static Backend? _instance;

  static Backend get instance =>
      _instance ?? (throw StateError('RustBackend.start 尚未就绪'));

  /// 打开数据根 [root]（`<AppSupport>/OtterPad`），首次启动时迁移 0.1.x 数据。
  ///
  /// 事件原样转发给调用方显示进度；`Ready` 时记录后端。
  static Stream<InitializationEvent> start(String root) async* {
    await RustLib.init();
    await for (final event in initialize(
      options: BackendOptions(
        root: root,
        pdfiumLibrary: bundledPdfiumLibrary(),
        bitmapCacheBytes: BigInt.from(128 << 20),
      ),
      taskId: 'startup',
    )) {
      if (event case InitializationEvent_Ready(:final backend)) {
        _instance = backend;
      }
      yield event;
    }
  }
}
