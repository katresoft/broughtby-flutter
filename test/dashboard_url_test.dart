import 'package:broughtby_flutter/src/dashboard_url.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the language carried to the dashboard.
///
/// The app's own language is not always the device language, so it travels
/// with the address. Everything else in the address has to survive the trip —
/// the entry token lives there too.
void main() {
  final Uri base = Uri.parse('https://app.broughtby.io/d/enter?t=abc123');

  group('dashboardUrlWithLanguage', () {
    test('adds the language without losing the entry token', () {
      final Uri url = dashboardUrlWithLanguage(base, 'en');

      expect(url.queryParameters['lang'], 'en');
      expect(url.queryParameters['t'], 'abc123');
      expect(url.path, '/d/enter');
    });

    test('leaves the address untouched when no language is known', () {
      expect(dashboardUrlWithLanguage(base, null), base);
      expect(dashboardUrlWithLanguage(base, ''), base);
    });

    test('replaces a language that is already there', () {
      final Uri withLang = dashboardUrlWithLanguage(base, 'tr');

      expect(dashboardUrlWithLanguage(withLang, 'fr').queryParameters['lang'], 'fr');
    });
  });

  group('dashboardLanguage', () {
    /// Reads what the SDK would send from an app running in [locale].
    ///
    /// Wraps the widget in Localizations directly rather than MaterialApp:
    /// that is the layer the SDK actually reads, and MaterialApp warns for
    /// any locale its delegates don't cover.
    Future<String?> languageIn(
      WidgetTester tester,
      Locale locale,
      String? override,
    ) async {
      String? seen;

      await tester.pumpWidget(
        Localizations(
          locale: locale,
          delegates: const <LocalizationsDelegate<dynamic>>[
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Builder(
            builder: (BuildContext context) {
              seen = dashboardLanguage(context, override);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      return seen;
    }

    testWidgets('follows the language the app is running in', (WidgetTester tester) async {
      expect(await languageIn(tester, const Locale('de'), null), 'de');
    });

    testWidgets('an explicit language wins over the app', (WidgetTester tester) async {
      expect(await languageIn(tester, const Locale('de'), 'en'), 'en');
    });

    testWidgets('normalises what the caller passes', (WidgetTester tester) async {
      expect(await languageIn(tester, const Locale('tr'), ' EN '), 'en');
      expect(await languageIn(tester, const Locale('tr'), '  '), 'tr');
    });

    testWidgets('stays null without an app around it', (WidgetTester tester) async {
      String? seen = 'unset';

      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            seen = dashboardLanguage(context, null);
            return const SizedBox.shrink();
          },
        ),
      );

      // No Localizations above: the server decides from the device instead.
      expect(seen, isNull);
    });
  });
}
