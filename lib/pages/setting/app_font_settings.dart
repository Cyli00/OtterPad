import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_fonts.dart';
import '../../core/l10n.dart';
import '../../providers/theme_provider.dart';
import '../../services/system_font_service.dart';
import '../../services/snackbar_service.dart';
import 'setting_group.dart';
import 'setting_picker.dart';

final systemFontFamiliesProvider = FutureProvider<List<String>>(
  (ref) => SystemFontService.listFamilies(),
);

class AppFontSettings extends ConsumerWidget {
  const AppFontSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final desktop = AppFonts.isDesktop(defaultTargetPlatform);
    final selected = ref.watch(themeProvider.select((state) => state.appFont));
    final fonts = desktop ? ref.watch(systemFontFamiliesProvider) : null;
    final options = <String>[
      AppFonts.sans,
      AppFonts.serif,
      if (desktop) ...{
        if (selected.startsWith(AppFonts.systemPrefix)) selected,
        ...?fonts?.asData?.value.map((name) => '${AppFonts.systemPrefix}$name'),
      },
    ];
    String label(String value) => switch (value) {
      AppFonts.sans => l10n.appFontSans,
      AppFonts.serif => l10n.appFontSerif,
      _ => value.substring(AppFonts.systemPrefix.length),
    };
    Future<void> select(String value) async {
      try {
        await ref.read(themeProvider.notifier).setAppFont(value);
      } catch (_) {
        if (context.mounted) {
          ref
              .read(snackBarServiceProvider)
              .showResult(message: l10n.appFontSaveFailed);
        }
      }
    }

    return SettingGroup(
      title: l10n.appFont,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              SettingPicker<String>(
                current: options.contains(selected) ? selected : AppFonts.sans,
                options: options,
                labelFor: label,
                sheetTitle: l10n.appFont,
                onChanged: select,
              )
            else
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  selectedBackgroundColor: theme.colorScheme.primaryContainer,
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(100),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                segments: [
                  for (final value in options)
                    ButtonSegment(value: value, label: Text(label(value))),
                ],
                selected: {
                  selected == AppFonts.serif ? AppFonts.serif : AppFonts.sans,
                },
                onSelectionChanged: (values) => select(values.single),
              ),
            if (fonts?.isLoading == true) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (fonts?.hasError == true) ...[
              const SizedBox(height: 12),
              Text(l10n.appFontLoadFailed, style: theme.textTheme.bodySmall),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => ref.invalidate(systemFontFamiliesProvider),
                  child: Text(l10n.retry),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.appFontPreview,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: AppFonts.family(selected, defaultTargetPlatform),
                fontFamilyFallback: AppFonts.fallbacks(
                  selected,
                  defaultTargetPlatform,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.appFontHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
