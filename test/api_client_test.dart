import 'dart:convert';

import 'package:broughtby_flutter/broughtby_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tests for the API client.
///
/// Runs against a fake HTTP client; the goal is to verify the wire
/// contract — which headers go out, which status code maps to which error,
/// whether a request goes out at all without identity.
void main() {
  late List<http.Request> sent;

  BroughtByApiClient clientReturning(
    int status,
    Map<String, dynamic> body, {
    String? token = 'jwt-token',
  }) {
    sent = <http.Request>[];
    final MockClient mock = MockClient((http.Request request) async {
      sent.add(request);
      return http.Response(jsonEncode(body), status, headers: <String, String>{
        'content-type': 'application/json',
      });
    });

    final BroughtByApiClient client = BroughtByApiClient(
      baseUrl: Uri.parse('https://api.example.com'),
      publicKey: 'bt_pk_test',
      httpClient: mock,
    );
    client.setUserToken(token);
    return client;
  }

  group('identity headers', () {
    test('every request carries the public key and the user token', () async {
      final BroughtByApiClient client =
          clientReturning(201, <String, dynamic>{'status': 'attributed'});

      await client.recordAttribution(
        code: 'AHMET34',
        source: AttributionSource.manualCode,
      );

      expect(sent, hasLength(1));
      expect(sent.first.headers['x-api-key'], 'bt_pk_test');
      expect(sent.first.headers['authorization'], 'Bearer jwt-token');
    });

    test('without a user token, the request never reaches the network', () async {
      final BroughtByApiClient client = clientReturning(
        201,
        <String, dynamic>{'status': 'attributed'},
        token: null,
      );

      final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
        code: 'AHMET34',
        source: AttributionSource.manualCode,
      );

      expect(result.isOk, isFalse);
      expect(result.errorOrNull?.kind, BroughtByErrorKind.notIdentified);
      expect(sent, isEmpty);
    });
  });

  group('recordAttribution', () {
    test('returns attributed when a new link is established', () async {
      final BroughtByApiClient client =
          clientReturning(201, <String, dynamic>{'status': 'attributed'});

      final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
        code: 'AHMET34',
        source: AttributionSource.installReferrer,
      );

      expect(result.valueOrNull, AttributionStatus.attributed);

      final Map<String, dynamic> body =
          jsonDecode(sent.first.body) as Map<String, dynamic>;
      expect(body['code'], 'AHMET34');
      expect(body['source'], 'install_referrer');
    });

    test('returns alreadyAttributed for an existing link', () async {
      final BroughtByApiClient client =
          clientReturning(200, <String, dynamic>{'status': 'already_attributed'});

      final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
        code: 'AHMET34',
        source: AttributionSource.manualCode,
      );

      expect(result.valueOrNull, AttributionStatus.alreadyAttributed);
    });

    test('translates server error codes into SDK errors', () async {
      final Map<String, BroughtByErrorKind> cases = <String, BroughtByErrorKind>{
        'unknown_code': BroughtByErrorKind.unknownCode,
        'already_claimed': BroughtByErrorKind.alreadyClaimed,
        'self_referral': BroughtByErrorKind.selfReferral,
        'invalid_body': BroughtByErrorKind.rejected,
      };

      for (final MapEntry<String, BroughtByErrorKind> entry in cases.entries) {
        final BroughtByApiClient client =
            clientReturning(409, <String, dynamic>{'error': entry.key});

        final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
          code: 'AHMET34',
          source: AttributionSource.manualCode,
        );

        expect(result.errorOrNull?.kind, entry.value, reason: entry.key);
      }
    });

    test('a network error does not throw — the app must not crash', () async {
      final MockClient mock = MockClient((http.Request request) async {
        throw http.ClientException('no connection');
      });
      final BroughtByApiClient client = BroughtByApiClient(
        baseUrl: Uri.parse('https://api.example.com'),
        publicKey: 'bt_pk_test',
        httpClient: mock,
      );
      client.setUserToken('jwt-token');

      final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
        code: 'AHMET34',
        source: AttributionSource.manualCode,
      );

      expect(result.errorOrNull?.kind, BroughtByErrorKind.network);
    });

    test('a malformed JSON response does not throw', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return http.Response('this is not JSON', 200);
      });
      final BroughtByApiClient client = BroughtByApiClient(
        baseUrl: Uri.parse('https://api.example.com'),
        publicKey: 'bt_pk_test',
        httpClient: mock,
      );
      client.setUserToken('jwt-token');

      final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
        code: 'AHMET34',
        source: AttributionSource.manualCode,
      );

      // Not a refusal: a captive portal answers 200 with its own page.
      expect(result.errorOrNull?.kind, BroughtByErrorKind.serverError);
      expect(result.errorOrNull?.isTransient, isTrue);
    });

    test('an expired token, a rate limit and a failing server are told apart', () async {
      final Map<int, BroughtByErrorKind> cases = <int, BroughtByErrorKind>{
        401: BroughtByErrorKind.unauthorized,
        403: BroughtByErrorKind.unauthorized,
        429: BroughtByErrorKind.rateLimited,
        500: BroughtByErrorKind.serverError,
        503: BroughtByErrorKind.serverError,
        400: BroughtByErrorKind.rejected,
      };

      for (final MapEntry<int, BroughtByErrorKind> entry in cases.entries) {
        final BroughtByApiClient client =
            clientReturning(entry.key, <String, dynamic>{'error': 'something_else'});

        final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
          code: 'AHMET34',
          source: AttributionSource.manualCode,
        );

        expect(result.errorOrNull?.kind, entry.value, reason: '${entry.key}');
        expect(
          result.errorOrNull?.isTransient,
          entry.value != BroughtByErrorKind.rejected,
          reason: '${entry.key}',
        );
      }
    });

    test('a rate limit carries how long the server asked to wait', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return http.Response('{"error":"rate_limited"}', 429, headers: <String, String>{
          'retry-after': '42',
        });
      });
      final BroughtByApiClient client = BroughtByApiClient(
        baseUrl: Uri.parse('https://api.example.com'),
        publicKey: 'bt_pk_test',
        httpClient: mock,
      );
      client.setUserToken('jwt-token');

      final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
        code: 'AHMET34',
        source: AttributionSource.manualCode,
      );

      expect(result.errorOrNull?.kind, BroughtByErrorKind.rateLimited);
      expect(result.errorOrNull?.retryAfter, const Duration(seconds: 42));
    });
  });

  group('fetchAffiliate', () {
    test('parses the affiliate info', () async {
      final BroughtByApiClient client = clientReturning(200, <String, dynamic>{
        'code': 'AHMET34',
        'shareUrl': 'https://go.broughtby.io/r/vakitnakit/AHMET34',
        'isCustom': true,
        'canCustomize': false,
      });

      final BroughtByResult<AffiliateInfo> result = await client.fetchAffiliate();
      final AffiliateInfo? info = result.valueOrNull;

      expect(info?.code, 'AHMET34');
      expect(info?.shareUrl, 'https://go.broughtby.io/r/vakitnakit/AHMET34');
      expect(info?.isCustom, isTrue);
      expect(info?.canCustomize, isFalse);
    });

    test('falls back to sensible defaults for missing fields', () async {
      final BroughtByApiClient client = clientReturning(200, <String, dynamic>{
        'code': 'AHMET34',
        'shareUrl': 'https://go.broughtby.io/r/vakitnakit/AHMET34',
      });

      final AffiliateInfo? info = (await client.fetchAffiliate()).valueOrNull;
      expect(info?.isCustom, isFalse);
      expect(info?.canCustomize, isTrue);
    });
  });

  group('custom code', () {
    test('sends the requested code and returns the updated record', () async {
      final BroughtByApiClient client = clientReturning(200, <String, dynamic>{
        'code': 'AHMET34',
        'shareUrl': 'https://go.example.com/r/app/AHMET34',
        'isCustom': true,
        'canCustomize': false,
      });

      final BroughtByResult<AffiliateInfo> result = await client.customizeCode('AHMET34');

      expect(sent.single.url.path, '/api/v1/affiliate/code');
      expect(jsonDecode(sent.single.body), <String, dynamic>{'code': 'AHMET34'});
      expect(result.valueOrNull?.code, 'AHMET34');
      expect(result.valueOrNull?.canCustomize, isFalse);
    });

    test('maps each rejection to its own error kind', () async {
      final Map<String, BroughtByErrorKind> expected = <String, BroughtByErrorKind>{
        'code_taken': BroughtByErrorKind.codeTaken,
        'invalid_code': BroughtByErrorKind.invalidCode,
        'already_customized': BroughtByErrorKind.alreadyCustomized,
      };

      for (final MapEntry<String, BroughtByErrorKind> entry in expected.entries) {
        final BroughtByApiClient client =
            clientReturning(409, <String, dynamic>{'error': entry.key});
        final BroughtByResult<AffiliateInfo> result = await client.customizeCode('X');
        expect(result.errorOrNull?.kind, entry.value, reason: entry.key);
      }
    });
  });

  group('new-user window', () {
    test('an expired window has its own error kind', () async {
      final BroughtByApiClient client =
          clientReturning(409, <String, dynamic>{'error': 'window_expired'});

      final BroughtByResult<AttributionStatus> result = await client.recordAttribution(
        code: 'AHMET34',
        source: AttributionSource.manualCode,
      );

      expect(result.errorOrNull?.kind, BroughtByErrorKind.windowExpired);
    });
  });
}
