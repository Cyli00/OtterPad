import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../providers/api_provider.dart';
import 'agent_model_list_tile.dart';
import 'agent_model_manage_sheet.dart';
import 'agent_model_params_sheet.dart';
import 'agent_model_tester.dart';

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
      onAdd: (id, {bool setAsDefault = false, bool setAsFast = false}) => ref
          .read(agentApiProvider.notifier)
          .addModel(id, setAsDefault: setAsDefault, setAsFast: setAsFast),
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
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AgentApiProvider>(
              segments: AgentApiProvider.values
                  .map((p) => ButtonSegment(value: p, label: Text(p.label)))
                  .toList(),
              selected: {agentState.provider},
              onSelectionChanged: (set) {
                if (agentState.provider != set.first) {
                  ref.read(agentApiProvider.notifier).setProvider(set.first);
                  final s = ref.read(agentApiProvider);
                  _keyCtrl.text = s.apiKey;
                  _urlCtrl.text = s.baseUrl.isNotEmpty
                      ? s.baseUrl
                      : set.first.defaultBaseUrl;
                  _modelTestResults.clear();
                }
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: cs.surface,
                selectedBackgroundColor: cs.primaryContainer,
                side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withAlpha(120),
                fontSize: 11,
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
              return AgentModelListTile(
                modelId: modelId,
                isDefault: agentState.defaultModelId == modelId,
                isFast: agentState.fastModelId == modelId,
                isTesting: _modelTesting.contains(modelId),
                hasTested: hasTested,
                errorMsg: errorMsg,
                hasCustomParams: !agentState.paramsFor(modelId).isDefault,
                onRemove: () {
                  ref.read(agentApiProvider.notifier).removeModel(modelId);
                  _modelTestResults.remove(modelId);
                },
                onTest: () => _testModel(modelId),
                onShowError: () => _showTestError(modelId, errorMsg!),
                onTune: () => _openModelParamsSheet(modelId),
              );
            }),
          ],
        ],
      ),
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
