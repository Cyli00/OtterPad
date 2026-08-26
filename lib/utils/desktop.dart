import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isDesktopOs =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

bool get isAppleDesktop => !kIsWeb && Platform.isMacOS;
