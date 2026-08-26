import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/api_provider.dart';
import '../../../providers/document_lifecycle_provider.dart';
import '../../../providers/favorites_provider.dart';
import '../../../providers/proxy_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../../router/app_routes.dart';
import '../../../services/ai_settings_prompt.dart';
import '../../../services/batch_extract_service.dart';
import '../../../services/haptics.dart';
import '../../../services/snackbar_service.dart';
import '../../../utils/desktop.dart';
import '../../../utils/doc_paths.dart';
import '../../../widgets/app_context_menu.dart';
import '../../../widgets/app_dialog.dart';
import '../../shelf/widgets/create_favorite_dialog.dart';
import '../../shelf/widgets/pick_favorite_sheet.dart';
import 'batch_progress_sheet.dart';

/// 文献卡片统一交互入口
///
/// 所有使用 [DocListCard] / [DocumentCard] 的页面（文献库、收藏夹、无文件条目等）
/// 都应通过此类获取回调，避免交互逻辑分散在各页面中导致不同步。
class DocCardActions {
  /// 点击卡片 → 记录阅读历史并打开 PDF 阅读器。
  ///
  /// [context] 为卡片自身（而非页面容器）时，会量取卡片在 root Navigator
  /// 坐标系中的矩形作为「卡片→阅读器」容器变换的起点矩形。
  static void openReader(BuildContext context, WidgetRef ref, Document doc) {
    ref.read(documentLifecycleProvider).recordOpen(doc.id);
    context.push(
      AppRoutes.reader,
      extra: (doc: doc, sourceRect: _sourceRectOf(context)),
    );
  }

