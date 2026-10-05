import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';
import 'referral_code.dart';
import 'dashboard_page.dart';
import 'dashboard_url.dart';
import 'setup_report.dart';
import 'sources.dart';

/// Broughtby SDK.
///
/// Integration is three calls:
/// ```dart
/// await BroughtBy.initialize(publicKey: 'bt_pk_...');
/// await BroughtBy.identify(
///   jwt: supabaseAccessToken,
///   revenueCatUserId: await Purchases.appUserID,
/// );
/// await BroughtBy.captureAttribution();
/// ```
///
/// There is very little to configure by hand on the other side. The first
/// time the app runs, the SDK reports what the app already knows about
/// itself — its bundle ID or package name, its signing fingerprint, which
/// service issued the session token — and the console fills itself in.
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
    required AppInfoSource appInfo,
    required this.shareUrlBase,
  })  : _client = client,
        _sources = sources,
        _appInfo = appInfo;

  static BroughtBy? _instance;

  final BroughtByApiClient _client;
  final List<ReferralCodeSource> _sources;
  final AppInfoSource _appInfo;
  final Uri shareUrlBase;

  /// Work started by `initialize` and `identify` that the caller doesn't
  /// wait for. Kept so tests can.
  final List<Future<void>> _background = <Future<void>>[];

  /// Marks that attribution has already been recorded successfully on this
  /// device.
  ///
  /// The server still has the final say; this flag only avoids an
  /// unnecessary clipboard read and network call on every launch.
  static const String _attributedKey = 'broughtby.attributed';

  /// Marks that the clipboard has been looked at once on this device.
  static const String _clipboardCheckedKey = 'broughtby.clipboard_checked';

  /// Marks that the server has everything the app can tell it, so setup
  /// reports stop. Suffixed with the tail of the public key: pointing the
  /// same build at a different app has to start over.
  String get _setupCompleteKey {
    final String key = _client.publicKey;
    return 'broughtby.setup_complete.${key.length <= 8 ? key : key.substring(key.length - 8)}';
  }

  /// The user / RevenueCat ID pair last reported, so it's sent once rather
  /// than on every launch.
  static const String _revenueCatLinkKey = 'broughtby.revenuecat_link';

  /// Sets up the SDK.
  ///
  /// [baseUrl] is only needed for tenants running their own server or
  /// pointing at a staging environment.
  ///
  /// The defaults below point at the temporary `broughtby.vercel.app`
  /// deployment. They will move to `api.broughtby.io` / `go.broughtby.io`
  /// once that domain is registered — a breaking change tracked for the
  /// next major version, not a silent swap.
  static Future<void> initialize({
    required String publicKey,
    Uri? baseUrl,
    Uri? shareUrlBase,
    http.Client? httpClient,
    List<ReferralCodeSource>? sources,
    AppInfoSource? appInfo,
  }) async {
    final Uri api = baseUrl ?? Uri.parse('https://broughtby.vercel.app');

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
      appInfo: appInfo ?? const PlatformAppInfoSource(),
      shareUrlBase: shareUrlBase ?? Uri.parse('https://broughtby.vercel.app'),
    );

    // Not awaited: telling the console about the app is a convenience for
    // the developer, and must never hold up the app's launch.
    _instance!._inBackground(_instance!._reportSetup());
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
  ///
  /// Pass [revenueCatUserId] — `await Purchases.appUserID` — whenever you
  /// have it. Purchases reach Broughtby under that ID; without it, they only
  /// match this user if you log RevenueCat in with exactly the same ID as
  /// the token's `sub`. A purchase that matches no user earns nobody
  /// anything, and nothing reports it as an error.
  static Future<void> identify({required String? jwt, String? revenueCatUserId}) async {
    final BroughtBy self = _required;
    self._client.setUserToken(jwt);

    if (jwt == null || jwt.isEmpty) return;
    final TokenInfo? token = readTokenInfo(jwt);

    // Neither is awaited; see `initialize`.
    self._inBackground(self._reportSetup(token: token));
    if (revenueCatUserId != null && revenueCatUserId.isNotEmpty) {
      self._inBackground(self._linkRevenueCatUser(revenueCatUserId, token?.subject));
    }
  }

  /// Replaces the user's generated code with one they chose, e.g. their
  /// name. Allowed once; check [AffiliateInfo.canCustomize] first.
  static Future<BroughtByResult<AffiliateInfo>> customizeCode(String input) {
    return _required._client.customizeCode(normalizeReferralCode(input));
  }

  /// Completes once the background work started so far has finished.
  @visibleForTesting
  static Future<void> get settled => Future.wait(_required._background.toList());

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
      // The clipboard is read once per install, on the first launch — the
      // moment it can plausibly hold an invite code. Reading it on every
      // launch would show the system's paste prompt each time, and would
      // keep sending whatever short text the user last copied to the server
      // for as long as they stay unattributed, which for an organic user is
      // forever.
      if (source is ClipboardSource) {
        if (await self._flag(_clipboardCheckedKey)) continue;
        await self._setFlag(_clipboardCheckedKey);
      }

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
    final String? language = dashboardLanguage(context, locale);

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

  Future<bool> _alreadyAttributedLocally() => _flag(_attributedKey);

  Future<void> _markAttributedLocally() => _setFlag(_attributedKey);

  Future<bool> _flag(String key) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      // No local storage available; the work is simply repeated.
      return false;
    }
  }

  Future<void> _setFlag(String key) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (_) {
      // If it can't be marked, it's simply retried on the next launch.
    }
  }

  void _inBackground(Future<void> work) {
    // Background work never surfaces an error: none of it is the app's
    // business, and an unhandled async error would be. Finished work is
    // dropped so a long-lived app refreshing its token doesn't accumulate it.
    late final Future<void> tracked;
    tracked = work.catchError((Object _) {}).whenComplete(() => _background.remove(tracked));
    _background.add(tracked);
  }

  /// Reports what the app knows about itself, until the server says it has
  /// everything.
  Future<void> _reportSetup({TokenInfo? token}) async {
    if (await _flag(_setupCompleteKey)) return;

    final AppInfo? app = await _appInfo.read();
    if (app == null) return;

    final bool? complete = await _client.reportSetup(app, token: token);
    if (complete == true) await _setFlag(_setupCompleteKey);
  }

  /// Reports the RevenueCat ID once per user / ID pair.
  Future<void> _linkRevenueCatUser(String revenueCatUserId, String? subject) async {
    final String pair = '${subject ?? ''}|$revenueCatUserId';

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_revenueCatLinkKey) == pair) return;

      final BroughtByResult<void> result = await _client.linkRevenueCatUser(revenueCatUserId);
      if (result.isOk) await prefs.setString(_revenueCatLinkKey, pair);
    } catch (_) {
      // Retried on the next identify.
    }
  }
}
