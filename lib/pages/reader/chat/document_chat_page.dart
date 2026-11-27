import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/animation_constants.dart';
import '../../../core/elevation.dart';
import '../../../core/l10n.dart';
import '../../../core/storage/settings_keys.dart';
import '../../../core/storage/storage.dart';
import '../../../data/models/book/document.dart';
import '../../../data/models/chat/chat_session.dart';
import '../../../data/models/ai/agent_config.dart';
import '../../../providers/document_chat_provider.dart';
import '../../../router/app_routes.dart';
import '../../../services/ai_settings_prompt.dart';
import '../../../services/builtin_tools.dart';
import '../../../services/haptics.dart';
import '../../../services/snackbar_service.dart';
import '../../../services/web_search_service.dart';
import '../../../utils/desktop.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/tactile_press.dart';
import '../../../core/folio_look.dart';
import '../../../widgets/ai_orb.dart';
import '../../../widgets/glass/liquid_glass.dart';
import '../../../widgets/staggered_entrance.dart';
import 'chat_markdown.dart';
import 'chat_activity_view.dart';
import 'chat_figure_attachment.dart';
import 'chat_model_picker.dart';
import 'chat_user_quote.dart';
import '../widgets/figure_viewer.dart';
import '../../../data/models/chat/chat_activity.dart';
import '../../../core/design_tokens.dart';

/// 定位原文：阅读器滚动后展示「返回问 AI」引导。
typedef LocateQuoteInReader =
    FutureOr<bool> Function(String quote, DocumentChatPageArgs returnArgs);

class DocumentChatPageArgs {
  final Document document;

  /// 划词进入时的引用文本；底栏入口为 null。
  final String? initialQuote;
  final Map<String, dynamic>? quoteAnchor;

  /// 从 Figure 查看器进入时附带的单张图片路径；非空时仅向模型发送此图。
  final String? figureImagePath;

  /// 阅读器按消息锚点或渲染文本定位；返回成功后聊天页才退出。
  final LocateQuoteInReader? onLocateQuote;

  /// 定位原文返回后重新打开时保留当前会话，不重置为草稿。
  final bool preserveSession;

  /// 每次划词/Figure 问 AI 递增；同值引用再入也要刷新 composer。
  final int quoteEpoch;

  /// 划词意图条（解释 / 说人话 / 举例 / 挑毛病）带进来的问题：
  /// 进入后连同引用自动发送，不用再打字。
  final String? initialPrompt;

  const DocumentChatPageArgs({
    required this.document,
    this.initialQuote,
    this.quoteAnchor,
    this.figureImagePath,
    this.onLocateQuote,
    this.preserveSession = false,
    this.quoteEpoch = 0,
    this.initialPrompt,
  });
}

/// 问 AI 对话页。状态在 [documentChatProvider]（family by documentId），
/// 页面自己只持「待发送引用」「回答角色」两个输入态。
class DocumentChatPage extends ConsumerStatefulWidget {
  final DocumentChatPageArgs args;

  /// 阅读器停靠栏内嵌：会话跟随 provider 保活，不在 [initState] 重置。
  final bool embedded;

  /// 嵌入态关闭停靠栏；全屏态不使用。
  final VoidCallback? onClose;

  /// 嵌入态抽屉宽度；必须等于停靠栏宽，禁止读窗口 [MediaQuery]。
  final double? paneWidth;

  /// 嵌入态发送后清掉父级暂存的 quote/图，避免 remount 灌回旧引用。
  final VoidCallback? onQuoteConsumed;

  const DocumentChatPage({
    super.key,
    required this.args,
    this.embedded = false,
    this.onClose,
    this.paneWidth,
    this.onQuoteConsumed,
  }) : assert(!embedded || paneWidth != null);

  @override
  ConsumerState<DocumentChatPage> createState() => _DocumentChatPageState();
}

