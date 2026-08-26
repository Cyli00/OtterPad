import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../core/storage/settings_keys.dart';
import '../../../core/storage/storage.dart';
import '../../../data/models/book/document.dart';
import '../../../data/models/chat/chat_session.dart';
import '../../../providers/api_provider.dart';
import '../../../providers/document_chat_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../router/app_routes.dart';
import '../../../services/ai_settings_prompt.dart';
import '../../../services/builtin_tools.dart';
import '../../../services/document_chat_service.dart';
import '../../../services/haptics.dart';
import '../../../services/snackbar_service.dart';
import '../../../services/tavily_search_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/tactile_press.dart';
import '../widgets/md_widget/nr_markdown_config.dart';

/// 定位原文：阅读器滚动后展示「返回问 AI」引导。
typedef LocateQuoteInReader = void Function(
  String quote,
  DocumentChatPageArgs returnArgs,
);

class DocumentChatPageArgs {
  final Document document;

  /// 划词进入时的引用文本；底栏入口为 null。
  final String? initialQuote;

  /// 从 Figure 查看器进入时附带的单张图片路径；非空时仅向模型发送此图。
  final String? figureImagePath;

  /// 会话历史「定位原文」回调——由阅读器注入（按引用文本找 markdown 偏移
  /// 并滚动）。阅读器在导航栈下层保持存活，回调可直接驱动它。
  final LocateQuoteInReader? onLocateQuote;

  /// 定位原文返回后重新打开时保留当前会话，不重置为草稿。
  final bool preserveSession;

  const DocumentChatPageArgs({
    required this.document,
    this.initialQuote,
    this.figureImagePath,
    this.onLocateQuote,
    this.preserveSession = false,
  });
}

/// 问 AI 全屏对话页。状态在 [documentChatProvider]（family by documentId），
/// 页面自己只持「待发送引用」「回答角色」两个输入态。
class DocumentChatPage extends ConsumerStatefulWidget {
  final DocumentChatPageArgs args;

  const DocumentChatPage({super.key, required this.args});

  @override
  ConsumerState<DocumentChatPage> createState() => _DocumentChatPageState();
}

