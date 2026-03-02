import 'package:get/get.dart';

import '../pages/annotation/view.dart';
import '../pages/discover/view.dart';
import '../pages/download/view.dart';
import '../pages/library/view.dart';
import '../pages/login/view.dart';
import '../pages/main/view.dart';
import '../pages/reader/view.dart';
import '../pages/search/view.dart';
import '../pages/setting/view.dart';
import '../pages/shelf/view.dart';
import 'app_routes.dart';

abstract class AppPages {
  static final routes = [
    GetPage(name: AppRoutes.main, page: () => const MainPage()),
    GetPage(name: AppRoutes.library, page: () => const LibraryPage()),
    GetPage(name: AppRoutes.shelf, page: () => const ShelfPage()),
    GetPage(name: AppRoutes.reader, page: () => const ReaderPage()),
    GetPage(name: AppRoutes.annotation, page: () => const AnnotationPage()),
    GetPage(name: AppRoutes.search, page: () => const SearchPage()),
    GetPage(name: AppRoutes.discover, page: () => const DiscoverPage()),
    GetPage(name: AppRoutes.download, page: () => const DownloadPage()),
    GetPage(name: AppRoutes.setting, page: () => const SettingPage()),
    GetPage(name: AppRoutes.login, page: () => const LoginPage()),
  ];
}
