import 'dart:io';

import 'package:path/path.dart' as p;

/// rust_builder/hook/build.dart 打包的 PDFium，传给 Rust 的 `BackendOptions.pdfiumLibrary`。
String? bundledPdfiumLibrary() {
  final directory = p.dirname(Platform.resolvedExecutable);
  return switch (Platform.operatingSystem) {
    'macos' => p.join(
      directory,
      '..',
      'Frameworks',
      'otter_pdfium.framework',
      'otter_pdfium',
    ),
    'windows' => p.join(directory, 'otter_pdfium.dll'),
    'linux' => p.join(directory, 'lib', 'libotter_pdfium.so'),
    // 由系统在应用的原生库目录中按名称查找。
    'android' => 'libotter_pdfium.so',
    _ => null,
  };
}
