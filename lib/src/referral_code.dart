/// Extracting and normalizing referral codes.
///
/// This file is deliberately pure Dart: no platform channel, no network
/// call. Extracting the code correctly from its various channels is the
/// most error-prone part of attribution, so this logic has to be testable
/// on its own.
library;

/// The key the code travels under inside the Play Store install referrer.
///
/// Must match `buildInstallReferrer` on the server exactly; if the two
/// drift apart, Android attribution silently stops working.
const String referrerCodeKey = 'btb_code';

/// Where share links live unless the app is told otherwise.
///
/// Temporary: moves to `go.broughtby.io` once that domain is registered.
final Uri defaultShareUrlBase = Uri.parse('https://broughtby.vercel.app');

/// Collapses whatever variation the user typed into one canonical code.
///
/// Users type codes with spaces, hyphens, or lowercase letters. Applies the
/// same rule as `normalizeCode` on the server; skipping this step is the
/// most common reason manual code entry fails.
String normalizeReferralCode(String input) {
  return input.trim().toUpperCase().replaceAll(RegExp(r'[\s\-_.]'), '');
}

/// Says whether a code is plausible in shape.
///
/// Assumes the input is **already normalized**: it does not strip
/// separators itself. That distinction matters — if it also stripped
/// separators here, arbitrary text like "code code code" would count as a
/// valid code, and the clipboard channel would send any text to the server.
///
/// The server has the final say; the check here only keeps obvious junk
/// from reaching the network.
bool looksLikeReferralCode(String candidate) {
  return RegExp(r'^[A-Z0-9]{3,20}$').hasMatch(candidate.trim().toUpperCase());
}

/// Extracts the code from a Play Store install referrer string.
///
/// The referrer is a query string passed through unmodified by Play:
/// `btb_code=AHMET34&utm_source=broughtby`. On organic installs our key is
/// absent and this returns null — that isn't an error, it's the normal case.
String? extractCodeFromInstallReferrer(String? referrer) {
  if (referrer == null || referrer.isEmpty) return null;

  final Uri parsed = Uri.parse('?$referrer');
  final String? raw = parsed.queryParameters[referrerCodeKey];
  if (raw == null) return null;

  // Our own server writes the referrer; we still normalize and validate it.
  final String code = normalizeReferralCode(raw);
  return looksLikeReferralCode(code) ? code : null;
}

/// Extracts the code from a universal / app link.
///
/// Exactly one shape is accepted, and only on the share host:
///   `https://go.broughtby.io/r/<slug>/<code>`
///
/// Everything else returns null, on purpose:
///
///   - **Other hosts.** Any link can open an app. A sign-in redirect, an
///     email confirmation or a password reset carries its own short-lived
///     secret, and reading a code out of a link we didn't write would send
///     that secret to Broughtby — or, if it happened to match a real code,
///     attribute the user to a stranger.
///   - **A `?code=` parameter.** That name belongs to OAuth and to most
///     email verification links. It is never read.
///   - **"The last path segment is the code".** The app's own deep links
///     (`/settings`, `/profile`) would be sent to the server as codes.
String? extractCodeFromLink(Uri? link, {required Uri shareUrlBase}) {
  if (link == null) return null;
  if (link.scheme != shareUrlBase.scheme) return null;
  if (link.host.toLowerCase() != shareUrlBase.host.toLowerCase()) return null;
  if (link.port != shareUrlBase.port) return null;

  final List<String> base = _segments(shareUrlBase);
  final List<String> segments = _segments(link);
  if (segments.length != base.length + 3) return null;
  for (int i = 0; i < base.length; i += 1) {
    if (segments[i] != base[i]) return null;
  }
  if (segments[base.length] != 'r') return null;

  final String code = normalizeReferralCode(segments[base.length + 2]);
  return looksLikeReferralCode(code) ? code : null;
}

List<String> _segments(Uri uri) =>
    uri.pathSegments.where((String segment) => segment.isNotEmpty).toList();

/// Treats clipboard content as a possible code.
///
/// On iOS the landing page writes the code to the clipboard. Because the
/// clipboard can hold anything, the check here is deliberately narrow: only
/// content that looks exactly like a code is accepted, never a code hidden
/// somewhere inside a longer text.
String? extractCodeFromClipboard(String? clipboard) {
  if (clipboard == null) return null;
  final String trimmed = clipboard.trim();
  if (trimmed.length > 32) return null;
  if (!looksLikeReferralCode(trimmed)) return null;
  return normalizeReferralCode(trimmed);
}
