import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/proxy_provider.dart';
import '../../services/identifier_resolver.dart';

class NetworkSettingsPage extends StatelessWidget {
  const NetworkSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '网络设置',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: const [
          _ProxySettingsSection(),
        ],
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
        _testResult = '连接成功，耗时 $ms ms';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      String msg;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        msg = '连接超时';
      } else if (e.type == DioExceptionType.connectionError) {
        msg = '无法连接，请检查代理设置';
      } else {
        msg = '请求失败：${e.message ?? e.type.name}';
      }
      setState(() {
        _testStatus = _TestStatus.failed;
        _testResult = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testStatus = _TestStatus.failed;
        _testResult = '测试失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final proxy = ref.watch(proxyProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: RadioGroup<ProxyMode>(
          groupValue: proxy.mode,
          onChanged: (v) {
            if (v != null) ref.read(proxyProvider.notifier).setMode(v);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('代理', style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold)),
              ),
              RadioListTile<ProxyMode>(
                title: const Text('自定义代理'),
                subtitle:
                    const Text('手动指定代理地址'),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostController,
                          decoration: InputDecoration(
                            labelText: '主机地址',
                            hintText: '127.0.0.1',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                          ),
                          onChanged: (_) => _onAddressChanged(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portController,
                          decoration: InputDecoration(
                            labelText: '端口',
                            hintText: '7890',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
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
                title: const Text('系统代理'),
                subtitle: const Text('使用系统环境变量中的代理设置'),
                value: ProxyMode.system,
              ),
              RadioListTile<ProxyMode>(
                title: const Text('不使用代理'),
                subtitle: const Text('直接连接网络'),
                value: ProxyMode.none,
              ),

              // ── 连通性测试 ──
              const Divider(indent: 16, endIndent: 16),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('连通性测试', style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          labelText: '测试地址',
                          hintText: 'https://google.com',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
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
                          : const Icon(Icons.network_ping_rounded),
                      label: const Text('测试'),
                    ),
                  ],
                ),
              ),
              if (_testResult.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Icon(
                        _testStatus == _TestStatus.success
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        size: 20,
                        color: _testStatus == _TestStatus.success
                            ? cs.primary
                            : cs.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult,
                          style: tt.bodyMedium?.copyWith(
                            color: _testStatus == _TestStatus.success
                                ? cs.primary
                                : cs.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
