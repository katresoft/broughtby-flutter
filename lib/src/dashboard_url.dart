import 'package:flutter/widgets.dart';

/// The language the dashboard should speak.
///
/// Defaults to the locale the host app is running in, which is not always the
/// device language: someone with a Turkish phone may be using the app in
/// English, and this screen opens inside that app. Returns null when the app
/// has no Localizations above it — then the server falls back to the device
/// language on its own.
String? dashboardLanguage(BuildContext context, String? override) {
  // A blank override means "no opinion", not "send nothing" — falling through
  // to the app's own locale is the useful reading.
  final String? asked = _clean(override);
  if (asked != null) return asked;

  return _clean(Localizations.maybeLocaleOf(context)?.languageCode);
}

String? _clean(String? value) {
  final String? code = value?.trim().toLowerCase();

  return code == null || code.isEmpty ? null : code;
}

/// Carries the chosen language to the dashboard address.
///
/// Kept out of the public API on purpose: it is an implementation detail of
/// [BroughtBy.openDashboard], not something an app should need to call.
Uri dashboardUrlWithLanguage(Uri url, String? language) {
  if (language == null || language.isEmpty) return url;

  return url.replace(
    queryParameters: <String, String>{...url.queryParameters, 'lang': language},
  );
}
