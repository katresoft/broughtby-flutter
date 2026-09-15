/// Carries the chosen language to the dashboard address.
///
/// Kept out of the public API on purpose: it is an implementation detail of
/// [BroughtBy.openDashboard], not something an app should need to call.
Uri dashboardUrlWithLanguage(Uri url, String? language) {
  final String? code = language?.trim().toLowerCase();
  if (code == null || code.isEmpty) return url;

  return url.replace(
    queryParameters: <String, String>{...url.queryParameters, 'lang': code},
  );
}
