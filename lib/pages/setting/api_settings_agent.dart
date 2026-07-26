import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/animation_constants.dart';
import '../../core/l10n.dart';
import '../../core/storage/storage.dart';
import '../../providers/api_provider.dart';
import '../../providers/model_test_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/agent_model_capability.dart';
import '../../services/model_capability_store.dart';
import '../../services/haptics.dart';
import '../../services/tavily_search_service.dart';
import '../../services/snackbar_service.dart';
import '../../widgets/onboarding_spotlight.dart';
import '../../widgets/tactile_press.dart';
import '../../utils/debounced_action.dart';
import 'agent_model_list_tile.dart';
import 'agent_model_capability_sheet.dart';
import 'agent_model_manage_sheet.dart';
import 'agent_model_tester.dart';

/// 协议副标题——给用户一个"选它能做什么"的简短提示。
String _protocolSubtitle(AgentApiProvider p, AppLocalizations l10n) =>
    switch (p) {
      AgentApiProvider.openai => l10n.providerDescOpenai,
      AgentApiProvider.anthropic => l10n.providerDescAnthropic,
      AgentApiProvider.gemini => l10n.providerDescGemini,
      AgentApiProvider.openAICompatible => l10n.providerDescOpenaiCompatible,
    };

/// 文档助手 Agent API 配置区块。
///
/// 单页内联布局：顶部 [SettingPicker] Sheet 切换服务商（内置三家 + 自定义），
/// 下方直接编辑当前服务商的 API Key / 地址 / 模型；底部为全局模型角色。
class AgentApiSection extends ConsumerStatefulWidget {
  const AgentApiSection({super.key});

  @override
  ConsumerState<AgentApiSection> createState() => _AgentApiSectionState();
}

class _AgentApiSectionState extends ConsumerState<AgentApiSection> {
  static const _lastInstanceKey = 'agent_api_last_instance';

  final _expertRoleKey = GlobalKey(debugLabel: 'expertRole');
  final _fastRoleKey = GlobalKey(debugLabel: 'fastRole');
  final _imageRoleKey = GlobalKey(debugLabel: 'imageRole');
  bool _onboardingScheduled = false;

  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;

  /// 当前正在编辑的实例 id，持久化到 Hive 以便跨页面保留选择。
  String _currentId = '';

  /// initState 缓存 notifier——Riverpod 3.x 禁止在 dispose() 中通过 ref.read
  /// 取 provider（widget 已 unmount-pending）。Notifier 实例的生命周期由
  /// provider 管理、独立于 widget，cache 安全（同 reader view.dart 先例）。
  late final AgentApiNotifier _apiNotifier;

  /// build 时缓存的当前实例 URL/Key，供 dispose 路径的 [_pendingEdits]
  /// 做差异比较（dispose 中不可用 ref）。替代旧 _apiSnapshot 全量快照。
  String _lastStoredUrl = '';
  String _lastStoredKey = '';

  bool _keyObscured = true;
  final _keyDebounce = DebouncedAction();
  final _urlDebounce = DebouncedAction();

  // Tavily 搜索回退的 Key 编辑态（key 本体存 SecureCredentialVault，
  // 由 TavilySearchService 作唯一存取接缝，不挂在 provider 实例上）
  late final TextEditingController _tavilyCtrl;
  bool _tavilyObscured = true;
  final _tavilyDebounce = DebouncedAction();

  ModelTestNotifier get _testNotifier => ref.read(modelTestProvider.notifier);

