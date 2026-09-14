/// The data types and result model the SDK exposes.
library;

/// The channel attribution was captured through.
///
/// Identical to the enum on the server; the values travel over the wire
/// under these exact names.
enum AttributionSource {
  deepLink('deep_link'),
  installReferrer('install_referrer'),
  manualCode('manual_code'),
  clipboard('clipboard');

  const AttributionSource(this.wireValue);

  final String wireValue;
}

/// The outcome of an attribution attempt.
enum AttributionStatus {
  /// The link was established on this call.
  attributed,

  /// The user was already linked to the same affiliate — calling again is
  /// harmless.
  alreadyAttributed,

  /// No code was found on any channel. The normal outcome for an organic
  /// install.
  noCodeFound,
}

class AttributionResult {
  const AttributionResult({
    required this.status,
    this.source,
    this.code,
  });

  final AttributionStatus status;
  final AttributionSource? source;
  final String? code;

  bool get isAttributed =>
      status == AttributionStatus.attributed ||
      status == AttributionStatus.alreadyAttributed;
}

/// An affiliate's own code and share link.
class AffiliateInfo {
  const AffiliateInfo({
    required this.code,
    required this.shareUrl,
    required this.isCustom,
    required this.canCustomize,
  });

  factory AffiliateInfo.fromJson(Map<String, dynamic> json) {
    return AffiliateInfo(
      code: json['code'] as String,
      shareUrl: json['shareUrl'] as String,
      isCustom: json['isCustom'] as bool? ?? false,
      canCustomize: json['canCustomize'] as bool? ?? true,
    );
  }

  final String code;
  final String shareUrl;
  final bool isCustom;

  /// The code can be customized once; false once that has already happened.
  final bool canCustomize;
}

/// SDK errors.
///
/// The priority is never crashing the app: referral isn't the app's core
/// function. So errors are never thrown as exceptions — they come back as a
/// result, and the caller shows the user as much or as little as it wants.
enum BroughtByErrorKind {
  /// Used before `initialize` was called.
  notInitialized,

  /// Something requiring identity was attempted before `identify` was
  /// called.
  notIdentified,

  /// Network error, or the server couldn't be reached.
  network,

  /// The server rejected the request (invalid key, expired token, malformed
  /// request).
  rejected,

  /// The code isn't valid.
  unknownCode,

  /// The user is already linked to a different affiliate.
  alreadyClaimed,

  /// An attempt to apply a user's own code to themselves.
  selfReferral,
}

class BroughtByError implements Exception {
  const BroughtByError(this.kind, [this.detail]);

  final BroughtByErrorKind kind;
  final String? detail;

  @override
  String toString() => 'BroughtByError(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// A result carrying either success or failure.
///
/// The same idea as the server's own Result type: expected errors are
/// visible in the type system, so the caller has to handle them.
sealed class BroughtByResult<T> {
  const BroughtByResult();

  bool get isOk => this is BroughtByOk<T>;

  T? get valueOrNull => switch (this) {
        BroughtByOk<T>(:final T value) => value,
        BroughtByFailure<T>() => null,
      };

  BroughtByError? get errorOrNull => switch (this) {
        BroughtByOk<T>() => null,
        BroughtByFailure<T>(:final BroughtByError error) => error,
      };
}

final class BroughtByOk<T> extends BroughtByResult<T> {
  const BroughtByOk(this.value);

  final T value;
}

final class BroughtByFailure<T> extends BroughtByResult<T> {
  const BroughtByFailure(this.error);

  final BroughtByError error;
}
