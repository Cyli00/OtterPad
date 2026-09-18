import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// 只枚举系统字体族，不扫描用户文档、不加载所有字体文件到内存。
class SystemFontService {
  static Future<List<String>> listFamilies() => Isolate.run(() {
    final names = Platform.isWindows
        ? _windowsFamilies()
        : Platform.isMacOS
        ? _macFamilies()
        : Platform.isLinux
        ? _linuxFamilies()
        : <String>[];
    final result =
        names
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty && !name.startsWith('@'))
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  });
}

// LOGFONTW：5 个 LONG、8 个 BYTE、32 个 WCHAR，与 Windows SDK 布局一致。
final class _LogFont extends Struct {
  @Array(5)
  external Array<Int32> metrics;
  @Array(8)
  external Array<Uint8> flags;
  @Array(32)
  external Array<Uint16> faceName;
}

typedef _FontCallback =
    Int32 Function(Pointer<_LogFont>, Pointer<Void>, Uint32, IntPtr);

List<String> _windowsFamilies() {
  final user = DynamicLibrary.open('user32.dll');
  final gdi = DynamicLibrary.open('gdi32.dll');
  final getDc = user
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('GetDC');
  final releaseDc = user
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>)
      >('ReleaseDC');
  final enumerate = gdi
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<_LogFont>,
          Pointer<NativeFunction<_FontCallback>>,
          IntPtr,
          Uint32,
        ),
        int Function(
          Pointer<Void>,
          Pointer<_LogFont>,
          Pointer<NativeFunction<_FontCallback>>,
          int,
          int,
        )
      >('EnumFontFamiliesExW');
  final dc = getDc(nullptr);
  if (dc == nullptr) throw StateError('GetDC failed');
  final font = calloc<_LogFont>();
  final names = <String>[];
  final callback = NativeCallable<_FontCallback>.isolateLocal((
    Pointer<_LogFont> font,
    Pointer<Void> metrics,
    int type,
    int data,
  ) {
    final units = <int>[];
    for (var i = 0; i < 32 && font.ref.faceName[i] != 0; i++) {
      units.add(font.ref.faceName[i]);
    }
    names.add(String.fromCharCodes(units));
    return 1;
  }, exceptionalReturn: 0);
  try {
    // DEFAULT_CHARSET 枚举所有字符集，不能用 ANSI_CHARSET 限制为西文字体。
    font.ref.flags[3] = 1;
    enumerate(dc, font, callback.nativeFunction, 0, 0);
    if (names.isEmpty) throw StateError('No system fonts returned');
    return names;
  } finally {
    callback.close();
    calloc.free(font);
    releaseDc(nullptr, dc);
  }
}

List<String> _macFamilies() {
  final ct = DynamicLibrary.open(
    '/System/Library/Frameworks/CoreText.framework/CoreText',
  );
  final cf = DynamicLibrary.open(
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
  );
  final copyNames = ct
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'CTFontManagerCopyAvailableFontFamilyNames',
      );
  final count = cf
      .lookupFunction<
        IntPtr Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('CFArrayGetCount');
  final at = cf
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, IntPtr),
        Pointer<Void> Function(Pointer<Void>, int)
      >('CFArrayGetValueAtIndex');
  final length = cf
      .lookupFunction<
        IntPtr Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('CFStringGetLength');
  final utf8 = cf
      .lookupFunction<
        Uint8 Function(Pointer<Void>, Pointer<Utf8>, IntPtr, Uint32),
        int Function(Pointer<Void>, Pointer<Utf8>, int, int)
      >('CFStringGetCString');
  final release = cf
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('CFRelease');
  final array = copyNames();
  if (array == nullptr) throw StateError('CoreText font enumeration failed');
  try {
    final names = <String>[];
    for (var i = 0; i < count(array); i++) {
      final name = at(array, i);
      final capacity = length(name) * 4 + 1;
      final buffer = calloc<Uint8>(capacity).cast<Utf8>();
      try {
        if (utf8(name, buffer, capacity, 0x08000100) != 0) {
          names.add(buffer.toDartString());
        }
      } finally {
        calloc.free(buffer);
      }
    }
    return names;
  } finally {
    release(array);
  }
}

List<String> _linuxFamilies() {
  final result = Process.runSync('fc-list', ['--format=%{family[0]}\n']);
  if (result.exitCode != 0) throw StateError('fontconfig enumeration failed');
  return (result.stdout as String).split('\n');
}
