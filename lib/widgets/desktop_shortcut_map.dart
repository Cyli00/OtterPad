import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../shortcuts/app_intents.dart';
import '../utils/desktop.dart';

/// 全局桌面快捷键。不含 Esc / Delete / Backspace。
final Map<ShortcutActivator, Intent> kDesktopShortcutMap = {
  desktopActivator(LogicalKeyboardKey.keyF): const OpenLibrarySearchIntent(),
  desktopActivator(LogicalKeyboardKey.keyO): const ImportPdfIntent(),
  desktopActivator(LogicalKeyboardKey.keyO, shift: true):
      const ImportByIdentifierIntent(),
  desktopActivator(LogicalKeyboardKey.comma): const OpenSettingsIntent(),
  desktopActivator(LogicalKeyboardKey.digit1):
      const ReaderToggleOutlineIntent(),
  desktopActivator(LogicalKeyboardKey.digit2): const ReaderToggleNotesIntent(),
  desktopActivator(LogicalKeyboardKey.digit3): const ReaderToggleAskAiIntent(),
  desktopActivator(LogicalKeyboardKey.keyT): const ReaderTranslateIntent(),
};
