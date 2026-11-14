import 'dart:ui' as ui;

import '../src/rust/pdf.dart';

/// Rust 渲染的 RGBA 位图转为 [ui.Image]。
Future<ui.Image> decodePdfBitmap(Bitmap bitmap) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bitmap.rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: bitmap.tile.width,
    height: bitmap.tile.height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}
