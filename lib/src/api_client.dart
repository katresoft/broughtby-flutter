import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// The Broughtby API client.
///
/// Carries two separate identities, and both are required:
///   - `X-Api-Key`: says which app it's speaking for (the public key)
///   - `Authorization: Bearer <jwt>`: proves who the user is
///
/// Without the second, anyone could claim to be any user and produce fake
/// attribution. That's why calls requiring identity never even reach the
/// network without a token.
///
/// What this client deliberately *doesn't* do: report a purchase. The only
/// source of truth for money is the webhook the server receives from the
/// payment provider; a purchase claim coming from the client is never
/// accepted.
class BroughtByApiClient {
  BroughtByApiClient({
    required this.baseUrl,
    required this.publicKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final String publicKey;
  final Duration timeout;
  final http.Client _http;

  String? _userToken;

  /// Stores the verified user token.
  void setUserToken(String? token) {
    _userToken = token;
  }

  bool get hasUserToken => _userToken != null && _userToken!.isNotEmpty;

  Map<String, String> _headers({bool withUser = false}) {
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
      'x-api-key': publicKey,
    };
    if (withUser && _userToken != null) {
      headers['authorization'] = 'Bearer $_userToken';
    }
    return headers;
  }

  /// Links the user to an affiliate.
  Future<BroughtByResult<AttributionStatus>> recordAttribution({
    required String code,
    required AttributionSource source,
  }) async {
    if (!hasUserToken) {
      return const BroughtByFailure<AttributionStatus>(
        BroughtByError(BroughtByErrorKind.notIdentified),
      );
    }

    return _send<AttributionStatus>(
      path: 'api/v1/attribution',
      body: <String, dynamic>{'code': code, 'source': source.wireValue},
      decode: (Map<String, dynamic> json) {
        final String status = json['status'] as String? ?? '';
        return status == 'attributed'
            ? AttributionStatus.attributed
            : AttributionStatus.alreadyAttributed;
      },
    );
  }

  /// Fetches the short-lived address that opens the dashboard.
  ///
  /// The address returned is only valid for a few minutes and is exchanged
  /// for a session cookie as soon as it's opened; it shouldn't be cached,
  /// and should be requested fresh on every open.
  Future<BroughtByResult<Uri>> fetchDashboardUrl() async {
    if (!hasUserToken) {
      return const BroughtByFailure<Uri>(
        BroughtByError(BroughtByErrorKind.notIdentified),
      );
    }

    return _send<Uri>(
      path: 'api/v1/dashboard-token',
      body: const <String, dynamic>{},
      decode: (Map<String, dynamic> json) => Uri.parse(json['url'] as String),
    );
  }

  /// Fetches the affiliate record, creating one if it doesn't exist yet.
  Future<BroughtByResult<AffiliateInfo>> fetchAffiliate() async {
    if (!hasUserToken) {
      return const BroughtByFailure<AffiliateInfo>(
        BroughtByError(BroughtByErrorKind.notIdentified),
      );
    }

    return _send<AffiliateInfo>(
      path: 'api/v1/affiliate',
      body: const <String, dynamic>{},
      decode: AffiliateInfo.fromJson,
    );
  }

  Future<BroughtByResult<T>> _send<T>({
    required String path,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic>) decode,
  }) async {
    http.Response response;
    try {
      response = await _http
          .post(
            baseUrl.resolve(path),
            headers: _headers(withUser: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (error) {
      // A network error shouldn't affect the app; the caller can silently
      // move on.
      return BroughtByFailure<T>(
        BroughtByError(BroughtByErrorKind.network, error.toString()),
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final Map<String, dynamic> json =
            jsonDecode(response.body) as Map<String, dynamic>;
        return BroughtByOk<T>(decode(json));
      } catch (error) {
        return BroughtByFailure<T>(
          BroughtByError(BroughtByErrorKind.rejected, 'Could not parse response: $error'),
        );
      }
    }

    return BroughtByFailure<T>(_errorFor(response));
  }

  BroughtByError _errorFor(http.Response response) {
    String code = '';
    try {
      code = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String? ?? '';
    } catch (_) {
      // If the body isn't JSON, the status code alone will have to do.
    }

    final BroughtByErrorKind kind = switch (code) {
      'unknown_code' => BroughtByErrorKind.unknownCode,
      'already_claimed' => BroughtByErrorKind.alreadyClaimed,
      'self_referral' => BroughtByErrorKind.selfReferral,
      _ => BroughtByErrorKind.rejected,
    };

    return BroughtByError(kind, 'HTTP ${response.statusCode}${code.isEmpty ? '' : ' $code'}');
  }

  void close() {
    _http.close();
  }
}
