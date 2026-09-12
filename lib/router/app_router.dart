import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import '../utils/desktop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/book/document.dart';
import '../data/models/collection/favorite.dart';
import '../pages/library/search_page.dart';
import '../pages/library/view.dart';
import '../pages/main/view.dart';
import '../pages/reader/chat/document_chat_page.dart';
import '../pages/reader/view.dart';
import '../pages/setting/view.dart';
import '../pages/shelf/add_documents_to_favorite_page.dart';
import '../pages/shelf/favorite_detail_page.dart';
import '../pages/shelf/cloud_sync_page.dart';
import '../pages/shelf/no_file_entries_page.dart';
import '../pages/shelf/reading_history_page.dart';
import '../pages/shelf/view.dart';
import 'app_routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 阅读器路由参数：文档 + 可选的卡片源矩形（容器变换起点，root Navigator 坐标系）
typedef ReaderArgs = ({Document doc, Rect? sourceRect});

/// Android 预测返回：手势进行中走框架 PredictiveBack，否则回落 [fallback]。
Widget _maybePredictiveBack<T>({
  required BuildContext context,
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  required Widget Function() fallback,
}) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final route = ModalRoute.of(context);
    if (route is PageRoute<T>) {
      return const PredictiveBackPageTransitionsBuilder().buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
  }
  return fallback();
}

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
      return _maybePredictiveBack<T>(
        context: context,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
        fallback: () => FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        ),
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
      return _maybePredictiveBack<T>(
        context: context,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
        fallback: () => SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: SharedAxisTransitionType.vertical,
          child: child,
        ),
      );
    },
  );
}

/// 桌面阅读器用淡入淡出保持导航栏位置稳定；移动端保留卡片容器变换。
CustomTransitionPage<T> _readerEntry<T>({
  required Widget child,
  required GoRouterState state,
  required Rect? sourceRect,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: isDesktopOs
        ? kAnim
        : (sourceRect != null ? kAnimEmphasis : kAnimSlow),
    reverseTransitionDuration: isDesktopOs
        ? kAnimFast
        : (sourceRect != null ? kAnimEmphasis : kAnimSlow),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: kAnimCurve,
        reverseCurve: kAnimCurveReverse,
      );
      if (isDesktopOs) {
        return FadeTransition(opacity: curved, child: child);
      }
      final fullRect = Offset.zero & MediaQuery.sizeOf(context);
      final from = sourceRect;
      // 无起点，或起点卡片已滚出屏幕 → 回落通用开场
      if (from == null || !from.overlaps(fullRect)) {
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
      }
      // 页面全程按全屏布局（避免 WebView 重排），只对最终呈现做
      // 裁切 + 到卡片矩形的缩放平移——手写双边界容器变换。
      return AnimatedBuilder(
        animation: curved,
        child: child,
        builder: (context, page) {
          if (page == null) return const SizedBox.shrink();
          final t = curved.value;
          final rect = Rect.lerp(from, fullRect, t)!;
          final sx = rect.width / fullRect.width;
          final sy = rect.height / fullRect.height;
          final center = fullRect.center;
          final d = rect.center - center;
          // 前段快速淡入，避免与旧页重叠过久
          final opacity = Curves.easeIn.transform(
            const Interval(0, 0.5).transform(t),
          );
          return ClipRRect(
            clipper: _RectMorphClipper(
              RRect.fromRectAndRadius(rect, Radius.circular(16 * (1 - t))),
            ),
            child: Opacity(
              opacity: opacity,
              child: Transform(
                origin: center,
                transform: Matrix4.translationValues(d.dx, d.dy, 0)
                  ..scaleByDouble(sx, sy, 1.0, 1.0),
                child: page,
              ),
            ),
          );
        },
      );
    },
  );
}

/// 固定 RRect 裁切（圆角随容器变换从 16 收拢为 0）
class _RectMorphClipper extends CustomClipper<RRect> {
  const _RectMorphClipper(this.rrect);

  final RRect rrect;

  @override
  RRect getClip(Size size) => rrect;

  @override
  bool shouldReclip(_RectMorphClipper old) => old.rrect != rrect;
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
      return _maybePredictiveBack<T>(
        context: context,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
        fallback: () => SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: SharedAxisTransitionType.horizontal,
          child: child,
        ),
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
        pageBuilder: (context, state) {
          final args = state.extra! as ReaderArgs;
          return _readerEntry(
            state: state,
            sourceRect: args.sourceRect,
            child: ReaderPage(document: args.doc),
          );
        },
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
      // 分组 overlay：统一走 SettingPage(initialSection:)，宽屏左右分栏、
      // 窄屏整页，一次 pop 回到调用页（禁止 overlay 嵌套 routes）
      GoRoute(
        path: AppRoutes.settingsOverlayExtract,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _lateral(
          state: state,
          child: const SettingPage(
            mode: SettingNavMode.overlay,
            initialSection: SettingsSection.extract,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayApi,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _lateral(
          state: state,
          child: const SettingPage(
            mode: SettingNavMode.overlay,
            initialSection: SettingsSection.api,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayGeneral,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _lateral(
          state: state,
          child: const SettingPage(
            mode: SettingNavMode.overlay,
            initialSection: SettingsSection.general,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayNetwork,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _lateral(
          state: state,
          child: const SettingPage(
            mode: SettingNavMode.overlay,
            initialSection: SettingsSection.network,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayAppearance,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _lateral(
          state: state,
          child: const SettingPage(
            mode: SettingNavMode.overlay,
            initialSection: SettingsSection.appearance,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayBackup,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _lateral(
          state: state,
          child: const SettingPage(
            mode: SettingNavMode.overlay,
            initialSection: SettingsSection.backup,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayStorage,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _forward(
          state: state,
          child: const SettingPage(
            mode: SettingNavMode.overlay,
            initialSection: SettingsSection.storage,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settingsOverlayAbout,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _lateral(
          state: state,
          child: const SettingPage(
            mode: SettingNavMode.overlay,
            initialSection: SettingsSection.about,
          ),
        ),
      ),
    ],
  );
});
