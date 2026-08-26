import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/book/document.dart';
import '../data/models/collection/favorite.dart';
import '../pages/library/search_page.dart';
import '../pages/library/view.dart';
import '../pages/main/view.dart';
import '../pages/reader/chat/document_chat_page.dart';
import '../pages/reader/view.dart';
import '../pages/setting/api_settings_page.dart';
import '../pages/setting/ocr_settings_page.dart';
import '../pages/setting/appearance_settings_page.dart';
import '../pages/setting/backup_settings_page.dart';
import '../pages/setting/network_settings_page.dart';
import '../pages/setting/about_page.dart';
import '../pages/setting/general_settings_page.dart';
import '../pages/setting/storage_space_page.dart';
import '../pages/setting/view.dart';
import '../pages/shelf/add_documents_to_favorite_page.dart';
import '../pages/shelf/favorite_detail_page.dart';
import '../pages/shelf/cloud_sync_page.dart';
import '../pages/shelf/no_file_entries_page.dart';
import '../pages/shelf/reading_history_page.dart';
import '../pages/shelf/view.dart';
import 'app_routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 平级切换：FadeThroughTransition（旧页淡出 → 新页淡入）
CustomTransitionPage<T> _lateral<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: kAnimSlow,
    reverseTransitionDuration: kAnimSlow,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    },
  );
}

/// 纵向钻入：SharedAxisTransition vertical（进入↑ / 返回↓）
CustomTransitionPage<T> _drillIn<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: kAnimSlow,
    reverseTransitionDuration: kAnimSlow,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.vertical,
        child: child,
      );
    },
  );
}

/// 阅读器入场：Scale + Fade + 微上移，模拟 Container Transform 的「展开」感
CustomTransitionPage<T> _readerEntry<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: kAnimSlow,
    reverseTransitionDuration: kAnimSlow,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: kAnimCurve,
        reverseCurve: kAnimCurveReverse,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// 横向前进：SharedAxisTransition horizontal（前进→ / 返回←）
CustomTransitionPage<T> _forward<T>({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: kAnimSlow,
    reverseTransitionDuration: kAnimSlow,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.horizontal,
        child: child,
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.library,
    // 防御：即便系统把 content:// / file:// 等 URI 塞进路由，也回到首页。
    // 真正的文件导入由 ShareReceiverService（MethodChannel）处理。
    redirect: (context, state) {
      final scheme = state.uri.scheme;
      if (scheme == 'content' || scheme == 'file') {
        return AppRoutes.library;
      }
      return null;
    },
    routes: [
      // 全屏页面（不含底部/侧边导航栏）
      GoRoute(
        path: AppRoutes.reader,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _readerEntry(
          state: state,
          child: ReaderPage(document: state.extra! as Document),
        ),
        routes: [
          GoRoute(
            path: 'chat',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (context, state) => _forward(
              state: state,
              child: DocumentChatPage(
                args: state.extra! as DocumentChatPageArgs,
              ),
            ),
          ),
        ],
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
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        _forward(state: state, child: const SearchPage()),
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
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _drillIn(
                      state: state,
                      child: FavoriteDetailPage(
                        favorite: state.extra! as Favorite,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'add-documents',
                        parentNavigatorKey: rootNavigatorKey,
                        pageBuilder: (context, state) => _forward(
                          state: state,
                          child: AddDocumentsToFavoritePage(
                            favorite: state.extra! as Favorite,
                          ),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'history',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _drillIn(
                      state: state,
                      child: const ReadingHistoryPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'no-file-entries',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _drillIn(
                      state: state,
                      child: const NoFileEntriesPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'cloud-sync',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        _drillIn(state: state, child: const CloudSyncPage()),
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
                builder: (context, state) =>
                    const SettingPage(mode: SettingNavMode.shell),
              ),
            ],
          ),
        ],
      ),

      // overlay 设置（root 平级）
      GoRoute(
        path: AppRoutes.settingsOverlay,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _forward(
          state: state,
          child: const SettingPage(mode: SettingNavMode.overlay),
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayExtract,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _lateral(state: state, child: const OcrSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayApi,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _lateral(state: state, child: const ApiSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayGeneral,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _lateral(state: state, child: const GeneralSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayNetwork,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _lateral(state: state, child: const NetworkSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayAppearance,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _lateral(state: state, child: const AppearanceSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayBackup,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _lateral(state: state, child: const BackupSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayStorage,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _forward(state: state, child: const StorageSpacePage()),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayAbout,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _lateral(state: state, child: const AboutPage()),
      ),
    ],
  );
});
