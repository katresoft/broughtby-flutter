import 'package:broughtby_flutter/broughtby_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the code extraction logic.
///
/// This step is attribution's real bottleneck on iOS: every case where the
/// user carries a code through one of the channels but the SDK fails to
/// read it means a lost commission. That's why there are deliberately many
/// "dirty input" cases here.
void main() {
  group('normalizeReferralCode', () {
    test('collapses whatever variation the user typed into one code', () {
      for (final String input in <String>[
        ' ahmet34 ',
        'AHMET-34',
        'ahmet_34',
        'Ahmet.34',
        'a h m e t 3 4',
      ]) {
        expect(normalizeReferralCode(input), 'AHMET34');
      }
    });

    test('matches the normalization the server applies', () {
      // Server: input.trim().toUpperCase().replace(/[\s\-_.]/g, "")
      expect(normalizeReferralCode('  bt-code_1.2  '), 'BTCODE12');
    });
  });

  group('looksLikeReferralCode', () {
    test('accepts valid codes', () {
      for (final String code in <String>['ABC', 'AHMET34', 'A1B2C3', 'X' * 20]) {
        expect(looksLikeReferralCode(code), isTrue, reason: code);
      }
    });

    test('rejects junk input', () {
      // Note: this function does not strip separators. That's exactly why
      // a string like "code code code" is not treated as valid.
      for (final String code in <String>[
        '',
        'AB',
        'X' * 21,
        'ahmet!',
        'code code code',
        'AHMET-34',
        'https://example.com',
      ]) {
        expect(looksLikeReferralCode(code), isFalse, reason: code);
      }
    });
  });

  group('extractCodeFromInstallReferrer', () {
    test('reads the code from a Play referrer string', () {
      expect(
        extractCodeFromInstallReferrer('btb_code=AHMET34&utm_source=broughtby'),
        'AHMET34',
      );
    });

    test('works regardless of parameter order', () {
      expect(
        extractCodeFromInstallReferrer('utm_source=broughtby&btb_code=AHMET34'),
        'AHMET34',
      );
    });

    test('returns null on an organic install — that is not an error', () {
      expect(
        extractCodeFromInstallReferrer('utm_source=google-play&utm_medium=organic'),
        isNull,
      );
    });

    test('handles a null or empty referrer safely', () {
      expect(extractCodeFromInstallReferrer(null), isNull);
      expect(extractCodeFromInstallReferrer(''), isNull);
    });

    test('rejects a referrer carrying junk', () {
      expect(extractCodeFromInstallReferrer('btb_code=x'), isNull);
      expect(extractCodeFromInstallReferrer('btb_code='), isNull);
    });

    test('decodes a URL-encoded value', () {
      expect(extractCodeFromInstallReferrer('btb_code=AHMET%2034'), 'AHMET34');
    });
  });

  group('extractCodeFromLink', () {
    final Uri share = Uri.parse('https://go.broughtby.io');
    String? extract(String url) => extractCodeFromLink(Uri.parse(url), shareUrlBase: share);

    test('reads the code from an invite link on the share host', () {
      expect(extract('https://go.broughtby.io/r/vakitnakit/AHMET34'), 'AHMET34');
      expect(extract('https://GO.broughtby.io/r/vakitnakit/ahmet34/'), 'AHMET34');
    });

    test('ignores the same path on any other host', () {
      // Any link can open an app; only ours carries a referral code.
      expect(extract('https://evil.example/r/vakitnakit/AHMET34'), isNull);
      expect(extract('http://go.broughtby.io/r/vakitnakit/AHMET34'), isNull);
      expect(extract('myapp://go.broughtby.io/r/vakitnakit/AHMET34'), isNull);
    });

    test('never reads a ?code= parameter', () {
      // That name belongs to OAuth redirects and email verification links:
      // reading it would send someone else's one-time secret to the server.
      expect(extract('https://app.example.com/auth/callback?code=483920'), isNull);
      expect(extract('https://go.broughtby.io/?code=AHMET34'), isNull);
      expect(extract('https://go.broughtby.io/r/app/PATHCODE?code=QUERYCODE'), 'PATHCODE');
    });

    test('accepts the invite path and nothing around it', () {
      expect(extract('https://go.broughtby.io/i/vakitnakit/AHMET34'), isNull);
      expect(extract('https://go.broughtby.io/x/r/vakitnakit/AHMET34'), isNull);
      expect(extract('https://go.broughtby.io/r/vakitnakit/AHMET34/extra'), isNull);
    });

    test('follows a share base that lives under a path', () {
      final Uri nested = Uri.parse('https://example.com/invite/');
      expect(
        extractCodeFromLink(
          Uri.parse('https://example.com/invite/r/app/AHMET34'),
          shareUrlBase: nested,
        ),
        'AHMET34',
      );
      expect(
        extractCodeFromLink(Uri.parse('https://example.com/r/app/AHMET34'), shareUrlBase: nested),
        isNull,
      );
    });

    test('returns null for a link with no code', () {
      expect(extract('https://go.broughtby.io/'), isNull);
      expect(extractCodeFromLink(null, shareUrlBase: share), isNull);
    });

    test('does not mistake the app\'s own deep links for a code', () {
      // The "treat the last path segment as the code" heuristic would have
      // turned these links into codes.
      for (final String url in <String>[
        'https://app.example.com/settings',
        'https://app.example.com/profile/edit',
        'myapp://launch/notifications',
      ]) {
        expect(extract(url), isNull, reason: url);
      }
    });

    test('does not crash on missing path segments', () {
      expect(extract('https://go.broughtby.io/r/'), isNull);
      expect(extract('https://go.broughtby.io/r/app'), isNull);
    });
  });

  group('extractCodeFromClipboard', () {
    test('reads the code from the clipboard', () {
      expect(extractCodeFromClipboard('  ahmet34 '), 'AHMET34');
    });

    test('rejects long text — the clipboard can carry anything', () {
      expect(extractCodeFromClipboard('X' * 40), isNull);
      expect(
        extractCodeFromClipboard('Hey, download the app, my code is AHMET34'),
        isNull,
      );
    });

    test('does not crash on a null or empty clipboard', () {
      expect(extractCodeFromClipboard(null), isNull);
      expect(extractCodeFromClipboard('   '), isNull);
    });

    test('does not treat a pasted URL as a code', () {
      expect(extractCodeFromClipboard('https://go.broughtby.io/r/a/AHMET34'), isNull);
    });
  });
}
