import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'providers/task_activity_provider.dart';
import 'providers/theme_provider.dart';
import 'router/app_router.dart';
import 'services/snackbar_service.dart';
import 'utils/desktop.dart';
import 'widgets/desktop_drop_host.dart';
import 'widgets/window_chrome.dart';

/// 各平台系统默认字体族
String? get _systemFontFamily {
  if (Platform.isWindows) return 'Microsoft YaHei UI';
  if (Platform.isMacOS || Platform.isIOS) return '.AppleSystemUIFont';
  // Android / Linux：返回 null 让 Flutter 走平台默认
  return null;
}

class OtterPadApp extends ConsumerWidget {
  const OtterPadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);

    // snackbar surface：Task Activity 变化时把单槽同步到当前活集合。
    ref.listen(taskActivityProvider, (_, tasks) {
      ref.read(snackBarServiceProvider).renderActiveTasks(tasks);
    });

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        ColorScheme lightScheme;
        ColorScheme darkScheme;

        if (themeState.useDynamicColor &&
            lightDynamic != null &&
            darkDynamic != null) {
          lightScheme = ColorScheme.fromSeed(
            seedColor: lightDynamic.primary,
            brightness: Brightness.light,
          );
          darkScheme = ColorScheme.fromSeed(
            seedColor: darkDynamic.primary,
            brightness: Brightness.dark,
          );
        } else {
          lightScheme = ColorScheme.fromSeed(
            seedColor: themeState.seedColor,
            brightness: Brightness.light,
          );
          darkScheme = ColorScheme.fromSeed(
            seedColor: themeState.seedColor,
            brightness: Brightness.dark,
          );
        }

        return MaterialApp.router(
          scaffoldMessengerKey: scaffoldMessengerKey,
          title: 'OtterPad',
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          themeMode: themeState.mode,
          theme: ThemeData(
            colorScheme: lightScheme,
            useMaterial3: true,
            fontFamily: _systemFontFamily,
          ),
          darkTheme: ThemeData(
            colorScheme: darkScheme,
            useMaterial3: true,
            fontFamily: _systemFontFamily,
          ),
          routerConfig: router,
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            final iconBrightness = brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light;
            final mq = MediaQuery.of(context);

            // 桌面端：在路由内容上方注入自定义 chrome（替换原生标题栏）
            Widget wrapped = child!;
            if (isDesktopOs) {
              wrapped = Column(
                children: [
                  const WindowChrome(),
                  Expanded(child: DesktopDropHost(child: child)),
                ],
              );
            }

            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(themeState.textScale),
              ),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: iconBrightness,
                  systemNavigationBarIconBrightness: iconBrightness,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarDividerColor:
                      Colors.transparent.withAlpha(1),
                  systemNavigationBarContrastEnforced: false,
                ),
                child: wrapped,
              ),
            );
          },
        );
      },
    );
  }
}
