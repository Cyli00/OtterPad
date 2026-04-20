import 'package:flutter/material.dart';

import 'api_settings_agent.dart';
import 'translation_settings_section.dart';

/// 模型服务设置页
class ApiSettingsPage extends StatelessWidget {
  const ApiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'AI 设置',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: Listener(
        onPointerDown: (_) => ScaffoldMessenger.of(context).clearSnackBars(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              .copyWith(bottom: 40),
          children: [
            _buildGroup(context, title: 'API 设置', child: const AgentApiSection()),
            _buildGroup(context, title: '翻译设置', child: const TranslationSettingsSection()),
          ],
        ),
      ),
    );
  }

  /// 复用网络设置/OCR 设置的分组样式：主题色标题 + surfaceContainerHigh 圆角容器
  Widget _buildGroup(BuildContext context,
      {required String title, required Widget child}) {
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
}
