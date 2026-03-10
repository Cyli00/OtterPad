import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_provider.dart';

class ApiSettingsPage extends ConsumerStatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  ConsumerState<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends ConsumerState<ApiSettingsPage> {
  late final TextEditingController _agentUrlCtrl;
  late final TextEditingController _agentKeyCtrl;
  late final TextEditingController _docUrlCtrl;
  late final TextEditingController _docKeyCtrl;

  bool _agentKeyObscured = true;
  bool _docKeyObscured = true;

  Timer? _agentUrlTimer;
  Timer? _agentKeyTimer;
  Timer? _docUrlTimer;
  Timer? _docKeyTimer;

  @override
  void initState() {
    super.initState();
    final agentState = ref.read(agentApiProvider);
    final docState = ref.read(docExtractApiProvider);
    _agentUrlCtrl = TextEditingController(text: agentState.baseUrl);
    _agentKeyCtrl = TextEditingController(text: agentState.apiKey);
    _docUrlCtrl = TextEditingController(text: docState.baseUrl);
    _docKeyCtrl = TextEditingController(text: docState.apiKey);
  }

  @override
  void dispose() {
    _agentUrlCtrl.dispose();
    _agentKeyCtrl.dispose();
    _docUrlCtrl.dispose();
    _docKeyCtrl.dispose();
    _agentUrlTimer?.cancel();
    _agentKeyTimer?.cancel();
    _docUrlTimer?.cancel();
    _docKeyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final agentState = ref.watch(agentApiProvider);

    InputDecoration fieldDeco({required String hint, Widget? suffix}) =>
        InputDecoration(
          hintText: hint,
          hintStyle: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant.withAlpha(130)),
          filled: true,
          fillColor: cs.surfaceContainer,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
          suffixIcon: suffix,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('API 服务商设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Agent API ──────────────────────────────────────────────────────
          _SectionTitle('Agent API'),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 服务商选择
                  Text(
                    '服务商',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AgentApiProvider>(
                      segments: AgentApiProvider.values
                          .map((p) =>
                              ButtonSegment(value: p, label: Text(p.label)))
                          .toList(),
                      selected: {agentState.provider},
                      onSelectionChanged: (set) => ref
                          .read(agentApiProvider.notifier)
                          .setProvider(set.first),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Base URL
                  Text(
                    'Base URL',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _agentUrlCtrl,
                    onChanged: (v) {
                      _agentUrlTimer?.cancel();
                      _agentUrlTimer =
                          Timer(const Duration(milliseconds: 600), () {
                        ref
                            .read(agentApiProvider.notifier)
                            .setBaseUrl(v.trim());
                      });
                    },
                    decoration:
                        fieldDeco(hint: agentState.provider.defaultBaseUrl),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  // API Key
                  Text(
                    'API Key',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _agentKeyCtrl,
                    onChanged: (v) {
                      _agentKeyTimer?.cancel();
                      _agentKeyTimer =
                          Timer(const Duration(milliseconds: 600), () {
                        ref
                            .read(agentApiProvider.notifier)
                            .setApiKey(v.trim());
                      });
                    },
                    obscureText: _agentKeyObscured,
                    decoration: fieldDeco(
                      hint: agentState.provider.apiKeyHint,
                      suffix: IconButton(
                        icon: Icon(
                          _agentKeyObscured
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _agentKeyObscured = !_agentKeyObscured),
                      ),
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 文档提取 API ────────────────────────────────────────────────────
          _SectionTitle('文档提取 API'),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 格式说明
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前仅支持 OpenAI 原生格式（兼容第三方接口）',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Base URL
                  Text(
                    'Base URL',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _docUrlCtrl,
                    onChanged: (v) {
                      _docUrlTimer?.cancel();
                      _docUrlTimer =
                          Timer(const Duration(milliseconds: 600), () {
                        ref
                            .read(docExtractApiProvider.notifier)
                            .setBaseUrl(v.trim());
                      });
                    },
                    decoration:
                        fieldDeco(hint: 'https://api.openai.com/v1'),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  // API Key
                  Text(
                    'API Key',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _docKeyCtrl,
                    onChanged: (v) {
                      _docKeyTimer?.cancel();
                      _docKeyTimer =
                          Timer(const Duration(milliseconds: 600), () {
                        ref
                            .read(docExtractApiProvider.notifier)
                            .setApiKey(v.trim());
                      });
                    },
                    obscureText: _docKeyObscured,
                    decoration: fieldDeco(
                      hint: 'sk-...',
                      suffix: IconButton(
                        icon: Icon(
                          _docKeyObscured
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _docKeyObscured = !_docKeyObscured),
                      ),
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
