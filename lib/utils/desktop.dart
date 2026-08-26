import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

bool get isDesktopOs =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

bool get isAppleDesktop => !kIsWeb && Platform.isMacOS;

SingleActivator desktopActivator(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
  bool includeRepeats = false,
}) => SingleActivator(
  key,
  control: !isAppleDesktop,
  meta: isAppleDesktop,
  shift: shift,
  alt: alt,
  includeRepeats: includeRepeats,
);
