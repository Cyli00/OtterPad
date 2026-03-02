import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'common/theme/app_theme.dart';
import 'router/app_pages.dart';
import 'router/app_routes.dart';

class NightReaderApp extends StatelessWidget {
  const NightReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return GetMaterialApp(
          title: 'NightReader',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(lightDynamic),
          darkTheme: AppTheme.dark(darkDynamic),
          themeMode: ThemeMode.system,
          initialRoute: AppRoutes.main,
          getPages: AppPages.routes,
        );
      },
    );
  }
}
