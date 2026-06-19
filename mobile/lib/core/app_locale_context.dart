import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'app_localizations.dart';

extension AppLocaleContext on BuildContext {
  String t(String key, {Map<String, Object?> args = const {}}) =>
      AppLocalizations.tr(watch<AppState>().localeCode, key, args: args);

  String tr(String key, {Map<String, Object?> args = const {}}) =>
      AppLocalizations.tr(read<AppState>().localeCode, key, args: args);

  String fieldLabel(String key) =>
      AppLocalizations.fieldLabel(watch<AppState>().localeCode, key);

  String singularFieldLabel(String key) =>
      AppLocalizations.singularLabel(watch<AppState>().localeCode, key);
}