class _DocumentChatPageState extends ConsumerState<DocumentChatPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputController = TextEditingController();
  String? _quote;
  String? _figureImagePath;
  ChatModelRole _role = ChatModelRole.expert;

  /// 编辑模式：被编辑的 user 消息在 messages 中的 index。
  int? _editingIndex;

  /// 会话级思考强度覆盖；null = 跟随模型参数里的设置。
  ThinkingLevel? _thinking;

  /// 模型内置网络搜索开关（会话级，默认关）。
  bool _webSearch = false;

  /// 流式输出开关（全局持久化偏好，默认开）。关闭时回答一次性整体呈现。
  static const _kChatStreamKey = SettingsKeys.chatStreamEnabled;
  late bool _stream = GStorage.setting.get(_kChatStreamKey) as bool? ?? true;

  String get _documentId => widget.args.document.id;

  @override
  void initState() {
    super.initState();
    _quote = widget.args.initialQuote?.trim();
    if (_quote?.isEmpty ?? false) _quote = null;
    _figureImagePath = widget.args.figureImagePath;
    // 每次进入都从新会话草稿开始；定位原文返回时保留会话。
    if (!widget.args.preserveSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(documentChatProvider(_documentId).notifier).startNewSession();
        }
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  /// 发图前角色解析：带图且当前 role 模型不支持图片 → 切专家 + 提示；
  /// 专家也不支持 → 提示 expertRequiresVision 并返回 null（中止）。无图或
  /// 当前模型已支持则原样返回 _role。切回快速由用户手动操作。
  ChatModelRole? _ensureRoleForFigure() {
    if (_figureImagePath == null) return _role;
    if (_role == ChatModelRole.expert) return _role;
    final notifier = ref.read(documentChatProvider(_documentId).notifier);
    if (notifier.supportsImages(_role)) return _role;
    if (!notifier.supportsImages(ChatModelRole.expert)) {
      ref.read(snackBarServiceProvider).showResult(
        message: context.l10n.expertRequiresVision,
      );
      return null;
    }
    setState(() => _role = ChatModelRole.expert);
    ref.read(snackBarServiceProvider).showResult(
      message: context.l10n.switchedToExpertForImage,
    );
    return ChatModelRole.expert;
  }

  void _send() {
    final chat = ref.read(documentChatProvider(_documentId));
    final text = _inputController.text.trim();
    if (text.isEmpty || chat.sending) return;
    Haptics.soft();

    final role = _ensureRoleForFigure();
    if (role == null) return;

    final editIdx = _editingIndex;
    if (editIdx != null) {
      ref
          .read(documentChatProvider(_documentId).notifier)
          .resendFrom(
            keepCount: editIdx,
            text: text,
            role: role,
            quotedText: _quote,
            figureImagePath: _figureImagePath,
            thinkingOverride: _thinking,
            webSearch: _webSearch,
            streaming: _stream,
          );
    } else {
      ref
          .read(documentChatProvider(_documentId).notifier)
          .send(
            text: text,
            role: role,
            quotedText: _quote,
            figureImagePath: _figureImagePath,
            thinkingOverride: _thinking,
            webSearch: _webSearch,
            streaming: _stream,
          );
    }
    _inputController.clear();
    setState(() {
      _quote = null;
      _editingIndex = null;
    });
  }

  void _cancelEditing() {
    _inputController.clear();
    setState(() {
      _editingIndex = null;
      _quote = null;
    });
  }

  void _startEditing(int messageIndex, ChatMessage msg) {
    _inputController.text = msg.content;
    setState(() {
      _editingIndex = messageIndex;
      _quote = msg.quotedText;
    });
  }

  /// 开启联网搜索时的兼容端提示：MiMo 官方端需先在平台控制台开通联网
  /// 插件；无原生搜索且未配置 Tavily 的厂商（DeepSeek 等）提示去
  /// AI 设置配置 Tavily Key，否则开关静默无效。
  void _maybeShowSearchHint() {
    final state = DocumentChatService.resolveRoleState(_role);
    // 按线上协议判定：xAI 已升格 Responses 线路、有原生搜索，不提示
    if (state == null ||
        state.provider.wireProtocol(state.effectiveBaseUrl) !=
            AgentApiProvider.openAICompatible) {
      return;
    }
    final vendor = BuiltInToolsHelper.compatSearchVendor(
      state.effectiveBaseUrl,
    );
    if (vendor == CompatSearchVendor.mimo) {
      final dismissed =
          GStorage.setting.get(_kMimoSearchHintDismissedKey) as bool? ?? false;
      if (!dismissed) _showMimoSearchHintDialog();
      return;
    }
    if (vendor == CompatSearchVendor.none &&
        !TavilySearchService.isConfigured) {
      final l10n = context.l10n;
      ref
          .read(snackBarServiceProvider)
          .showResult(
            message: l10n.tavilyNotConfiguredHint,
            duration: const Duration(seconds: 7),
            action: SnackBarAction(
              label: l10n.goToSettings,
              onPressed: () => context.push(AppRoutes.settingsOverlayApi),
            ),
          );
    }
  }

  /// 「不再提醒」的持久化 key——MiMo 联网搜索插件提示，全局一次性偏好。
  static const _kMimoSearchHintDismissedKey =
      SettingsKeys.mimoSearchPluginHintDismissed;

  static const _kMimoPluginConsoleUrl =
      'https://platform.xiaomimimo.com/console/plugin';

  /// MiMo 官方端开启联网搜索时的开通提示弹窗：超链接包成「打开插件控制台」
  /// 按钮（外部浏览器打开），「不再提醒」按钮写入 [_kMimoSearchHintDismissedKey]
  /// 后不再弹出。视觉沿用 [_showNewChatDialog] 的圆角卡片样式。
  Future<void> _showMimoSearchHintDialog() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        final width = (MediaQuery.of(dialogContext).size.width * 0.85).clamp(
          320.0,
          480.0,
        );
        return Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.mimoSearchPluginTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.mimoSearchPluginHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                // 超链接包成扁平文字按钮：§3.1 禁止 Dialog 内 OutlinedButton /
                // 等宽布局，按钮统一 TextButton。primary 文字色 + 外链图标即表达
                // 「主操作链接」，点击走外部浏览器打开插件控制台。
                TextButton.icon(
                  onPressed: () {
                    Haptics.soft();
                    launchUrl(
                      Uri.parse(_kMimoPluginConsoleUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Symbols.open_in_new_rounded, size: 18),
                  label: Text(l10n.mimoSearchPluginOpenConsole),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        GStorage.setting.put(
                          _kMimoSearchHintDismissedKey,
                          true,
                        );
                        Navigator.of(dialogContext).pop();
                      },
                      child: Text(l10n.dontRemindAgain),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(l10n.close),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 「不再提醒」的持久化 key——全局一次性偏好，不分文献。
  static const _kNewChatHintDismissedKey = SettingsKeys.chatNewSessionHintDismissed;

  /// 新建会话：首次（未勾选不再提醒）先确认「新会话仍基于当前文献」，
  /// 避免用户误以为开新会话 = 脱离文献的自由聊天。
  Future<void> _handleNewChat() async {
    final notifier = ref.read(documentChatProvider(_documentId).notifier);
    // 已经在新会话草稿上，无需任何操作
    if (ref.read(documentChatProvider(_documentId)).activeSessionId == null) {
      return;
    }
    final dismissed =
        GStorage.setting.get(_kNewChatHintDismissedKey) as bool? ?? false;
    if (dismissed) {
      notifier.startNewSession();
      setState(() => _figureImagePath = null);
      return;
    }
    final confirmed = await _showNewChatDialog();
    if (confirmed == true && mounted) {
      notifier.startNewSession();
      setState(() => _figureImagePath = null);
    }
  }

  Future<bool?> _showNewChatDialog() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    var dontRemind = false;
    return showAppDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        final width = (MediaQuery.of(dialogContext).size.width * 0.85).clamp(
          320.0,
          480.0,
        );
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Material(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: width,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.newChat,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.chatNewSessionHint(widget.args.document.title),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: dontRemind,
                      onChanged: (v) => setLocal(() => dontRemind = v ?? false),
                      title: Text(
                        l10n.dontRemindAgain,
                        style: theme.textTheme.bodyMedium,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: Text(l10n.cancel),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            if (dontRemind) {
                              GStorage.setting.put(
                                _kNewChatHintDismissedKey,
                                true,
                              );
                            }
                            Navigator.of(dialogContext).pop(true);
                          },
                          child: Text(l10n.confirm),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 点击消息中的引用块 → 让下层阅读器滚到引用原文并返回。
  void _locateQuote(String quote) {
    final locate = widget.args.onLocateQuote;
    if (locate == null) return;
    Haptics.soft();
    locate(
      quote,
      DocumentChatPageArgs(
        document: widget.args.document,
        preserveSession: true,
        onLocateQuote: widget.args.onLocateQuote,
      ),
    );
    context.pop();
  }

  Future<void> _showError(String message) async {
    final handled = await AiSettingsPrompt.showForConfigError(
      context: context,
      error: message,
    );
    if (!handled) {
      ref.read(snackBarServiceProvider).showResult(message: message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final chat = ref.watch(documentChatProvider(_documentId));

    ref.listen<String?>(
      documentChatProvider(_documentId).select((s) => s.error),
      (prev, next) {
        if (next != null && next != prev) _showError(next);
      },
    );

    final session = chat.activeSession;
    final messages = session?.messages ?? const <ChatMessage>[];

    return Scaffold(
      key: _scaffoldKey,
      // 全覆盖抽屉与系统返回/横滑手势冲突，只走按钮开启。
      drawerEnableOpenDragGesture: false,
      drawer: _buildSessionsDrawer(theme, cs),
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          session?.title ?? l10n.askAi,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Symbols.history_rounded, size: 22),
            tooltip: l10n.chatHistory,
            onPressed: () {
              Haptics.soft();
              _scaffoldKey.currentState?.openDrawer();
            },
          ),
          IconButton(
            icon: const Icon(Symbols.add_comment_rounded, size: 22),
            tooltip: l10n.newChat,
            onPressed: () {
              Haptics.soft();
              _handleNewChat();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty && !chat.sending
                ? _buildEmptyState(theme, cs)
                : _buildMessageList(
                    theme,
                    cs,
                    messages,
                    chat.sending,
                    chat.streamingText,
                  ),
          ),
          _buildComposer(theme, cs, chat.sending),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.auto_awesome_rounded,
            size: 40,
            color: cs.onSurfaceVariant.withAlpha(120),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              context.l10n.chatEmptyHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    ThemeData theme,
    ColorScheme cs,
    List<ChatMessage> messages,
    bool sending,
    String? streamingText,
  ) {
    // reverse 列表让新消息自动贴底；index 0 是最新项（发送中占位优先）。
    final itemCount = messages.length + (sending ? 1 : 0);
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (sending && index == 0) {
          if (streamingText == null || streamingText.isEmpty) {
            return _buildPendingBubble(cs);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildAssistantBubble(theme, cs, streamingText),
          );
        }
        final msgIndex = messages.length - 1 - (sending ? index - 1 : index);
        final msg = messages[msgIndex];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: msg.isUser
              ? _buildUserBubble(theme, cs, msg, msgIndex)
              : _buildAssistantBubble(
                  theme,
                  cs,
                  msg.content,
                  messageIndex: msgIndex,
                ),
        );
      },
    );
  }

  Widget _buildPendingBubble(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.onSurfaceVariant.withAlpha(140),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserMessageMenu(
    BuildContext context,
    Offset position,
    int messageIndex,
    ChatMessage msg,
  ) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surfaceContainerHigh,
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Expanded(child: Text(l10n.chatCopyMessage)),
              Icon(
                Symbols.content_copy_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              Expanded(child: Text(l10n.chatSelectText)),
              Icon(
                Symbols.select_all_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Expanded(child: Text(l10n.edit)),
              Icon(Symbols.edit_rounded, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: msg.content));
          Haptics.soft();
        case 'select':
          _showSelectableTextDialog(msg.content);
        case 'edit':
          _startEditing(messageIndex, msg);
      }
    });
  }

  void _showSelectableTextDialog(String text) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    showAppDialog(
      context: context,
      builder: (_) => Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: (MediaQuery.of(context).size.width * 0.85).clamp(300.0, 480.0),
          constraints: const BoxConstraints(maxHeight: 400),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SelectableText(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserBubble(
    ThemeData theme,
    ColorScheme cs,
    ChatMessage msg,
    int messageIndex,
  ) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPressStart: (details) {
          Haptics.medium();
          _showUserMessageMenu(
            context,
            details.globalPosition,
            messageIndex,
            msg,
          );
        },
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.quotedText != null) ...[
                // 点击引用块 → 回阅读器定位原文（末尾的 my_location 是可点暗示）
                Tooltip(
                  message: context.l10n.chatLocateSource,
                  child: TactilePress(
                    onTap: () => _locateQuote(msg.quotedText!),
                    baseColor: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: _QuoteBlock(
                              text: msg.quotedText!,
                              textColor: cs.onPrimaryContainer.withAlpha(170),
                              accentColor: cs.onPrimaryContainer.withAlpha(100),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Symbols.my_location_rounded,
                            size: 14,
                            color: cs.onPrimaryContainer.withAlpha(140),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                msg.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(
    ThemeData theme,
    ColorScheme cs,
    String content, {
    int? messageIndex,
  }) {
    const defaultSettings = ReaderSettingsState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBlock(
          data: content,
          selectable: true,
          config: buildReaderMarkdownConfig(
            settings: defaultSettings,
            colorScheme: cs,
          ),
          generator: buildReaderMarkdownGenerator(settings: defaultSettings),
        ),
        if (messageIndex != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                _BubbleAction(
                  icon: Symbols.content_copy_rounded,
                  tooltip: context.l10n.copy,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: content));
                    Haptics.soft();
                  },
                ),
                _BubbleAction(
                  icon: Symbols.share_rounded,
                  tooltip: context.l10n.share,
                  onTap: () {
                    Haptics.soft();
                    Share.share(content);
                  },
                ),
                _BubbleAction(
                  icon: Symbols.call_split_rounded,
                  tooltip: context.l10n.chatFork,
                  onTap: () {
                    Haptics.soft();
                    ref
                        .read(documentChatProvider(_documentId).notifier)
                        .forkFromMessage(messageIndex);
                  },
                ),
                _BubbleAction(
                  icon: Symbols.refresh_rounded,
                  tooltip: context.l10n.retry,
                  onTap: () {
                    Haptics.soft();
                    _retryFromAssistant(messageIndex);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _retryFromAssistant(int assistantIndex) {
    final session = ref.read(documentChatProvider(_documentId)).activeSession;
    if (session == null) return;
    ChatMessage? userMsg;
    for (var i = assistantIndex - 1; i >= 0; i--) {
      if (session.messages[i].isUser) {
        userMsg = session.messages[i];
        break;
      }
    }
    if (userMsg == null) return;
    final role = _ensureRoleForFigure();
    if (role == null) return;
    ref
        .read(documentChatProvider(_documentId).notifier)
        .resendFrom(
          keepCount: assistantIndex,
          text: userMsg.content,
          role: role,
          quotedText: userMsg.quotedText,
          figureImagePath: _figureImagePath,
          thinkingOverride: _thinking,
          webSearch: _webSearch,
          streaming: _stream,
        );
  }

  Widget _buildComposer(ThemeData theme, ColorScheme cs, bool sending) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withAlpha(80), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_editingIndex != null) ...[
                Text(
                  l10n.chatEditHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_quote != null || _figureImagePath != null) ...[
                _QuoteCard(
                  text: _quote ?? '',
                  imagePath: _figureImagePath,
                  onRemove: () {
                    Haptics.soft();
                    setState(() {
                      _quote = null;
                      _figureImagePath = null;
                    });
                  },
                ),
                const SizedBox(height: 8),
              ],
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withAlpha(100)),
                ),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_editingIndex != null)
                      Container(
                        margin: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Symbols.edit_rounded,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.chatEditingMessage,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _cancelEditing,
                              child: Icon(
                                Symbols.close_rounded,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _inputController,
                      minLines: 2,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: l10n.chatInputHint,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _role == ChatModelRole.expert
                                ? Symbols.psychology_rounded
                                : Symbols.bolt_rounded,
                            size: 22,
                            color: cs.onSurfaceVariant,
                          ),
                          tooltip: _role == ChatModelRole.expert
                              ? l10n.expert
                              : l10n.fast,
                          onPressed: () {
                            Haptics.soft();
                            setState(() {
                              _role = _role == ChatModelRole.expert
                                  ? ChatModelRole.fast
                                  : ChatModelRole.expert;
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Symbols.neurology_rounded,
                            size: 22,
                            color: _thinking != null
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          tooltip: l10n.thinkingIntensity,
                          onPressed: () {
                            Haptics.soft();
                            _showThinkingSheet();
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Symbols.travel_explore_rounded,
                            size: 22,
                            color: _webSearch
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          tooltip: l10n.searchToolLabel,
                          onPressed: () {
                            Haptics.soft();
                            final enabled = !_webSearch;
                            setState(() => _webSearch = enabled);
                            if (enabled) _maybeShowSearchHint();
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Symbols.flowsheet,
                            size: 22,
                            color: _stream ? cs.primary : cs.onSurfaceVariant,
                          ),
                          tooltip: l10n.streamOutput,
                          onPressed: () {
                            Haptics.soft();
                            setState(() => _stream = !_stream);
                            GStorage.setting.put(_kChatStreamKey, _stream);
                          },
                        ),
                        const Spacer(),
                        sending
                            ? IconButton.filled(
                                icon: const Icon(
                                  Symbols.stop_rounded,
                                  size: 22,
                                ),
                                tooltip: l10n.cancel,
                                style: IconButton.styleFrom(
                                  backgroundColor: cs.errorContainer,
                                  foregroundColor: cs.onErrorContainer,
                                ),
                                onPressed: () {
                                  Haptics.soft();
                                  ref
                                      .read(
                                        documentChatProvider(
                                          _documentId,
                                        ).notifier,
                                      )
                                      .cancel();
                                },
                              )
                            : IconButton.filled(
                                icon: const Icon(
                                  Symbols.arrow_upward_rounded,
                                  size: 22,
                                ),
                                tooltip: l10n.chatSend,
                                onPressed: _send,
                              ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 思考强度 ───

  /// 档位显示名——复用设置页同一组 l10n key。
  String _thinkingLabel(ThinkingLevel? level) {
    final l10n = context.l10n;
    return switch (level) {
      null => l10n.defaultLevel,
      ThinkingLevel.off => l10n.off,
      ThinkingLevel.low => l10n.low,
      ThinkingLevel.medium => l10n.medium,
      ThinkingLevel.high => l10n.high,
      ThinkingLevel.xhigh => l10n.ultraHigh,
    };
  }

  void _showThinkingSheet() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const options = [
      null,
      ThinkingLevel.off,
      ThinkingLevel.low,
      ThinkingLevel.medium,
      ThinkingLevel.high,
      ThinkingLevel.xhigh,
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).padding.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(
                  context.l10n.thinkingIntensity,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final level in options)
                InkWell(
                  onTap: () {
                    Haptics.soft();
                    setState(() => _thinking = level);
                    Navigator.of(sheetContext).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _thinkingLabel(level),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: _thinking == level
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _thinking == level
                                  ? cs.primary
                                  : cs.onSurface,
                            ),
                          ),
                        ),
                        if (_thinking == level)
                          Icon(
                            Symbols.check_rounded,
                            size: 20,
                            color: cs.primary,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─── 会话历史抽屉（左侧全覆盖）───

  Widget _buildSessionsDrawer(ThemeData theme, ColorScheme cs) {
    final l10n = context.l10n;
    final chat = ref.watch(documentChatProvider(_documentId));
    final notifier = ref.read(documentChatProvider(_documentId).notifier);

    return Drawer(
      width: MediaQuery.of(context).size.width,
      backgroundColor: cs.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Symbols.arrow_back_rounded),
                    tooltip: l10n.close,
                    onPressed: () {
                      Haptics.soft();
                      _scaffoldKey.currentState?.closeDrawer();
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      l10n.chatHistory,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 锚定文献：本抽屉里所有会话都属于这一篇
            GestureDetector(
              onTap: () {
                Haptics.soft();
                context.pop();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Icon(
                      Symbols.description_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.args.document.title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (chat.sessions.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    l10n.chatNoHistory,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: chat.sessions.length,
                  itemBuilder: (context, index) {
                    final session = chat.sessions[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SessionCard(
                        session: session,
                        selected: session.id == chat.activeSessionId,
                        onTap: () {
                          notifier.switchSession(session.id);
                          _scaffoldKey.currentState?.closeDrawer();
                        },
                        onDelete: () {
                          Haptics.medium();
                          notifier.deleteSession(session.id);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 会话卡：AI 总结标题 + 消息数与删除操作。
class _SessionCard extends StatelessWidget {
  final ChatSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    return AnimatedContainer(
      duration: kAnimFast,
      curve: kAnimCurve,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? cs.primary.withAlpha(160) : Colors.transparent,
          width: 2,
        ),
      ),
      child: TactilePress(
        onTap: onTap,
        baseColor: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        pressedScale: 0.98,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  session.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    l10n.chatMessageCount(session.messages.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Symbols.delete_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    tooltip: l10n.delete,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 子组件 ───

/// 消息气泡内的引用块（不可交互）。
class _QuoteBlock extends StatelessWidget {
  final String text;
  final Color textColor;
  final Color accentColor;

  const _QuoteBlock({
    required this.text,
    required this.textColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accentColor, width: 2)),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: textColor),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 输入区上方的待发送引用卡（可移除）。
class _QuoteCard extends StatefulWidget {
  final String text;
  final String? imagePath;
  final VoidCallback onRemove;

  const _QuoteCard({
    required this.text,
    this.imagePath,
    required this.onRemove,
  });

  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

/// 点击在「2 行摘要 ↔ 全文」间切换——提问前能看全到底引用了什么。
class _QuoteCardState extends State<_QuoteCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedSize(
      duration: kAnim,
      curve: kAnimCurve,
      alignment: Alignment.topCenter,
      child: TactilePress(
        onTap: () => setState(() => _expanded = !_expanded),
        baseColor: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // IntrinsicHeight + infinity 让引用条随展开后的文本高度伸长
                Container(
                  width: 3,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(160),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.imagePath != null &&
                            File(widget.imagePath!).existsSync()) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(widget.imagePath!),
                              height: 72,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              cacheWidth: 360,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (widget.text.isNotEmpty)
                          Text(
                            widget.text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: _expanded ? null : 2,
                            overflow:
                                _expanded ? null : TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: kAnimFast,
                  curve: kAnimCurve,
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(
                      Symbols.expand_more_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant.withAlpha(160),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Symbols.close_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: context.l10n.chatRemoveQuote,
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _BubbleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: TactilePress(
        onTap: onTap,
        baseColor: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: cs.onSurfaceVariant.withAlpha(160)),
      ),
    );
  }
}
