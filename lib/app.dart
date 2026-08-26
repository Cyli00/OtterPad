import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';
import 'pages/library/widgets/identifier_dialog.dart';
import 'providers/locale_provider.dart';
import 'providers/task_activity_provider.dart';
import 'providers/task_provider.dart';
import 'providers/theme_provider.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'services/snackbar_service.dart';
import 'shortcuts/app_intents.dart';
import 'utils/desktop.dart';
import 'utils/responsive.dart';
import 'widgets/desktop_drop_host.dart';
import 'widgets/desktop_shortcut_map.dart';
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
              wrapped = Shortcuts(
                shortcuts: kDesktopShortcutMap,
                child: Actions(
                  actions: {
                    ImportPdfIntent: EnabledCallbackAction<ImportPdfIntent>(
                      onInvoke: (_) {
                        unawaited(_importPdfs(ref));
                        return null;
                      },
                    ),
                    ImportByIdentifierIntent:
                        EnabledCallbackAction<ImportByIdentifierIntent>(
                          onInvoke: (_) {
                            final ctx =
                                rootNavigatorKey.currentContext ?? context;
                            unawaited(_importByIdentifier(ctx, ref));
                            return null;
                          },
                        ),
                    OpenLibrarySearchIntent:
                        EnabledCallbackAction<OpenLibrarySearchIntent>(
                          onInvoke: (_) {
                            final ctx =
                                FocusManager.instance.primaryFocus?.context ??
                                rootNavigatorKey.currentContext ??
                                context;
                            ctx.push(AppRoutes.librarySearch);
                            return null;
                          },
                        ),
                    OpenSettingsIntent:
                        EnabledCallbackAction<OpenSettingsIntent>(
                          enabled: () => _settingsShortcutEnabled(router),
                          onInvoke: (_) {
                            _openSettings(context);
                            return null;
                          },
                        ),
                  },
                  child: Column(
                    children: [
                      const WindowChrome(),
                      Expanded(child: DesktopDropHost(child: child)),
                    ],
                  ),
                ),
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
                  systemNavigationBarDividerColor: Colors.transparent.withAlpha(
                    1,
                  ),
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

bool _settingsShortcutEnabled(GoRouter router) {
  final path = router.state.uri.path;
  if (path == AppRoutes.settings) return false;
  if (path.startsWith(AppRoutes.settingsOverlay)) return false;
  return true;
}

void _openSettings(BuildContext context) {
  final ctx =
      FocusManager.instance.primaryFocus?.context ??
      rootNavigatorKey.currentContext ??
      context;
  if (!ctx.mounted) return;
  final showRail = Responsive.showNavigationRail(ctx);
  final shell = StatefulNavigationShell.maybeOf(ctx);
  if (showRail && shell != null) {
    shell.goBranch(2);
    return;
  }
  ctx.push(AppRoutes.settingsOverlay);
}

Future<void> _importPdfs(WidgetRef ref) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    allowMultiple: true,
  );
  if (result == null) return;
  final paths = result.files
      .where((f) => f.path != null)
      .map((f) => f.path!)
      .toList();
  if (paths.isEmpty) return;
  await ref.read(taskProvider.notifier).addFiles(paths);
}

Future<void> _importByIdentifier(BuildContext context, WidgetRef ref) async {
  if (!context.mounted) return;
  final identifier = await showIdentifierDialog(context);
  if (identifier == null) return;
  ref.read(taskProvider.notifier).addByIdentifier(identifier);
}
