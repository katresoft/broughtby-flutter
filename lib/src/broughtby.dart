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

  /// The `sub` of the token last passed to `identify`; null when signed out.
  String? _subject;

  /// Work started by `initialize` and `identify` that the caller doesn't
  /// wait for. Kept so tests can.
  final List<Future<void>> _background = <Future<void>>[];

  /// Marks that the signed-in user's attribution has been settled.
  ///
  /// Kept per user, not per device: the phone's second account has not been
  /// attributed just because the first one was. The server still has the
  /// final say; this flag only avoids a lookup and a network call on every
  /// launch.
  String get _attributedKey => '$_legacyAttributedKey.${_subject ?? ''}';

  /// 0.3 and earlier kept one flag for the whole device.
  static const String _legacyAttributedKey = 'broughtby.attributed';

  /// Marks that the clipboard has been looked at once on this device.
  static const String _clipboardCheckedKey = 'broughtby.clipboard_checked';

  /// Marks that the install referrer's code has been answered by the server.
  ///
  /// That code belongs to the install. Without this, every account opened
  /// on the phone afterwards would be attributed to the same invite.
  static const String _installReferrerUsedKey = 'broughtby.install_referrer_used';

  /// Codes delivered by a link that the server has already answered, for
  /// the same reason: one tap on an invite is one referral.
  static const String _deliveredLinkCodesKey = 'broughtby.delivered_link_codes';

  /// A code that was read but that the server hasn't answered yet, stored
  /// as `<source>|<code>`.
  ///
  /// Most channels give up a code once: the clipboard is read a single
  /// time, a launch link is gone on the next launch. Writing the code down
  /// before sending it means a dropped connection costs a retry, not the
  /// referral.
  static const String _pendingCodeKey = 'broughtby.pending_code';

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
    final Uri share = shareUrlBase ?? defaultShareUrlBase;

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
            DeepLinkSource(shareUrlBase: share),
            const InstallReferrerSource(),
            const ClipboardSource(),
          ],
      appInfo: appInfo ?? const PlatformAppInfoSource(),
      shareUrlBase: share,
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

    final TokenInfo? token = jwt == null || jwt.isEmpty ? null : readTokenInfo(jwt);
    self._subject = token?.subject;
    if (jwt == null || jwt.isEmpty) return;

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
  ///
  /// Call it after `identify`. Without a signed-in user it returns
  /// [BroughtByErrorKind.notIdentified] and reads nothing.
  static Future<BroughtByResult<AttributionResult>> captureAttribution({
    bool force = false,
  }) async {
    final BroughtBy self = _required;

    // Nothing is read before there is someone to attribute. The clipboard
    // can be read once; a code found now could not be sent, and would be
    // gone by the time it could.
    if (!self._client.hasUserToken) {
      return const BroughtByFailure<AttributionResult>(
        BroughtByError(BroughtByErrorKind.notIdentified),
      );
    }

    if (!force && await self._isAttributed()) {
      // Whatever was waiting was meant for a user who had no referrer yet.
      await self._remove(_pendingCodeKey);
      return const BroughtByOk<AttributionResult>(
        AttributionResult(status: AttributionStatus.alreadyAttributed),
      );
    }

    // A code read on an earlier call that the server never got to answer.
    final ({String code, AttributionSource source})? pending = await self._pending();
    if (pending != null) {
      final BroughtByResult<AttributionResult> result =
          await self._claim(pending.code, pending.source);
      if (result.errorOrNull?.kind != BroughtByErrorKind.unknownCode) return result;
    }

    for (final ReferralCodeSource source in self._sources) {
      final AttributionSource wire = _sourceFor(source.name);

      // The clipboard is read once per install, on the first launch — the
      // moment it can plausibly hold an invite code. Reading it on every
      // launch would show the system's paste prompt each time, and would
      // keep sending whatever short text the user last copied to the server
      // for as long as they stay unattributed, which for an organic user is
      // forever.
      if (wire == AttributionSource.clipboard && await self._flag(_clipboardCheckedKey)) continue;
      if (wire == AttributionSource.installReferrer && await self._flag(_installReferrerUsedKey)) {
        continue;
      }

      final String? read = await source.read();
      final String? code =
          read != null && wire == AttributionSource.deepLink && await self._wasDelivered(read)
              ? null
              : read;

      // Written down before the clipboard is marked as read: from here on
      // the device is the only place the code exists.
      if (code != null) await self._keep(code, wire);
      if (wire == AttributionSource.clipboard) await self._setFlag(_clipboardCheckedKey);
      if (code == null) continue;

      final BroughtByResult<AttributionResult> result = await self._claim(code, wire);

      // If the code is invalid on this channel, keep trying the rest. Any
      // other outcome stops here and is reported to the caller.
      if (result.errorOrNull?.kind == BroughtByErrorKind.unknownCode) continue;
      return result;
    }

    return const BroughtByOk<AttributionResult>(
      AttributionResult(status: AttributionStatus.noCodeFound),
    );
  }

  /// Hands the SDK a link the app received while it was already running.
  ///
  /// `captureAttribution` only sees the link the app was launched with.
  /// Pass every later link here, from wherever your app receives them — an
  /// `app_links` stream, your router. Anything that isn't a Broughtby
  /// invite returns [AttributionStatus.noCodeFound] without touching the
  /// network.
  ///
  /// Safe to call before `identify`: the code is kept, and the next
  /// `captureAttribution` sends it.
  static Future<BroughtByResult<AttributionResult>> handleLink(Uri link) async {
    final BroughtBy self = _required;

    final String? code = extractCodeFromLink(link, shareUrlBase: self.shareUrlBase);
    if (code == null || await self._wasDelivered(code)) {
      return const BroughtByOk<AttributionResult>(
        AttributionResult(status: AttributionStatus.noCodeFound),
      );
    }

    if (!self._client.hasUserToken) {
      // The link won't be delivered a second time.
      await self._keep(code, AttributionSource.deepLink);
      return const BroughtByFailure<AttributionResult>(
        BroughtByError(BroughtByErrorKind.notIdentified),
      );
    }

    if (await self._isAttributed()) {
      return const BroughtByOk<AttributionResult>(
        AttributionResult(status: AttributionStatus.alreadyAttributed),
      );
    }

    await self._keep(code, AttributionSource.deepLink);
    return self._claim(code, AttributionSource.deepLink);
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

    return self._claim(code, AttributionSource.manualCode);
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
              refreshUrl: () async {
                final Uri? fresh = (await _required._client.fetchDashboardUrl()).valueOrNull;
                return fresh == null ? null : dashboardUrlWithLanguage(fresh, language);
              },
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

  /// Sends a code to the server and settles what the device remembers
  /// about it.
  ///
  /// The code stays written down until the server has actually answered.
  /// A dropped connection, an expired token or a failing server is not an
  /// answer; a refusal is.
  Future<BroughtByResult<AttributionResult>> _claim(String code, AttributionSource source) async {
    // Read before the request: the user may sign out while it's in flight.
    final String attributedKey = _attributedKey;

    final BroughtByResult<AttributionStatus> result =
        await _client.recordAttribution(code: code, source: source);

    switch (result) {
      case BroughtByOk<AttributionStatus>(:final AttributionStatus value):
        await _setFlag(attributedKey);
        await _settle(code, source, attributed: true);
        return BroughtByOk<AttributionResult>(
          AttributionResult(status: value, source: source, code: code),
        );

      case BroughtByFailure<AttributionStatus>(:final BroughtByError error):
        if (!error.isTransient) await _settle(code, source, attributed: false);
        return BroughtByFailure<AttributionResult>(error);
    }
  }

  /// Records that the server has answered for [code].
  Future<void> _settle(String code, AttributionSource source, {required bool attributed}) async {
    // An attributed user has no use for a code still waiting; otherwise
    // only the code that was answered is done with.
    if (attributed || (await _pending())?.code == code) await _remove(_pendingCodeKey);

    switch (source) {
      case AttributionSource.installReferrer:
        await _setFlag(_installReferrerUsedKey);
      case AttributionSource.deepLink:
        try {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final List<String> delivered = <String>[
            ...?prefs.getStringList(_deliveredLinkCodesKey),
            code,
          ];
          // Bounded: a phone that taps invites for years keeps the recent ones.
          await prefs.setStringList(
            _deliveredLinkCodesKey,
            delivered.length > 20 ? delivered.sublist(delivered.length - 20) : delivered,
          );
        } catch (_) {
          // At worst the same link is sent once more; the server ignores it.
        }
      case AttributionSource.clipboard || AttributionSource.manualCode:
        break;
    }
  }

  Future<bool> _wasDelivered(String code) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_deliveredLinkCodesKey)?.contains(code) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<({String code, AttributionSource source})?> _pending() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_pendingCodeKey);
      if (raw == null) return null;

      final int cut = raw.indexOf('|');
      if (cut <= 0) return null;

      final AttributionSource? source = AttributionSource.values
          .where((AttributionSource s) => s.wireValue == raw.substring(0, cut))
          .firstOrNull;
      final String code = raw.substring(cut + 1);
      if (source == null || !looksLikeReferralCode(code)) return null;

      return (code: code, source: source);
    } catch (_) {
      return null;
    }
  }

  Future<void> _keep(String code, AttributionSource source) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingCodeKey, '${source.wireValue}|$code');
    } catch (_) {
      // Without storage the code only lives as long as this call does.
    }
  }

  Future<bool> _isAttributed() async {
    if (await _flag(_attributedKey)) return true;

    // 0.3 and earlier kept a single flag for the device. It is handed to
    // whoever is signed in when the upgrade first runs — far more often
    // than not, the user it was set for.
    if (!await _flag(_legacyAttributedKey)) return false;
    await _setFlag(_attributedKey);
    await _setFlag(_installReferrerUsedKey);
    await _remove(_legacyAttributedKey);
    return true;
  }

  Future<void> _remove(String key) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      // Left in place, it's simply looked at again next time.
    }
  }

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
