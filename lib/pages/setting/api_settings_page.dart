import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'api_settings_agent.dart';
import 'image_generation_settings_section.dart';
import 'setting_group.dart';
import 'translation_settings_section.dart';

/// 模型服务设置页
class ApiSettingsPage extends StatelessWidget {
  const ApiSettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: embedded
          ? null
          : AppBar(
              title: Text(
                context.l10n.aiSettings,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: false,
              backgroundColor: cs.surface,
              scrolledUnderElevation: 0,
            ),
      body: Listener(
        onPointerDown: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          ScaffoldMessenger.of(context).clearSnackBars();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ).copyWith(bottom: 40),
          children: [
            SettingGroup(
              title: context.l10n.modelApi,
              child: const AgentApiSection(),
            ),
            SettingGroup(
              title: context.l10n.translationSettings,
              child: const TranslationSettingsSection(),
            ),
            SettingGroup(
              title: context.l10n.imageGenSettings,
              child: const ImageGenerationSettingsSection(),
            ),
          ],
        ),
      ),
    );
  }
}
