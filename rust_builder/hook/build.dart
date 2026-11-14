// 把 rust/pdfium-binaries.json 锁定的 PDFium 打进应用，供 Rust 的 pdfium-render 按路径加载。
//
// 资产名用 otter_pdfium 而不是 pdfium：避免与其他插件打包的 libpdfium 同名覆盖；
// `bundledPdfiumLibrary()` 按这个名字找库。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final target = switch ((code.targetOS, code.targetArchitecture)) {
      (OS.android, Architecture.arm64) => 'aarch64-linux-android',
      (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
      (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
      (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
      (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
      // 不发布的目标不打包；Rust 打开 PDF 时返回 Pdf 错误码。
      _ => null,
    };
    if (target == null) return;

    final manifestUri = input.packageRoot.resolve(
      '../rust/pdfium-binaries.json',
    );
    output.dependencies.add(manifestUri);
    final manifest = jsonDecode(await File.fromUri(manifestUri).readAsString())
        as Map<String, dynamic>;
    final release = manifest['release'] as String;
    final entry = (manifest['targets'] as Map<String, dynamic>)[target]
        as Map<String, dynamic>;
    final digest = entry['sha256'] as String;
    final fileName = code.targetOS.dylibFileName('otter_pdfium');
    final library = File.fromUri(
      input.outputDirectoryShared.resolve('$digest/$fileName'),
    );
    if (!library.existsSync()) {
      final bytes = await _download(
        Uri.parse(
          'https://github.com/bblanchon/pdfium-binaries/releases/download/'
          '$release/${entry['archive']}',
        ),
      );
      if (sha256.convert(bytes).toString() != digest) {
        throw StateError('PDFium archive checksum mismatch for $target');
      }
      final archive =
          TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      final members = archive.files
          .where((f) => f.isFile && f.name.split('/').last == entry['library'])
          .toList();
      if (members.length != 1) {
        throw StateError('PDFium archive has an unexpected library layout');
      }
      await library.parent.create(recursive: true);
      // 先写临时文件再改名，避免中断后留下不完整的库被下次构建当作缓存。
      final partial = File('${library.path}.partial');
      await partial.writeAsBytes(members.single.content);
      await partial.rename(library.path);
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'otter_pdfium',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}

Future<List<int>> _download(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(
          const Duration(seconds: 60),
        );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final builder = BytesBuilder(copy: false);
    await response.timeout(const Duration(seconds: 60)).forEach(builder.add);
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}
