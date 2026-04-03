import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_provider.dart';

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

  // ── 模型检测 ──

  Future<void> _testModel(String modelId) async {
    if (_modelTesting.contains(modelId)) return;
    setState(() {
      _modelTesting.add(modelId);
      _modelTestResults.remove(modelId);
    });

    final agentState = ref.read(agentApiProvider);
    final provider = agentState.provider;
    final baseUrl = agentState.effectiveBaseUrl;
    final apiKey = agentState.apiKey;

    final url = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      switch (provider) {
        case AgentApiProvider.openai:
          await dio.post(
            '$url${provider.chatPath}',
            data: {
              'model': modelId,
              'input': 'hi',
              'max_output_tokens': 16,
            },
            options: Options(headers: {
              'Authorization': 'Bearer $apiKey',
            }),
          );
        case AgentApiProvider.anthropic:
          await dio.post(
            '$url${provider.chatPath}',
            data: {
              'model': modelId,
              'max_tokens': 1,
              'messages': [
                {'role': 'user', 'content': 'hi'}
              ],
            },
            options: Options(headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            }),
          );
        case AgentApiProvider.gemini:
          await dio.post(
            '$url${provider.chatPath}/models/$modelId:generateContent',
            queryParameters: {'key': apiKey},
            data: {
              'contents': [
                {
                  'parts': [
                    {'text': 'hi'}
                  ]
                }
              ],
              'generationConfig': {'maxOutputTokens': 1},
            },
          );
      }
      if (mounted) {
        setState(() => _modelTestResults[modelId] = null);
        _showTestSuccess(modelId);
      }
    } on DioException catch (e) {
      if (provider == AgentApiProvider.anthropic &&
          e.response?.statusCode == 400) {
        if (mounted) {
          setState(() => _modelTestResults[modelId] = null);
          _showTestSuccess(modelId);
        }
        return;
      }
      String msg;
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        final apiErr = body['error'];
        if (apiErr is Map) {
          msg = apiErr['message'] as String? ??
              'HTTP ${e.response?.statusCode}';
        } else if (apiErr is String) {
          msg = apiErr;
        } else {
          msg = body['message'] as String? ??
              'HTTP ${e.response?.statusCode}';
        }
      } else {
        msg = e.response?.statusCode != null
            ? 'HTTP ${e.response!.statusCode}'
            : (e.message ?? e.type.name);
      }
      if (mounted) setState(() => _modelTestResults[modelId] = msg);
    } catch (e) {
      if (mounted) setState(() => _modelTestResults[modelId] = '$e');
    } finally {
      if (mounted) setState(() => _modelTesting.remove(modelId));
    }
  }

  void _showTestSuccess(String modelId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 18),
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
            Icon(Icons.error_outline_rounded, color: cs.error, size: 18),
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

  Future<void> _showModelManageSheet() async {
    final s = ref.read(agentApiProvider);
    if (s.apiKey.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ModelManageSheet(
        baseUrl: s.effectiveBaseUrl,
        apiKey: s.apiKey,
        providerType: s.provider,
        providerLabel: s.provider.label,
        addedModels: s.models,
        onAdd: (id) => ref.read(agentApiProvider.notifier).addModel(id),
      ),
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
          fillColor: cs.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: cs.outlineVariant.withAlpha(100),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: cs.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          isDense: true,
          suffixIcon: suffix,
        );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 服务商 ──
          Text(
            '服务商',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
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
                  ref
                      .read(agentApiProvider.notifier)
                      .setProvider(set.first);
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
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── API Key ──
          Text(
            'API Key',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
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
                  _keyObscured
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _keyObscured = !_keyObscured),
              ),
            ),
            autocorrect: false,
            enableSuggestions: false,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),

          // ── API 地址 ──
          Text(
            'API 地址',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
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
                  Icons.tune_rounded,
                  size: 20,
                  color: agentState.apiKey.isNotEmpty
                      ? cs.primary
                      : cs.onSurfaceVariant.withAlpha(80),
                ),
                tooltip: '管理模型',
                onPressed: agentState.apiKey.isNotEmpty
                    ? _showModelManageSheet
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
            Text(
              '模型',
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...agentState.models.map((modelId) {
              final hasTested = _modelTestResults.containsKey(modelId);
              final isOk = hasTested && _modelTestResults[modelId] == null;
              final errorMsg = _modelTestResults[modelId];
              final isTesting = _modelTesting.contains(modelId);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isOk
                          ? cs.primary.withAlpha(100)
                          : (hasTested && !isOk)
                              ? cs.error.withAlpha(100)
                              : cs.outlineVariant.withAlpha(60),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOk
                                ? cs.primary
                                : (hasTested && !isOk)
                                    ? cs.error
                                    : cs.outlineVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            modelId,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: isTesting
                              ? const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    Icons.monitor_heart_outlined,
                                    size: 20,
                                    color: isOk
                                        ? cs.primary
                                        : (hasTested && !isOk)
                                            ? cs.error
                                            : cs.onSurfaceVariant,
                                  ),
                                  padding: EdgeInsets.zero,
                                  tooltip: (hasTested && !isOk)
                                      ? errorMsg
                                      : '检测模型',
                                  onPressed: (hasTested && !isOk)
                                      ? () => _showTestError(
                                          modelId, errorMsg!)
                                      : () => _testModel(modelId),
                                ),
                        ),
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: cs.onSurfaceVariant.withAlpha(120),
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: '移除',
                            onPressed: () {
                              ref
                                  .read(agentApiProvider.notifier)
                                  .removeModel(modelId);
                              _modelTestResults.remove(modelId);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─── 模型管理底部弹窗 ────────────────────────────────────────────────────────

class _ModelManageSheet extends StatefulWidget {
  final String baseUrl;
  final String apiKey;
  final AgentApiProvider providerType;
  final String providerLabel;
  final List<String> addedModels;
  final ValueChanged<String> onAdd;

  const _ModelManageSheet({
    required this.baseUrl,
    required this.apiKey,
    required this.providerType,
    required this.providerLabel,
    required this.addedModels,
    required this.onAdd,
  });

  static const _anthropicModels = [
    'claude-opus-4-20250514',
    'claude-sonnet-4-20250514',
    'claude-3-5-haiku-20241022',
  ];

  @override
  State<_ModelManageSheet> createState() => _ModelManageSheetState();
}

class _ModelManageSheetState extends State<_ModelManageSheet> {
  List<String>? _models;
  bool _loading = true;
  String? _error;
  String _query = '';
  final _addedDuringSession = <String>{};

  @override
  void initState() {
    super.initState();
    _fetchModels();
  }

  Future<void> _fetchModels() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (widget.providerType == AgentApiProvider.anthropic) {
      if (mounted) {
        setState(() {
          _models = List.from(_ModelManageSheet._anthropicModels);
          _loading = false;
        });
      }
      return;
    }

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      switch (widget.providerType) {
        case AgentApiProvider.openai:
          final response = await dio.get<Map<String, dynamic>>(
            '${widget.baseUrl}${widget.providerType.modelsPath}',
            options: Options(
              headers: {'Authorization': 'Bearer ${widget.apiKey}'},
            ),
          );
          final data = response.data?['data'] as List<dynamic>?;
          if (data != null) {
            final ids = data
                .map((m) =>
                    (m as Map<String, dynamic>)['id'] as String? ?? '')
                .where((id) => id.isNotEmpty)
                .toList()
              ..sort();
            if (mounted) setState(() => _models = ids);
          }

        case AgentApiProvider.gemini:
          final response = await dio.get<Map<String, dynamic>>(
            '${widget.baseUrl}${widget.providerType.modelsPath}',
            queryParameters: {'key': widget.apiKey},
          );
          final list = response.data?['models'] as List<dynamic>? ?? [];
          final ids = list.map((m) {
            final name =
                (m as Map<String, dynamic>)['name'] as String? ?? '';
            return name.startsWith('models/') ? name.substring(7) : name;
          }).where((id) => id.isNotEmpty).toList()
            ..sort();
          if (mounted) setState(() => _models = ids);

        case AgentApiProvider.anthropic:
          break;
      }
    } catch (e) {
      if (mounted) setState(() => _error = '获取模型列表失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _filtered {
    if (_models == null) return [];
    if (_query.isEmpty) return _models!;
    final q = _query.toLowerCase();
    return _models!.where((m) => m.toLowerCase().contains(q)).toList();
  }

  bool _isAdded(String id) =>
      widget.addedModels.contains(id) || _addedDuringSession.contains(id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.75;
    final filtered = _filtered;
    final addedCount =
        _addedDuringSession.length + widget.addedModels.length;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    '${widget.providerLabel} 模型',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  if (_models != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_models!.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded,
                        size: 20, color: cs.onSurfaceVariant),
                    tooltip: '刷新',
                    onPressed: _fetchModels,
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: cs.onSurfaceVariant),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                textAlignVertical: TextAlignVertical.center,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: '搜索模型 ID 或名称',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant.withAlpha(120),
                  ),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (addedCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '已添加 $addedCount 个模型',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_rounded,
                                  size: 40,
                                  color: cs.error.withAlpha(160)),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: cs.error)),
                              const SizedBox(height: 16),
                              FilledButton.tonal(
                                onPressed: _fetchModels,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(48),
                              child: Text('无匹配结果',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                          color: cs.onSurfaceVariant)),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.only(
                                left: 12,
                                right: 12,
                                top: 4,
                                bottom:
                                    MediaQuery.of(context).padding.bottom +
                                        16,
                              ),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final id = filtered[index];
                                final added = _isAdded(id);

                                return Material(
                                  color: added
                                      ? cs.primaryContainer.withAlpha(60)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    onTap: added
                                        ? null
                                        : () {
                                            widget.onAdd(id);
                                            setState(() =>
                                                _addedDuringSession
                                                    .add(id));
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              id,
                                              style: theme
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: added
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                                color: added
                                                    ? cs.primary
                                                    : cs.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (added)
                                            Container(
                                              padding:
                                                  const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: cs.primary
                                                    .withAlpha(30),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        8),
                                              ),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                      Icons.check_rounded,
                                                      size: 14,
                                                      color: cs.primary),
                                                  const SizedBox(
                                                      width: 4),
                                                  Text(
                                                    '已添加',
                                                    style: theme.textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                      color: cs.primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            Icon(
                                                Icons
                                                    .add_circle_outline,
                                                size: 22,
                                                color:
                                                    cs.onSurfaceVariant),
                                        ],
                                      ),
                                    ),
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
