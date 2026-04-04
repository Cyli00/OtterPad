import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
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
import '../pages/setting/backup_settings_page.dart';
import '../pages/setting/network_settings_page.dart';
import '../pages/setting/view.dart';
import '../pages/shelf/favorite_detail_page.dart';
import '../pages/shelf/no_file_entries_page.dart';
import '../pages/shelf/starred_items_page.dart';
import '../pages/shelf/view.dart';
import 'app_routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// 统一路由转场：FadeThroughTransition（旧页淡出 → 新页淡入）
CustomTransitionPage<T> _buildAnimatedPage<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
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
                    path: 'starred',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: const StarredItemsPage(),
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
                  GoRoute(
                    path: 'backup',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: const BackupSettingsPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'backupHome',
                    parentNavigatorKey: _rootNavigatorKey,
                    pageBuilder: (context, state) => _buildAnimatedPage(
                      state: state,
                      child: const BackupSettingsPage(),
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