class _DocumentChatPageState extends ConsumerState<DocumentChatPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputController = TextEditingController();
  final _messageScroll = ScrollController();
  bool _followOutput = true;
  bool _scrollScheduled = false;
  String? _quote;
  Map<String, dynamic>? _quoteAnchor;
  bool _locatingQuote = false;
  String? _figureImagePath;
  final ChatModelRole _role = ChatModelRole.expert;
  ChatModelSelection? _model;

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

  /// 悬浮输入框的实测高度：消息列表底部留出同样的空间。
  double _composerHeight = 0;

  /// 入场动画只给「打开会话之后」新出现的消息：切会话时记下当时的条数。
  String? _entranceSession;
  int _entranceFrom = 0;

  /// 流式回答落定成消息时不再重放入场（它已经在屏幕上了）。
  int? _streamedIndex;

  @override
  void initState() {
    super.initState();
    _quote = widget.args.initialQuote?.trim();
    if (_quote?.isEmpty ?? false) _quote = null;
    _figureImagePath = widget.args.figureImagePath;
    _quoteAnchor = widget.args.quoteAnchor;
    // 全屏且非 preserveSession：进入即新会话草稿。嵌入停靠栏跟随 provider 保活。
    if (!widget.embedded && !widget.args.preserveSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(documentChatProvider(_documentId).notifier)
              .startNewSession();
        }
      });
    }
    _scheduleAutoSend(widget.args.initialPrompt);
  }

  /// 意图条进入：问题直接发出去（排在新会话初始化之后）。
  void _scheduleAutoSend(String? prompt) {
    final text = prompt?.trim();
    if (text == null || text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputController.text = text;
      _send();
    });
  }

  /// 空状态的起手问题卡：点一下即发送。
  void _sendStarter(String text) {
    _inputController.text = text;
    _send();
  }

  @override
  void didUpdateWidget(covariant DocumentChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.args.quoteEpoch == oldWidget.args.quoteEpoch) return;
    setState(() {
      var q = widget.args.initialQuote?.trim();
      if (q?.isEmpty ?? false) q = null;
      _quote = q;
      _figureImagePath = widget.args.figureImagePath;
      _quoteAnchor = widget.args.quoteAnchor;
    });
    _scheduleAutoSend(widget.args.initialPrompt);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _messageScroll.dispose();
    super.dispose();
  }

  void _pauseOutputFollow() => _followOutput = false;

  // 顺序列表固定展开起点；只有跟随回答时才随布局更新滚到底部。
  // 滚动或展开会暂停跟随，避免流式更新把用户正在查看的内容移出视野。
  void _scrollToLatest() {
    if (_scrollScheduled || !_followOutput) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_followOutput || !_messageScroll.hasClients) return;
      final position = _messageScroll.position;
      if (position.pixels != position.maxScrollExtent) {
        _messageScroll.jumpTo(position.maxScrollExtent);
      }
    });
  }

  Future<void> _openFigure(String imagePath, String caption) =>
      showFigureViewer(context, [
        FigureView(path: imagePath, caption: caption),
      ]);

  void _notifyFigurePolicy() {
    final fast = isFastModel(_role, _model);
    final images = ref
        .read(documentChatProvider(_documentId).notifier)
        .supportsImages(_role, model: _model);
    if (fast || (_figureImagePath != null && !images)) {
      ref
          .read(snackBarServiceProvider)
          .showResult(
            message: fast
                ? context.l10n.chatFastTextOnly
                : context.l10n.chatModelTextOnly,
          );
    }
  }

  void _send() {
    final chat = ref.read(documentChatProvider(_documentId));
    final text = _inputController.text.trim();
    if (text.isEmpty || chat.sending) return;
    Haptics.soft();

    _notifyFigurePolicy();
    final role = _role;

    final editIdx = _editingIndex;
    if (editIdx != null) {
      ref
          .read(documentChatProvider(_documentId).notifier)
          .resendFrom(
            keepCount: editIdx,
            text: text,
            role: role,
            model: _model,
            quotedText: _quote,
            quoteAnchor: _quoteAnchor,
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
            model: _model,
            quotedText: _quote,
            quoteAnchor: _quoteAnchor,
            figureImagePath: _figureImagePath,
            thinkingOverride: _thinking,
            webSearch: _webSearch,
            streaming: _stream,
          );
    }
    _inputController.clear();
    setState(() {
      _quote = null;
      _quoteAnchor = null;
      _figureImagePath = null;
      _editingIndex = null;
    });
    widget.onQuoteConsumed?.call();
  }

  void _cancelEditing() {
    _inputController.clear();
    setState(() {
      _editingIndex = null;
      _quote = null;
      _quoteAnchor = null;
    });
  }

  void _startEditing(int messageIndex, ChatMessage msg) {
    _inputController.text = msg.content;
    setState(() {
      _editingIndex = messageIndex;
      _quote = msg.quotedText;
      _quoteAnchor = msg.quoteAnchor;
      _figureImagePath = msg.figureImagePath;
    });
  }

  /// 开启联网搜索时的兼容端提示：MiMo 官方端需先在平台控制台开通联网
  /// 插件；无原生搜索且未配置外部搜索 的厂商（DeepSeek 等）提示去
  /// AI 设置配置所选服务的 Key，否则开关静默无效。
  void _maybeShowSearchHint() {
    final state = resolveModelState(_role, _model);
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
    if (vendor == CompatSearchVendor.none && !WebSearchService.isConfigured) {
      final l10n = context.l10n;
      ref
          .read(snackBarServiceProvider)
          .showResult(
            message: l10n.webSearchNotConfigured,
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
          color: cs.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.lgAll,
            side: AppStroke.side(cs),
          ),
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
                  style: theme.textTheme.titleLarge?.copyWith(),
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
  static const _kNewChatHintDismissedKey =
      SettingsKeys.chatNewSessionHintDismissed;

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
              color: cs.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.lgAll,
                side: AppStroke.side(cs),
              ),
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
                      style: theme.textTheme.titleLarge?.copyWith(),
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

  Future<void> _locateQuote(ChatMessage message) async {
    final locate = widget.args.onLocateQuote;
    if (locate == null || _locatingQuote) return;
    _locatingQuote = true;
    Haptics.soft();
    try {
      final found = await locate(
        message.quotedText ?? '',
        DocumentChatPageArgs(
          document: widget.args.document,
          preserveSession: true,
          quoteAnchor: message.quoteAnchor,
          figureImagePath: message.figureImagePath,
          onLocateQuote: widget.args.onLocateQuote,
        ),
      );
      if (!mounted) return;
      if (!found) {
        ref
            .read(snackBarServiceProvider)
            .showResult(
              tone: SnackTone.error,
              message: context.l10n.chatSourceNotFound,
            );
      } else if (!widget.embedded) {
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        ref
            .read(snackBarServiceProvider)
            .showResult(
              tone: SnackTone.error,
              message: context.l10n.chatSourceNotFound,
            );
      }
    } finally {
      _locatingQuote = false;
    }
  }

  Future<void> _showError(String message) async {
    final handled = await AiSettingsPrompt.showForConfigError(
      context: context,
      error: message,
    );
    if (!mounted) return;
    if (!handled) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: message, tone: SnackTone.error);
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

    ref.listen(documentChatProvider(_documentId), (previous, next) {
      final changedSession = previous?.activeSessionId != next.activeSessionId;
      final startedSending = previous?.sending != true && next.sending;
      if (changedSession || startedSending) {
        _followOutput = true;
      }
      _scrollToLatest();
    });

    final session = chat.activeSession;
    final messages = session?.messages ?? const <ChatMessage>[];
    if (session?.id != _entranceSession) {
      _entranceSession = session?.id;
      _entranceFrom = messages.length;
      _streamedIndex = null;
    }
    if (chat.sending && (chat.streamingText?.isNotEmpty ?? false)) {
      _streamedIndex = messages.length;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final drawerWidth = widget.embedded
            ? (constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : widget.paneWidth!)
            : math.min(360.0, MediaQuery.sizeOf(context).width);
        return Scaffold(
          key: _scaffoldKey,
          // 全覆盖抽屉与系统返回/横滑手势冲突，只走按钮开启。
          drawerEnableOpenDragGesture: false,
          drawer: _buildSessionsDrawer(theme, cs, drawerWidth),
          appBar: AppBar(
            leading: widget.embedded
                ? IconButton(
                    icon: const Icon(Symbols.close_rounded),
                    tooltip: l10n.close,
                    onPressed: () {
                      Haptics.soft();
                      widget.onClose?.call();
                    },
                  )
                : const BackButton(),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AiOrb(size: 18, thinking: chat.sending),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    session?.title ?? l10n.askAi,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
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
          extendBodyBehindAppBar: true,
          // extendBodyBehindAppBar 时 Scaffold 把栏高并进 body 的 padding.top
          body: Builder(
            builder: (context) => _buildBody(
              theme,
              cs,
              chat,
              messages,
              MediaQuery.paddingOf(context).top,
            ),
          ),
        );
      },
    );
  }

  /// 页面主体：顶部一层主题色柔光；悬浮玻璃打开时输入框浮在消息上方，
  /// 关闭时输入框与消息上下排列。
  Widget _buildBody(
    ThemeData theme,
    ColorScheme cs,
    DocumentChatState chat,
    List<ChatMessage> messages,
    double topInset,
  ) {
    final floating = FolioLook.of(context).floatingBars;
    final content = messages.isEmpty && !chat.sending
        ? _buildEmptyState(theme, cs)
        : _buildMessageList(
            theme,
            cs,
            messages,
            chat.sending,
            chat.streamingText,
          );
    final composer = _buildComposer(theme, cs, chat.sending);

    return Stack(
      children: [
        // 顶部极光：发送中更亮一些
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: topInset + 220,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: chat.sending ? 1 : .7,
              duration: kAnim,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -1.4),
                    radius: 1.3,
                    colors: [
                      cs.primary.withValues(alpha: .16),
                      cs.tertiary.withValues(alpha: .06),
                      cs.surface.withValues(alpha: 0),
                    ],
                    stops: const [0, .45, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topInset),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: floating
                ? Stack(
                    children: [
                      Positioned.fill(child: content),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _SizeReporter(
                          onSize: (size) {
                            if ((size.height - _composerHeight).abs() > .5) {
                              setState(() => _composerHeight = size.height);
                            }
                          },
                          child: composer,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: content),
                      composer,
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// 悬浮输入框盖住的高度（平铺时为 0）。
  double get _composerInset =>
      FolioLook.of(context).floatingBars ? _composerHeight : 0;

  Widget _buildEmptyState(ThemeData theme, ColorScheme cs) {
    final l10n = context.l10n;
    final hasQuote = _quote != null || _figureImagePath != null;
    // 带着划词进来：给「对这段话」的意图；否则给「对这篇文献」的起手问题
    final starters = hasQuote
        ? [
            (
              Symbols.lightbulb_rounded,
              l10n.aiPromptExplain,
              l10n.aiPromptExplain,
            ),
            (
              Symbols.chat_bubble_rounded,
              l10n.aiPromptSimplify,
              l10n.aiPromptSimplify,
            ),
            (
              Symbols.category_rounded,
              l10n.aiPromptExample,
              l10n.aiPromptExample,
            ),
            (
              Symbols.balance_rounded,
              l10n.aiPromptChallenge,
              l10n.aiPromptChallenge,
            ),
          ]
        : [
            (
              Symbols.summarize_rounded,
              l10n.chatStarterSummary,
              l10n.chatStarterSummary,
            ),
            (
              Symbols.science_rounded,
              l10n.chatStarterMethod,
              l10n.chatStarterMethod,
            ),
            (
              Symbols.report_rounded,
              l10n.chatStarterLimits,
              l10n.chatStarterLimits,
            ),
            (
              Symbols.forum_rounded,
              l10n.chatStarterPlain,
              l10n.chatStarterPlain,
            ),
          ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 520;
        final cardWidth = twoColumns
            ? (math.min(constraints.maxWidth, 640) - 48 - 12) / 2
            : double.infinity;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + _composerInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(
                0,
                constraints.maxHeight - 48 - _composerInset,
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 592),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AiOrb(size: 64),
                    const SizedBox(height: 24),
                    Text(
                      l10n.chatEmptyTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.args.document.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (var i = 0; i < starters.length; i++)
                          SizedBox(
                            width: cardWidth,
                            child: StaggeredEntrance(
                              index: i + 1,
                              child: _StarterCard(
                                icon: starters[i].$1,
                                label: starters[i].$2,
                                onTap: () => _sendStarter(starters[i].$3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageList(
    ThemeData theme,
    ColorScheme cs,
    List<ChatMessage> messages,
    bool sending,
    String? streamingText,
  ) {
    final activities = ref.watch(documentChatProvider(_documentId)).activities;
    _scrollToLatest();
    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          _followOutput =
              notification.direction == ScrollDirection.idle &&
              notification.metrics.extentAfter < 48;
        }
        return false;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _scrollToLatest();
          return false;
        },
        child: ListView.builder(
          key: ValueKey(
            ref.watch(documentChatProvider(_documentId)).activeSessionId,
          ),
          controller: _messageScroll,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + _composerInset),
          itemCount: messages.length + (sending ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length) {
              if ((streamingText == null || streamingText.isEmpty) &&
                  activities.isEmpty) {
                return _MessageEntrance(
                  key: const ValueKey('pending'),
                  child: _buildPendingBubble(theme, cs),
                );
              }
              return Padding(
                key: const ValueKey('streaming'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _buildAssistantBubble(
                  theme,
                  cs,
                  streamingText ?? '',
                  activities: activities,
                  thinking: true,
                ),
              );
            }
            final msg = messages[index];
            final animate =
                index >= _entranceFrom &&
                !(index == _streamedIndex && !msg.isUser);
            final bubble = Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: msg.isUser
                  ? _buildUserBubble(theme, cs, msg, index)
                  : _buildAssistantBubble(
                      theme,
                      cs,
                      msg.content,
                      messageIndex: index,
                      activities: msg.activities,
                    ),
            );
            return animate
                ? _MessageEntrance(
                    key: ValueKey(msg.id),
                    fromRight: msg.isUser,
                    child: bubble,
                  )
                : KeyedSubtree(key: ValueKey(msg.id), child: bubble);
          },
        ),
      ),
    );
  }

  /// 等待首个字：光球加速呼吸 + 一行流光的「正在思考」。
  Widget _buildPendingBubble(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const AiOrb(size: 22, thinking: true),
          const SizedBox(width: 12),
          ShimmerText(
            context.l10n.chatThinking,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
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
        color: cs.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: AppStroke.side(cs),
        ),
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
    return LayoutBuilder(
      builder: (context, constraints) => Align(
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
          // 用户气泡：强调色淡彩、右下角收成小圆角，像从右侧「说出来」
          child: Container(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .86),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primaryContainer,
                  Color.alphaBlend(
                    cs.tertiaryContainer.withValues(alpha: .45),
                    cs.primaryContainer,
                  ),
                ],
              ),
              shape: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.lg),
                  topRight: Radius.circular(AppRadius.lg),
                  bottomLeft: Radius.circular(AppRadius.lg),
                  bottomRight: Radius.circular(AppRadius.xs - 2),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.figureImagePath != null) ...[
                  ChatFigureAttachment(
                    imagePath: msg.figureImagePath!,
                    onOpen: () =>
                        _openFigure(msg.figureImagePath!, msg.quotedText ?? ''),
                  ),
                  const SizedBox(height: 8),
                ],
                if (msg.quotedText != null) ...[
                  ChatUserQuote(
                    text: msg.quotedText!,
                    onToggle: _pauseOutputFollow,
                    onLocate: widget.args.onLocateQuote == null
                        ? null
                        : () => _locateQuote(msg),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  msg.content,
                  style: chatBodyStyle(theme).copyWith(color: cs.onSurface),
                ),
              ],
            ),
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
    List<ChatActivity> activities = const [],
    bool thinking = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 回答以一颗光球开头；生成中它在转
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AiOrb(size: 20, thinking: thinking, glow: thinking),
        ),
        ChatActivityView(activities: activities, onToggle: _pauseOutputFollow),
        if (content.isNotEmpty) ChatMarkdown(data: content),
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
                // 桌面已有复制，不弹系统分享面板
                if (!isDesktopOs)
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
    int? userIndex;
    for (var i = assistantIndex - 1; i >= 0; i--) {
      if (session.messages[i].isUser) {
        userMsg = session.messages[i];
        userIndex = i;
        break;
      }
    }
    if (userMsg == null) return;
    _notifyFigurePolicy();
    final role = _role;
    ref
        .read(documentChatProvider(_documentId).notifier)
        .resendFrom(
          keepCount: userIndex!,
          text: userMsg.content,
          role: role,
          model: _model,
          quotedText: userMsg.quotedText,
          quoteAnchor: userMsg.quoteAnchor,
          figureImagePath: userMsg.figureImagePath,
          thinkingOverride: _thinking,
          webSearch: _webSearch,
          streaming: _stream,
        );
  }

  Widget _composerToolButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final compact = isDesktopOs || widget.embedded;
    return IconButton(
      icon: Icon(icon, size: 20, color: color),
      iconSize: 20,
      tooltip: tooltip,
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      constraints: compact
          ? BoxConstraints.tight(const Size(36, 36))
          : const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: onPressed,
    );
  }

  Widget _buildComposer(ThemeData theme, ColorScheme cs, bool sending) {
    final l10n = context.l10n;
    final embedded = widget.embedded;
    final toolButtons = [
      ChatModelPicker(
        selected: _model,
        onChanged: (model) {
          setState(() => _model = model);
          _notifyFigurePolicy();
          if (_webSearch) _maybeShowSearchHint();
        },
      ),
      _buildThinkingToolButton(cs),
      _composerToolButton(
        icon: Symbols.travel_explore_rounded,
        color: _webSearch ? cs.primary : cs.onSurfaceVariant,
        tooltip: l10n.searchToolLabel,
        onPressed: () {
          Haptics.soft();
          final enabled = !_webSearch;
          setState(() => _webSearch = enabled);
          if (enabled) _maybeShowSearchHint();
        },
      ),
      _composerToolButton(
        icon: Symbols.flowsheet,
        color: _stream ? cs.primary : cs.onSurfaceVariant,
        tooltip: l10n.streamOutput,
        onPressed: () {
          Haptics.soft();
          setState(() => _stream = !_stream);
          GStorage.setting.put(_kChatStreamKey, _stream);
        },
      ),
    ];
    final sendSize = isDesktopOs ? 36.0 : 40.0;
    final sendButton = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _inputController,
      builder: (context, input, _) => _SendOrb(
        key: const ValueKey('chat-send-button'),
        size: sendSize,
        sending: sending,
        enabled: sending || input.text.trim().isNotEmpty,
        tooltip: sending ? l10n.cancel : l10n.chatSend,
        onPressed: sending
            ? () {
                Haptics.soft();
                ref.read(documentChatProvider(_documentId).notifier).cancel();
              }
            : _send,
      ),
    );

    Widget inner = Column(
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
        _composerShell(
          cs: cs,
          sending: sending,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_quote != null || _figureImagePath != null) ...[
                if (_figureImagePath != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ChatFigureAttachment(
                      imagePath: _figureImagePath!,
                      onOpen: () =>
                          _openFigure(_figureImagePath!, _quote ?? ''),
                      onRemove: () => setState(() {
                        _quote = null;
                        _quoteAnchor = null;
                        _figureImagePath = null;
                      }),
                    ),
                  )
                else
                  _QuoteCard(
                    text: _quote ?? '',
                    onRemove: () {
                      Haptics.soft();
                      setState(() {
                        _quote = null;
                        _quoteAnchor = null;
                        _figureImagePath = null;
                      });
                    },
                  ),
                const SizedBox(height: 8),
              ],

              if (_editingIndex != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: ShapeDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: AppShape.sm(),
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
                style: chatBodyStyle(theme),
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  hintText: l10n.chatInputHint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: toolButtons),
                    ),
                  ),
                  const SizedBox(width: 8),
                  sendButton,
                ],
              ),
            ],
          ),
        ),
      ],
    );

    // 输入框是一枚浮起的大圆角胶囊：悬浮玻璃打开时是玻璃，关闭时是实色
    return SafeArea(
      top: false,
      child: Padding(
        padding: embedded
            ? const EdgeInsets.fromLTRB(10, 4, 10, 10)
            : const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: inner,
      ),
    );
  }

  static const double _composerRadius = AppRadius.lg;

  Widget _composerShell({
    required ColorScheme cs,
    required bool sending,
    required Widget child,
  }) {
    const padding = EdgeInsets.fromLTRB(10, 6, 8, 8);
    final body = FolioLook.of(context).floatingBars
        ? LiquidGlass(radius: _composerRadius, padding: padding, child: child)
        : DecoratedBox(
            decoration: ShapeDecoration(
              color: cs.surfaceContainerLow,
              shape: AppShape.of(_composerRadius, side: AppStroke.side(cs)),
              shadows: AppShadows.bar,
            ),
            child: Padding(padding: padding, child: child),
          );
    // 发送中：一道极光沿输入框边缘流动
    return AuroraRing(
      active: sending,
      radius: _composerRadius,
      width: 2,
      child: body,
    );
  }

  // ─── 思考强度 ───

  static const _thinkingOptions = <ThinkingLevel?>[
    null,
    ThinkingLevel.off,
    ThinkingLevel.low,
    ThinkingLevel.medium,
    ThinkingLevel.high,
    ThinkingLevel.xhigh,
  ];

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

  Widget _buildThinkingToolButton(ColorScheme cs) {
    final l10n = context.l10n;
    Widget button(VoidCallback onPressed) => _composerToolButton(
      icon: Symbols.neurology_rounded,
      color: _thinking != null ? cs.primary : cs.onSurfaceVariant,
      tooltip: l10n.thinkingIntensity,
      onPressed: onPressed,
    );
    if (!isDesktopOs) {
      return button(() {
        Haptics.soft();
        _showThinkingSheet();
      });
    }
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      builder: (context, controller, _) => button(() {
        Haptics.soft();
        if (controller.isOpen) {
          controller.close();
        } else {
          controller.open();
        }
      }),
      menuChildren: [
        for (final level in _thinkingOptions)
          MenuItemButton(
            onPressed: () {
              Haptics.soft();
              setState(() => _thinking = level);
            },
            trailingIcon: _thinking == level
                ? Icon(Symbols.check_rounded, size: 20, color: cs.primary)
                : null,
            child: Text(_thinkingLabel(level)),
          ),
      ],
    );
  }

  void _showThinkingSheet() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: AppRadius.sheetTop,
            border: Border(top: AppStroke.side(cs)),
            boxShadow: AppShadows.sheet,
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
              for (final level in _thinkingOptions)
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

  Widget _buildSessionsDrawer(ThemeData theme, ColorScheme cs, double width) {
    final l10n = context.l10n;
    final chat = ref.watch(documentChatProvider(_documentId));
    final notifier = ref.read(documentChatProvider(_documentId).notifier);

    return Drawer(
      width: width,
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
                      style: theme.textTheme.titleLarge?.copyWith(),
                    ),
                  ),
                ],
              ),
            ),
            // 锚定文献：本抽屉里所有会话都属于这一篇
            GestureDetector(
              onTap: () {
                Haptics.soft();
                if (widget.embedded) {
                  _scaffoldKey.currentState?.closeDrawer();
                } else {
                  context.pop();
                }
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
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: selected ? cs.primary.withAlpha(160) : Colors.transparent,
          width: 2,
        ),
      ),
      child: TactilePress(
        onTap: onTap,
        baseColor: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
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

/// 输入区上方的待发送引用卡（可移除）。
class _QuoteCard extends StatefulWidget {
  final String text;
  final VoidCallback onRemove;

  const _QuoteCard({required this.text, required this.onRemove});

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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
                        if (widget.text.isNotEmpty)
                          Text(
                            widget.text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: _expanded ? null : 2,
                            overflow: _expanded ? null : TextOverflow.ellipsis,
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: cs.onSurfaceVariant.withAlpha(160)),
      ),
    );
  }
}

