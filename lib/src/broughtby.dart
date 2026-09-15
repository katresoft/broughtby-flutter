import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';
import 'referral_code.dart';
import 'dashboard_page.dart';
import 'dashboard_url.dart';
import 'sources.dart';

/// Broughtby SDK.
///
/// Integration is three calls:
/// ```dart
/// await BroughtBy.initialize(publicKey: 'bt_pk_...');
/// await BroughtBy.identify(jwt: supabaseAccessToken);
/// await BroughtBy.captureAttribution();
/// ```
///
/// `appId` is not requested: the public key already maps to one app on the
/// server. Accepting both would open the door to silent bugs if they ever
/// disagree.
///
/// The SDK **has no method for reporting a purchase.** This isn't a gap,
/// it's a design decision: the only source of truth for money is the
/// webhook the server receives from the payment provider.
class BroughtBy {
  BroughtBy._({
    required BroughtByApiClient client,
    required List<ReferralCodeSource> sources,
    required this.shareUrlBase,
  })  : _client = client,
        _sources = sources;

  static BroughtBy? _instance;

  final BroughtByApiClient _client;
  final List<ReferralCodeSource> _sources;
  final Uri shareUrlBase;

  /// Marks that attribution has already been recorded successfully on this
  /// device.
  ///
  /// The server still has the final say; this flag only avoids an
  /// unnecessary clipboard read and network call on every launch.
  static const String _attributedKey = 'broughtby.attributed';

  /// Sets up the SDK.
  ///
  /// [baseUrl] is only needed for tenants running their own server or
  /// pointing at a staging environment.
  static Future<void> initialize({
    required String publicKey,
    Uri? baseUrl,
    Uri? shareUrlBase,
    http.Client? httpClient,
    List<ReferralCodeSource>? sources,
  }) async {
    final Uri api = baseUrl ?? Uri.parse('https://api.broughtby.io');

    _instance = BroughtBy._(
      client: BroughtByApiClient(
        baseUrl: api,
        publicKey: publicKey,
        httpClient: httpClient,
      ),
      // Ordered by reliability: channels that cost the user nothing come
      // first, the clipboard — which interrupts the user — comes last.
      sources: sources ??
          <ReferralCodeSource>[
            DeepLinkSource(),
            const InstallReferrerSource(),
            const ClipboardSource(),
          ],
      shareUrlBase: shareUrlBase ?? Uri.parse('https://go.broughtby.io'),
    );
  }

  static BroughtBy get _required {
    final BroughtBy? instance = _instance;
    if (instance == null) {
      throw const BroughtByError(
        BroughtByErrorKind.notInitialized,
        'BroughtBy.initialize must be called first.',
      );
    }
    return instance;
  }

  /// Sets the token that proves the user's identity.
  ///
  /// The token comes from the tenant's own identity provider (e.g. a
  /// Supabase session token) and is verified on the server. Call
  /// `identify(jwt: null)` when the user signs out.
  static Future<void> identify({required String? jwt}) async {
    _required._client.setUserToken(jwt);
  }

  /// Looks for a code across every channel and reports it to the server if
  /// found.
  ///
  /// Safe to call on every app launch: it's idempotent and does nothing if
  /// no code is found. On an organic install, the expected result is
  /// [AttributionStatus.noCodeFound] — that isn't an error.
  static Future<BroughtByResult<AttributionResult>> captureAttribution({
    bool force = false,
  }) async {
    final BroughtBy self = _required;

    if (!force && await self._alreadyAttributedLocally()) {
      return const BroughtByOk<AttributionResult>(
        AttributionResult(status: AttributionStatus.alreadyAttributed),
      );
    }

    for (final ReferralCodeSource source in self._sources) {
      final String? code = await source.read();
      if (code == null) continue;

      final AttributionSource wire = _sourceFor(source.name);
      final BroughtByResult<AttributionStatus> result =
          await self._client.recordAttribution(code: code, source: wire);

      switch (result) {
        case BroughtByOk<AttributionStatus>(:final AttributionStatus value):
          await self._markAttributedLocally();
          return BroughtByOk<AttributionResult>(
            AttributionResult(status: value, source: wire, code: code),
          );

        case BroughtByFailure<AttributionStatus>(:final BroughtByError error):
          // If the code is invalid on this channel, keep trying the rest.
          // Any other error stops here and is reported to the caller.
          if (error.kind == BroughtByErrorKind.unknownCode) continue;
          return BroughtByFailure<AttributionResult>(error);
      }
    }

    return const BroughtByOk<AttributionResult>(
      AttributionResult(status: AttributionStatus.noCodeFound),
    );
  }

