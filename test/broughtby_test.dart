import 'dart:convert';

import 'package:broughtby_flutter/broughtby_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for the SDK's own behavior on top of the API client: what it sends
/// without being asked, and — as importantly — what it stops sending.
class FixedAppInfo implements AppInfoSource {
  const FixedAppInfo(this.info);

  final AppInfo? info;

  @override
  Future<AppInfo?> read() async => info;
}

class FixedSource implements ReferralCodeSource {
  FixedSource(this.name, this.code);

  @override
  final String name;
  final String? code;
  int reads = 0;

  @override
  Future<String?> read() async {
    reads += 1;
    return code;
  }
}

/// A clipboard that counts how often it's read, without a platform channel.
class CountingClipboard extends ClipboardSource {
  int reads = 0;

  @override
  Future<String?> read() async {
    reads += 1;
    return null;
  }
}

String jwt({String issuer = 'https://abc.supabase.co/auth/v1', String sub = 'user-1'}) {
  String segment(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${segment(<String, dynamic>{'alg': 'ES256'})}.'
      '${segment(<String, dynamic>{'iss': issuer, 'sub': sub})}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> sent;
  late bool setupComplete;

  const AppInfo android = AppInfo(
    platform: 'android',
    appIdentifier: 'com.example.app',
    signingFingerprint: 'AABBCC',
    countryCode: 'TR',
  );

  Future<void> start({
    AppInfo? app = android,
    List<ReferralCodeSource>? sources,
  }) async {
    final MockClient mock = MockClient((http.Request request) async {
      sent.add(request);
      final Map<String, dynamic> body = switch (request.url.path) {
        '/api/v1/setup' => <String, dynamic>{'complete': setupComplete},
        '/api/v1/identity' => <String, dynamic>{'status': 'linked'},
        _ => <String, dynamic>{'status': 'attributed'},
      };
      return http.Response(jsonEncode(body), 200);
    });

    await BroughtBy.initialize(
      publicKey: 'bt_pk_test_key_1234',
      baseUrl: Uri.parse('https://api.example.com'),
      httpClient: mock,
      appInfo: FixedAppInfo(app),
      sources: sources ?? <ReferralCodeSource>[],
    );
    await BroughtBy.settled;
  }

  List<http.Request> requestsTo(String path) =>
      sent.where((http.Request r) => r.url.path == path).toList();

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sent = <http.Request>[];
    setupComplete = false;
  });

  tearDown(BroughtBy.resetForTesting);

  group('setup report', () {
    test('initialize reports what the app knows about itself', () async {
      await start();

      final http.Request report = requestsTo('/api/v1/setup').single;
      expect(bodyOf(report), <String, dynamic>{
        'platform': 'android',
        'appIdentifier': 'com.example.app',
        'signingFingerprint': 'AABBCC',
        'countryCode': 'TR',
      });
    });

    test('carries the public key but never the user token', () async {
      await start();
      await BroughtBy.identify(jwt: jwt());
      await BroughtBy.settled;

      for (final http.Request report in requestsTo('/api/v1/setup')) {
        expect(report.headers['x-api-key'], 'bt_pk_test_key_1234');
        expect(report.headers.containsKey('authorization'), isFalse);
      }
    });

    test('identify adds who issued the token and how it is signed', () async {
      await start();
      await BroughtBy.identify(jwt: jwt());
      await BroughtBy.settled;

      final Map<String, dynamic> report = bodyOf(requestsTo('/api/v1/setup').last);
      expect(report['tokenIssuer'], 'https://abc.supabase.co/auth/v1');
      expect(report['tokenAlgorithm'], 'ES256');
      // The subject identifies the user; a setup report has no use for it.
      expect(report.containsKey('sub'), isFalse);
      expect(jsonEncode(report), isNot(contains('user-1')));
    });

    test('stops once the server has everything', () async {
      setupComplete = true;
      await start();
      expect(requestsTo('/api/v1/setup'), hasLength(1));

      await BroughtBy.identify(jwt: jwt());
      await BroughtBy.settled;
      BroughtBy.resetForTesting();
      await start();

      expect(requestsTo('/api/v1/setup'), hasLength(1));
    });

    test('sends nothing on platforms the server has no use for', () async {
      await start(app: null);
      expect(requestsTo('/api/v1/setup'), isEmpty);
    });
  });

  group('RevenueCat user', () {
    test('identify reports the RevenueCat ID with the user token', () async {
      await start();
      final String token = jwt();
      await BroughtBy.identify(jwt: token, revenueCatUserId: r'$RCAnonymousID:abc');
      await BroughtBy.settled;

      final http.Request link = requestsTo('/api/v1/identity').single;
      expect(bodyOf(link), <String, dynamic>{'revenueCatUserId': r'$RCAnonymousID:abc'});
      expect(link.headers['authorization'], 'Bearer $token');
    });

    test('the same pair is reported once, not on every launch', () async {
      await start();
      await BroughtBy.identify(jwt: jwt(), revenueCatUserId: 'rc-1');
      await BroughtBy.settled;
      await BroughtBy.identify(jwt: jwt(), revenueCatUserId: 'rc-1');
      await BroughtBy.settled;

      expect(requestsTo('/api/v1/identity'), hasLength(1));
    });

    test('a different user on the same device is reported again', () async {
      await start();
      await BroughtBy.identify(jwt: jwt(sub: 'user-1'), revenueCatUserId: 'rc-1');
      await BroughtBy.settled;
      await BroughtBy.identify(jwt: jwt(sub: 'user-2'), revenueCatUserId: 'rc-1');
      await BroughtBy.settled;

      expect(requestsTo('/api/v1/identity'), hasLength(2));
    });

    test('nothing is sent without a RevenueCat ID, or on sign-out', () async {
      await start();
      await BroughtBy.identify(jwt: jwt());
      await BroughtBy.identify(jwt: null, revenueCatUserId: 'rc-1');
      await BroughtBy.settled;

      expect(requestsTo('/api/v1/identity'), isEmpty);
    });
  });

  group('clipboard', () {
    test('is read once per install, not on every launch', () async {
      final CountingClipboard clipboard = CountingClipboard();
      await start(sources: <ReferralCodeSource>[clipboard]);
      await BroughtBy.identify(jwt: jwt());

      await BroughtBy.captureAttribution();
      await BroughtBy.captureAttribution();
      await BroughtBy.captureAttribution();

      expect(clipboard.reads, 1);
    });

    test('other channels are still tried on every launch', () async {
      final FixedSource referrer = FixedSource('install_referrer', null);
      await start(sources: <ReferralCodeSource>[referrer, CountingClipboard()]);
      await BroughtBy.identify(jwt: jwt());

      await BroughtBy.captureAttribution();
      await BroughtBy.captureAttribution();

      expect(referrer.reads, 2);
    });
  });
}
