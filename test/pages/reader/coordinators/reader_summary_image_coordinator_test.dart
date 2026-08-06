import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/pages/reader/coordinators/reader_summary_image_coordinator.dart';

/// 空 [ImageStreamCompleter] 桩：仅用于把 key 塞进全局 ImageCache（保持 live）。
/// 不做真实解码——测试只关心 evict 契约，obtainKey / putIfAbsent / evict 都只按
/// key 走缓存，不读文件，因此无需真实图片字节，也不触发 FakeAsync 下的真实 IO。
class _FakeCompleter extends ImageStreamCompleter {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('evictSummaryImageCaches 清理三类渲染路径的缓存 key', (tester) async {
    addTearDown(() => PaintingBinding.instance.imageCache.clear());

    // 路径无需真实存在——三类 provider 的 obtainKey/evict 只按 key 走缓存。
    const path = 'non_existent_summary.png';

    // 三类渲染路径对应 provider（与真实渲染一致）。
    final fileProvider = FileImage(File(path));
    final resizeProvider = ResizeImage(fileProvider, width: 600);
    final extProvider = ExtendedFileImageProvider(File(path));

    final cache = PaintingBinding.instance.imageCache;
    final fileKey = await fileProvider.obtainKey(ImageConfiguration.empty);
    final resizeKey = await resizeProvider.obtainKey(ImageConfiguration.empty);
    final extKey = await extProvider.obtainKey(ImageConfiguration.empty);

    // 关键点：FileImage 与 ExtendedFileImageProvider 是不同 runtimeType → 不同 key，
    // 证明第三次 evict（extended_image 键）不可省，防止维护者误删。
    expect(fileKey, isNot(equals(extKey)));
    expect(resizeKey, isNot(equals(fileKey)));
    expect(resizeKey, isNot(equals(extKey)));

    // 预热：把三类 key 塞进全局 ImageCache 作为 live 条目。
    cache.putIfAbsent(fileKey, _FakeCompleter.new);
    cache.putIfAbsent(resizeKey, _FakeCompleter.new);
    cache.putIfAbsent(extKey, _FakeCompleter.new);
    expect(cache.statusForKey(fileKey).tracked, isTrue);
    expect(cache.statusForKey(resizeKey).tracked, isTrue);
    expect(cache.statusForKey(extKey).tracked, isTrue);

    // 统一清理 helper 一次驱逐三类键。
    await ReaderSummaryImageCoordinator.evictSummaryImageCaches(path);

    expect(cache.statusForKey(fileKey).tracked, isFalse);
    expect(cache.statusForKey(resizeKey).tracked, isFalse);
    expect(cache.statusForKey(extKey).tracked, isFalse);
  });
}
