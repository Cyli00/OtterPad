import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../providers/proxy_provider.dart';
import '../../services/identifier_resolver.dart';
import 'package:material_symbols_icons/symbols.dart';

class NetworkSettingsPage extends StatelessWidget {
  const NetworkSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          context.l10n.networkSettings,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: Listener(
        onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
            .copyWith(bottom: 40),
        children: const [
          _ProxySettingsSection(),
        ],
      ),
      ),
    );
  }
}

enum _TestStatus { idle, testing, success, failed }

class _ProxySettingsSection extends ConsumerStatefulWidget {
  const _ProxySettingsSection();

  @override
  ConsumerState<_ProxySettingsSection> createState() =>
      _ProxySettingsSectionState();
}

class _ProxySettingsSectionState extends ConsumerState<_ProxySettingsSection> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  final _urlController = TextEditingController(text: 'https://google.com');
  Timer? _debounce;
  _TestStatus _testStatus = _TestStatus.idle;
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    final proxy = ref.read(proxyProvider);
    _hostController = TextEditingController(text: proxy.host);
    _portController = TextEditingController(text: proxy.port.toString());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hostController.dispose();
    _portController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onAddressChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      final host = _hostController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 7890;
      if (host.isNotEmpty) {
        ref.read(proxyProvider.notifier).setAddress(host, port);
      }
    });
  }

  Future<void> _runTest() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _testStatus = _TestStatus.testing;
      _testResult = '';
    });

    try {
      final ms = await IdentifierResolver.instance.testConnectivity(url);
      if (!mounted) return;
      setState(() {
        _testStatus = _TestStatus.success;
        _testResult = context.l10n.connectionOkMs(ms.toString());
      });
    } on DioException catch (e) {
      if (!mounted) return;
      String msg;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        msg = context.l10n.connectionTimeout;
      } else if (e.type == DioExceptionType.connectionError) {
        msg = context.l10n.cannotConnectCheckProxy;
      } else {
        msg = context.l10n.requestFailed(e.message ?? e.type.name);
      }
      setState(() {
        _testStatus = _TestStatus.failed;
        _testResult = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testStatus = _TestStatus.failed;
        _testResult = context.l10n.testFailed(e.toString());
      });
    }
  }

  Widget _buildGroup(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12, top: 24),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }

  InputDecoration _fieldDeco(
    BuildContext context, {
    required String hint,
    String? label,
    Widget? suffix,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InputDecoration(
      labelText: label,
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
          width: 1,
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
  }

  @override
  Widget build(BuildContext context) {
    final proxy = ref.watch(proxyProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        // ── 代理设置 ──
        _buildGroup(
          context,
          title: context.l10n.proxy,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: RadioGroup<ProxyMode>(
              groupValue: proxy.mode,
              onChanged: (v) {
                if (v != null) ref.read(proxyProvider.notifier).setMode(v);
              },
              child: Column(
                children: [
                  RadioListTile<ProxyMode>(
                    title: Text(context.l10n.customProxy,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(context.l10n.customProxySubtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    value: ProxyMode.custom,
                  ),
                  Animate(
                    target: proxy.mode == ProxyMode.custom ? 1 : 0,
                    effects: [
                      FadeEffect(duration: 200.ms),
                      CustomEffect(
                        duration: 200.ms,
                        curve: Curves.easeOut,
                        builder: (context, value, child) => ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: value,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _hostController,
                              decoration: _fieldDeco(
                                context,
                                hint: '127.0.0.1',
                                label: context.l10n.hostAddress,
                              ),
                              onChanged: (_) => _onAddressChanged(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _portController,
                              decoration: _fieldDeco(
                                context,
                                hint: '7890',
                                label: context.l10n.port,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(5),
                              ],
                              onChanged: (_) => _onAddressChanged(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  RadioListTile<ProxyMode>(
                    title: Text(context.l10n.systemProxy,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(context.l10n.systemProxySubtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    value: ProxyMode.system,
                  ),
                  RadioListTile<ProxyMode>(
                    title: Text(context.l10n.noProxy,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(context.l10n.noProxySubtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    value: ProxyMode.none,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── 连通性测试 ──
        _buildGroup(
          context,
          title: context.l10n.connectivityTest,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.testAddress,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: _fieldDeco(
                          context,
                          hint: 'https://google.com',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed:
                          _testStatus == _TestStatus.testing ? null : _runTest,
                      icon: _testStatus == _TestStatus.testing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onSecondaryContainer,
                              ),
                            )
                          : const Icon(Symbols.network_ping_rounded),
                      label: Text(context.l10n.test),
                    ),
                  ],
                ),
                if (_testResult.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _testStatus == _TestStatus.success
                            ? Symbols.check_circle_rounded
                            : Symbols.error_rounded,
                        size: 20,
                        color: _testStatus == _TestStatus.success
                            ? cs.primary
                            : cs.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _testStatus == _TestStatus.success
                                ? cs.primary
                                : cs.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
