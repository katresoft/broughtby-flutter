/// Broughtby — referral tracking SDK for mobile apps.
///
/// ```dart
/// await BroughtBy.initialize(publicKey: 'bt_pk_...');
/// await BroughtBy.identify(jwt: supabaseAccessToken);
/// await BroughtBy.captureAttribution();
/// ```
library;

export 'src/api_client.dart' show BroughtByApiClient;
export 'src/broughtby.dart' show BroughtBy;
export 'src/dashboard_page.dart' show BroughtByDashboardPage;
export 'src/models.dart'
    show
        AffiliateInfo,
        AttributionResult,
        AttributionSource,
        AttributionStatus,
        BroughtByError,
        BroughtByErrorKind,
        BroughtByFailure,
        BroughtByOk,
        BroughtByResult;
export 'src/referral_code.dart'
    show
        extractCodeFromClipboard,
        extractCodeFromInstallReferrer,
        extractCodeFromLink,
        looksLikeReferralCode,
        normalizeReferralCode;
export 'src/sources.dart'
    show ClipboardSource, DeepLinkSource, InstallReferrerSource, ReferralCodeSource;