  /// 量取 [context] 对应 RenderBox 在 root Navigator 中的矩形。
  /// context 是整页容器（与 Navigator 几乎同尺寸）或不可测时返回 null——
  /// 那种起点做容器变换没有意义。
  static Rect? _sourceRectOf(BuildContext context) {
    final box = context.findRenderObject();
    final nav = Navigator.maybeOf(context, rootNavigator: true);
    final navBox = nav?.context.findRenderObject();
    if (box is! RenderBox ||
        !box.hasSize ||
        navBox is! RenderBox ||
        !navBox.hasSize) {
      return null;
    }
    if (box.size.width >= navBox.size.width * 0.95 &&
        box.size.height >= navBox.size.height * 0.95) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: navBox) & box.size;
  }

  /// 删除文献（级联：文库条目 + 磁盘文件 + 提取产物 + 缩略图 + 收藏夹 + 高亮 + 历史）
  static Future<void> delete(WidgetRef ref, String docId) async {
    await ref.read(documentLifecycleProvider).deleteDocument(docId);
  }

  static void handleTap({
    required bool isSelectionMode,
    required VoidCallback onOpen,
    VoidCallback? onToggle,
    VoidCallback? onModifierToggle,
    VoidCallback? onSelectRange,
  }) {
    if (isDesktopOs) {
      final keyboard = HardwareKeyboard.instance;
      if (keyboard.isShiftPressed && onSelectRange != null) {
        onSelectRange();
        return;
      }
      if ((keyboard.isControlPressed || keyboard.isMetaPressed) &&
          onModifierToggle != null) {
        onModifierToggle();
        return;
      }
    }
    if (isSelectionMode) {
      onToggle?.call();
    } else {
      onOpen();
    }
  }

  static void modifierToggle(
    WidgetRef ref,
    String docId,
    String sourceContext,
  ) {
    final sel = ref.read(selectionProvider);
    final notifier = ref.read(selectionProvider.notifier);
    if (!sel.isActive || sel.sourceContext != sourceContext) {
      notifier.enter(docId, sourceContext);
    } else {
      notifier.toggle(docId);
    }
  }

  static void selectRange(
    WidgetRef ref, {
    required String docId,
    required String sourceContext,
    required List<String> orderedIds,
  }) {
    final sel = ref.read(selectionProvider);
    final notifier = ref.read(selectionProvider.notifier);
    if (!sel.isActive || sel.sourceContext != sourceContext) {
      notifier.enter(docId, sourceContext);
    }
    notifier.selectRange(orderedIds: orderedIds, toId: docId);
  }

  static Future<void> showMenu({
    required BuildContext context,
    required WidgetRef ref,
    required Offset globalPosition,
    required Document doc,
    required String sourceContext,
    required List<String> orderedIds,
    bool canOpen = true,
    bool canExtract = true,
    bool canEnterSelection = true,
    Future<void> Function()? onDeleteOverride,
    bool confirmOverrideDelete = true,
  }) async {
    final l10n = context.l10n;
    final hasPdf = doc.contentHash != null;
    final sel = ref.read(selectionProvider);
    final inSelection = sel.isActive && sel.sourceContext == sourceContext;
    final result = await showAppContextMenu<String>(
      context: context,
      globalPosition: globalPosition,
      items: [
        if (canOpen && hasPdf)
          AppContextMenuItem(
            value: 'open',
            label: l10n.openInReader,
            icon: Symbols.menu_book_rounded,
          ),
        AppContextMenuItem(
          value: 'favorite',
          label: l10n.addToFavorite,
          icon: Symbols.bookmark_add_rounded,
        ),
        if (canExtract && hasPdf)
          AppContextMenuItem(
            value: 'extract',
            label: l10n.textExtraction,
            icon: Symbols.auto_awesome_rounded,
          ),
        if (canEnterSelection && !inSelection)
          AppContextMenuItem(
            value: 'select',
            label: l10n.enterSelection,
            icon: Symbols.check_box_rounded,
          ),
        AppContextMenuItem(
          value: 'delete',
          label: l10n.delete,
          icon: Symbols.delete_rounded,
          destructive: true,
        ),
      ],
    );
    if (!context.mounted || result == null) return;
    switch (result) {
      case 'open':
        openReader(context, ref, doc);
      case 'favorite':
        await addToFavorite(context, ref, {doc.id});
      case 'extract':
        await extract(context, ref, [doc]);
      case 'select':
        ref.read(selectionProvider.notifier).enter(doc.id, sourceContext);
      case 'delete':
        if (onDeleteOverride != null) {
          if (confirmOverrideDelete) {
            final ok = await confirmDelete(
              context,
              title: l10n.batchDelete,
              message: l10n.confirmDeleteDocuments(1),
            );
            if (!ok) return;
          }
          await onDeleteOverride();
        } else {
          final ok = await confirmDelete(
            context,
            title: l10n.batchDelete,
            message: l10n.confirmDeleteDocuments(1),
          );
          if (!ok || !context.mounted) return;
          await delete(ref, doc.id);
        }
    }
  }

  static Future<bool> confirmDelete(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, false);
            },
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, true);
            },
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  static Future<void> addToFavorite(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedIds, {
    bool exitSelection = false,
  }) async {
    if (selectedIds.isEmpty) return;

    final favorites = ref.read(favoritesProvider).value ?? const [];
    final result = await showPickFavoriteSheet(
      context: context,
      favorites: favorites,
      selectedDocumentIds: selectedIds,
      onCreateFavorite: () async {
        final res = await showCreateFavoriteDialog(context);
        if (res == null) return null;
        return ref
            .read(favoritesProvider.notifier)
            .create(emoji: res['emoji']!, name: res['name']!);
      },
    );
    if (result == null) return;

    final added = await ref
        .read(documentLifecycleProvider)
        .addToFavoriteBatch(result.favoriteId, selectedIds);
    if (!context.mounted) return;
    final skipped = selectedIds.length - added;
    final l10n = context.l10n;
    final msg = skipped == 0
        ? l10n.documentsAddedCount(added)
        : l10n.documentsAddedSkipped(added, skipped);
    ref.read(snackBarServiceProvider).showResult(message: msg);
    if (exitSelection) {
      ref.read(selectionProvider.notifier).exit();
    }
  }

  static Future<void> extract(
    BuildContext context,
    WidgetRef ref,
    List<Document> docs, {
    bool exitSelection = false,
  }) async {
    final withPdf = docs.where((d) => d.contentHash != null).toList();
    if (withPdf.isEmpty) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.noPdfFilesSelected);
      return;
    }

    final apiState = ref.read(docExtractApiProvider);
    if (!await AiSettingsPrompt.ensureExtractConfigured(
      context: context,
      apiState: apiState,
    )) {
      return;
    }
    if (!context.mounted) return;

    final items = [
      for (final d in withPdf)
        BatchExtractItem(
          documentId: d.id,
          filePath: DocPaths.pdf(d.id),
          title: d.title,
        ),
    ];

    final proxyState = ref.read(proxyProvider);
    BatchExtractService.instance.applyProxy(
      proxyState.mode,
      proxyState.host,
      proxyState.port,
    );

    if (exitSelection) {
      ref.read(selectionProvider.notifier).exit();
    }
    if (!context.mounted) return;
    await showBatchProgress(context: context, items: items, apiState: apiState);
  }
}
