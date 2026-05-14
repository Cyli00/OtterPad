import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../providers/api_provider.dart';
import '../../services/agent_model_capability.dart';
import 'agent_model_list_tile.dart';
import 'agent_model_manage_sheet.dart';
import 'agent_model_params_sheet.dart';
import 'agent_model_tester.dart';
import 'setting_picker.dart';

/// 服务商副标题——给用户一个"选它能做什么"的简短提示。
String _providerSubtitle(AgentApiProvider p) => switch (p) {
      AgentApiProvider.openai => 'gpt / o 系列 · 生图支持 gpt-image-2',
      AgentApiProvider.anthropic => 'Claude 系列',
      AgentApiProvider.gemini => 'Google AI · 多模态',
      AgentApiProvider.openAICompatible =>
        'DeepSeek / 自部署等 OpenAI 兼容 API',
    };

/// 文档助手 Agent API 配置区块
class AgentApiSection extends ConsumerStatefulWidget {
  const AgentApiSection({super.key});

  @override
  ConsumerState<AgentApiSection> createState() => _AgentApiSectionState();
}

class _AgentApiSectionState extends ConsumerState<AgentApiSection> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;

  bool _keyObscured = true;
  Timer? _urlTimer;
  Timer? _keyTimer;

  // key 在结果集中 → 已测过；value 为 null → 成功，非空 → 错误消息
  final _modelTestResults = <String, String?>{};
  final _modelTesting = <String>{};

  @override
  void initState() {
    super.initState();
    final s = ref.read(agentApiProvider);
    _urlCtrl = TextEditingController(
      text: s.baseUrl.isNotEmpty ? s.baseUrl : s.provider.defaultBaseUrl,
    );
    _keyCtrl = TextEditingController(text: s.apiKey);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _urlTimer?.cancel();
    _keyTimer?.cancel();
    super.dispose();
  }

  // ── 模型连通性检测 ──

  Future<void> _testModel(String modelId) async {
    if (_modelTesting.contains(modelId)) return;
    setState(() {
      _modelTesting.add(modelId);
      _modelTestResults.remove(modelId);
    });

    final agentState = ref.read(agentApiProvider);
    final err = await testAgentModel(
      provider: agentState.provider,
      baseUrl: agentState.effectiveBaseUrl,
      apiKey: agentState.apiKey,
      modelId: modelId,
    );

    if (!mounted) return;
    setState(() {
      _modelTestResults[modelId] = err;
      _modelTesting.remove(modelId);
    });
    if (err == null) {
      _showTestSuccess(modelId);
    }
  }

  void _showTestSuccess(String modelId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Symbols.check_circle_rounded,
              color: Colors.green,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('$modelId 连接成功')),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showTestError(String modelId, String error) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Symbols.error_rounded, color: cs.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                '$modelId: $error',
                style: TextStyle(color: cs.onInverseSurface),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '重试',
          onPressed: () => _testModel(modelId),
        ),
      ),
    );
  }

  Future<void> _openModelManageSheet() async {
    final s = ref.read(agentApiProvider);
    if (s.apiKey.isEmpty) return;

    await showAgentModelManageSheet(
      context: context,
      baseUrl: s.effectiveBaseUrl,
      apiKey: s.apiKey,
      providerType: s.provider,
      providerLabel: s.provider.label,
      addedModels: s.models,
      currentDefaultModel: s.defaultModelId,
      currentFastModel: s.fastModelId,
      currentImageModel: s.imageModelId,
      onAdd: (id, {bool setAsDefault = false, bool setAsFast = false, bool setAsImage = false}) => ref
          .read(agentApiProvider.notifier)
          .addModel(id, setAsDefault: setAsDefault, setAsFast: setAsFast, setAsImage: setAsImage),
      onRemove: (id) {
        ref.read(agentApiProvider.notifier).removeModel(id);
        _modelTestResults.remove(id);
      },
    );
  }

  Future<void> _openModelParamsSheet(String modelId) async {
    final s = ref.read(agentApiProvider);
    await showAgentModelParamsSheet(
      context: context,
      provider: s.provider,
      providerLabel: s.provider.label,
      modelId: modelId,
      initialParams: s.paramsFor(modelId),
      onSave: (p) =>
          ref.read(agentApiProvider.notifier).setModelParams(modelId, p),
    );
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final agentState = ref.watch(agentApiProvider);

    InputDecoration fieldDeco({required String hint, Widget? suffix}) =>
        InputDecoration(
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          suffixIcon: suffix,
        );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 服务商 ──
          _sectionLabel(theme, cs, '服务商'),
          const SizedBox(height: 12),
          SettingPicker<AgentApiProvider>(
            current: agentState.provider,
            options: AgentApiProvider.values,
            labelFor: (p) => p.label,
            subtitleFor: _providerSubtitle,
            sheetTitle: '服务商',
            onChanged: (next) {
              if (agentState.provider == next) return;
              ref.read(agentApiProvider.notifier).setProvider(next);
              final s = ref.read(agentApiProvider);
              _keyCtrl.text = s.apiKey;
              _urlCtrl.text =
                  s.baseUrl.isNotEmpty ? s.baseUrl : next.defaultBaseUrl;
              _modelTestResults.clear();
            },
          ),
          const SizedBox(height: 24),

          // ── API Key ──
          _sectionLabel(theme, cs, 'API Key'),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            onChanged: (v) {
              _keyTimer?.cancel();
              _keyTimer = Timer(const Duration(milliseconds: 600), () {
                ref.read(agentApiProvider.notifier).setApiKey(v.trim());
              });
            },
            obscureText: _keyObscured,
            decoration: fieldDeco(
              hint: agentState.provider.apiKeyHint,
              suffix: IconButton(
                icon: Icon(
                  _keyObscured ? Symbols.visibility_off : Symbols.visibility,
                  size: 20,
                ),
                onPressed: () => setState(() => _keyObscured = !_keyObscured),
              ),
            ),
            autocorrect: false,
            enableSuggestions: false,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),

          // ── API 地址 ──
          _sectionLabel(theme, cs, 'API 地址'),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            onChanged: (v) {
              _urlTimer?.cancel();
              _urlTimer = Timer(const Duration(milliseconds: 600), () {
                ref.read(agentApiProvider.notifier).setBaseUrl(v.trim());
              });
            },
            decoration: fieldDeco(
              hint: agentState.provider.defaultBaseUrl,
              suffix: IconButton(
                icon: Icon(
                  Symbols.tune_rounded,
                  size: 20,
                  color: agentState.apiKey.isNotEmpty
                      ? cs.primary
                      : cs.onSurfaceVariant.withAlpha(80),
                ),
                tooltip: '管理模型',
                onPressed: agentState.apiKey.isNotEmpty
                    ? _openModelManageSheet
                    : null,
              ),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: theme.textTheme.bodyMedium,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              '预览: ${agentState.effectiveBaseUrl}${agentState.provider.chatPath}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withAlpha(120),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ── 模型列表 ──
          if (agentState.models.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionLabel(theme, cs, '模型'),
            const SizedBox(height: 12),
            ...agentState.models.map((modelId) {
              final hasTested = _modelTestResults.containsKey(modelId);
              final errorMsg = _modelTestResults[modelId];
              final isImage = AgentModelCapability.isImageGenerationModel(
                provider: agentState.provider,
                modelId: modelId,
              );
              return AgentModelListTile(
                key: ValueKey(modelId),
                modelId: modelId,
                isTesting: _modelTesting.contains(modelId),
                hasTested: hasTested,
                errorMsg: errorMsg,
                hasCustomParams: !agentState.paramsFor(modelId).isDefault,
                isImageModel: isImage,
                onRemove: () {
                  ref.read(agentApiProvider.notifier).removeModel(modelId);
                  _modelTestResults.remove(modelId);
                },
                onTest: () => _testModel(modelId),
                onShowError: () => _showTestError(modelId, errorMsg!),
                onTune: isImage ? null : () => _openModelParamsSheet(modelId),
              );
            }),
          ],

          // ── 全局模型角色 ──
          const SizedBox(height: 24),
          _sectionLabel(theme, cs, '全局模型角色'),
          const SizedBox(height: 12),
          _buildGlobalRoles(theme, cs),
        ],
      ),
    );
  }

  Widget _buildGlobalRoles(ThemeData theme, ColorScheme cs) {
    final defaultRole = AgentApiNotifier.globalDefaultRole;
    final fastRole = AgentApiNotifier.globalFastRole;
    final imageRole = AgentApiNotifier.globalImageRole;

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
            icon: Symbols.gavel_rounded,
            iconBg: cs.primaryContainer,
            iconFg: cs.onPrimaryContainer,
            label: '专家模型',
            provider: defaultRole.provider,
            modelId: defaultRole.modelId,
            onTap: () => _showRolePickerDialog(
              roleLabel: '专家模型',
              currentProvider: defaultRole.provider,
              currentModelId: defaultRole.modelId,
              onSelect: (prov, id) => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalDefaultModel(prov, id),
              onClear: () => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalDefaultModel(null, null),
            ),
          ),
          divider,
          _roleRow(
            theme,
            cs,
            icon: Symbols.bolt_rounded,
            iconBg: cs.tertiaryContainer,
            iconFg: cs.onTertiaryContainer,
            label: '快速模型',
            provider: fastRole.provider,
            modelId: fastRole.modelId,
            onTap: () => _showRolePickerDialog(
              roleLabel: '快速模型',
              currentProvider: fastRole.provider,
              currentModelId: fastRole.modelId,
              onSelect: (prov, id) => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalFastModel(prov, id),
              onClear: () => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalFastModel(null, null),
            ),
          ),
          divider,
          _roleRow(
            theme,
            cs,
            icon: Symbols.palette_rounded,
            iconBg: cs.secondaryContainer,
            iconFg: cs.onSecondaryContainer,
            label: '生图模型',
            provider: imageRole.provider,
            modelId: imageRole.modelId,
            onTap: () => _showRolePickerDialog(
              roleLabel: '生图模型',
              currentProvider: imageRole.provider,
              currentModelId: imageRole.modelId,
              imageOnly: true,
              onSelect: (prov, id) => ref
                  .read(agentApiProvider.notifier)
                  .setGlobalImageModel(prov, id),
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
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required String label,
    required AgentApiProvider? provider,
    required String? modelId,
    required VoidCallback onTap,
  }) {
    final isSet = provider != null && modelId != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSet
                      ? iconBg
                      : cs.surfaceContainerHighest.withAlpha(120),
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
                        '$modelId · ${provider.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        '未设置',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withAlpha(120),
                        ),
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

  Future<void> _showRolePickerDialog({
    required String roleLabel,
    required AgentApiProvider? currentProvider,
    required String? currentModelId,
    bool imageOnly = false,
    required void Function(AgentApiProvider provider, String modelId) onSelect,
    required VoidCallback onClear,
  }) async {
    final allModels = AgentApiNotifier.getAllConfiguredModels();
    final displayModels = allModels.map(
      (provider, models) => MapEntry(
        provider,
        models.where((modelId) {
          final isImage = AgentModelCapability.isImageGenerationModel(
            provider: provider,
            modelId: modelId,
          );
          return imageOnly ? isImage : !isImage;
        }).toList(),
      ),
    );
    displayModels.removeWhere((_, models) => models.isEmpty);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final isSet = currentProvider != null && currentModelId != null;

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
                    '选择$roleLabel',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (displayModels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          imageOnly ? '请先添加支持图片输出的模型' : '请先在各服务商下添加模型',
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
                              for (final entry in displayModels.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 2,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    entry.key.label,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ...entry.value.map((modelId) {
                                  final selected =
                                      entry.key == currentProvider &&
                                      modelId == currentModelId;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Material(
                                      color: selected
                                          ? cs.primaryContainer
                                          : cs.surfaceContainerHighest
                                                .withAlpha(80),
                                      borderRadius: BorderRadius.circular(12),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          onSelect(entry.key, modelId);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  modelId,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight: selected
                                                            ? FontWeight.w600
                                                            : null,
                                                        color: selected
                                                            ? cs.onPrimaryContainer
                                                            : cs.onSurface,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                            Navigator.pop(ctx);
                            onClear();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: cs.error,
                          ),
                          child: const Text('清除'),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
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
