import 'dart:convert';

import 'package:broughtby_flutter/src/setup_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an unsigned token; the signature is irrelevant to what's read.
String token(Map<String, dynamic> header, Map<String, dynamic> payload) {
  String segment(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${segment(header)}.${segment(payload)}.signature';
}

void main() {
  group('readTokenInfo', () {
    test('reads the issuer, algorithm and subject', () {
      final TokenInfo? info = readTokenInfo(token(
        <String, dynamic>{'alg': 'ES256', 'typ': 'JWT'},
        <String, dynamic>{'iss': 'https://abc.supabase.co/auth/v1', 'sub': 'user-1'},
      ));

      expect(info?.issuer, 'https://abc.supabase.co/auth/v1');
      expect(info?.algorithm, 'ES256');
      expect(info?.subject, 'user-1');
    });

    test('leaves out claims the token does not carry', () {
      final TokenInfo? info = readTokenInfo(token(
        <String, dynamic>{'alg': 'HS256'},
        <String, dynamic>{'sub': 'user-1'},
      ));

      expect(info?.issuer, isNull);
      expect(info?.algorithm, 'HS256');
    });

    test('returns null for anything that is not a JWT', () {
      for (final String bad in <String>['', 'not-a-token', 'a.b', 'a.b.c', '....']) {
        expect(readTokenInfo(bad), isNull, reason: bad);
      }
    });

    test('ignores claims of the wrong type instead of throwing', () {
      final TokenInfo? info = readTokenInfo(token(
        <String, dynamic>{'alg': 256},
        <String, dynamic>{'iss': <String>['a', 'b']},
      ));

      expect(info?.issuer, isNull);
      expect(info?.algorithm, isNull);
    });
  });
}
