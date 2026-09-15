import 'package:broughtby_flutter/src/dashboard_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the language carried to the dashboard.
///
/// The app's own language is not always the device language, so it travels
/// with the address. Everything else in the address has to survive the trip —
/// the entry token lives there too.
void main() {
  final Uri base = Uri.parse('https://app.broughtby.io/d/enter?t=abc123');

  test('adds the language without losing the entry token', () {
    final Uri url = dashboardUrlWithLanguage(base, 'en');

    expect(url.queryParameters['lang'], 'en');
    expect(url.queryParameters['t'], 'abc123');
    expect(url.path, '/d/enter');
  });

  test('leaves the address untouched when no language is known', () {
    expect(dashboardUrlWithLanguage(base, null), base);
    expect(dashboardUrlWithLanguage(base, ''), base);
    expect(dashboardUrlWithLanguage(base, '  '), base);
  });

  test('normalises the language code', () {
    expect(dashboardUrlWithLanguage(base, 'EN').queryParameters['lang'], 'en');
    expect(dashboardUrlWithLanguage(base, ' de ').queryParameters['lang'], 'de');
  });

  test('replaces a language that is already there', () {
    final Uri withLang = dashboardUrlWithLanguage(base, 'tr');

    expect(dashboardUrlWithLanguage(withLang, 'fr').queryParameters['lang'], 'fr');
  });
}
