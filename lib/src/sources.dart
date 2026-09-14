import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:play_install_referrer/play_install_referrer.dart';

import 'referral_code.dart';

/// The channels a code can arrive through.
///
/// Each channel is its own class because their reliability and platform
/// support differ; disabling one or adding a new one should be possible
/// without touching the others.
abstract interface class ReferralCodeSource {
  /// The source name — reported to the server as the channel it came from.
  String get name;

  /// Reads the code. Returns null if this channel isn't available on this
  /// device or doesn't carry a code.
  Future<String?> read();
}

/// Universal Link / App Link.
///
/// Only works while the app is *already installed*. It returns nothing on
/// the first launch after install — iOS has no such thing as a deferred
/// deep link.
class DeepLinkSource implements ReferralCodeSource {
  DeepLinkSource({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  String get name => 'deep_link';

  @override
  Future<String?> read() async {
    try {
      final Uri? initial = await _appLinks.getInitialLink();
      return extractCodeFromLink(initial);
    } catch (_) {
      return null;
    }
  }
}

/// Google Play Install Referrer.
///
/// This is the channel that solves attribution on Android: the user does
/// nothing, and Play carries the code through to install. There's no
/// equivalent on iOS.
class InstallReferrerSource implements ReferralCodeSource {
  const InstallReferrerSource();

  @override
  String get name => 'install_referrer';

  @override
  Future<String?> read() async {
    try {
      final ReferrerDetails details = await PlayInstallReferrer.installReferrer;
      return extractCodeFromInstallReferrer(details.installReferrer);
    } catch (_) {
      // Expected off Android, or when Play Services isn't available.
      return null;
    }
  }
}

/// Clipboard.
///
/// On iOS, the landing page writes the code to the clipboard. Because iOS
/// 14+ shows the user a notice on clipboard reads, this channel is tried
/// last, and only content that looks exactly like a code is accepted.
class ClipboardSource implements ReferralCodeSource {
  const ClipboardSource();

  @override
  String get name => 'clipboard';

  @override
  Future<String?> read() async {
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      return extractCodeFromClipboard(data?.text);
    } catch (_) {
      return null;
    }
  }
}
