import 'package:flutter/widgets.dart';
import 'l10n/app_localizations.dart';
export 'l10n/app_localizations.dart';

extension DemoL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