/// 空状态里的起手问题卡：图标落在强调色淡彩圆里，右侧一枚斜箭头。
class _StarterCard extends StatelessWidget {
  const _StarterCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: TactilePress(
        onTap: () {
          Haptics.soft();
          onTap();
        },
        baseColor: cs.surfaceContainerLow.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: ShapeDecoration(shape: AppShape.md(AppStroke.side(cs))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [cs.primaryContainer, cs.tertiaryContainer],
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: cs.onPrimaryContainer,
                    fill: 1,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Symbols.north_east_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 发送键：一颗圆形渐变按钮；可发送时亮起并带一圈主题色光晕，
/// 发送中变成停止键。
class _SendOrb extends StatelessWidget {
  const _SendOrb({
    super.key,
    required this.size,
    required this.sending,
    required this.enabled,
    required this.tooltip,
    required this.onPressed,
  });

  final double size;
  final bool sending;
  final bool enabled;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final live = enabled && !sending;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: enabled ? onPressed : null,
          child: AnimatedScale(
            scale: live ? 1 : .92,
            duration: kAnimFast,
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: kAnimFast,
              curve: kAnimCurve,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sending
                    ? cs.errorContainer
                    : live
                    ? null
                    : cs.surfaceContainerHighest,
                gradient: live
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [cs.primary, cs.tertiary],
                      )
                    : null,
                boxShadow: live
                    ? [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: .35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: kAnimFast,
                transitionBuilder: (child, a) => RotationTransition(
                  turns: Tween(begin: -.25, end: 0.0).animate(a),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: Icon(
                  sending ? Symbols.stop_rounded : Symbols.arrow_upward_rounded,
                  key: ValueKey(sending),
                  size: 20,
                  weight: 600,
                  fill: 1,
                  color: sending
                      ? cs.onErrorContainer
                      : live
                      ? cs.onPrimary
                      : cs.onSurfaceVariant.withValues(alpha: .6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 新消息入场：弹簧把气泡从下方（用户消息从右下）托上来，同时淡入。
class _MessageEntrance extends StatefulWidget {
  const _MessageEntrance({
    super.key,
    required this.child,
    this.fromRight = false,
  });

  final Widget child;
  final bool fromRight;

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _c.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 28),
        0,
        1,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(widget.fromRight ? 18 * (1 - t) : 0, 22 * (1 - t)),
            child: Transform.scale(
              scale: .94 + .06 * t,
              alignment: widget.fromRight
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 把子组件布局后的尺寸报给父级（用于悬浮输入框给列表留白）。
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}