  /// Submits a code the user typed in by hand.
  ///
  /// On iOS this is the real channel; call it from an onboarding screen's
  /// "Have a referral code?" field.
  static Future<BroughtByResult<AttributionResult>> submitCode(String input) async {
    final BroughtBy self = _required;
    final String code = normalizeReferralCode(input);

    if (!looksLikeReferralCode(code)) {
      return const BroughtByFailure<AttributionResult>(
        BroughtByError(BroughtByErrorKind.unknownCode, 'Code format is invalid.'),
      );
    }

    final BroughtByResult<AttributionStatus> result = await self._client
        .recordAttribution(code: code, source: AttributionSource.manualCode);

    switch (result) {
      case BroughtByOk<AttributionStatus>(:final AttributionStatus value):
        await self._markAttributedLocally();
        return BroughtByOk<AttributionResult>(
          AttributionResult(
            status: value,
            source: AttributionSource.manualCode,
            code: code,
          ),
        );

      case BroughtByFailure<AttributionStatus>(:final BroughtByError error):
        return BroughtByFailure<AttributionResult>(error);
    }
  }

  /// Fetches the user's own affiliate record and code.
  static Future<BroughtByResult<AffiliateInfo>> getAffiliate() {
    return _required._client.fetchAffiliate();
  }

  /// Opens the earnings dashboard inside the app.
  ///
  /// The dashboard is rendered on the server, so screens are written once
  /// and behave the same on every platform, and a design change never
  /// requires an app update.
  ///
  /// [title] is shown in the app bar. Pass your own already-translated
  /// string; the SDK ships no copy of its own.
  ///
  /// [locale] decides the language of the dashboard. It defaults to the
  /// locale your app is currently running in, which is not always the
  /// device language: someone with a Turkish phone may be using your app in
  /// English, and this screen opens inside your app.
  static Future<BroughtByResult<void>> openDashboard(
    BuildContext context, {
    String? title,
    String? locale,
  }) async {
    final String? language =
        locale ?? Localizations.maybeLocaleOf(context)?.languageCode;

    final BroughtByResult<Uri> url = await _required._client.fetchDashboardUrl();

    switch (url) {
      case BroughtByOk<Uri>(:final Uri value):
        if (!context.mounted) return const BroughtByOk<void>(null);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BroughtByDashboardPage(
              url: dashboardUrlWithLanguage(value, language),
              title: title,
            ),
          ),
        );
        return const BroughtByOk<void>(null);

      case BroughtByFailure<Uri>(:final BroughtByError error):
        return BroughtByFailure<void>(error);
    }
  }

  /// The link an affiliate shares.
  static Uri shareUrlFor(String appSlug, String code) {
    return _required.shareUrlBase.resolve('r/$appSlug/$code');
  }

  /// Resets state between tests.
  static void resetForTesting() {
    _instance = null;
  }

  static AttributionSource _sourceFor(String name) {
    return switch (name) {
      'deep_link' => AttributionSource.deepLink,
      'install_referrer' => AttributionSource.installReferrer,
      'clipboard' => AttributionSource.clipboard,
      _ => AttributionSource.manualCode,
    };
  }

  Future<bool> _alreadyAttributedLocally() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_attributedKey) ?? false;
    } catch (_) {
      // No local storage available; retrying on every launch is harmless.
      return false;
    }
  }

  Future<void> _markAttributedLocally() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_attributedKey, true);
    } catch (_) {
      // If it can't be marked, it's simply retried on the next launch.
    }
  }
}
