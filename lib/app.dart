import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/main/view.dart';
import 'providers/theme_provider.dart';

class NightReaderApp extends ConsumerWidget {
  const NightReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);

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

        return MaterialApp(
          title: '晚读 Otero',
          debugShowCheckedModeBanner: false,
          themeMode: themeState.mode,
          theme: ThemeData(
            colorScheme: lightScheme,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkScheme,
            useMaterial3: true,
          ),
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            final iconBrightness = brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: iconBrightness,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor:
                    Colors.transparent.withAlpha(1),
                systemNavigationBarContrastEnforced: false,
              ),
              child: child!,
            );
          },
          home: const MainPage(),
        );
      },
    );
  }
}