  @override
  void initState() {
    super.initState();
    _apiNotifier = ref.read(agentApiProvider.notifier);
    final instances = ref.read(agentApiProvider).instances;
    final lastId = GStorage.setting.get(_lastInstanceKey) as String?;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeStartOnboardingGuide());
    final inst =
        instances.where((i) => i.id == lastId).firstOrNull ??
        (instances.isNotEmpty ? instances.first : null);
    _currentId = inst?.id ?? '';
    _urlCtrl = TextEditingController(text: _urlText(inst));
    _keyCtrl = TextEditingController(text: inst?.apiKey ?? '');
    _tavilyCtrl = TextEditingController(text: TavilySearchService.apiKey);
  }

  @override
  void dispose() {
    _flushEditsDeferred();
    _tavilyDebounce.cancel();
    final tavilyKey = _tavilyCtrl.text.trim();
    if (tavilyKey != TavilySearchService.apiKey) {
      TavilySearchService.setApiKey(tavilyKey);
    }
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _tavilyCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybeStartOnboardingGuide() async {
    if (_onboardingScheduled) return;
    final step = ref.read(onboardingProvider);
    if (step != OnboardingStep.aiExpert) return;
    _onboardingScheduled = true;

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await _runAiOnboardingGuide();
  }

  Future<void> _runAiOnboardingGuide() async {
    final notifier = ref.read(onboardingProvider.notifier);
    final l10n = context.l10n;

    // ① Expert Model
    await _scrollToAndSpotlight(
      key: _expertRoleKey,
      message: l10n.onboardingExpertHint,
      actionLabel: l10n.onboardingNext,
    );
    if (!mounted) return;
    notifier.advance(); // → aiFast

    // ② Fast Model
    await _scrollToAndSpotlight(
      key: _fastRoleKey,
      message: l10n.onboardingFastHint,
      actionLabel: l10n.onboardingNext,
    );
    if (!mounted) return;
    notifier.advance(); // → aiImageGen

    // ③ Image Gen Model
    await _scrollToAndSpotlight(
      key: _imageRoleKey,
      message: l10n.onboardingImageGenHint,
      actionLabel: l10n.onboardingFinish,
    );
    if (!mounted) return;
    notifier.complete();
  }

  Future<void> _scrollToAndSpotlight({
    required GlobalKey key,
    required String message,
    required String actionLabel,
  }) async {
    final ctx = key.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: kAnim,
        curve: kAnimCurve,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    await showOnboardingSpotlight(
      context: context,
      targetKey: key,
      message: message,
      actionLabel: actionLabel,
      borderRadius: 16,
    );
  }

  /// URL 输入框显示值：用户未填时回落到协议默认地址。
  String _urlText(AgentProviderInstance? inst) => inst == null
      ? ''
      : (inst.baseUrl.isNotEmpty ? inst.baseUrl : inst.protocol.defaultBaseUrl);

  /// 当前输入框相对已落盘值的未保存编辑。
  /// 读 [_lastStoredUrl]/[_lastStoredKey] 而非 ref——dispose 路径也会调。
  ({String id, String? url, String? key}) _pendingEdits() {
    final urlText = _urlCtrl.text.trim();
    final keyText = _keyCtrl.text.trim();
    return (
      id: _currentId,
      url: urlText != _lastStoredUrl ? urlText : null,
      key: keyText != _lastStoredKey ? keyText : null,
    );
  }

  /// 把尚未过防抖期的 URL/Key 编辑立即落盘，返回落盘后的最新实例。
  /// 打开模型管理 / 连通性测试前必须调用——这些路径会把 URL/Key 冻结
  /// 进调用参数，拿旧值会导致请求打到错误地址。
  Future<AgentProviderInstance?> _commitPendingEdits() async {
    _urlDebounce.cancel();
    _keyDebounce.cancel();
    final edits = _pendingEdits();
    if (edits.url != null) await _apiNotifier.setBaseUrl(edits.id, edits.url!);
    if (edits.key != null) await _apiNotifier.setApiKey(edits.id, edits.key!);
    return ref.read(agentApiProvider).byId(edits.id);
  }

  /// 退出页面 / 切换实例时兜底落盘（原实现直接 cancel 会丢失 600ms 内的
  /// 编辑）。推迟到微任务执行，避免在元素卸载过程中同步触发 provider 通知。
  void _flushEditsDeferred() {
    _urlDebounce.cancel();
    _keyDebounce.cancel();
    final edits = _pendingEdits();
    if (edits.url == null && edits.key == null) return;
    Future.microtask(() async {
      try {
        if (edits.url != null) {
          await _apiNotifier.setBaseUrl(edits.id, edits.url!);
        }
        if (edits.key != null) {
          await _apiNotifier.setApiKey(edits.id, edits.key!);
        }
      } catch (_) {}
    });
  }

  /// 切换当前编辑的实例，同步输入框并持久化选择。
  void _switchTo(AgentProviderInstance inst) {
    _flushEditsDeferred(); // 旧实例的未落盘编辑
    setState(() {
      _currentId = inst.id;
      _keyCtrl.text = inst.apiKey;
      _urlCtrl.text = _urlText(inst);
    });
    _testNotifier.clearAll();
    GStorage.setting.put(_lastInstanceKey, inst.id);
  }

  // ── 添加 / 删除服务商 ──

  Future<void> _addProvider() async {
    final protocol = await _showProtocolPicker();
    if (protocol == null || !mounted) return;

    // 选完协议后填表确认——名称 / 地址 / Key 都填齐才能创建
    final form =
        await showDialog<({String name, String baseUrl, String apiKey})>(
          context: context,
          builder: (_) => _AddProviderDialog(protocol: protocol),
        );
    if (form == null || !mounted) return;

    final id = await ref
        .read(agentApiProvider.notifier)
        .addInstance(
          protocol,
          name: form.name,
          baseUrl: form.baseUrl,
          apiKey: form.apiKey,
        );
    final inst = ref.read(agentApiProvider).byId(id);
    if (inst != null && mounted) _switchTo(inst);
  }

  /// 删除指定自定义实例（带确认）。删的若是当前项，删后切回第一个。
  Future<void> _deleteInstance(AgentProviderInstance inst) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text(
            context.l10n.deleteProvider,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(context.l10n.confirmDeleteProvider(inst.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: Text(context.l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final wasCurrent = inst.id == _currentId;
    await ref.read(agentApiProvider.notifier).removeInstance(inst.id);
    if (!mounted) return;
    // 删的是当前项才切回第一个（内置三家恒在，列表必非空）
    if (wasCurrent) {
      _switchTo(ref.read(agentApiProvider).instances.first);
    }
  }

  // ── 服务商切换器（折叠 tile + 管理 sheet）──

  /// 折叠态：当前服务商名 + ▼（§3.8 SettingPicker 折叠态规格）。
  Widget _providerTile(
    ThemeData theme,
    ColorScheme cs,
    AgentProviderInstance current,
  ) {
    return TactilePress(
      borderRadius: BorderRadius.circular(16),
      baseColor: cs.surface,
      border: Border.all(color: cs.outlineVariant.withAlpha(100)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: _showProviderSwitcher,
      child: Row(
        children: [
          Expanded(
            child: Text(
              current.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Symbols.expand_more_rounded,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// 管理 sheet：点选切换、自定义行尾删除、底部「添加服务商」。
  /// picker 类内容无预览语义，按 §3.8 例外不加 BackdropFilter。
  Future<void> _showProviderSwitcher() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final maxH = MediaQuery.sizeOf(ctx).height * 0.7;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.providers,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: Consumer(
                  builder: (context, ref, _) {
                    final instances = ref.watch(agentApiProvider).instances;
                    return ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(ctx).padding.bottom + 12,
                      ),
                      children: [
                        ...instances.map(
                          (inst) => _switcherRow(ctx, theme, cs, inst),
                        ),
                        _addRow(ctx, theme, cs),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _switcherRow(
    BuildContext sheetCtx,
    ThemeData theme,
    ColorScheme cs,
    AgentProviderInstance inst,
  ) {
    final selected = inst.id == _currentId;
    final isCustom = !AgentApiNotifier.isBuiltin(inst.id);
    return TactilePress(
      onTap: () {
        Navigator.pop(sheetCtx);
        _switchTo(inst);
      },
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inst.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  inst.protocol.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Symbols.check_rounded, size: 20, color: cs.primary),
            ),
          if (isCustom)
            IconButton(
              icon: Icon(
                Symbols.delete_rounded,
                size: 20,
                color: cs.onSurfaceVariant.withAlpha(160),
              ),
              tooltip: context.l10n.delete,
              onPressed: () {
                Haptics.soft();
                _deleteInstance(inst);
              },
            ),
        ],
      ),
    );
  }

  Widget _addRow(BuildContext sheetCtx, ThemeData theme, ColorScheme cs) {
    return TactilePress(
      onTap: () {
        Navigator.pop(sheetCtx);
        _addProvider();
      },
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Icon(Symbols.add_rounded, size: 22, color: cs.primary),
          const SizedBox(width: 12),
          Text(
            context.l10n.addProvider,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }

  Future<AgentApiProvider?> _showProtocolPicker() {
    return showModalBottomSheet<AgentApiProvider>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Text(
                  context.l10n.selectProtocol,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              ...AgentApiProvider.values.map((p) {
                return TactilePress(
                  onTap: () => Navigator.pop(ctx, p),
                  baseColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _protocolSubtitle(p, context.l10n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }

  // ── 模型连通性检测 ──

  Future<void> _testModel(AgentProviderInstance inst, String modelId) async {
    final testState = ref.read(modelTestProvider);
    if (testState.testing.contains(modelId)) return;
    final fresh = await _commitPendingEdits() ?? inst;
    if (!mounted) return;
    _testNotifier.startTest(modelId);

    final err = await testAgentModel(
      provider: fresh.protocol,
      baseUrl: fresh.effectiveBaseUrl,
      apiKey: fresh.apiKey,
      modelId: modelId,
    );

    if (!mounted) return;
    _testNotifier.finishTest(modelId, err);
    final snackBar = ref.read(snackBarServiceProvider);
    if (err == null) {
      snackBar.showResult(message: context.l10n.modelConnected(modelId));
    } else {
      _showTestError(modelId, err);
    }
  }

  void _showTestError(String modelId, String error) {
    ref
        .read(snackBarServiceProvider)
        .showResult(
          message: '$modelId: $error',
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: context.l10n.retry,
            onPressed: () {
              final inst = ref.read(agentApiProvider).byId(_currentId);
              if (inst != null) _testModel(inst, modelId);
            },
          ),
        );
  }

  Future<void> _openModelManageSheet(AgentProviderInstance inst) async {
    // sheet 一打开就把 URL/Key 冻结进参数，必须先落盘未过防抖的编辑
    inst = await _commitPendingEdits() ?? inst;
    if (!mounted || inst.apiKey.isEmpty) return;
    final notifier = ref.read(agentApiProvider.notifier);
    final id = inst.id;
    await showAgentModelManageSheet(
      context: context,
      baseUrl: inst.effectiveBaseUrl,
      apiKey: inst.apiKey,
      providerType: inst.protocol,
      providerLabel: inst.name,
      addedModels: inst.models,
      currentDefaultModel: () {
            final r = ref.read(agentApiProvider).defaultRole;
            return r.id == id ? r.modelId : null;
          }(),
      currentFastModel: () {
            final r = ref.read(agentApiProvider).fastRole;
            return r.id == id ? r.modelId : null;
          }(),
      currentImageModel: () {
            final r = ref.read(agentApiProvider).imageRole;
            return r.id == id ? r.modelId : null;
          }(),
      onAdd:
          (
            modelId, {
            bool setAsDefault = false,
            bool setAsFast = false,
            bool setAsImage = false,
          }) => notifier.addModel(
            id,
            modelId,
            setAsDefault: setAsDefault,
            setAsFast: setAsFast,
            setAsImage: setAsImage,
          ),
      onRemove: (modelId) {
        notifier.removeModel(id, modelId);
        _testNotifier.clearResult(modelId);
      },
    );
  }

  Future<void> _openCapabilitySheet(
    AgentProviderInstance inst,
    String modelId,
  ) async {
    await showAgentModelCapabilitySheet(
      context: context,
      modelId: modelId,
      protocol: inst.protocol,
      initial: inst.capabilityFor(modelId),
      inferred: ModelCapabilityStore.instance.lookup(modelId) ??
          AgentModelCapability.infer(
            provider: inst.protocol,
            modelId: modelId,
          ),
      onSave: (cap) => ref
          .read(agentApiProvider.notifier)
          .setModelCapability(inst.id, modelId, cap),
      onReset: () {
        ref
            .read(agentApiProvider.notifier)
            .resetModelCapability(inst.id, modelId);
        ref
            .read(agentApiProvider.notifier)
            .setModelThinkingLevel(inst.id, modelId, null);
      },
      initialThinkingLevel: inst.paramsFor(modelId).thinkingLevel,
      onThinkingLevelChanged: (level) => ref
          .read(agentApiProvider.notifier)
          .setModelThinkingLevel(inst.id, modelId, level),
    );
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final apiState = ref.watch(agentApiProvider);
    final instances = apiState.instances;
    // 当前实例；id 失效（极少见）时回落到第一个
    final current = instances.firstWhere(
      (i) => i.id == _currentId,
      orElse: () => instances.first,
    );
    // dispose 路径的差异比较用（见 _pendingEdits）
    _lastStoredUrl = _urlText(current);
    _lastStoredKey = current.apiKey;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 服务商（点开 sheet 切换 / 添加 / 删除）──
          _sectionLabel(theme, cs, context.l10n.providers),
          const SizedBox(height: 12),
          _providerTile(theme, cs, current),
          const SizedBox(height: 24),

          // ── API Key ──
          Row(
            children: [
              _sectionLabel(theme, cs, context.l10n.apiKey),
              const Spacer(),
              if (AgentApiNotifier.presetApiKeyUrl(current.id)
                  case final url?)
                IconButton(
                  onPressed: () {
                    Haptics.soft();
                    launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: Icon(
                    Symbols.arrow_outward_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: context.l10n.getToken,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            onChanged: (v) {
              // setState 让「管理模型」按钮的启用态跟随输入实时刷新
              setState(() {});
              _keyDebounce.run(() {
                ref
                    .read(agentApiProvider.notifier)
                    .setApiKey(current.id, v.trim());
              });
            },
            obscureText: _keyObscured,
            decoration: _fieldDeco(
              theme,
              cs,
              hint:
                  AgentApiNotifier.presetKeyHint(current.id) ??
                  current.protocol.apiKeyHint,
              suffix: IconButton(
                icon: Icon(
                  _keyObscured
                      ? Symbols.visibility_off_rounded
                      : Symbols.visibility_rounded,
                  size: 20,
                ),
                onPressed: () {
                  Haptics.soft();
                  setState(() => _keyObscured = !_keyObscured);
                },
              ),
            ),
            autocorrect: false,
            enableSuggestions: false,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),

          // ── API 地址 ──
          _sectionLabel(theme, cs, context.l10n.apiAddress),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            onChanged: (v) {
              // setState 让下方预览地址跟随输入实时刷新（落盘仍走防抖）
              setState(() {});
              _urlDebounce.run(() {
                ref
                    .read(agentApiProvider.notifier)
                    .setBaseUrl(current.id, v.trim());
              });
            },
            decoration: _fieldDeco(
              theme,
              cs,
              hint: current.protocol.defaultBaseUrl,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: theme.textTheme.bodyMedium,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              // 预览跟随输入框现值实时变化；清空时回落到当前生效地址
              context.l10n.previewUrl(
                current.protocol.chatUrl(
                  _urlCtrl.text.trim().isNotEmpty
                      ? _urlCtrl.text.trim()
                      : current.effectiveBaseUrl,
                ),
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withAlpha(120),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ── 模型列表（永驻：无模型时只显示标题 + 管理按钮）──
          const SizedBox(height: 24),
          Row(
            children: [
              _sectionLabel(theme, cs, context.l10n.models),
              const Spacer(),
              IconButton(
                onPressed: _keyCtrl.text.trim().isNotEmpty
                    ? () {
                        Haptics.soft();
                        _openModelManageSheet(current);
                      }
                    : null,
                icon: Icon(
                  Symbols.playlist_add_rounded,
                  size: 20,
                  weight: 600,
                  color: _keyCtrl.text.trim().isNotEmpty
                      ? cs.onSurfaceVariant
                      : cs.onSurfaceVariant.withAlpha(80),
                ),
                tooltip: _keyCtrl.text.trim().isNotEmpty
                    ? context.l10n.manageModels
                    : context.l10n.addApiKeyFirst,
              ),
            ],
          ),
          if (current.models.isNotEmpty) ...[
            const SizedBox(height: 12),
            Consumer(
              builder: (context, ref, _) {
                final testState = ref.watch(modelTestProvider);
                return Column(
                  children: current.models.map((modelId) {
                    final hasTested =
                        testState.results.containsKey(modelId);
                    final errorMsg = testState.results[modelId];
                    return AgentModelListTile(
                      key: ValueKey('${current.id}/$modelId'),
                      modelId: modelId,
                      isTesting: testState.testing.contains(modelId),
                      hasTested: hasTested,
                      errorMsg: errorMsg,
                      capability: current.capabilityFor(modelId),
                      onRemove: () {
                        ref
                            .read(agentApiProvider.notifier)
                            .removeModel(current.id, modelId);
                        ref
                            .read(modelTestProvider.notifier)
                            .clearResult(modelId);
                      },
                      onTest: () => _testModel(current, modelId),
                      onShowError: () =>
                          _showTestError(modelId, errorMsg!),
                      onEdit: () =>
                          _openCapabilitySheet(current, modelId),
                    );
                  }).toList(),
                );
              },
            ),
          ],

          // ── 全局模型角色 ──
          const SizedBox(height: 24),
          _sectionLabel(theme, cs, context.l10n.globalModelRoles),
          const SizedBox(height: 12),
          Consumer(
            builder: (context, ref, _) {
              // select 角色元组——records 有结构比较，只在角色变化时重建
              ref.watch(
                agentApiProvider.select(
                  (s) => (s.defaultRole, s.fastRole, s.imageRole),
                ),
              );
              final fullState = ref.read(agentApiProvider);
              return _buildGlobalRoles(theme, cs, fullState);
            },
          ),

          // ── 联网搜索回退（Tavily）──
          const SizedBox(height: 24),
          _sectionLabel(theme, cs, context.l10n.tavilySearchSection),
          const SizedBox(height: 12),
          TextField(
            controller: _tavilyCtrl,
            onChanged: (v) {
              _tavilyDebounce.run(
                () => TavilySearchService.setApiKey(v.trim()),
              );
            },
            obscureText: _tavilyObscured,
            decoration: _fieldDeco(
              theme,
              cs,
              hint: 'tvly-...',
              suffix: IconButton(
                icon: Icon(
                  _tavilyObscured
                      ? Symbols.visibility_off_rounded
                      : Symbols.visibility_rounded,
                  size: 20,
                ),
                onPressed: () {
                  Haptics.soft();
                  setState(() => _tavilyObscured = !_tavilyObscured);
                },
              ),
            ),
            autocorrect: false,
            enableSuggestions: false,
            style: theme.textTheme.bodyMedium,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              context.l10n.tavilySearchDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalRoles(
    ThemeData theme,
    ColorScheme cs,
    AgentProvidersState apiState,
  ) {
    final defaultRole = apiState.defaultRole;
    final fastRole = apiState.fastRole;
    final imageRole = apiState.imageRole;

    final divider = Divider(
      height: 1,
      thickness: 1,
      indent: 14,
      endIndent: 14,
      color: cs.outlineVariant.withAlpha(40),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withAlpha(60)),
      ),
      child: Column(
        children: [
          _roleRow(
            theme,
            cs,
            key: _expertRoleKey,
            icon: Symbols.psychology_rounded,
            iconBg: cs.primaryContainer,
            iconFg: cs.onPrimaryContainer,
            label: context.l10n.expertModel,
            instanceId: defaultRole.id,
            modelId: defaultRole.modelId,
            onTap: () => _showRolePickerDialog(
              roleLabel: context.l10n.expertModel,
              currentInstanceId: defaultRole.id,
              currentModelId: defaultRole.modelId,
              multimodalOnly: true,
              onSelect: (instId, id) => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalDefaultModel(instId, id),
              onClear: () => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalDefaultModel(null, null),
            ),
          ),
          divider,
          _roleRow(
            theme,
            cs,
            key: _fastRoleKey,
            icon: Symbols.bolt_rounded,
            iconBg: cs.tertiaryContainer,
            iconFg: cs.onTertiaryContainer,
            label: context.l10n.fastModel,
            instanceId: fastRole.id,
            modelId: fastRole.modelId,
            onTap: () => _showRolePickerDialog(
              roleLabel: context.l10n.fastModel,
              currentInstanceId: fastRole.id,
              currentModelId: fastRole.modelId,
              onSelect: (instId, id) => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalFastModel(instId, id),
              onClear: () => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalFastModel(null, null),
            ),
          ),
          divider,
          _roleRow(
            theme,
            cs,
            key: _imageRoleKey,
            icon: Symbols.palette_rounded,
            iconBg: cs.secondaryContainer,
            iconFg: cs.onSecondaryContainer,
            label: context.l10n.imageModel,
            instanceId: imageRole.id,
            modelId: imageRole.modelId,
            onTap: () => _showRolePickerDialog(
              roleLabel: context.l10n.imageModel,
              currentInstanceId: imageRole.id,
              currentModelId: imageRole.modelId,
              imageOnly: true,
              onSelect: (instId, id) => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalImageModel(instId, id),
              onClear: () => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalImageModel(null, null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleRow(
    ThemeData theme,
    ColorScheme cs, {
    Key? key,
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required String label,
    required String? instanceId,
    required String? modelId,
    required VoidCallback onTap,
  }) {
    final instName = ref.read(agentApiProvider).byId(instanceId)?.name;
    final isSet = instanceId != null && modelId != null && instName != null;

    return TactilePress(
      key: key,
      onTap: onTap,
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isSet ? iconBg : cs.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 20,
              color: isSet ? iconFg : cs.onSurfaceVariant.withAlpha(120),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                if (isSet)
                  Text(
                    '$modelId · $instName',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    context.l10n.notSet,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant.withAlpha(120),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRolePickerDialog({
    required String roleLabel,
    required String? currentInstanceId,
    required String? currentModelId,
    bool imageOnly = false,
    bool multimodalOnly = false,
    required void Function(String instanceId, String modelId) onSelect,
    required VoidCallback onClear,
  }) async {
    // 按实例分组收集可选模型；按角色用能力过滤后剔除空实例：
    // Expert 角色只收多模态；生图角色只收 canGenerateImage；
    // 快速模型排除嵌入与生图模型。
    final entries = <({String id, String name, List<String> models})>[];
    for (final inst in ref.read(agentApiProvider).instances) {
      final models = inst.models.where((modelId) {
        final cap = inst.capabilityFor(modelId);
        if (imageOnly) return cap.canGenerateImage;
        if (multimodalOnly) return cap.imageInput && !cap.embedding && !cap.imageOutput;
        return !cap.embedding && !cap.imageOutput;
      }).toList();
      if (models.isNotEmpty) {
        entries.add((id: inst.id, name: inst.name, models: models));
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final isSet = currentInstanceId != null && currentModelId != null;

        return Dialog(
          backgroundColor: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.selectRole(roleLabel),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          imageOnly
                              ? ctx.l10n.pleaseAddImageModel
                              : multimodalOnly
                                  ? ctx.l10n.pleaseAddMultimodalModel
                                  : ctx.l10n.pleaseAddModels,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant.withAlpha(160),
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(right: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final entry in entries) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 2,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    entry.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ...entry.models.map((modelId) {
                                  final selected =
                                      entry.id == currentInstanceId &&
                                      modelId == currentModelId;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: TactilePress(
                                      borderRadius: BorderRadius.circular(12),
                                      baseColor: selected
                                          ? cs.primaryContainer
                                          : cs.surfaceContainerHighest
                                                .withAlpha(80),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        onSelect(entry.id, modelId);
                                      },
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              modelId,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: selected
                                                        ? FontWeight.w600
                                                        : null,
                                                    color: selected
                                                        ? cs.onPrimaryContainer
                                                        : cs.onSurface,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (selected)
                                            Icon(
                                              Symbols.check_rounded,
                                              size: 18,
                                              color: cs.onPrimaryContainer,
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isSet)
                        TextButton(
                          onPressed: () {
                            Haptics.soft();
                            Navigator.pop(ctx);
                            onClear();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: cs.error,
                          ),
                          child: Text(ctx.l10n.clearField),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(ctx.l10n.cancel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  InputDecoration _fieldDeco(
    ThemeData theme,
    ColorScheme cs, {
    required String hint,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant.withAlpha(120),
    ),
    filled: true,
    fillColor: cs.surfaceContainerLow,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.primary, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    suffixIcon: suffix,
  );

  Widget _sectionLabel(ThemeData theme, ColorScheme cs, String text) {
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 「添加服务商」第二步：填写名称 / API 地址 / API Key，三项齐备方可创建。
/// 取消返回 null；确认返回 (name, baseUrl, apiKey)。
class _AddProviderDialog extends StatefulWidget {
  final AgentApiProvider protocol;
  const _AddProviderDialog({required this.protocol});

  @override
  State<_AddProviderDialog> createState() => _AddProviderDialogState();
}

class _AddProviderDialogState extends State<_AddProviderDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  bool _keyObscured = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.protocol.label);
    _urlCtrl = TextEditingController(text: widget.protocol.defaultBaseUrl);
    _keyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  bool get _canAdd =>
      _nameCtrl.text.trim().isNotEmpty &&
      _urlCtrl.text.trim().isNotEmpty &&
      _keyCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    InputDecoration deco(String hint, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant.withAlpha(120),
      ),
      filled: true,
      fillColor: cs.surfaceContainerHighest.withAlpha(80),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      suffixIcon: suffix,
      isDense: true,
    );

    Widget fieldLabel(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6, left: 2),
      child: Text(
        t,
        style: theme.textTheme.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Dialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.addProtocol(widget.protocol.label),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              fieldLabel(context.l10n.nameField),
              TextField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                decoration: deco(context.l10n.providerName),
                autocorrect: false,
                style: theme.textTheme.bodyMedium,
              ),
              fieldLabel(context.l10n.apiAddress),
              TextField(
                controller: _urlCtrl,
                onChanged: (_) => setState(() {}),
                decoration: deco(widget.protocol.defaultBaseUrl),
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: theme.textTheme.bodyMedium,
              ),
              fieldLabel(context.l10n.apiKey),
              TextField(
                controller: _keyCtrl,
                onChanged: (_) => setState(() {}),
                obscureText: _keyObscured,
                decoration: deco(
                  widget.protocol.apiKeyHint,
                  suffix: IconButton(
                    icon: Icon(
                      _keyObscured
                          ? Symbols.visibility_off_rounded
                          : Symbols.visibility_rounded,
                      size: 20,
                    ),
                    onPressed: () {
                      Haptics.soft();
                      setState(() => _keyObscured = !_keyObscured);
                    },
                  ),
                ),
                autocorrect: false,
                enableSuggestions: false,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Haptics.soft();
                      Navigator.pop(context);
                    },
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canAdd
                        ? () {
                            Haptics.soft();
                            Navigator.pop(context, (
                              name: _nameCtrl.text.trim(),
                              baseUrl: _urlCtrl.text.trim(),
                              apiKey: _keyCtrl.text.trim(),
                            ));
                          }
                        : null,
                    child: Text(context.l10n.add),
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
