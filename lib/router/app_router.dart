import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/book/document.dart';
import '../data/models/collection/favorite.dart';
import '../pages/library/search_page.dart';
import '../pages/library/view.dart';
import '../pages/main/view.dart';
import '../pages/reader/view.dart';
import '../pages/setting/api_settings_page.dart';
import '../pages/setting/appearance_settings_page.dart';
import '../pages/setting/network_settings_page.dart';
import '../pages/setting/view.dart';
import '../pages/shelf/favorite_detail_page.dart';
import '../pages/shelf/no_file_entries_page.dart';
import '../pages/shelf/view.dart';
import 'app_routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// 统一的页面过渡动画：fade + slideY，符合 MD3 Emphasized 过渡规范
CustomTransitionPage<T> _buildAnimatedPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child
          .animate(autoPlay: false, value: animation.value)
          .fade(
            begin: 0,
            end: 1,
            duration: 300.ms,
            curve: Curves.easeOut,
          )
          .slideY(
            begin: 0.04,
            end: 0,
            duration: 300.ms,
            curve: Curves.easeOut,
          );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.library,
    routes: [
      // 全屏页面（不含底部/侧边导航栏）
      GoRoute(
        path: AppRoutes.reader,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _buildAnimatedPage(
          state: state,
          child: ReaderPage(document: state.extra! as Document),
        ),
      ),

      // 主导航 Shell（IndexedStack 保持各 Tab 页状态）
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          // ── Tab 0: 文献库 ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.library,
                builder: (context, state) => const LibraryPage(),
                routes: [
                  GoRoute(
                    path: 'search',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: const SearchPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Tab 1: 书架 ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shelf,
                builder: (context, state) => const ShelfPage(),
                routes: [
                  GoRoute(
                    path: 'favorite',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: FavoriteDetailPage(
                        favorite: state.extra! as Favorite,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'no-file-entries',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: const NoFileEntriesPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Tab 2: 设置 ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingPage(),
                routes: [
                  GoRoute(
                    path: 'network',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: const NetworkSettingsPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'api',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: const ApiSettingsPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'appearance',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: const AppearanceSettingsPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
