import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What the running app already knows about itself.
///
/// Setting up an app used to mean copying values from other dashboards
/// into the Broughtby console: the bundle ID, the package name, the signing
/// fingerprint, the address of the sign-in service. The running app knows
/// all of them, so the SDK reports them and the console fills itself in.
///
/// Nothing here is a secret, and nothing here identifies the user.
class AppInfo {
  const AppInfo({
    required this.platform,
    required this.appIdentifier,
    this.signingFingerprint,
    this.countryCode,
  });

  /// `ios` or `android` — the only two platforms the server asks about.
  final String platform;

  /// The bundle ID on iOS, the package name on Android.
  final String appIdentifier;

  /// SHA-256 of the signing certificate. Android only; App Links need it.
  final String? signingFingerprint;

  /// The device's region. The server uses it to look the app up in the
  /// right App Store storefront — an app published in one country isn't
  /// found in another's.
  final String? countryCode;
}

/// Reads [AppInfo]. Separate from the SDK so tests don't need a platform.
abstract interface class AppInfoSource {
  /// Returns null on platforms the server has no use for (web, desktop).
  Future<AppInfo?> read();
}

class PlatformAppInfoSource implements AppInfoSource {
  const PlatformAppInfoSource();

  @override
  Future<AppInfo?> read() async {
    if (kIsWeb) return null;

    final String? platform = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => null,
    };
    if (platform == null) return null;

    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (info.packageName.isEmpty) return null;

      return AppInfo(
        platform: platform,
        appIdentifier: info.packageName,
        signingFingerprint:
            platform == 'android' && info.buildSignature.isNotEmpty ? info.buildSignature : null,
        countryCode: PlatformDispatcher.instance.locale.countryCode,
      );
    } catch (_) {
      // Reporting is a convenience for the developer; it must never get in
      // the way of the app.
      return null;
    }
  }
}

/// The two public facts about a session token the server needs in order to
/// suggest how to verify it: who issued it, and how it's signed.
class TokenInfo {
  const TokenInfo({this.issuer, this.algorithm, this.subject});

  /// The `iss` claim — it names the sign-in service (Supabase, Firebase…).
  final String? issuer;

  /// The `alg` header. A symmetric algorithm means the developer has to
  /// supply the signing secret by hand; it can't be discovered.
  final String? algorithm;

  /// The `sub` claim. Never sent in a setup report; used only on the device
  /// to tell one signed-in user from another.
  final String? subject;
}

/// Reads [TokenInfo] out of a JWT **without verifying it**.
///
/// That's fine for this purpose and only this purpose: the server treats
/// the result as a suggestion a human has to confirm, and does its own
/// verification on every real request.
TokenInfo? readTokenInfo(String jwt) {
  final List<String> parts = jwt.split('.');
  if (parts.length != 3) return null;

  final Map<String, dynamic>? header = _decodeSegment(parts[0]);
  final Map<String, dynamic>? payload = _decodeSegment(parts[1]);
  if (header == null || payload == null) return null;

  return TokenInfo(
    issuer: _string(payload['iss']),
    algorithm: _string(header['alg']),
    subject: _string(payload['sub']),
  );
}

Map<String, dynamic>? _decodeSegment(String segment) {
  try {
    final Object? decoded = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(segment))));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;
