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

/// The query parameter the code travels under in a deep link.
const String deepLinkCodeParam = 'code';

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
/// Only two shapes are accepted:
///   `https://go.broughtby.io/r/<slug>/<code>`
///   `https://app.example.com/invite?code=<code>`
///
/// A heuristic like "treat the last path segment as the code" is
/// deliberately **absent**: the app's own deep links (`/settings`,
/// `/profile`) would otherwise be mistaken for a referral code and junk
/// would be sent to the server on every launch.
String? extractCodeFromLink(Uri? link) {
  if (link == null) return null;

  final String? queryRaw = link.queryParameters[deepLinkCodeParam];
  if (queryRaw != null) {
    final String code = normalizeReferralCode(queryRaw);
    if (looksLikeReferralCode(code)) return code;
  }

  final List<String> segments = link.pathSegments;
  final int marker = segments.indexOf('r');
  if (marker != -1 && segments.length >= marker + 3) {
    final String code = normalizeReferralCode(segments[marker + 2]);
    if (looksLikeReferralCode(code)) return code;
  }

  return null;
}

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
