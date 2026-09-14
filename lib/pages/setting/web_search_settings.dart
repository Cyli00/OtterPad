import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../../services/web_search_service.dart';
import '../../utils/debounced_action.dart';
import 'setting_group.dart';
import 'setting_picker.dart';

class WebSearchSettings extends StatefulWidget {
  const WebSearchSettings({super.key});

  @override
  State<WebSearchSettings> createState() => _WebSearchSettingsState();
}

class _WebSearchSettingsState extends State<WebSearchSettings> {
  late WebSearchProvider _provider = WebSearchService.provider;
  late final _controllers = {
    for (final p in WebSearchProvider.values)
      p: TextEditingController(text: WebSearchService.keyFor(p)),
  };
  bool _obscured = true;
  final _save = DebouncedAction();

  void _flushKey() {
    _save.cancel();
    final value = _controllers[_provider]!.text.trim();
    if (value != WebSearchService.keyFor(_provider)) {
      WebSearchService.setKey(_provider, value);
    }
  }

  @override
  void dispose() {
    _flushKey();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return SettingGroup(
      title: l10n.webSearchSettingsTitle,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingPicker<WebSearchProvider>(
              current: _provider,
              options: WebSearchProvider.values,
              labelFor: (p) => switch (p) {
                WebSearchProvider.tavily => 'Tavily',
                WebSearchProvider.exa => 'Exa',
                WebSearchProvider.brave => 'Brave',
              },
              sheetTitle: l10n.webSearchSettingsTitle,
              onChanged: (value) {
                _flushKey();
                setState(() {
                  _provider = value;
                  _obscured = true;
                });
                WebSearchService.setProvider(value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey(_provider),
              controller: _controllers[_provider],
              obscureText: _obscured,
              autocorrect: false,
              enableSuggestions: false,
              style: text.bodyMedium,
              onChanged: (_) => _save.run(_flushKey),
              decoration: InputDecoration(
                labelText: l10n.apiKey,
                filled: true,
                fillColor: cs.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  tooltip: l10n.chatToggleKeyVisibility,
                  onPressed: () => setState(() => _obscured = !_obscured),
                  icon: Icon(
                    _obscured
                        ? Symbols.visibility_off_rounded
                        : Symbols.visibility_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.webSearchSettingsDesc,
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
